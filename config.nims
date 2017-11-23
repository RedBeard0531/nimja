task build, "build nimja":
  exec "nim re2c"
  setCommand "cpp"

task re2c, "generate the cpp-lexer.in.cc file":
  exec "mkdir -p nimcache"
  exec "re2c -b cpp-lexer.in.cc -o nimcache/cpp-lexer.cc"

task clean, "delete the nimcache dir":
  exec "rm -r nimcache"

