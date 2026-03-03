# Package

version       = "0.1.0"
author        = "zenywallet"
description   = "A native miner and web miner for BitZeny"
license       = "MIT"
srcDir        = "src"
installExt    = @["nim", "js"]
bin           = @["zenyminer"]


# Dependencies

requires "nim >= 2.2.4"
requires "zenycore"
requires "zenyjs"


task webminer, "Build webminer":
  exec "nim c -r --forceBuild src/zenyminer/webminer_build.nim"
  exec "rm src/zenyminer/webminer_build"

task webmining, "Build webmining":
  exec "nim c -r --forceBuild src/zenyminer/webmining_build.nim"
  exec "rm src/zenyminer/webmining_build"

before build:
  webminerTask()
  webminingTask()
