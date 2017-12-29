{.experimental.} # automatic deference first param

import lexer as lexmod
import tables
import strutils
import sequtils
import utils
import asyncdispatch

type
  Rule* = ref object
    vars*: OrderedTableRef[string, EvalString]
    name*: string

  InputKind* = enum iExplicit, iImplicit, iOrderOnly
  OutputKind* = enum oExplicit, oImplicit
  Input* = tuple[path: string, kind: InputKind]
  Output* = tuple[path: string, kind: OutputKind]

  BuildAction* = ref BuildActionObj
  BuildActionObj* = object
    inputs*: seq[Input]
    outputs*: seq[Output]
    rule*: Rule
    vars*: Vars
    # The rest are states for execution.
    # TODO pull out to separate class?
    executed*: bool
    seen*: bool
    run*: Future[void]

  Manifest* = ref ManifestObj
  ManifestObj* = object
    vars*: Vars
    defaults*: seq[string]
    pools*: OrderedTable[string, int]
    actions*: seq[BuildAction]
    rules*: Table[string, Rule]

proc newManifest(): Manifest =
  result.new
  result.vars = newStrtab()
  result.defaults = @[]
  result.pools = initOrderedTable[string, int]()
  result.actions = @[]
  result.rules = {"phony": Rule(name: "phony")}.toTable

proc newBuildAction(): BuildAction =
  result.new
  result.inputs = @[]
  result.outputs = @[]
  result.vars = newStrtab()

using
  lexer: var Lexer
  manifest: Manifest
  action: BuildAction

proc fatal(lexer; msg: varargs[string, `$`]) {.noreturn.} =
  {.breakpoint.}
  when not defined(release):
    let ex = getCurrentException()
    if ex != nil:
      stdout.writeLine ex.getStackTrace()
    else:
      writeStackTrace()
  lexer.makeError(join(msg))
  quit $lexer.getError

proc skipToken(lexer; expected: Token) =
  let found = lexer.readToken()
  if found != expected:
    lexer.fatal("Expected ", expected, " but found ", found)

proc readIdent(lexer): string =
  result = $lexer.readIdentUnsafe()
  if result.empty:
    lexer.fatal("Expected ", IDENT, " but found ", lexer.readToken())

iterator readPaths(lexer; varsTables: varargs[Vars]): string =
  while true:
    var val = initEvalString()
    if not lexer.readPathUnsafe(addr val):
      quit $lexer.getError()
    if val.empty():
      break
    yield val.eval(varsTables)

proc parseVar(lexer): tuple[name: string, val: EvalString] =
  result.name = lexer.readIdent()
  lexer.skipToken(EQUALS)
  result.val = initEvalString()
  if not lexer.readVarValueUnsafe(addr result.val):
    quit $lexer.getError()

proc parseRule(lexer): Rule =
  result.new
  result.name = lexer.readIdent()
  result.vars = newOrderedTable[string, EvalString](1)

  lexer.skipToken(NEWLINE)
  while lexer.peekToken(INDENT):
    let (name, val) = lexer.parseVar()
    result.vars[name] = val
  
proc parseAction(lexer, manifest) =
  var action = newBuildAction()

  for path in lexer.readPaths(manifest.vars):
    action.outputs &= (path, oExplicit)
  if lexer.peekToken(PIPE):
    for path in lexer.readPaths(manifest.vars):
      action.outputs &= (path, oImplicit)
  if action.outputs.empty():
    lexer.fatal("Need an output")

  lexer.skipToken(COLON)
  var ruleName = lexer.readIdent()
  try:
    action.rule = manifest.rules[ruleName]
  except KeyError:
    lexer.fatal("Unknown rule: " & ruleName)

  for path in lexer.readPaths(manifest.vars):
    action.inputs &= (path, iExplicit)
  if lexer.peekToken(PIPE):
    for path in lexer.readPaths(manifest.vars):
      action.inputs &= (path, iImplicit)
  if lexer.peekToken(PIPE2):
    for path in lexer.readPaths(manifest.vars):
      action.inputs &= (path, iOrderOnly)

  lexer.skipToken(NEWLINE)
  while lexer.peekToken(INDENT):
    let (name, val) = lexer.parseVar()
    action.vars[name] = val.eval(action.vars, manifest.vars)
  manifest.actions &= action

proc parseManifestImpl(manifest; fileName: string) =
  proc loadFile(): string =
    result = readFile(fileName)
    result.shallow
    result.GC_ref # Keep file buffers alive to allow EvalString to hold views.
  let raw = loadFile()
  var lexer = constructLexer()
  lexer.start(fileName, raw)

  try:
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
        for path in lexer.readPaths(manifest.vars):
          manifest.defaults &= path
          havePath = true
        if not havePath:
          lexer.fatal("Expected at least one path in `default` statement")

      of IDENT: # variable definition
        lexer.unreadToken()
        let (name, val) = lexer.parseVar()
        manifest.vars.add name, val.eval(manifest.vars)

      of POOL:
        let name = lexer.readIdent()
        lexer.skipToken(NEWLINE)
        lexer.skipToken(INDENT)
        let (depth, val) = lexer.parseVar()
        assert depth == "depth"
        manifest.pools[name] = parseInt(val.eval())

      of INCLUDE:
        block includeBlock:
          for file in lexer.readPaths(manifest.vars):
            parseManifestImpl(manifest, file)
            lexer.skipToken(NEWLINE)
            break includeBlock
          lexer.fatal("Expected a path")
      of BUILD:
        lexer.parseAction(manifest)
      of Token.RULE:
        let rule = lexer.parseRule()
        try: manifest.rules[rule.name] = rule
        except KeyError: lexer.fatal("Duplicate rule: " & rule.name)
  except Exception as ex:
    lexer.fatal($ex.name & ": " & ex.msg)

proc parseManifest*(fileName: string): Manifest =
  result = newManifest()
  result.parseManifestImpl(fileName)
