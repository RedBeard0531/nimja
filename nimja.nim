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
type RuleVars = OrderedTableRef[string, EvalString]
proc initRuleVars(): RuleVars = newOrderedTable[string, EvalString](1)

type
  Target = ref TargetObj
  TargetObj = object
    inputs*: seq[string]
    implicits*: seq[string]
    order_only*: seq[string]
    outputs*: seq[string]
    implicit_outs*: seq[string]
    rule*: string
    vars*: Strtab
    command: string

var
  vars: Strtab = initStrtab()
  defaults: seq[string] = @[]
  pools = initOrderedTable[string, int]()
  targets: seq[Target] = @[]
  rules = initOrderedTable[string, RuleVars]()

proc newTarget(): Target =
  result.new
  result.inputs = @[]
  result.implicits = @[]
  result.order_only = @[]
  result.outputs = @[]
  result.implicit_outs = @[]
  result.rule = ""
  result.vars = initStrtab()
  result.command = ""

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

proc fatal(lexer: var Lexer, msg: varargs[string, `$`]) {.noreturn.} =
    lexer.makeError(join(msg))
    quit $lexer.getError

template empty[T](container: T): bool = container.len == 0

proc skipToken(lexer: var Lexer, expected: Token) =
  let found = lexer.readToken()
  if found != expected:
    lexer.fatal("Expected ", expected, " but found ", found)

proc readIdent(lexer: var Lexer): string =
  result = lexer.readIdentUnsafe()
  if result.empty:
    lexer.fatal("Expected ", IDENT, " but found ", lexer.readToken())

iterator readPaths(lexer: var Lexer, varsTables: varargs[Strtab]): string =
  var val = initEvalString()
  while true:
    val.parts.setLen(0)
    if not lexer.readPathUnsafe(addr val):
      quit $lexer.getError()
    if val.parts.empty():
      break
    yield val.eval(varsTables)

proc parseVar(lexer: var Lexer): tuple[name: string, val: EvalString] =
  result.name = lexer.readIdent()
  lexer.skipToken(EQUALS)
  result.val = initEvalString()
  if not lexer.readVarValueUnsafe(addr result.val):
    quit $lexer.getError()

proc parseRule(lexer: var Lexer) =
  var ruleVars = initRuleVars()
  let name = lexer.readIdent()
  lexer.skipToken(NEWLINE)
  while lexer.peekToken(INDENT):
    let (name, val) = lexer.parseVar()
    ruleVars[name] = val
  rules[name] = ruleVars
  
proc parseTarget(lexer: var Lexer) =
  var target = newTarget()

  for path in lexer.readPaths(vars):
    target.outputs &= path
  if lexer.peekToken(PIPE):
    for path in lexer.readPaths(vars):
      target.implicit_outs &= path
  lexer.skipToken(COLON)

  if target.outputs.empty() and target.implicit_outs.empty():
    lexer.fatal("Need an output")

  target.rule = lexer.readIdent()

  for path in lexer.readPaths(vars):
    target.inputs &= path
  if lexer.peekToken(PIPE):
    for path in lexer.readPaths(vars):
      target.implicits &= path
  if lexer.peekToken(PIPE2):
    for path in lexer.readPaths(vars):
      target.order_only &= path
  lexer.skipToken(NEWLINE)

  while lexer.peekToken(INDENT):
    let (name, val) = lexer.parseVar()
    target.vars[name] = val.eval(target.vars, vars)

  if target.rule != "phony":
    let rule = rules[target.rule]
    var extra_vars = initStrtab(4)
    let quoted_in = target.inputs.map(quoteShell)
    vars["in"] = join(quoted_in, " ")
    vars["in_newlines"] = join(quoted_in, "\n")
    vars["out"] = join(target.outputs.map(quoteShell), " ")

    target.command = rule["command"].eval(extra_vars, target.vars, vars)

  targets &= target

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
    of RULE:
      lexer.parseRule()

when isMainModule:
  try:
    parseManifest(args.manifest)

    case args.tool
    of tNone:
      discard #TODO build stuff
    of tCommands:
      for t in targets:
        echo t.command # TODO consider targets and order
  except Exception as ex:
    stderr.write("Exception: " & $ex.name & ": " & ex.msg)
    quit getStackTrace(ex)
    quit 1

