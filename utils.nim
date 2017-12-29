import tables
import strutils
import sequtils
import times
import patty

export tables # needed to do anything with Vars

template empty*[T](container: T): bool = container.len == 0

type
  Vars* = OrderedTableRef[string, string]

  SimpleStringPiece* = object # Can't put StringPiece in EvalStringPart union.
    str*: pointer
    len*: csize

  EvalStringKind = enum esText, esVar
  EvalStringPart = object
    case kind: EvalStringKind
    of esText:
      when false:
        text: SimpleStringPiece #TODO see if this is actually worth it vs gc string
      else:
        text: string
    of esVar:
      varName: string

  EvalString* {.exportc.} = object
    parts: seq[EvalStringPart]

variantp MTime:
  Oldest
  Known(mtime: Time)
  Newest

proc `<`*(a,b: MTime): bool {.inline.} =
  if a.kind != b.kind:
    return a.kind < b.kind
  if a.kind == MTimeKind.Known:
    return a.mtime < b.mtime
  return false # equal Oldest or Newest

proc `<=`*(a,b: MTime): bool {.inline.} =
  if a.kind != b.kind:
    return a.kind <= b.kind
  if a.kind == MTimeKind.Known:
    return a.mtime <= b.mtime
  return true # equal Oldest or Newest

proc newStrtab*(cap=1): Vars = newOrderedTable[string, string](cap)

proc `&=`(str: var string, sp: SimpleStringPiece) {.used.} =
  let offset = str.len
  str.setlen(offset + sp.len)
  copyMem(addr str[offset], sp.str, sp.len)

proc `$`*(sp: SimpleStringPiece): string =
  result = newStringOfCap(sp.len)
  result.shallow()
  result &= sp

proc initEvalString*(): EvalString =
  result.parts = @[]
  result.parts.shallow

proc addText*(eval: ptr EvalString, text: SimpleStringPiece) =
  eval.parts &= EvalStringPart(kind: esText, text: $text)
proc addSpecial*(eval: ptr EvalString, text: SimpleStringPiece) =
  eval.parts &= EvalStringPart(kind: esVar, varName: $text)

proc empty*(es: EvalString): bool = es.parts.empty

proc eval*(es: EvalString, varsTables: varargs[Vars]): string =
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
        echo "WARNING: undefined var $" & part.varName
