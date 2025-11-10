# Package

version       = "0.1.0"
author        = "zenywallet"
description   = "A native miner and web miner for BitZeny"
license       = "MIT"
srcDir        = "src"
installExt    = @["nim"]
bin           = @["zenyminer"]


# Dependencies

requires "nim >= 2.2.4"
requires "zenycore"
requires "zenyjs"


task webminer, "Build webminer":
  exec "nim c -r src/zenyminer/webminer_build.nim"
  exec "rm src/zenyminer/webminer_build"
