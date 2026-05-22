#{.link: "newres.res".}
import tables, strutils, macros, logging, json, os, base64, strformat, std/exitprocs
import platforms/win/webview2/[types,controllers,context,dialog,com,environment_options,loader]
import winim
import winim/inc/winuser
import winim/[utils]
import std/[os, pathnorm]
import platforms/win/miowebview2
import platforms/win/dpi_util
export types,dialog

const classname = "WebView"

#var miatoolb* : HINSTANCE

import std/[strutils]

const
  jsTemplate = """
    if (typeof $2 === 'undefined') {
      $2 = {};
    }
    $2.$1 = (arg) => {
      window.external.invoke(
        JSON.stringify(
          {scope: "$2", name: "$1", args: JSON.stringify(arg)}
        )
      );
    };
  """.strip
  jsTemplateWithReturn = """
    if (typeof $2 === 'undefined') {
      $2 = {};
    }
    $2.$1 = (arg) => {
      return new Promise((resolve) => {
        const id = ++window._nimCallbackId;
        window._nimCallbacks[id] = resolve;
        window.external.invoke(
          JSON.stringify(
            {scope: "$2", name: "$1", args: JSON.stringify(arg), callbackId: id}
          )
        );
      });
    };
  """.strip
  jsTemplateOnlyArg = """
    if (typeof $2 === 'undefined') {
      $2 = {};
    }
    $2.$1 = (arg) => {
      window.external.invoke(
        JSON.stringify(
          {scope: "$2", name: "$1", args: JSON.stringify(arg)}
        )
      );
    };
  """.strip
  jsTemplateNoArg = """
    if (typeof $2 === 'undefined') {
      $2 = {};
    }
    $2.$1 = () => {
      window.external.invoke(
        JSON.stringify(
          {scope: "$2", name: "$1", args: ""}
        )
      );
    };
  """.strip
  cssInjectFunction = """
  (function(e){window.onload = function(){
  var t=document.createElement('style'),d=document.head||document.getElementsByTagName('head')[0];
  t.setAttribute('type','text/css');
  t.styleSheet?t.styleSheet.cssText=e:t.appendChild(document.createTextNode(e)),d.appendChild(t);
  }})
  """.strip.unindent

func jsEncode(s: string): string =
  result = newStringOfCap(s.len * 4) # Allocate reasonable buffer size
  var n = s.len * 4
  var r = 1 # At least one byte for trailing zero
  for c in s:
    let byte = c.uint8
    if byte >= 0x20 and byte < 0x80 and c notin {'<', '>', '\\', '\'', '"'}:
      if n > 0:
        result.add c
        dec(n)
      r += 1
    else:
      if n > 0:
        result.add "\\x" & byte.toHex(2)
        n -= 4 # We add 4 bytes, so we want to subtract 4 from remaining space
      r += 4

proc mio_embed*( w: WebView) =
  let exePath = getAppFilename()
  var (dir, name, ext) = splitFile(exePath)
  var dataPath = normalizePath(getEnv("AppData") / name)
  createDir(dataPath)
  var controllerCompletedHandler = newControllerCompletedHandler(w.priv.windowHandle, w.priv.controller, w.priv.view, w.priv.settings)
  var environmentCompletedHandler = newEnvironmentCompletedHandler(w.priv.windowHandle, controllerCompletedHandler)
  var options = create(ICoreWebView2EnvironmentOptions)
  options.lpVtbl = create(ICoreWebView2EnvironmentOptionsVTBL)
  options.lpVtbl.QueryInterface = environment_options.QueryInterface
  options.lpVtbl.AddRef = environment_options.AddRef
  options.lpVtbl.Release = environment_options.Release
  options.lpVtbl.get_AdditionalBrowserArguments = environment_options.get_AdditionalBrowserArguments
  options.lpVtbl.put_AdditionalBrowserArguments = environment_options.put_AdditionalBrowserArguments
  options.lpVtbl.get_Language = environment_options.get_Language
  options.lpVtbl.put_Language = environment_options.put_Language
  options.lpVtbl.get_TargetCompatibleBrowserVersion = environment_options.get_TargetCompatibleBrowserVersion
  options.lpVtbl.put_TargetCompatibleBrowserVersion = environment_options.put_TargetCompatibleBrowserVersion
  options.lpVtbl.get_AllowSingleSignOnUsingOSPrimaryAccount = environment_options.get_AllowSingleSignOnUsingOSPrimaryAccount
  options.lpVtbl.put_AllowSingleSignOnUsingOSPrimaryAccount = environment_options.put_AllowSingleSignOnUsingOSPrimaryAccount
  options.lpVtbl.get_ExclusiveUserDataFolderAccess = environment_options.get_ExclusiveUserDataFolderAccess
  options.lpVtbl.put_ExclusiveUserDataFolderAccess = environment_options.put_ExclusiveUserDataFolderAccess
  let r1 = CreateCoreWebView2EnvironmentWithOptions("", dataPath, options, environmentCompletedHandler)
  doAssert r1 == S_OK, "failed to call CreateCoreWebView2EnvironmentWithOptions"
  # simulate synchronous
  # https://github.com/MicrosoftEdge/WebView2Feedback/issues/740
  #assert w.created == false, "Expected false at line 242, but got $w.created}"
  if w.created==false:
    echo w.created
  else:
    echo w.created
  var msg: MSG
  while w.created == false and GetMessage(msg.addr, 0, 0, 0).bool:
    TranslateMessage(msg.addr)
    DispatchMessage(msg.addr)



proc  miowebview_init*(w: Webview): cint =
  if w.created:
    return 0
  var wc:WNDCLASSEX
  var hInstance:HINSTANCE
  var g_hInstance:HINSTANCE
  var style:DWORD
  var clientRect:RECT
  var rect:RECT

  hInstance = GetModuleHandle(NULL)
  g_hInstance = GetModuleHandle(NULL)
  if hInstance == 0:
    echo "hInstance is null!"
    return -1
  
  OleUninitialize()
  if OleInitialize(NULL) != S_OK:
    echo "OleInitialize failed (not S_OK)!"
    #OleUninitialize()
    return -1

  ZeroMemory(&wc, sizeof(WNDCLASSEX))
  wc.cbSize = sizeof(WNDCLASSEX).UINT
  wc.hInstance = hInstance
  wc.lpfnWndProc = wndproc
  wc.lpszClassName = classname
  wc.hbrBackground = CreateSolidBrush(RGB(255, 255, 255))
  RegisterClassExW(&wc)

  style = WS_OVERLAPPEDWINDOW
  # if not w.resizable:
  #   style = WS_OVERLAPPED or WS_CAPTION or WS_MINIMIZEBOX or WS_SYSMENU
  rect.top = 160
  rect.left = 0
  rect.right = w.width.LONG
  rect.bottom = w.height.LONG
  AdjustWindowRect(&rect, WS_OVERLAPPEDWINDOW, 0)
  
  GetClientRect(GetDesktopWindow(), &clientRect)

  let left = (clientRect.right div 2) - ((rect.right - rect.left) div 2)
  let top = (clientRect.bottom div 2) - ((rect.bottom - rect.top) div 2)
  rect.right = rect.right - rect.left + left
  rect.left = left
  rect.bottom = rect.bottom - rect.top + top
  rect.top = top
  setDpiAwareness(DPI_AWARENESS_CONTEXT_SYSTEM_AWARE)
  
  ##here the window is included in webview object
  w.priv.windowHandle = CreateWindowW(classname, w.title, style, rect.left, rect.top,
    rect.right - rect.left, rect.bottom - rect.top,
    HWND_DESKTOP, cast[HMENU](NULL), hInstance, cast[LPVOID](w))
  ####

  if (w.priv.windowHandle == 0):
    OleUninitialize()
    return -1
  SetWindowText(w.priv.windowHandle, w.title)
  ShowWindow(w.priv.windowHandle, SW_SHOW)
  #miatoolb = custom_toolb(w, g_hInstance)
  #miaglob_toolb=miatoolb
  #ShowWindow(miatoolb, SW_SHOW)
  UpdateWindow(w.priv.windowHandle)
  SetFocus(w.priv.windowHandle)
  try:
    if CoInitializeEx(nil, COINIT_APARTMENTTHREADED).FAILED: raise
    defer: CoUninitialize()
  except:
    discard
  w.mio_embed()

  w.mio_move_client(w.miotop)
  return 0



#import mie_tbars

var logger = newRollingFileLogger(expandTilde("~/crowngui.log"))
addHandler(logger)

when defined(linux):
  {.passc: "-DWEBVIEW_GTK=1 " & staticExec"pkg-config --cflags gtk+-3.0 webkit2gtk-4.0",
      passl: staticExec"pkg-config --libs gtk+-3.0 webkit2gtk-4.0".}
elif defined(windows):
  import platforms/win/miowebview2
  export miowebview2
  import winim
elif defined(macosx):
  import objc_runtime
  import darwin / [app_kit, foundation]
  import platforms/macos/menu
  import platforms/macos/webview
  import platforms/macos/appdelegate
  import platforms/macos/windowcontroller
  export webview

type
  DispatchFn* = proc()
  CallHook = proc (params: string): string # json -> proc -> json
  MethodInfo = object
    scope, name, args, callbackId: string
  ExternalInvokeCb* = proc (w: Webview; arg: cstring) ## External CallBack Proc

template dataUriHtmlHeader*(s: string): string =
  ## Data URI for HTML UTF-8 header string. For Mac uses Base64, `import base64` to use.
  when defined(osx): "data:text/html;charset=utf-8;base64," & base64.encode(s)
  else: "data:text/html," & s

const
  fileLocalHeader* = "file:///" ## Use Local File as URL

var
  eps = newTable[Webview, TableRef[string, TableRef[string, CallHook]]]()       # for bindProc
  cbs = newTable[Webview, ExternalInvokeCb]()                                   # easy callbacks
  dispatchTable = newTable[int, DispatchFn]()                                   # for dispatch

proc css*(w:Webview, css: string): void =
  w.addUserScriptAtDocumentStart(cssInjectFunction & "(\"" & css.jsEncode & "\")")

proc generalExternalInvokeCallback(w: Webview; arg: cstring) {.exportc.} =
  # assign to webview.external_invoke_cb using eps,cbs store user defined proc
  var handled = false
  if eps.hasKey(w):
    try:
      var mi = parseJson($arg).to(MethodInfo)
      if hasKey(eps[w], mi.scope) and hasKey(eps[w][mi.scope], mi.name):
        let resultJson = eps[w][mi.scope][mi.name](mi.args)
        if mi.callbackId.len > 0:
          let js = "window._nimCallbacks[" & mi.callbackId & "](" & resultJson & ")"
          w.eval(js)
        handled = true
    except:
      when defined(release): discard else: echo getCurrentExceptionMsg()
  elif cbs.hasKey(w):
    cbs[w](w, arg)
    handled = true
  when not defined(release):
    if unlikely(handled == false): echo "Error on External invoke: ", arg

proc `externalInvokeCB=`*(w: Webview; callback: ExternalInvokeCb) {.inline.} =
  ## Set the external invoke callback for webview, for Advanced users only
  cbs[w] = callback

proc generalDispatchProc(w: Webview; arg: pointer) {.exportc.} =
  let idx = cast[int](arg)
  let fn = dispatchTable[idx]
  fn()

proc dispatch*(w: Webview; fn: DispatchFn) {.inline.} =
  ## Explicitly force dispatch a function, for advanced users only
  let idx = dispatchTable.len() + 1
  dispatchTable[idx] = fn
  webview_dispatch(w, generalDispatchProc, cast[pointer](idx))

proc bindProc[P, R](w: Webview; scope, name: string; p: (proc(param: P): R)): string {.used.} =
  assert name.len > 0, "Name must not be empty string"
  proc hook(hookParam: string): string =
    var paramVal: P
    var retVal: R
    try:
      let jnode = parseJson(hookParam)
      when not defined(release): echo jnode
      paramVal = jnode.to(P)
    except:
      when defined(release): discard else: return getCurrentExceptionMsg()
    retVal = p(paramVal)
    return $(%*retVal) # ==> json
  discard eps.hasKeyOrPut(w, newTable[string, TableRef[string, CallHook]]())
  discard hasKeyOrPut(eps[w], scope, newTable[string, CallHook]())
  eps[w][scope][name] = hook
  return jsTemplateWithReturn % [name, scope]

proc bindProcNoArg(w: Webview; scope, name: string; p: proc()): string {.used.} =
  assert name.len > 0, "Name must not be empty string"
  proc hook(hookParam: string): string =
    p()
    return ""
  discard eps.hasKeyOrPut(w, newTable[string, TableRef[string, CallHook]]())
  discard hasKeyOrPut(eps[w], scope, newTable[string, CallHook]())
  eps[w][scope][name] = hook
  return jsTemplateNoArg % [name, scope]

proc bindProc[P](w: Webview; scope, name: string; p: proc(arg: P)): string {.used.} =
  assert name.len > 0, "Name must not be empty string"
  proc hook(hookParam: string): string =
    var paramVal: P
    try:
      let jnode = parseJson(hookParam)
      paramVal = jnode.to(P)
    except:
      when defined(release): discard else: return getCurrentExceptionMsg()
    p(paramVal)
    return ""
  discard eps.hasKeyOrPut(w, newTable[string, TableRef[string, CallHook]]())
  discard hasKeyOrPut(eps[w], scope, newTable[string, CallHook]())
  eps[w][scope][name] = hook
  return jsTemplateOnlyArg % [name, scope]

macro bindProcs*(w: Webview; scope: string; n: untyped): untyped =
  ## You can bind functions with the signature like:
  ## .. code-block:: nim
  ##    proc functionName[T, U](argumentString: T): U
  ##    proc functionName[T](argumentString: T)
  ##    proc functionName()
  ##
  ## Then you can call the function in JavaScript side, like this:
  ## .. code-block:: js
  ##    scope.functionName(argumentString)
  ##
  ## Example:
  ## .. code-block:: js
  ##    let app = newWebView()
  ##    app.bindProcs("api"):
  ##      proc changeTitle(title: string) = app.setTitle(title) ## You can call code on the right-side,
  ##      proc changeCss(stylesh: string) = app.css(stylesh)    ## from JavaScript Web Frontend GUI,
  ##      proc injectJs(jsScript: string) = app.js(jsScript)    ## by the function name on the left-side.
  ##      ## (JS) JavaScript Frontend <-- = --> Nim Backend (Native Code, C Speed)
  ##
  ## The only limitation is `1` string argument only, but you can just use JSON.
  expectKind(n, nnkStmtList)
  result = nnkStmtList.newTree()
  let body = n
  var jsIdent = genSym(nskVar)
  var jsStr = nnkVarSection.newTree(
    nnkIdentDefs.newTree(
      jsIdent,
      newIdentNode("string"),
      newLit("")
    )
  )
  result.add jsStr
  for def in n:
    expectKind(def, {nnkProcDef, nnkFuncDef, nnkLambda})
    let params = def.params()
    let fname = $def[0]
    # expectKind(params[0], nnkSym)
    if params.len() == 1 and params[0].kind() == nnkEmpty: # no args
      var bindCall = newCall(bindSym"bindProcNoArg", w, scope, newLit(fname), newIdentNode(fname))
      body.add(newCall("add", jsIdent, bindCall))
      continue
    if params.len > 2: error("Argument must be proc or func of 0 or 1 arguments", def)
    var bindCall = newCall(bindSym"bindProc", w, scope, newLit(fname), newIdentNode(fname))
    body.add(newCall("add", jsIdent, bindCall))
  result.add newBlockStmt(body)
  let w2 = w
  result.add(quote do:
    `w2`.dispatch(proc() = `w2`.eval(`jsIdent`))
  )

proc run*(w: Webview; quitProc: proc () {.noconv.}; controlCProc: proc () {.noconv.}) {.inline.} =
  ## `run` starts the main UI loop until the user closes the window. Same as `run` but with extras.
  ## * `quitProc` is a function to run at exit, needs `{.noconv.}` pragma.
  ## * `controlCProc` is a function to run at CTRL+C, needs `{.noconv.}` pragma.
  ## * `autoClose` set to `true` to automatically run `exit()` at exit.
  exitprocs.addExitProc(quitProc)
  system.setControlCHook(controlCProc)
  w.run
###


proc mio_new_webview*(path: string = ""; title = ""; width: Positive = 1000; height: Positive = 700;
    resizable: bool = true; debug: bool = not defined(release); callback: ExternalInvokeCb = nil;
    miotop: LONG = 62): Webview =
    result = create(WebviewObj)
    result.title = title
    if path == "":
      const htmlContent = staticRead("static/index.html")
      result.initHtml = htmlContent
    else:
      result.url = path
    result.width = width
    result.height = height
    result.resizable = resizable
    result.debug = true
    result.invokeCb = generalExternalInvokeCallback
    result.miotop = miotop
    if callback != nil: result.externalInvokeCB = callback
    ##
    if result.miowebview_init() != 0: return nil ## calls miowebview_init (defined in miowv.nim)
    ##
    mio_move_client(result, result.miotop)
#####



proc mioMaximize*(v:Webview):void=
    discard ShowWindow(v.priv.windowHandle,SW_MAXIMIZE)


when isMainModule:
  var w = mio_new_webview(width=1000, height=1000)
  w.externalInvokeCB = proc (w: Webview; arg: cstring) =
    try:
      let json = parseJson($arg)
      if json["scope"].getStr() == "api" and json["name"].getStr() == "printPippo":
        # args is JSON.stringify(arg), so it must be re-parsed to extract the actual value
        let rawArgs = json["args"].getStr()
        let msg = parseJson(rawArgs).getStr()
        echo "pippo"
        let resultJson = $(%*("Ricevuto: " & msg & " -> variabile da js"))
        let cbId = $json["callbackId"].getInt()
        let js = "window._nimCallbacks[" & cbId & "](" & resultJson & ")"
        w.eval(js)
    except:
      echo "Error in externalInvokeCB: ", getCurrentExceptionMsg()
  w.run()