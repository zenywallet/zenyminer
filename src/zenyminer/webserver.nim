# Copyright (c) 2026 zenywallet

import caprese
import webmining_index

server(ssl = true, ip = "0.0.0.0", port = 8009):
  routes:
    get "/": response(content(IndexHtml, "html"))
    get "/mining.js": response(content(staticRead("mining.js"), "js"))
    get "/zenyjs.wasm": response(content(staticRead("zenyjs.wasm"), "wasm"))
    send("Not Found".addHeader(Status404))

serverStart()
