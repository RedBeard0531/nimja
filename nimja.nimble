# Package
include "config.nims"

version       = "0.1.0"
author        = "Mathias Stearn"
description   = "ninja build system in nim = nimja!"
license       = "Apache-2.0"

bin = @["nimja"]
backend = "cpp"

# Dependencies

requires "nim >= 0.17.2"
requires "docopt"

before build:
  exec "nim re2c"

