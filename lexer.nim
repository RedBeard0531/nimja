##  Copyright 2011 Google Inc. All Rights Reserved.
## 
##  Licensed under the Apache License, Version 2.0 (the "License");
##  you may not use this file except in compliance with the License.
##  You may obtain a copy of the License at
## 
##      http://www.apache.org/licenses/LICENSE-2.0
## 
##  Unless required by applicable law or agreed to in writing, software
##  distributed under the License is distributed on an "AS IS" BASIS,
##  WITHOUT WARRANTIES OR CONDITIONS OF ANY KIND, either express or implied.
##  See the License for the specific language governing permissions and
##  limitations under the License.

# Generated with c2nim on cpp-lexer.nin.h with extensive edits
type
  StringPiece {.importcpp: "StringPiece", header: "../cpp-lexer.in.h", bycopy.} = object
    str* {.importc: "str_".}: cstring
    len* {.importc: "len_".}: csize

  SimpleStringPiece* = object # Can't put StringPiece in EvalStringPart union.
    str*: cstring
    len*: csize

  EvalStringKind* = enum esText, esVar
  EvalStringPart = object
    case kind*: EvalStringKind
    of esText:
      when false:
        text*: SimpleStringPiece #TODO see if this is actually worth it vs gc string
      else:
        text*: string
    of esVar:
      varName*: string
  EvalString* {.exportc.} = object
    parts*: seq[EvalStringPart]
    
converter toSimpleStringPiece(sp: StringPiece): SimpleStringPiece {.used.} =
  SimpleStringPiece(str: cast[cstring](sp.str), len: sp.len)

proc constructStringPiece*(): StringPiece {.constructor,
    importcpp: "StringPiece(@)", header: "../cpp-lexer.in.h".}
converter constructStringPiece*(str: cstring): StringPiece {.constructor,
    importcpp: "StringPiece(@)", header: "../cpp-lexer.in.h".}
proc constructStringPiece*(str: cstring; len: csize): StringPiece {.constructor,
    importcpp: "StringPiece(@)", header: "../cpp-lexer.in.h".}
proc `==`*(this: StringPiece; other: StringPiece): bool {.noSideEffect,
    importcpp: "(# == #)", header: "../cpp-lexer.in.h".}

type
  Lexer* {.importcpp: "Lexer", header: "../cpp-lexer.in.h", byref.} = object ## / Skip past whitespace (called after each read token/ident/etc.).

# This can't be tagged as a constructor since it leads to Most Vexing Parse :(
proc constructLexer*(): Lexer {.importcpp: "Lexer(@)", header: "../cpp-lexer.in.h".}

type
  Token* {.size: sizeof(cint), importcpp: "Lexer::Token", header: "../cpp-lexer.in.h".} = enum
    ERROR, BUILD, COLON, DEFAULT, EQUALS, IDENT, INCLUDE, INDENT, NEWLINE, PIPE, PIPE2,
    POOL, RULE, SUBNINJA, TEOF


converter tokenName*(t: Token): cstring {.importcpp: "Lexer::TokenName(@)",
                                 header: "../cpp-lexer.in.h".}
proc tokenErrorHint*(expected: Token): cstring {.
    importcpp: "Lexer::TokenErrorHint(@)", header: "../cpp-lexer.in.h".}
proc describeLastError*(this: var Lexer): cstring {.importcpp: "DescribeLastError",
    header: "../cpp-lexer.in.h".}
proc start*(this: var Lexer; filename: StringPiece; input: StringPiece) {.
    importcpp: "Start", header: "../cpp-lexer.in.h".}
proc readToken*(this: var Lexer): Token {.importcpp: "ReadToken", header: "../cpp-lexer.in.h".}
proc unreadToken*(this: var Lexer) {.importcpp: "UnreadToken", header: "../cpp-lexer.in.h".}
proc peekToken*(this: var Lexer; token: Token): bool {.importcpp: "PeekToken",
    header: "../cpp-lexer.in.h".}
proc readIdentUnsafe*(this: var Lexer): StringPiece {.importcpp: "ReadIdent",
    header: "../cpp-lexer.in.h".}
proc readPathUnsafe*(this: var Lexer; path: ptr EvalString): bool {.importcpp: "ReadPath",
    header: "../cpp-lexer.in.h".}
proc readVarValueUnsafe*(this: var Lexer; value: ptr EvalString): bool {.
    importcpp: "ReadVarValue", header: "../cpp-lexer.in.h".}
proc makeError*(this: var Lexer; message: cstring) {.importcpp: "Error",
    header: "../cpp-lexer.in.h".}
proc getError*(this: Lexer): cstring {.noSideEffect, importcpp: "GetError",
                                   header: "../cpp-lexer.in.h".}

{.compile: "nimcache/cpp-lexer.cc"}

converter toString*(sp: StringPiece|SimpleStringPiece): string =
  result = newString(sp.len)
  result.shallow()
  copyMem(addr result[0], sp.str, sp.len)

proc `&=`*(str: var string, sp: StringPiece|SimpleStringPiece) =
  let offset = str.len
  str.setlen(offset + sp.len)
  copyMem(addr str[offset], sp.str, sp.len)

converter toStringPiece*(str: string): StringPiece =
  result.str = str
  result.len = str.len

proc addText(eval: ptr EvalString, text: StringPiece) {.exportc: "AddText".} =
  eval.parts &= EvalStringPart(kind: esText, text: text)
proc addSpecial(eval: ptr EvalString, text: StringPiece) {.exportc: "AddSpecial".} =
  eval.parts &= EvalStringPart(kind: esVar, varName: text)

proc initEvalString*(): EvalString =
  result.parts = @[]
  result.parts.shallow
