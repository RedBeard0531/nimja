{.experimental.} # automatic deference first param
import lexer as lexmod
import os
import ospaths
import osproc
import tables
import strutils
import sequtils

when isMainModule:
  import arg_parser

type Strtab = OrderedTableRef[string, string]
proc initStrtab(cap=1): Strtab = newOrderedTable[string, string](cap)
type Rule = ref object
  vars: OrderedTableRef[string, EvalString]
  name: string

type
  InputKind = enum iExplicit, iImplicit, iOrderOnly
  OutputKind = enum oExplicit, oImplicit
  Input = tuple[path: string, kind: InputKind]
  Output = tuple[path: string, kind: OutputKind]

  Target = ref TargetObj
  TargetObj = object
    inputs*: seq[Input]
    outputs*: seq[Output]
    rule: Rule
    vars*: Strtab

using
  lexer: var Lexer
  target: Target

var
  vars: Strtab = initStrtab()
  defaults: seq[string] = @[]
  pools = initOrderedTable[string, int]()
  targets: seq[Target] = @[]
  rules = {"phony": Rule(name: "phony")}.toTable

proc newTarget(): Target =
  result.new
  result.inputs = @[]
  result.outputs = @[]
  result.vars = initStrtab()

proc eval(es: EvalString, varsTables: varargs[Strtab]): string =
  let sizeEstimate = foldl(es.parts):
    case b.kind
    of esText:
      a + b.text.len
    of esVar:
      a + 10
  do:
      0
  result = newStringOfCap(sizeEstimate)
  #result = ""
  result.shallow
  for part in es.parts.items:
    case part.kind:
    of esText: result &= part.text
    of esVar:
      block expand:
        for vars in varsTables:
          if part.varName in vars:
            result &= vars[part.varName]
            break expand
        raise newException(KeyError, "Undefined var: " & part.varName)

proc fatal(lexer; msg: varargs[string, `$`]) {.noreturn.} =
    lexer.makeError(join(msg))
    quit $lexer.getError

template empty[T](container: T): bool = container.len == 0

proc skipToken(lexer; expected: Token) =
  let found = lexer.readToken()
  if found != expected:
    lexer.fatal("Expected ", expected, " but found ", found)

proc readIdent(lexer): string =
  result = lexer.readIdentUnsafe()
  if result.empty:
    lexer.fatal("Expected ", IDENT, " but found ", lexer.readToken())

iterator readPaths(lexer; varsTables: varargs[Strtab]): string =
  var val = initEvalString()
  while true:
    val.parts.setLen(0)
    if not lexer.readPathUnsafe(addr val):
      quit $lexer.getError()
    if val.parts.empty():
      break
    yield val.eval(varsTables)

proc parseVar(lexer): tuple[name: string, val: EvalString] =
  result.name = lexer.readIdent()
  lexer.skipToken(EQUALS)
  result.val = initEvalString()
  if not lexer.readVarValueUnsafe(addr result.val):
    quit $lexer.getError()

proc parseRule(lexer) =
  var rule = Rule.new
  rule.name = lexer.readIdent()
  rule.vars = newOrderedTable[string, EvalString](1)

  lexer.skipToken(NEWLINE)
  while lexer.peekToken(INDENT):
    let (name, val) = lexer.parseVar()
    rule.vars[name] = val
  try:
    rules[rule.name] = rule
  except KeyError:
    lexer.fatal("Duplicate rule: " & rule.name)
  
proc parseTarget(lexer) =
  var target = newTarget()

  for path in lexer.readPaths(vars):
    target.outputs &= (path, oExplicit)
  if lexer.peekToken(PIPE):
    for path in lexer.readPaths(vars):
      target.outputs &= (path, oImplicit)
  if target.outputs.empty():
    lexer.fatal("Need an output")

  lexer.skipToken(COLON)
  var ruleName = lexer.readIdent()
  try:
    target.rule = rules[ruleName]
  except KeyError:
    lexer.fatal("Unknown rule: " & ruleName)

  for path in lexer.readPaths(vars):
    target.inputs &= (path, iExplicit)
  if lexer.peekToken(PIPE):
    for path in lexer.readPaths(vars):
      target.inputs &= (path, iImplicit)
  if lexer.peekToken(PIPE2):
    for path in lexer.readPaths(vars):
      target.inputs &= (path, iOrderOnly)

  lexer.skipToken(NEWLINE)
  while lexer.peekToken(INDENT):
    let (name, val) = lexer.parseVar()
    target.vars[name] = val.eval(target.vars, vars)
  targets &= target

proc magicVars(target): Strtab =
  let quoted_in =
    target.inputs.filterIt(it.kind == iExplicit)
                 .mapIt(it.path.quoteShell)
  let quoted_out =
    target.outputs.filterIt(it.kind == oExplicit)
                  .mapIt(it.path.quoteShell)
  result = initStrtab(4)
  result["in"] = join(quoted_in, " ")
  result["in_newlines"] = join(quoted_in, "\n")
  result["out"] = join(quoted_out, " ")

proc parseManifest(fileName: string) =
  proc loadFile(): string =
    result = readFile(fileName)
    result.shallow
    result.GC_ref # Keep file buffers alive to allow EvalString to hold views.
  let raw = loadFile()
  var lexer = constructLexer()
  lexer.start(fileName, raw)

  while true:
    let tok = lexer.readToken()
    case tok
    of TEOF: break
    of NEWLINE: continue
    of SUBNINJA:
      lexer.fatal("Not supported yet")
    of ERROR:
      quit $lexer.getError()
    of PIPE, PIPE2,INDENT, EQUALS, COLON:
      lexer.fatal("misplaced token " & $tok)
    of DEFAULT:
      var havePath = false
      for path in lexer.readPaths(vars):
        defaults &= path
        havePath = true
      if not havePath:
        lexer.fatal("Expected at least one path in `default` statement")

    of IDENT: # variable definition
      lexer.unreadToken()
      let (name, val) = lexer.parseVar()
      vars.add name, val.eval(vars)

    of POOL:
      let name = lexer.readIdent()
      lexer.skipToken(NEWLINE)
      lexer.skipToken(INDENT)
      let (depth, val) = lexer.parseVar()
      assert depth == "depth"
      pools[name] = parseInt(val.eval())

    of INCLUDE:
      block includeBlock:
        for file in lexer.readPaths(vars):
          parseManifest(file)
          lexer.skipToken(NEWLINE)
          break includeBlock
        lexer.fatal("Expected a path")
    of BUILD:
      lexer.parseTarget()
    of Token.RULE:
      lexer.parseRule()

when isMainModule:
  try:
    parseManifest(args.manifest)

    case args.tool
    of tNone:
      discard #TODO build stuff
    of tCommands:
      for t in targets:
        if t.rule.name != "phony":
          # TODO need to handle rule-vars referring to others,
          # but watch out for cycles!
          echo t.rule.vars["command"].eval(t.magicVars, t.vars, vars)
  except Exception as ex:
    stderr.write("Exception: " & $ex.name & ": " & ex.msg)
    quit getStackTrace(ex)
    quit 1

