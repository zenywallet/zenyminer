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


import emsdkenv

task webminer, "Build web miner":
  exec "nim js -d:release -o:src/zenyminer/web_miner_loader.js src/zenyminer/web_miner_loader.nim"
  exec "nim js -d:release -d:nodejs -o:src/zenyminer/web_miner_externs.js src/zenyminer/web_miner_externs.nim"
  emsdkEnv "nim c -d:release -d:emscripten -o:public/miner.js_tmp --mm:orc src/zenyminer/web_miner.nim"
  emsdkEnv "nim c -d:release -d:emscripten -d:ENABLE_SIMD128 -o:public/miner-simd128.js_tmp --mm:orc src/zenyminer/web_miner.nim"
  exec "nim c -r src/zenyminer/web_miner_patch.nim"
  exec "rm src/zenyminer/web_miner_patch"
  exec """
if [ -x "$(command -v google-closure-compiler)" ]; then
  closure_compiler="google-closure-compiler"
else
  closure_compiler="java -jar $(ls closure-compiler-*.jar | sort -r | head -n1)"
fi
echo "use $closure_compiler"
$closure_compiler --compilation_level ADVANCED --jscomp_off=checkVars --jscomp_off=checkTypes --jscomp_off=uselessCode --js_output_file=public/miner.js --externs src/zenyminer/web_miner_externs.js public/miner.js_tmp 2>&1 | cut -c 1-240
$closure_compiler --compilation_level ADVANCED --jscomp_off=checkVars --jscomp_off=checkTypes --jscomp_off=uselessCode --js_output_file=public/miner-simd128.js --externs src/zenyminer/web_miner_externs.js public/miner-simd128.js_tmp 2>&1 | cut -c 1-240
"""
  exec "rm public/miner-simd128.js_tmp"
  exec "rm public/miner.js_tmp"
  exec "rm src/zenyminer/web_miner_externs.js"
  exec "rm src/zenyminer/web_miner_loader.js"
