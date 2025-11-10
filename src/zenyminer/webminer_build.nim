# Copyright (c) 2025 zenywallet

import std/os
import std/osproc
import emsdkenv

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
  exec "nim js -d:release -o:webminer_loader.js webminer_loader.nim"
  exec "nim js -d:release -d:nodejs -o:webminer_externs.js webminer_externs.nim"
  emsdkEnv "nim c -d:release -d:emscripten -o:public/miner.js_tmp --mm:orc webminer.nim"
  emsdkEnv "nim c -d:release -d:emscripten -d:ENABLE_SIMD128 -o:public/miner-simd128.js_tmp --mm:orc webminer.nim"
  exec "nim c -r webminer_patch.nim"
  exec "rm webminer_patch"
  exec """
if [ -x "$(command -v google-closure-compiler)" ]; then
  closure_compiler="google-closure-compiler"
else
  closure_compiler="java -jar $(ls closure-compiler-*.jar | sort -r | head -n1)"
fi
echo "use $closure_compiler"
$closure_compiler --compilation_level ADVANCED --jscomp_off=checkVars --jscomp_off=checkTypes --jscomp_off=uselessCode --js_output_file=public/miner.js --externs webminer_externs.js public/miner.js_tmp 2>&1 | cut -c 1-240
$closure_compiler --compilation_level ADVANCED --jscomp_off=checkVars --jscomp_off=checkTypes --jscomp_off=uselessCode --js_output_file=public/miner-simd128.js --externs webminer_externs.js public/miner-simd128.js_tmp 2>&1 | cut -c 1-240
"""
  exec "rm public/miner-simd128.js_tmp"
  exec "rm public/miner.js_tmp"
  exec "rm webminer_externs.js"
  exec "rm webminer_loader.js"
