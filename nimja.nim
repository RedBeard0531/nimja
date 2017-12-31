{.experimental.} # automatic deference first param

import manifest as manifestMod
import utils
import depsfile

import os
import ospaths
import tables
import strutils
import strfmt
import sequtils
import times
import deques
import future

import asyncdispatch
import asyncfile

#import osproc
when declared(quoteShell):
  import asynctools/asyncproc except quoteShell
else:
  import asynctools/asyncproc

when isMainModule:
  import arg_parser

type
  BuildNode = ref BuildNodeObj
  BuildNodeObj = object of RootObj
    name*: string
    action*: BuildAction # nil means it should be a file
    case haveMtime: bool
    of false: discard # default state
    of true: mtime*: MTime

using
  action: BuildAction
  node: BuildNode

var
  fs = initTable[string, BuildNode]()
  manifest: Manifest

proc newNode(name: string): BuildNode =
  result.new
  result.name = name

proc newestInput(action): MTime =
  if action.inputs.empty:
    Oldest()
  else:
    max action.inputs
        .filterIt(it.kind != iOrderOnly)
        .mapIt do:
          assert fs[it.path].haveMtime
          fs[it.path].mtime

proc assumeDirty(node) =
  node.haveMtime = true
  node.mtime = Newest()

proc fillMtime(node; force=false) =
  if not force and node.haveMtime: return

  node.haveMtime = true
  if node.name.fileExists:
    node.mtime = Known(node.name.getLastModificationTime)
  elif node.action.isNil:
    raise newException(Exception, "no rule to build " & node.name)
  elif node.action.rule.name == "phony":
    if node.action.inputs.empty:
      node.mtime = Newest()
    else:
      node.mtime = node.action.newestInput
  else:
    node.mtime = Oldest()

proc magicVars(action): Vars =
  let quoted_in =
    action.inputs.filterIt(it.kind == iExplicit)
                 .mapIt(it.path.quoteShell)
  let quoted_out =
    action.outputs.filterIt(it.kind == oExplicit)
                  .mapIt(it.path.quoteShell)
  result = newStrtab(4)
  result["in"] = join(quoted_in, " ")
  result["in_newlines"] = join(quoted_in, "\n")
  result["out"] = join(quoted_out, " ")

proc populateFSFromActions() =
  for action in manifest.actions:
    for output, kind in action.outputs.items:
      var node = newNode(output)
      node.action = action
      fs[output] = node

type CycleDetected = object of Exception
  path: seq[string]

proc evalRuleVar(action; varName: string): string =
    # TODO need to handle rule-vars referring to others,
    # but watch out for cycles!
    if varName notin action.rule.vars:
      return ""
    action.rule.vars[varName].eval(action.magicVars, action.vars, manifest.vars)

proc printCommands(next: string) =
  let node = fs.getOrDefault(next)
  if node == nil: return
  var action = node.action
  if action == nil: return
  if action.executed: return

  if action.seen:
    var x = newException(CycleDetected, "CycleDetected")
    x.path = @[next]
    raise x
  action.seen = true

  for input in action.inputs:
    try:
      printCommands(input.path)
    except CycleDetected as ex:
      ex.path &= next
      raise

  action.executed = true

  if action.rule.name != "phony":
    echo action.evalRuleVar("command")

proc targets(): seq[string] =
  if args.targets.empty:
    manifest.defaults
  else:
    args.targets

proc checkValidTarget(target: string) =
  if target notin fs:
    var best = (score: int.high, str: "")
    for output in fs.keys:
      let d = editDistance(target, output)
      if d < best.score:
        best.score = d
        best.str = output

    if best.str.empty:
      quit $$"unknown target '$target'"
    else:
      quit $$"unknown target '$target'\ndid you mean '${best.str}'"

type Throttle = object
  jobs: int
  queue: Deque[Future[void]]
var throttle = Throttle(jobs: 1, queue: initDeque[Future[void]]())

# returns nil on success. Non-nil return requires looping
# TODO figure out a better API
proc startJob: Future[void] =
  if throttle.jobs > 0:
    throttle.jobs -= 1
    return
  assert throttle.jobs >= 0
  result = newFuture[void]()
  throttle.queue.addLast(result)

proc finishJob =
  assert throttle.jobs >= 0
  throttle.jobs += 1
  assert throttle.jobs > 0
  assert throttle.jobs <= args.jobs
  if not throttle.queue.empty:
    throttle.queue.popFirst().complete()

type Process = object
  output: string
  status: int

proc isRestat(action): bool =
  let restat = action.evalRuleVar("restat")
  case restat
  of "", "0": return false
  of "1": return true
  else:
    raise newException(
      Exception,
      $$"Illegal restat value '$restat' in rule ${action.rule.name}")

proc fillMtimeMaybeRestat(node) =
  if node.action.isRestat:
    node.fillMtime(force=true)
  else:
    node.assumeDirty

var allGood = true
proc launch(cmd: string): Future[Process] {.async.} =
  var opts = {poStdErrToStdOut, poUsePath, poEvalCommand}
  when false: opts.incl poEchoCmd
  let p = await execProcess(cmd, options=opts)
  result.output = p.output
  result.status = p.exitcode

proc run(action): Future[Process] =
  let
    command = action.evalRuleVar("command")
    rspFile = action.evalRuleVar("rspfile")
    rspContent = action.evalRuleVar("rspfile_content")
    #TODO deps depfile restat msvc_deps_prefix description generator

  for output in action.outputs:
    createDir output.path.splitFile.dir

  if not rspFile.empty:
    writeFile(rspFile, rspContent)
  return launch(command)

proc build(target: string): Future[void]

proc buildImpl(target: string, node, action): Future[void] {.async.} =
  if not allGood: return
  await all action.inputs.mapIt(build it.path).filterIt(not it.isNil)
  if not allGood: return

  block checkIfUpToDate:
    var seenSelf = false
    var oldestOutput = Newest()
    for output in action.outputs:
      let oNode = fs[output.path]
      if not oNode.haveMtime:
        oNode.fillMtime
      if oNode == node: seenSelf = true
      oldestOutput = min(oldestOutput, oNode.mtime)

    assert seenSelf

    if action.rule.name == "phony": return

    let anyMissing = oldestOutput == Oldest()
    if not anyMissing and oldestOutput >= action.newestInput:
      let depfile = action.evalRuleVar("depfile")
      if fileExists(depfile):
        let deps = depfile.readFile.parseDeps
        assert deps.output == target
        for input in deps.inputs:
          let iNode = addr fs.mgetOrPut(input, nil)
          if iNode[] == nil: iNode[] = newNode(input)
          if not iNode.haveMtime:
            iNode.fillMtime
          if iNode.mtime > oldestOutput:
            break checkIfUpToDate # not up to date
      return # up to date

  while true:
    let ticket = startJob()
    if ticket.isNil: break
    await ticket
  if not allGood:
    finishJob()
    return

  let p = await run(action)
  finishJob()

  for output in action.outputs:
    fs[output.path].fillMtimeMaybeRestat()

  if p.status != 0:
    allgood = false
    raise newException(Exception, $$"Failed on $target: ${p.status}\n ${p.output}")
  echo $$"\n$target\n${p.output}"

proc build(target: string): Future[void] =
  if not allGood: return
  let node = addr fs.mgetOrPut(target, nil)
  if node[] == nil: node[] = newNode(target)
  var action = node.action
  if action == nil:
    node.fillMtime()
    return
  if action.run == nil:
    action.run = buildImpl(target, node[], action)
  return action.run

when isMainModule:
  try:
    if args.dir != nil:
      setCurrentDir(args.dir)

    throttle.jobs = args.jobs
    manifest = parseManifest(args.manifest)
    populateFSFromActions()

    case args.tool
    of tNone:
      setGlobalDispatcher newDispatcher()
      waitFor all targets().map(build)
    of tCommands:
      try:
        for t in targets():
          checkValidTarget(t)
        for t in targets():
          printCommands(t)
      except CycleDetected as ex:
        quit $$"dependency cycle detected: ${ex.path:a| <- }"

  except Exception as ex:
    stderr.write("Exception: " & $ex.name & ": " & ex.msg)
    quit getStackTrace(ex)

