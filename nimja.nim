{.experimental.} # automatic deference first param

import os
import ospaths
import osproc
import tables
import strutils
import strfmt
import sequtils
import times
import manifest as manifestMod
import utils

when isMainModule:
  import arg_parser

type
  BuildNode = ref BuildNodeObj
  BuildNodeObj = object of RootObj
    name*: string
    action*: BuildAction # nil means it should be a file
    case haveMtime: bool
    of false: discard
    of true: mtime*: Time

using
  action: BuildAction
  node: BuildNode

var
  fs = initTable[string, BuildNode]()
  manifest: Manifest

proc newNode(name: string): BuildNode =
  result.new
  result.name = name

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
    # TODO need to handle rule-vars referring to others,
    # but watch out for cycles!
    echo action.rule.vars["command"].eval(action.magicVars, action.vars, manifest.vars)

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

when isMainModule:
  try:
    if args.dir != nil:
      setCurrentDir(args.dir)

    manifest = parseManifest(args.manifest)
    populateFSFromActions()

    case args.tool
    of tNone:
      discard #TODO build stuff
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
    quit 1

