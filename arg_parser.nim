import docopt

let help = """nimja builds things

Usage:
  nimja [options] [<targets> ...]
  nimja [options] --help
  nimja [options] -t commands [<targets> ...]

  If no targets are specified, it will build all default targets
  declared in the manifest

Options:
  -C DIR         cd to this directory before doing anything else
  -f FILE        path to build manifest [default: build.ninja]
  -h --help      show this help

  -t commands    print all commands that would be executed
                 to build targets without building anything
"""

type Tool* = enum
  tNone,
  tCommands

type Args = object
  manifest*: string
  dir*: string
  targets*: seq[string]
  case tool*: Tool
  of tNone, tCommands:
    discard # No tool-specific args

proc parseArgs(): Args =
  let rawArgs = docopt help
  when defined(debugArgParse):
    quit $rawArgs
  result.manifest = $rawArgs["-f"]
  result.manifest = $rawArgs["-f"]
  result.targets = @(rawArgs["<targets>"])

  if rawArgs["-C"]:
    result.dir = $rawArgs["-C"]

  if rawArgs["-t"]:
    case $rawArgs["-t"]
    of "commands":
      result.tool = tCommands
    else:
      quit "Unknown tool " & $rawArgs["-t"]

let args* = parseArgs()
