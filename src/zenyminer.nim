# Copyright (c) 2025 zenywallet

import std/posix
import zenyminer/mining

onSignal(SIGINT, SIGTERM):
  echo "bye from signal ", sig
  mining.doAbort()

signal(SIGPIPE, SIG_IGN)

try:
  mining.main()
except:
  let e = getCurrentException()
  echo e.name, ": ", e.msg
