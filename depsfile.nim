# This is based on ninja's depfile_parser.in.cc
import strutils
import sequtils
import algorithm

when defined(useSSE42):
  import x86_simd/x86_sse42
  import x86_simd/x86_sse41
  import x86_simd/x86_sse2
  import bitops

  let prStr = "azAZ09\x80\xFF\0                 " # padded to hold at least 16 bytes.
  let pcStr = "+,/_:.~()}{@=!-\0                "
  let plain_ranges = loadu_si128(cast[ptr m128i](unsafeAddr prStr[0]))
  let plain_chars = loadu_si128(cast[ptr m128i](unsafeAddr pcStr[0]))

const
  plain = {'a'..'z', 'A'..'Z', '0'..'9', '+', ',', '/', '_', ':', '.', '~',
           '(', ')', '}', '{', '@', '=', '!', '-', '\x80'..'\xFF'}
  escaped = {' ', '\\', '#', '*', '[', '|'} # \c -> c
  notEscaped = {'\0', '\c', '\L'} # swallow the \ and handle c normally

type Deps* = object
  output*: string
  inputs*: seq[string]

proc parseDeps*(s: string): Deps =
  result.inputs = @[]

  var
    haveColon = false
    curStr = newStringOfCap(64)
    i = 0

  while true:
    let c = s[i]
    inc i
    case c
    of plain:
      let begin = i-1
      block findPlainRange:
        when defined(useSSE42):
          if s.len-i >= 16:
            while s.len-i >= 16:
              let vec = loadu_si128(cast[ptr m128i](unsafeAddr s[i]))
              const commonFlags = SIDD_NEGATIVE_POLARITY or SIDD_UNIT_MASK
              let rMask = cmpistrm(plain_ranges, vec, SIDD_CMP_RANGES or commonFlags)
              let pMask = cmpistrm(plain_chars, vec, SIDD_CMP_EQUAL_ANY or commonFlags)
              if not testz_si128(rMask, pMask).bool:
                let mask = and_si128(rMask, pMask)
                let bits = movemask_epi8(mask)
                i += bits.countTrailingZeroBits
                break findPlainRange
              i += 16
        while s[i] in plain: inc i
      curStr &= s[begin..<i]
    of '\\':
      if s[i] in escaped:
        curStr &= s[i]
        inc i
      elif s[i] in notEscaped:
        discard # swallow the '\'
      else:
        curStr &= c # Use the '\' as a normal char
                    # TODO consider normalizing to '/' here
    of '$':
      if s[i] == '$':
        curStr &= c
        inc i
    else:
      curStr.shallow
      let isTarget = not haveColon
      if curStr.len > 0 and curStr[^1] == ':':
        if haveColon:
          echo "Warning: ignoring last colon in '" & curStr & '\''
        curStr.setLen(curStr.len-1)
        haveColon = true

      if curStr.len == 0:
        if c == '\0': break
        continue

      if isTarget:
        if not result.output.isNil:
          raise newException(Exception, "multiple outputs in depfile not supported")
        result.output = curStr
      else:
        result.inputs &= curStr
      if c == '\0': break
      curStr = newStringOfCap(64)

  if not haveColon:
    raise newException(Exception, "no colon in deps file")

when isMainModule:
  import sets
  import os

  var seen = initSet[string]()

  let files = commandLineParams()
  doAssert files.len > 0

  for f in files:
    let deps = f.readFile.parseDeps
    if files.len == 0:
      echo $deps
    for input in deps.inputs:
      if not seen.containsOrIncl input:
        if input.fileExists:
          discard input.getLastModificationTime()
        
