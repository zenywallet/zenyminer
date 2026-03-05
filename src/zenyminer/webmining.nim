# Copyright (c) 2022 zenywallet

import zenyjs
import jsffi except `.=`
import zenyjs/jslib
import asyncjs
import zenyjs/arraylib
import json
import strformat
import times
import zenyjs/deoxy

import os, macros

const WEBSOCKET_PROTOCOL = "deoxy-0.1"
const WEBSOCKET_ENTRY_URL = "wss://localhost:8000/ws"

import zenyjs/config
networksDefault()

import zenyjs/address
include karax / prelude


{.experimental: "dotOperators".}
macro `.=`*(obj: JsObject, field, value: untyped): untyped =
  let importString = "#." & $field & " = #"
  result = quote do:
    proc helper(o: JsObject, v: auto)
      {.importjs: `importString`, gensym.}
    helper(`obj`, `value`)


proc jq(selector: cstring): JsObject {.importcpp: "$$(#)".}
template fmtj(pattern: static string): untyped = fmt(pattern, '<', '>')


import strutils

proc convCoin(val: string): string =
  if val.len > 8:
    result = val[0..^9] & "." & val[^8..^1]
  else:
    result = (parseFloat(val) / 100000000).formatFloat(ffDecimal, 8)
  result.trimZeros()

proc convCoin(val: JsonNode): string =
  let kind = val.kind
  if kind == JsonNodeKind.JInt:
    result = convCoin($val.getBiggestInt)
  elif kind == JsonNodeKind.JString:
    result = convCoin(val.getStr)


type Notify = enum
  Success
  Error
  Warning
  Info

const NotifyVal = [Success: "success".cstring, Error: "error".cstring,
                  Warning: "warning".cstring, Info: "info".cstring]

proc show(notify: Notify, msg: cstring, tag: string = "", infinite: bool = false) =
  let notifyVal = NotifyVal[notify]
  jq("body").toast(JsObject{
    title: ($notify).cstring,
    message: msg,
    class: notifyVal,
    className: JsObject{
      toast: (if tag.len > 0: ("ui message " & tag).cstring else: "ui message".cstring)
    },
    displayTime: (if infinite: 0 else: 5000)
  })

proc clearNotify(tag: string = "") =
  jq((".ui.message" & (if tag.len > 0: "." & tag else: "")).cstring).toast("close")


var appInst: KaraxInstance
var noraList: seq[string]
var activeNid: int
var statusDatas: JsonNode = %*{}
var blockDatas: JsonNode = %*{}
var addressDatas: JsonNode = %*{}
var addrlogDatas: JsonNode = %*{}
var miningAddress: string = ""
var miningAddressValid = false
var miningActive = false
var cpuCount: int
var cpuMaxCount: int
var cpuMaxCountUnknown: bool = false
var optimizedId: int
var miningWorkers = [].toJs
var miningWorkersNumber = [].toJs
var miningStatus = JsObject{}
var miningData: JsObject
var miningHashRate: int
var miningHashRateWaiting: bool
var miningPendingFinds = [].toJs
var tvalMiningDataUpdater: int
var connectionError = false
var pageUnload = false
var stream = new Deoxy

import std/base64
macro constMinerScripts(): untyped =
  var scriptNames = ["miner.js", "miner-simd128.js"]
  var bracket = nnkBracket.newTree()
  for name in scriptNames:
    var srcBin = encode(staticRead(currentSourcePath().parentDir() / name))
    bracket.add(newLit("data:application/javascript;base64," & srcBin))
  bracket

const minerScripts = constMinerScripts()

try:
  cpuMaxCount = window.navigator.hardwareConcurrency.to(int)
  if cpuMaxCount.toJs == jsNull:
    raise newException(CatchableError, "")
  cpuCount = cpuMaxCount
except:
  cpuCount = 4
  cpuMaxCount = 16
  cpuMaxCountUnknown = true

let cpuMaxCountStr = $cpuMaxCount

proc changeMiningWorker(num: int) =
  miningWorkersNumber.push(num)
  var req: JsObject
  while 0 < miningWorkersNumber.length.to(int):
    req = miningWorkersNumber.shift()
  if not req.isNil:
    while req.to(int) < miningWorkers.length.to(int):
      let worker = miningWorkers.pop()
      let id = worker.id.to(cstring)
      discard jsDelete(miningStatus[id])
      worker.terminate()
    while req.to(int) > miningWorkers.length.to(int):
      let worker = newWorker(cstring(minerScripts[optimizedId]))
      worker.onerror = proc(e: JsObject) = console.dir(e)
      worker.id = miningWorkers.length
      worker.readyFlag = false
      worker.started = false
      {.push warning[Deprecated]: off.}
      worker.onmessage = bindMethod proc(this: JsObject, e: JsObject) =
        if e.data["cmd"].to(cstring) == "find".cstring:
          let findData = strToUint8Array(JSON.stringify(e.data))
          let retSend = stream.send(findData)
          if not retSend:
            miningPendingFinds.push(findData)
        elif e.data["cmd"].to(cstring) == "status".cstring:
          miningStatus[this.id.to(cstring)] = e.data["data"]
        elif e.data["cmd"].to(cstring) == "ready".cstring:
          this.readyFlag = true
      {.pop.}
      miningWorkers.push(worker)

let number0x100000000 = (0x7fffffff.toJs + 1.toJs) * 2.toJs
proc postMiningData() =
  var nonce =
    if not window.crypto.isNil and not window.crypto.getRandomValues.isNil:
      let seedData = newUint8Array(4)
      window.crypto.getRandomValues(seedData)
      let dataView = newDataView(seedData.buffer)
      dataView.getUint32(0, false)
    else:
      Math.floor(Math.random() * number0x100000000)
  let step = Math.round(number0x100000000 / miningWorkers.length)
  for worker in items(miningWorkers):
    miningData.nonce = nonce
    worker.postMessage(miningData)
    worker.started = true
    nonce = (nonce + step) % number0x100000000

proc startMiningDataUpdater() =
  var allReady = true
  for worker in items(miningWorkers):
    if not worker.readyFlag.to(bool):
      allReady = false
      break
  if allReady:
    var allStarted = true
    for worker in items(miningWorkers):
      if not worker.started.to(bool):
        allStarted = false
    if not allStarted:
      if not miningData.isNil:
        postMiningData()

  var total = 0.toJs
  for val in items(miningStatus):
    total += val
  let totalSec = Math.round(total).to(int)
  if miningHashRate != totalSec:
    miningHashRate = totalSec
    miningHashRateWaiting = false
    appInst.redraw()

  tvalMiningDataUpdater = setTimeout(startMiningDataUpdater, 1000)

proc stopMiningDataUpdater() =
  clearTimeout(tvalMiningDataUpdater)
  miningHashRate = 0
  miningHashRateWaiting = false
  appInst.redraw()

proc onRate(value: int) =
  cpuCount = value
  miningAddressValid = checkAddress(activeNid.NetworkId, miningAddress.cstring)
  if miningActive and miningAddressValid:
    changeMiningWorker(cpuCount)
  appInst.redraw()

proc onOptimizeChange() =
  optimizedId = jq("input:radio[name='optimize']:checked").val().to(cstring).parseInt
  changeMiningWorker(0)
  miningAddressValid = checkAddress(activeNid.NetworkId, miningAddress.cstring)
  if miningActive and miningAddressValid:
    changeMiningWorker(cpuCount)

proc afterScript(data: RouterData) =
  jq("#mining .mining.checkbox").checkbox()
  jq("#mining .optimize .checkbox").checkbox(JsObject{onChange: onOptimizeChange})
  jq("#mining .rating").rating(JsObject{onRate: onRate})

proc cmdSend(cmd: string) = stream.send(strToUint8Array(cmd.cstring))

proc appMain(data: RouterData): VNode =
  result = buildHtml(tdiv(class="ui inverted main text container")):
    let activeNidStr = $activeNid
    h1(class="ui inverted dividing header"): text "Web Mining Benchmark"
    if activeNid < noraList.len:
      tdiv(class="ui inverted basic buttons"):
        for i, n in noraList:
          tdiv(class=cstring("ui inverted button" & (if i == activeNid: " active" else: "")), data-value=cstring($i)):
            proc onclick(ev: Event, n: Vnode) =
              let newActiveNid = n.getAttr("data-value").parseInt
              if activeNid != newActiveNid:
                if miningActive:
                  jq(".preventnetwork.modal").modal("show")
                else:
                  let oldActiveNid = activeNid
                  activeNid = newActiveNid
                  if miningAddressValid:
                    cmdSend fmtj"""{"cmd":"addr-off","data":{"nid":<oldActiveNid>,"addr":"<miningAddress>"}}"""
                  miningAddressValid = checkAddress(activeNid.NetworkId, miningAddress.cstring)
                  if miningAddressValid:
                    cmdSend fmtj"""{"cmd":"addr-on","data":{"nid":<activeNid>,"addr":"<miningAddress>"}}"""
            text n
      h2(class="ui inverted dividing header"): text noraList[activeNid]
      if blockDatas.hasKey(activeNidStr):
        tdiv(class="ui inverted segment"):
          tdiv(class="ui inverted relaxed divided list"):
            for d in blockDatas[activeNidStr]["blocks"]:
              tdiv(class="item"):
                tdiv(class="content"):
                  let blkTime = d["time"].getInt.fromUnix()
                  tdiv(class="header"):
                    text blkTime.format("yyyy-MM-dd HH:mm:ss (zzz)")
                    span(class="blockheight"):
                      text "#" & $d["height"].getInt
                  code: tdiv(class="hash"): text d["hash"].getStr
              break

      tdiv(class="ui inverted center aligned segment"):
        if miningHashRateWaiting:
          span(class="ui inverted huge text"): verbatim "&nbsp;"
          tdiv(class="ui active"):
            tdiv(class="ui active slow inverted double loader")
        else:
          span(class="ui inverted huge text"): text $miningHashRate
          text " H/s"

      tdiv(class="ui inverted fluid right labeled left icon input"):
        italic(class="piggy bank icon")
        input(type="text", placeholder="Enter your receiving address", value=miningAddress.cstring, disabled=miningActive.toDisabled()):
          proc onkeyup(ev: Event, n: Vnode) =
            let oldMiningAddress = miningAddress
            miningAddress = $n.value()
            if oldMiningAddress != miningAddress:
              if miningAddressValid:
                cmdSend fmtj"""{"cmd":"addr-off","data":{"nid":<activeNid>,"addr":"<oldMiningAddress>"}}"""
              miningAddressValid = checkAddress(activeNid.NetworkId, miningAddress.cstring)
              if miningAddressValid:
                cmdSend fmtj"""{"cmd":"addr-on","data":{"nid":<activeNid>,"addr":"<miningAddress>"}}"""
        a(class="ui inverted tag label"):
          proc onclick(ev: Event, n: Vnode) =
            if miningActive:
              miningActive = false
              if miningAddressValid:
                cmdSend fmtj"""{"cmd":"mining-off","data":{"nid":<activeNid>,"addr":"<miningAddress>"}}"""
                miningData = jsNull
                changeMiningWorker(0)
                stopMiningDataUpdater()
              jq(".ui.mining.checkbox").checkbox("set unchecked")
            else:
              miningActive = true
              jq(".ui.mining.checkbox").checkbox("set checked")
              miningAddressValid = checkAddress(activeNid.NetworkId, miningAddress.cstring)
              if miningAddressValid:
                clearNotify()
                miningHashRateWaiting = true
                changeMiningWorker(cpuCount)
                startMiningDataUpdater()
                cmdSend fmtj"""{"cmd":"mining-on","data":{"nid":<activeNid>,"addr":"<miningAddress>"}}"""
              else:
                Notify.Error.show("invalid address")

                setTimeout(proc() =
                  jq(".ui.mining.checkbox").checkbox("set unchecked")
                  miningActive = false
                  changeMiningWorker(0)
                  stopMiningDataUpdater()
                  appInst.redraw(), 1000)

          tdiv(class="ui inverted right aligned toggle mining checkbox"):
            input(type="checkbox")
            label: text "Mining"

      let cpuCountStr = $cpuCount
      h3(class="ui inverted header"):
        italic(class="microchip icon")
        tdiv(class="content"):
          text fmt"CPU {cpuCountStr} / {cpuMaxCountStr}"
          if cpuMaxCountUnknown:
            text " (Unknown CPU)"

      tdiv(class="ui orange huge rating", data-icon="circle", data-rating=cpuCountStr.cstring, data-max-rating=cpuMaxCountStr.cstring):
        for i in 0..<cpuCount:
          italic(class="circle icon active")
        for i in 0..<cpuMaxCount - cpuCount:
          italic(class="circle icon")

      tdiv(class="ui inverted optimize form"):
        tdiv(class="inline fields"):
          label: text "Optimization"
          tdiv(class="field"):
            tdiv(class="ui radio checkbox"):
              input(type="radio", name="optimize", value="0", checked="checked")
              label: text "None"
          tdiv(class="field"):
            tdiv(class="ui radio checkbox"):
              input(type="radio", name="optimize", value="1")
              label: text "SIMD128"

      h3(class="ui inverted header"): text "Your Receiving Address"
      tdiv:
        bold: text "address: "
        if miningAddress.len > 0:
          text miningAddress
          if not miningAddressValid:
            text " "
            tdiv(class="ui red label"): text "invalid"
        else:
          text "(unset)"

      if addressDatas.hasKey(activeNidStr) and miningAddress == addressDatas[activeNidStr]["addr"].getStr:
        tdiv:
          bold: text "amount: "
          if addressDatas[activeNidStr].hasKey("val"):
            text convCoin(addressDatas[activeNidStr]["val"])
          else:
            text "(unused)"
        tdiv:
          if addressDatas[activeNidStr].hasKey("utxo_count"):
            bold: text "utxo count: "
            text $addressDatas[activeNidStr]["utxo_count"].getInt

      h3(class="ui inverted header"): text "Transaction Logs"
      if addrlogDatas.hasKey(activeNidStr) and
        miningAddress == addrlogDatas[activeNidStr]["addr"].getStr and
        addrlogDatas[activeNidStr]["addrlogs"].len > 0:
        tdiv(class="ui inverted segment"):
          tdiv(class="ui inverted relaxed divided list"):
            for d in addrlogDatas[activeNidStr]["addrlogs"]:
              tdiv(class="item"):
                tdiv(class="content"):
                  let blkTime = d["blktime"].getInt.fromUnix()
                  tdiv(class="header"):
                    text blkTime.format("yyyy-MM-dd HH:mm:ss (zzz)")
                    span(class="blockheight"): text "#" & $d["height"].getInt
                  code:
                    tdiv(class="hash"): text "txid: " & d["tx"].getStr
                    tdiv: text "value: " & convCoin(d["val"])
                    tdiv:
                      text "type: " & (if d["trans"].getInt == 0: "Send" else: "Receive")
                      if d["mined"].getInt == 1:
                        text " (mined)"
      else:
        tdiv: text "no logs"

    else:
      if connectionError:
        tdiv: text "Server connection failed."
      else:
        tdiv(class="ui active dimmer"):
          tdiv(class="ui indeterminate text loader"): text "Loading ..."


let miningPreventChangeNetwork = buildHtml(tdiv(class="ui preventnetwork inverted modal")):
  tdiv(class="header"): text "Network changes are preventing"
  tdiv(class="content"): p: text "Mining is currently running. Please stop the mining before changing the network."
  tdiv(class="actions"):
    tdiv(class="ui inverted ok button"): text "OK"

document.body.appendChild(vnodeToDom(miningPreventChangeNetwork))

appInst = setInitializer(appMain, "mining", afterScript)
appInst.surpressRedraws = false

window.addEventListener("beforeunload", proc() = pageUnload = true)

zenyjs.ready:
  stream.connect(WEBSOCKET_ENTRY_URL, WEBSOCKET_PROTOCOL):
    onOpen:
      connectionError = false
      clearNotify("connect")

    onReady:
      cmdSend """{"cmd":"status-on"}"""
      cmdSend """{"cmd":"noralist"}"""
      if miningActive:
        cmdSend fmtj"""{"cmd":"addr-on","data":{"nid":<activeNid>,"addr":"<miningAddress>"}}"""
        cmdSend fmtj"""{"cmd":"mining-on","data":{"nid":<activeNid>,"addr":"<miningAddress>"}}"""

    onRecv:
      let d = parseJson($data.uint8ArrayToStr())
      let recvType = d["type"].getStr
      let recvData = d["data"]

      if recvType == "mining":
        while 0 < miningPendingFinds.length.to(int):
          let findData = miningPendingFinds.shift().to(Uint8Array)
          let retSend = stream.send(findData)
          if not retSend:
            miningPendingFinds.push(findData)
            break
        miningData = JSON.parse(cstring($recvData))
        postMiningData()

      elif recvType == "noralist":
        noraList = @[]
        for n in recvData:
          noraList.add(n.getStr)
        appInst.redraw()

      elif recvType == "status":
        let nid = recvData["nid"].getInt
        let nidStr = $nid
        statusDatas[nidStr] = recvData

        let height = recvData["height"].getInt
        let lastHeight = recvData["lastHeight"].getInt
        if height == lastHeight:
          cmdSend fmtj"""{"cmd":"block","data":{"nid":<nid>,"height":<height>,"limit":1}}"""

      elif recvType == "block":
        let nid = recvData["nid"].getInt
        let nidStr = $nid
        blockDatas[nidStr] = recvData
        if activeNid == nid:
          appInst.redraw()

      elif recvType == "addr":
        let nid = recvData["nid"].getInt
        let nidStr = $nid
        addressDatas[nidStr] = recvData
        appInst.redraw()
        cmdSend fmtj"""{"cmd":"addrlog","data":{"nid":<nid>,"addr":"<miningAddress>","rev":1}}"""

      elif recvType == "addrlog":
        let nid = recvData["nid"].getInt
        let nidStr = $nid
        addrlogDatas[nidStr] = recvData
        appInst.redraw()

    onClose:
      if not pageUnload:
        if not connectionError:
          Notify.Error.show("Server connection failed.", "connect", true)
          when defined(MINING_STOP_WHEN_DISCONNECTED):
            setTimeout(proc() =
              jq(".ui.mining.checkbox").checkbox("set unchecked")
              miningActive = false
              changeMiningWorker(0)
              stopMiningDataUpdater()
              appInst.redraw(), 1000)
        connectionError = true
        appInst.redraw()
