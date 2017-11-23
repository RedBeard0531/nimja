// Copyright 2011 Google Inc. All Rights Reserved.
//
// Licensed under the Apache License, Version 2.0 (the "License");
// you may not use this file except in compliance with the License.
// You may obtain a copy of the License at
//
//     http://www.apache.org/licenses/LICENSE-2.0
//
// Unless required by applicable law or agreed to in writing, software
// distributed under the License is distributed on an "AS IS" BASIS,
// WITHOUT WARRANTIES OR CONDITIONS OF ANY KIND, either express or implied.
// See the License for the specific language governing permissions and
// limitations under the License.

// NIMJA NOTE:
// Taken directly from the original C++ codebase and very lightly modified.

#ifndef NINJA_LEXER_H_
#define NINJA_LEXER_H_

#include <string>
#include <cstring>

/// StringPiece represents a slice of a string whose memory is managed
/// externally.  It is useful for reducing the number of std::strings
/// we need to allocate.
struct StringPiece {
  typedef const char* const_iterator;

  StringPiece() : str_(NULL), len_(0) {}

  /// The constructors intentionally allow for implicit conversions.
  StringPiece(const std::string& str) : str_(str.data()), len_(str.size()) {}
  StringPiece(const char* str) : str_(str), len_(strlen(str)) {}

  StringPiece(const char* str, size_t len) : str_(str), len_(len) {}

  bool operator==(const StringPiece& other) const {
    return len_ == other.len_ && memcmp(str_, other.str_, len_) == 0;
  }
  bool operator!=(const StringPiece& other) const {
    return !(*this == other);
  }

  /// Convert the slice into a full-fledged std::string, copying the
  /// data into a new string.
  std::string AsString() const {
    return len_ ? std::string(str_, len_) : std::string();
  }

  const_iterator begin() const {
    return str_;
  }

  const_iterator end() const {
    return str_ + len_;
  }

  char operator[](size_t pos) const {
    return str_[pos];
  }

  size_t size() const {
    return len_;
  }

  const char* str_;
  size_t len_;
};

// Windows may #define ERROR.
#ifdef ERROR
#undef ERROR
#endif

struct EvalString;

struct Lexer {
  Lexer() {}
  /// Helper ctor useful for tests.
  explicit Lexer(const char* input);

  enum Token {
    ERROR,
    BUILD,
    COLON,
    DEFAULT,
    EQUALS,
    IDENT,
    INCLUDE,
    INDENT,
    NEWLINE,
    PIPE,
    PIPE2,
    POOL,
    RULE,
    SUBNINJA,
    TEOF,
  };

  /// Return a human-readable form of a token, used in error messages.
  static const char* TokenName(Token t);

  /// Return a human-readable token hint, used in error messages.
  static const char* TokenErrorHint(Token expected);

  /// If the last token read was an ERROR token, provide more info
  /// or the empty string.
 
  const char* DescribeLastError();

  /// Start parsing some input.
  void Start(StringPiece filename, StringPiece input);

  /// Read a Token from the Token enum.
  Token ReadToken();

  /// Rewind to the last read Token.
  void UnreadToken();

  /// If the next token is \a token, read it and return true.
  bool PeekToken(Token token);

  /// Read a simple identifier (a rule or variable name).
  /// Returns false if a name can't be read.
  StringPiece ReadIdent();

  /// Read a path (complete with $escapes).
  /// Returns false only on error, returned path may be empty if a delimiter
  /// (space, newline) is hit.
  bool ReadPath(EvalString* path) {
    return ReadEvalString(path, true);
  }

  /// Read the value side of a var = value line (complete with $escapes).
  /// Returns false only on error.
  bool ReadVarValue(EvalString* value) {
    return ReadEvalString(value, false);
  }

  /// Construct an error message with context.
  bool Error(const char* message);

  
  // Yucky const cast :(
  char* GetError() const {
      return err.empty()? NULL : const_cast<char*>(err.c_str());
  }

private:
  /// Skip past whitespace (called after each read token/ident/etc.).
  void EatWhitespace();

  /// Read a $-escaped string.
  bool ReadEvalString(EvalString* eval, bool path);

  StringPiece filename_;
  StringPiece input_;
  const char* ofs_;
  const char* last_token_;
  std::string err;
};

#endif // NINJA_LEXER_H_
