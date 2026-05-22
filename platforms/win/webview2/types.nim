import winim
import com
# import std/[atomics]

type
  WebView* = ptr WebViewObj
  OnOpenFile* = proc (w: Webview; filePath: string; name = ""):bool
  WebViewObj* = object
    url* : string
    title* : string
    width* : int
    height* : int
    resizable*: bool
    debug* : bool
    invokeCb* : pointer
    priv*: WebviewPrivObj
    created*: bool
    onOpenFile*: OnOpenFile
    initHtml*: string  # patch: embedded HTML loaded at startup via NavigateToString (instead of navigating to a URL)
    miotop*: LONG      # top offset for WebView bounds (0 = full client area; 62 = legacy toolbar space)
  WebviewPrivObj* = object
    windowHandle*: HWND
    view*: ptr ICoreWebView2
    controller*: ptr ICoreWebView2Controller
    settings*: ptr ICoreWebView2Settings

