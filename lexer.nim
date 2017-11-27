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

import utils

type
  StringPiece {.importcpp: "StringPiece", header: "../cpp-lexer.in.h", bycopy.} = object
    str* {.importc: "str_".}: cstring
    len* {.importc: "len_".}: csize

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

converter toSimpleStringPiece(sp: StringPiece): SimpleStringPiece  =
  SimpleStringPiece(str: sp.str, len: sp.len)

converter `$`*(sp: StringPiece): string =
  $sp.toSimpleStringPiece()

converter toStringPiece*(str: string): StringPiece =
  result.str = str
  result.len = str.len

proc addTextWrapper(eval: ptr EvalString, text: StringPiece) {.exportc: "AddText".} =
  eval.addText(text)
proc addSpecialWrapper(eval: ptr EvalString, text: StringPiece) {.exportc: "AddSpecial".} =
  eval.addSpecial(text)
