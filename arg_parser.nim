import docopt

let help = """nimja builds things

Usage:
  nimja [options] [<targets> ...]
  nimja [options] --help

  If no targets are specified, it will build all default targets
  declared in the manifest

Options:
  -f FILE    path to build manifest [default: build.ninja]
  -h --help  show this help
"""

type Args = object
  manifest*: string
  targets*: seq[string]
  

proc parseArgs(): Args =
  let rawArgs = docopt help
  when defined(debugArgParse):
    quit $rawArgs

  result.manifest = $rawArgs["-f"]
  result.targets = @(rawArgs["<targets>"])

let args* = parseArgs()
