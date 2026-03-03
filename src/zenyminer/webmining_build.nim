# Copyright (c) 2025 zenywallet

import std/os
import std/osproc
import emsdkenv
import zenyjs
import zenyjs/exec
import zenyjs/zenyjs_externs

const srcDir = currentSourcePath().parentDir()

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

withDir srcDir:
  exec "nim js -d:release --mm:orc -o:mining.js_tmp webmining.nim"
  let minJs = minifyJsCode(srcDir, readFile("mining.js_tmp"), ZenyJsExterns)
  writeFile("mining.js", minJs)
  writeFile("zenyjs.wasm", ZenyWasm)
  exec "rm mining.js_tmp"
