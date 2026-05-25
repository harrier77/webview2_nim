import webview2/[types,controllers,context,dialog,com,environment_options,loader]
import winim
import winim/inc/winuser
import winim/inc/commctrl
import winim/[utils]
import std/[os, pathnorm]
import ./dpi_util
export types,dialog

var miaglob_toolb*:HWND

# Toolbar command IDs
const
  ID_REFRESH* = 101
  ID_BACK* = 102
  ID_FORWARD* = 103

const classname = "WebView"

# Window size hints
const WEBVIEW_HINT_NONE = 0  # Width and height are default size
const WEBVIEW_HINT_MIN = 1   # Width and height are minimum bounds
const WEBVIEW_HINT_MAX = 2   # Width and height are maximum bounds
const WEBVIEW_HINT_FIXED = 3 # Window size can not be changed by a user

var m_maxsz: POINT
var m_minsz: POINT

type WebviewDispatchCtx {.pure.} = object
  w: Webview
  arg: pointer
  fn: pointer

type WebviewDispatchCtx2 {.pure.} = object
  w: Webview
  arg: pointer
  fn: proc (w: Webview; arg: pointer)

proc terminate*(w: Webview): void
proc resize*(w: WebView;): void
#proc embed*( w: WebView)

const TOOLBAR_HEIGHT* = 30  ## Default toolbar height in pixels

proc mio_move_client*(w: WebView,miotop=cast[LONG](0)): void =
  var bounds: RECT
  let g = GetClientRect(w.priv.windowHandle, bounds)
  doAssert g == TRUE, $GetLastError()
  doAssert w.priv.controller != nil
  bounds.top=miotop
  discard w.priv.controller.put_Bounds(bounds)
  # Resize toolbar to fill the full width of the parent window
  if miaglob_toolb != 0:
    MoveWindow(miaglob_toolb, 0, 0, bounds.right - bounds.left, TOOLBAR_HEIGHT, TRUE)
  UpdateWindow(w.priv.windowHandle)


  
proc custom_toolb*(parent: HWND, hInstance: HINSTANCE): HWND =
  ## Create a toolbar with navigation buttons (Back, Forward, Refresh)
  InitCommonControls()

  # Get parent client width for initial toolbar sizing
  var parentRect: RECT
  GetClientRect(parent, parentRect.addr)
  let parentW = parentRect.right - parentRect.left

  let hwndToolbar = CreateWindowEx(
    0, TOOLBARCLASSNAME, nil,
    WS_CHILD or WS_VISIBLE or TBSTYLE_FLAT or TBSTYLE_TOOLTIPS,
    0, 0, parentW, TOOLBAR_HEIGHT,
    parent, cast[HMENU](0), hInstance, nil
  )
  if hwndToolbar == 0:
    return 0

  # Tell toolbar the TBBUTTON structure size (compatibility)
  SendMessage(hwndToolbar, TB_BUTTONSTRUCTSIZE, sizeof(TBBUTTON), 0)

  # Set explicit button dimensions: 60px wide x 26px tall
  SendMessage(hwndToolbar, TB_SETBUTTONSIZE, 0, MAKELPARAM(60, 26))

  # Allocate wide strings for button labels
  let backText = T("  Back  ")
  let fwdText = T("  Forward  ")
  let refText = T("  Refresh  ")

  # Define buttons
  var buttons: array[3, TBBUTTON]
  zeroMem(addr buttons, sizeof(buttons))

  # Button 1: Back
  buttons[0].iBitmap = I_IMAGENONE
  buttons[0].idCommand = ID_BACK
  buttons[0].fsState = TBSTATE_ENABLED
  buttons[0].fsStyle = BTNS_BUTTON or BTNS_AUTOSIZE
  buttons[0].dwData = 0
  buttons[0].iString = cast[INT_PTR](&backText)

  # Button 2: Forward
  buttons[1].iBitmap = I_IMAGENONE
  buttons[1].idCommand = ID_FORWARD
  buttons[1].fsState = TBSTATE_ENABLED
  buttons[1].fsStyle = BTNS_BUTTON or BTNS_AUTOSIZE
  buttons[1].dwData = 0
  buttons[1].iString = cast[INT_PTR](&fwdText)

  # Button 3: Refresh
  buttons[2].iBitmap = I_IMAGENONE
  buttons[2].idCommand = ID_REFRESH
  buttons[2].fsState = TBSTATE_ENABLED
  buttons[2].fsStyle = BTNS_BUTTON or BTNS_AUTOSIZE
  buttons[2].dwData = 0
  buttons[2].iString = cast[INT_PTR](&refText)

  discard SendMessage(hwndToolbar, TB_ADDBUTTONS, 3, cast[LPARAM](addr buttons))

  # Auto-size the toolbar after buttons are added
  SendMessage(hwndToolbar, TB_AUTOSIZE, 0, 0)

  # Force the toolbar to repaint
  InvalidateRect(hwndToolbar, nil, TRUE)
  UpdateWindow(hwndToolbar)

  return hwndToolbar



proc wndproc*(hwnd: HWND, msg: UINT, wParam: WPARAM, lParam: LPARAM): LRESULT {.stdcall.} =
    var w = cast[Webview](GetWindowLongPtr(hwnd, GWLP_USERDATA))
    case msg
      of WM_CREATE:
        var
          pCreate = cast[ptr CREATESTRUCT](lParam)
          p = cast[LONG_PTR](pCreate.lpCreateParams)
        hwnd.SetWindowLongPtr(GWLP_USERDATA, p)
      of WM_SIZE:
        if w != nil and w.priv.controller != nil:
          w.resize()
          w.mio_move_client(w.miotop)
      of WM_CLOSE:
        echo "msg WM_CLOSE..."
        DestroyWindow(hwnd)
        ShowWindow(w.priv.windowHandle, SW_HIDE)
      of WM_DESTROY:
        echo "msg WM_DESTROY..."
        w.terminate()
        return TRUE
      of WM_COMMAND:
        # Handle toolbar button clicks
        let cmdId = LOWORD(wParam)
        if w != nil:
          case cmdId
            of ID_REFRESH:
              if w.priv.view != nil:
                echo "[toolbar] Refresh clicked"
                discard w.priv.view.ExecuteScript(&T("location.reload()"), nil)
            of ID_BACK:
              if w.priv.view != nil:
                echo "[toolbar] Back clicked"
                discard w.priv.view.GoBack()
            of ID_FORWARD:
              if w.priv.view != nil:
                echo "[toolbar] Forward clicked"
                discard w.priv.view.GoForward()
            else:
              return DefWindowProc(hwnd, msg, wParam, lParam)
        else:
          return DefWindowProc(hwnd, msg, wParam, lParam)
      else:
        return DefWindowProc(hwnd, msg, wParam, lParam)


proc run*(w: Webview) =
  ## `run` starts the main UI loop until the user closes the window or `exit()` is called.
  var msg: MSG
  
  while GetMessage(msg.addr, 0, 0, 0) != -1:
    if msg.hwnd != 0:
      TranslateMessage(msg.addr)
      DispatchMessage(msg.addr)
      continue
    case msg.message:
    of WM_APP:
      let fn = cast[proc(env:pointer):void {.stdcall.}](msg.lParam)
      fn(cast[pointer](msg.wParam))
    of WM_QUIT:
      return
    of WM_COMMAND,
      WM_KEYDOWN,
      WM_KEYUP:
      echo "WM_COMMAND / keyboard message"
      if (msg.wParam == VK_F5):
        return
    else:
      discard

proc terminate*(w: Webview): void =
  PostQuitMessage(0)
  echo "terminate procedure completed..."

proc destroy*(w: Webview): void =
  w.terminate()


  
proc setTitle*(w: Webview; title: string ): void =
  discard SetWindowTextW(w.priv.windowHandle, &T(title))

proc navigate*(w: Webview; urlOrData: string ): void =
  discard w.priv.view.Navigate(&T(urlOrData))

proc setHtml*(w: Webview; html: string): void =
  discard w.priv.view.NavigateToString(&T(html))

proc eval*(w: Webview; js: string): void =
  discard w.priv.view.ExecuteScript(&T(js), nil)

proc setSize*(w: Webview; width: int; height: int; hints: int): void =
  var style = GetWindowLong(w.priv.windowHandle, GWL_STYLE)
  if hints == WEBVIEW_HINT_FIXED:
    style = style and not(WS_THICKFRAME or WS_MAXIMIZEBOX)
  else:
    style = style or (WS_THICKFRAME or WS_MAXIMIZEBOX)

  SetWindowLong(w.priv.windowHandle, GWL_STYLE, style)

  if hints == WEBVIEW_HINT_MAX:
    m_maxsz.x = width.LONG
    m_maxsz.y = height.LONG
  elif hints == WEBVIEW_HINT_MIN:
    m_minsz.x = width.LONG
    m_minsz.y = height.LONG
  else:
    var r: RECT
    r.left = 0
    r.top = 0
    r.right = width.LONG
    r.bottom = height.LONG
    AdjustWindowRect(r.addr, WS_OVERLAPPEDWINDOW, 0)
    discard SetWindowPos(w.priv.windowHandle, 0.HWND, r.left, r.top, r.right - r.left, r.bottom - r.top,
        SWP_NOZORDER or SWP_NOACTIVATE or SWP_NOMOVE or SWP_FRAMECHANGED)
    w.resize()

proc webview_dispatch*(w: Webview; fn: pointer; arg: pointer) {.stdcall.} =
  let mainThread = GetCurrentThreadId()
  var cb = proc() = cast[proc (w: Webview;arg: pointer){.stdcall.}](fn)(w, arg)
  PostThreadMessage(mainThread, WM_APP, cast[WPARAM](cb.rawEnv), cast[LPARAM](cb.rawProc))

proc resize*(w: WebView;): void =
  var bounds: RECT
  let g = GetClientRect(w.priv.windowHandle, bounds)
  doAssert g == TRUE, $GetLastError()
  doAssert w.priv.controller != nil
  discard w.priv.controller.put_Bounds(bounds)



proc addUserScriptAtDocumentStart*(w: WebView; script: string) =
  var script = T(script)
  discard w.priv.view.AddScriptToExecuteOnDocumentCreated(&script, NULL)

proc addUserScriptAtDocumentEnd*(w: WebView; script: string) =
  var token: EventRegistrationToken
  var handler = create(ICoreWebView2DOMContentLoadedEventHandler)
  handler.lpVtbl = create(ICoreWebView2DOMContentLoadedEventHandlerVTBL)
  handler.lpVtbl.QueryInterface = icorewebview2domcontentloadedeventhandler.QueryInterface
  handler.lpVtbl.AddRef = icorewebview2domcontentloadedeventhandler.AddRef
  handler.lpVtbl.Release = icorewebview2domcontentloadedeventhandler.Release
  handler.script = script
  handler.lpVtbl.Invoke = proc (self: ptr ICoreWebView2DOMContentLoadedEventHandler;
      sender: ptr ICoreWebView2;
      args: ptr ICoreWebView2DOMContentLoadedEventArgs): HRESULT {.stdcall.} =
    var script = T(self.script)
    sender.ExecuteScript(&script, NULL)  # patch: fixed typo NUll -> NULL

  discard w.priv.view.add_DOMContentLoaded(handler, token.addr)

when isMainModule:
  SetCurrentProcessExplicitAppUserModelID("webview2 app")
  #import ../../webview.nim  # does not work here
  var v = newWebView()
  assert v.webview_init() == 0

  v.run