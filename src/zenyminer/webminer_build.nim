# Copyright (c) 2025 zenywallet

import std/os
import std/osproc
import regex
import emsdkenv
import zenyjs/exec

const srcDir = currentSourcePath().parentDir()

const externs = """
var webminer_externs = {
  minerMod: {
    onRuntimeInitialized: function() {},
    preRun: [],
    postRun: [],
    print: function() {},
    printErr: function() {},
    setStatus: function() {},
    getExceptionMessage: function() {}
  },
  cwrap: function() {},
  ccall: function() {},
  _malloc: function() {},
  _free: function() {},
  stackSave: function() {},
  stackAlloc: function() {},
  stackRestore: function() {},
  UTF8ToString: function() {},
  HEAPU8: {},
  HEAPU32: {},
  buffer: 0
};

var MinerData = {
  header: {},
  target: {},
  nid: 0
};

var FindData = {
  cmd: {},
  data: {
    header: {},
    nid: {}
  }
};
"""

proc errCheck(errCode: int) =
  if errCode != 0:
    raise

proc exec(cmd: string) = errCheck execCmd(cmd)

template withDir(dir: string; body: untyped): untyped =
  let curDir = getCurrentDir()
  try:
    setCurrentDir(dir)
    body
  finally:
    setCurrentDir(curDir)

proc patch(file: string): string =
  var s = readFile(file)
  s = s.replace(re2"""class\s+ExitStatus\s*\{\s*name\s*=\s*"ExitStatus"\s*;\s*constructor\s*\(\s*status\s*\)\s*\{""",
    """class ExitStatus {
  constructor(status) {
    this.name = "ExitStatus";""")
  s

withDir srcDir:
  exec "nim js -d:release -o:webminer_loader.js webminer_loader.nim"
  emsdkEnv "nim c -d:release -d:emscripten -o:miner.js_tmp --mm:orc webminer.nim"
  emsdkEnv "nim c -d:release -d:emscripten -d:ENABLE_SIMD128 -o:miner-simd128.js_tmp --mm:orc webminer.nim"
  writeFile("miner.js", minifyJsCode(srcDir, patch("miner.js_tmp"), externs))
  writeFile("miner-simd128.js", minifyJsCode(srcDir, patch("miner-simd128.js_tmp"), externs))
  exec "rm miner-simd128.js_tmp"
  exec "rm miner.js_tmp"
  exec "rm webminer_loader.js"
