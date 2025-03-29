import winim/com
import winim/lean except RECT
import os

const
  APPLICATION_NAME = "WebView2"
  altezza_bar = 30
  WM_DPICHANGED = 0x02E0
  DPI_AWARENESS_CONTEXT_PER_MONITOR_AWARE_V2 = cast[pointer](-4)
  COINIT_APARTMENTTHREADED = 0x2  # STA threading model

type
  DPI_AWARENESS_CONTEXT = pointer
  PROCESS_DPI_AWARENESS = enum
    PROCESS_DPI_UNAWARE = 0,
    PROCESS_SYSTEM_DPI_AWARE = 1,
    PROCESS_PER_MONITOR_DPI_AWARE = 2

var
  hWnd: HWND = nil
  panel_bar: HWND = nil
  webviewController: pointer = nil
  webviewWindow: pointer = nil
  #bEnvCreated = false
  HandlerRefCount: ULONG = 0

proc LoadLibrary(lpLibFileName: LPCWSTR): HMODULE {.stdcall, importc: "LoadLibraryW", dynlib: "kernel32.dll".}
proc GetProcAddress(hModule: HMODULE; lpProcName: LPCSTR): FARPROC {.stdcall, importc, dynlib: "kernel32.dll".}
proc FreeLibrary(hModule: HMODULE): BOOL {.stdcall, importc, dynlib: "kernel32.dll".}
proc CoInitializeEx(pvReserved: pointer; dwCoInit: DWORD): HRESULT {.stdcall, importc, dynlib: "ole32.dll".}
proc CoUninitialize() {.stdcall, importc, dynlib: "ole32.dll".}
#proc freopen(filename: cstring; mode: cstring; stream: pointer): pointer {.stdcall, importc, dynlib: "msvcrt.dll".}
#proc getch(): int32 {.stdcall, importc: "_getch", dynlib: "msvcrt.dll".}
proc SetProcessDpiAwarenessContext(value: DPI_AWARENESS_CONTEXT): BOOL {.stdcall, importc, dynlib: "user32.dll".}
proc SetProcessDPIAware(): BOOL {.stdcall, importc, dynlib: "user32.dll".}
proc SetProcessDpiAwareness(value: PROCESS_DPI_AWARENESS): HRESULT {.stdcall, importc, dynlib: "Shcore.dll".}

type
  CreateCoreWebView2EnvironmentWithOptionsProc = proc(
    browserExecutableFolder: LPCWSTR,
    userDataFolder: LPCWSTR,
    environmentOptions: pointer,
    environmentCreatedHandler: pointer
  ): HRESULT {.stdcall.}

  ICoreWebView2EnvironmentVtbl = object
    QueryInterface: proc(self: pointer; riid: REFIID; ppvObject: ptr pointer): HRESULT {.stdcall.}
    AddRef: proc(self: pointer): ULONG {.stdcall.}
    Release: proc(self: pointer): ULONG {.stdcall.}
    CreateCoreWebView2Controller: proc(self: pointer; parentWindow: HWND; handler: pointer): HRESULT {.stdcall.}

  ICoreWebView2ControllerVtbl = object
    QueryInterface: proc(self: pointer; riid: REFIID; ppvObject: ptr pointer): HRESULT {.stdcall.}
    AddRef: proc(self: pointer): ULONG {.stdcall.}
    Release: proc(self: pointer): ULONG {.stdcall.}
    get_CoreWebView2: proc(self: pointer; webview: ptr pointer): HRESULT {.stdcall.}
    put_Bounds: proc(self: pointer; bounds: RECT): HRESULT {.stdcall.}

  ICoreWebView2Vtbl = object
    QueryInterface: proc(self: pointer; riid: REFIID; ppvObject: ptr pointer): HRESULT {.stdcall.}
    AddRef: proc(self: pointer): ULONG {.stdcall.}
    Release: proc(self: pointer): ULONG {.stdcall.}
    get_Settings: proc(self: pointer; settings: ptr pointer): HRESULT {.stdcall.}
    Navigate: proc(self: pointer; uri: LPCWSTR): HRESULT {.stdcall.}

  ICoreWebView2SettingsVtbl = object
    QueryInterface: proc(self: pointer; riid: REFIID; ppvObject: ptr pointer): HRESULT {.stdcall.}
    AddRef: proc(self: pointer): ULONG {.stdcall.}
    Release: proc(self: pointer): ULONG {.stdcall.}
    put_IsScriptEnabled: proc(self: pointer; enabled: BOOL): HRESULT {.stdcall.}
    put_AreDefaultScriptDialogsEnabled: proc(self: pointer; enabled: BOOL): HRESULT {.stdcall.}
    put_IsWebMessageEnabled: proc(self: pointer; enabled: BOOL): HRESULT {.stdcall.}
    put_AreDevToolsEnabled: proc(self: pointer; enabled: BOOL): HRESULT {.stdcall.}
    put_AreDefaultContextMenusEnabled: proc(self: pointer; enabled: BOOL): HRESULT {.stdcall.}
    put_IsStatusBarEnabled: proc(self: pointer; enabled: BOOL): HRESULT {.stdcall.}
    put_IsZoomControlEnabled: proc(self: pointer; enabled: BOOL): HRESULT {.stdcall.}

  ICoreWebView2Environment = object
    lpVtbl: ptr ICoreWebView2EnvironmentVtbl
       
  ICoreWebView2Controller = object
    lpVtbl: ptr ICoreWebView2ControllerVtbl

  ICoreWebView2 = object
    lpVtbl: ptr ICoreWebView2Vtbl

  ICoreWebView2Settings = object
    lpVtbl: ptr ICoreWebView2SettingsVtbl
       
  ICoreWebView2CreateCoreWebView2EnvironmentCompletedHandlerVtbl = object
    QueryInterface: proc(self: pointer; riid: REFIID; ppvObject: ptr pointer): HRESULT {.stdcall.}
    AddRef: proc(self: pointer): ULONG {.stdcall.}
    Release: proc(self: pointer): ULONG {.stdcall.}
    Invoke: proc(self: pointer; errorCode: HRESULT; createdEnvironment: ptr ICoreWebView2Environment): HRESULT {.stdcall.}

  #[ICoreWebView2CreateCoreWebView2ControllerCompletedHandlerVtbl = object
    QueryInterface: proc(self: pointer; riid: REFIID; ppvObject: ptr pointer): HRESULT {.stdcall.}
    AddRef: proc(self: pointer): ULONG {.stdcall.}
    Release: proc(self: pointer): ULONG {.stdcall.}
    Invoke: proc(self: pointer; errorCode: HRESULT; controller: ptr ICoreWebView2Controller): HRESULT {.stdcall.}]#

  EnvironmentHandler = object
    lpVtbl: ptr ICoreWebView2CreateCoreWebView2EnvironmentCompletedHandlerVtbl

proc AddRef(this: pointer): ULONG {.stdcall.} =
  inc HandlerRefCount
  return HandlerRefCount

proc Release(this: pointer): ULONG {.stdcall.} =
  dec HandlerRefCount
  return HandlerRefCount

proc QueryInterface(this: pointer; riid: REFIID; ppvObject: ptr pointer): HRESULT {.stdcall.} =
  if ppvObject == nil:
    return E_POINTER
  ppvObject[] = this
  discard AddRef(this)
  return S_OK


# Simplified handler implementation
proc SimpleEnvInvoke(this: pointer; errorCode: HRESULT; createdEnvironment: ptr ICoreWebView2Environment): HRESULT {.stdcall.} =
  echo "Entering SimpleEnvInvoke..."
  if errorCode != S_OK:
    echo "Environment creation failed with error: ", errorCode
    return errorCode
  if createdEnvironment == nil:
    echo "Created environment is nil"
    return E_FAIL
  echo "Environment created successfully at: ", cast[int](createdEnvironment)
  return S_OK

#[proc ControllerInvoke(this: pointer; errorCode: HRESULT; controller: ptr ICoreWebView2Controller): HRESULT {.stdcall.} =
  echo "Entering ControllerInvoke..."
  if errorCode != S_OK:
    echo "Controller creation failed with error: ", errorCode
    return errorCode
  if controller == nil:
    echo "Controller is nil"
    return E_FAIL
  webviewController = controller
  let hr = cast[ptr ICoreWebView2Controller](webviewController).lpVtbl.get_CoreWebView2(webviewController, addr webviewWindow)
  if hr != S_OK:
    echo "get_CoreWebView2 failed with error: ", hr
    return hr
  echo "WebView2 controller initialized successfully"
  discard cast[ptr ICoreWebView2Controller](webviewController).lpVtbl.AddRef(webviewController)
  var settings: pointer
  let hrSettings = cast[ptr ICoreWebView2](webviewWindow).lpVtbl.get_Settings(webviewWindow, addr settings)
  if hrSettings != S_OK:
    echo "get_Settings failed with error: ", hrSettings
    return hrSettings
  let settingsTyped = cast[ptr ICoreWebView2Settings](settings)
  discard settingsTyped.lpVtbl.put_IsScriptEnabled(settingsTyped, TRUE)
  discard settingsTyped.lpVtbl.put_AreDefaultScriptDialogsEnabled(settingsTyped, TRUE)
  discard settingsTyped.lpVtbl.put_IsWebMessageEnabled(settingsTyped, TRUE)
  discard settingsTyped.lpVtbl.put_AreDevToolsEnabled(settingsTyped, FALSE)
  discard settingsTyped.lpVtbl.put_AreDefaultContextMenusEnabled(settingsTyped, TRUE)
  discard settingsTyped.lpVtbl.put_IsStatusBarEnabled(settingsTyped, TRUE)
  discard settingsTyped.lpVtbl.put_IsZoomControlEnabled(settingsTyped, TRUE)
  var bounds: RECT
  GetClientRect(hWnd, addr bounds)
  bounds.top = altezza_bar
  discard cast[ptr ICoreWebView2Controller](webviewController).lpVtbl.put_Bounds(webviewController, bounds)
  discard cast[ptr ICoreWebView2](webviewWindow).lpVtbl.Navigate(webviewWindow, "file://C:/Users/pr30565/Desktop")
  echo "ControllerInvoke completed"
  return S_OK]#

proc WindowProc(hWnd: HWND; uMsg: UINT; wParam: WPARAM; lParam: LPARAM): LRESULT {.stdcall.} =
  case uMsg:
  of WM_DPICHANGED:
    let newWindowSize = cast[ptr RECT](lParam)
    SetWindowPos(hWnd, nil, newWindowSize.left, newWindowSize.top,
                 newWindowSize.right - newWindowSize.left,
                 newWindowSize.bottom - newWindowSize.top,
                 SWP_NOZORDER or SWP_NOACTIVATE)
    return TRUE
  of WM_SIZE:
    if panel_bar != nil:
      SetWindowPos(panel_bar, nil, 0, 0, 1900, 40, 0)
    if webviewController != nil:
      var bounds: RECT
      GetClientRect(hWnd, addr bounds)
      bounds.top = altezza_bar
      discard cast[ptr ICoreWebView2Controller](webviewController).lpVtbl.put_Bounds(webviewController, bounds)
  of WM_DESTROY:
    PostQuitMessage(0)
  else:
    return DefWindowProc(hWnd, uMsg, wParam, lParam)
  return 0

proc mia_crea_webview() =
  echo "Entering mia_crea_webview..."
  if not fileExists("WebView2Loader.dll"):
    echo "WebView2Loader.dll not found in current directory!"
    return
  echo "WebView2Loader.dll found"
  let hModule = LoadLibrary("WebView2Loader.dll")
  if hModule == nil:
    echo "Failed to load WebView2Loader.dll: ", GetLastError()
    return
  echo "WebView2Loader.dll loaded successfully"
  let createEnvProc = cast[CreateCoreWebView2EnvironmentWithOptionsProc](
    GetProcAddress(hModule, "CreateCoreWebView2EnvironmentWithOptions")
  )
  if createEnvProc == nil:
    echo "Failed to get CreateCoreWebView2EnvironmentWithOptions address: ", GetLastError()
    discard FreeLibrary(hModule)
    return
  echo "CreateCoreWebView2EnvironmentWithOptions address obtained"
  var envHandlerVtbl = ICoreWebView2CreateCoreWebView2EnvironmentCompletedHandlerVtbl(
    QueryInterface: QueryInterface,
    AddRef: AddRef,
    Release: Release,
    Invoke: SimpleEnvInvoke
  )
  var envHandler = EnvironmentHandler(lpVtbl: addr envHandlerVtbl)
  echo "Environment handler allocated at: ", cast[int](addr envHandler)
  echo "Calling CreateCoreWebView2EnvironmentWithOptions with handler..."
  let hr = createEnvProc(nil, nil, nil, addr envHandler)
  if hr != S_OK:
    echo "CreateCoreWebView2EnvironmentWithOptions failed with error: ", hr
  else:
    echo "CreateCoreWebView2EnvironmentWithOptions succeeded"
  discard FreeLibrary(hModule)

proc WinMain(hInstance: HINSTANCE; hPrevInstance: HINSTANCE; lpCmdLine: LPWSTR; nShowCmd: int32): int32 {.stdcall.} =
  #discard AllocConsole()
  #discard freopen("CONOUT$", "w", stdout)
  echo "Attempting SetProcessDpiAwarenessContext..."
  if not SetProcessDpiAwarenessContext(DPI_AWARENESS_CONTEXT_PER_MONITOR_AWARE_V2):
    let error1 = GetLastError()
    echo "SetProcessDpiAwarenessContext failed with error: ", error1
    echo "Falling back to SetProcessDPIAware..."
    if not SetProcessDPIAware():
      let error2 = GetLastError()
      echo "SetProcessDPIAware failed with error: ", error2
      echo "Falling back to SetProcessDpiAwareness..."
      if SetProcessDpiAwareness(PROCESS_PER_MONITOR_DPI_AWARE) != S_OK:
        echo "SetProcessDpiAwareness failed with HRESULT: ", GetLastError()
        echo "Proceeding without DPI awareness setting..."
      else:
        echo "SetProcessDpiAwareness succeeded"
    else:
      echo "SetProcessDPIAware succeeded"
  else:
    echo "SetProcessDpiAwarenessContext succeeded"
  echo "Initializing COM with STA..."
  let hrInit = CoInitializeEx(nil, COINIT_APARTMENTTHREADED)
  if hrInit != S_OK:
    echo "CoInitializeEx failed with error: ", hrInit
    #discard getch()
    return int32(hrInit)
  var wndClass: WNDCLASS
  wndClass.style = CS_HREDRAW or CS_VREDRAW
  wndClass.lpfnWndProc = WindowProc
  wndClass.hInstance = hInstance
  wndClass.hCursor = LoadCursor(nil, IDC_ARROW)
  wndClass.hbrBackground = cast[HBRUSH](COLOR_WINDOW + 1)
  wndClass.lpszClassName = APPLICATION_NAME
  echo "Registering window class..."
  if RegisterClass(addr wndClass) == 0:
    echo "RegisterClass failed with error: ", GetLastError()
    #discard getch()
    return int32(GetLastError())
  echo "Creating window..."
  hWnd = CreateWindowEx(
    0,
    APPLICATION_NAME,
    APPLICATION_NAME,
    WS_OVERLAPPEDWINDOW,
    100, 100, 800, 800,
    nil, nil, hInstance, nil
  )
  if hWnd == nil:
    echo "Errore in CreateWindowEx: ", GetLastError()
    #discard getch()
    return int32(GetLastError())
  echo "Window created with hWnd: ", cast[int](hWnd)
  ShowWindow(hWnd, nShowCmd)
  #[echo "Creating toolbar..."
  panel_bar = CreateWindowEx(0, TOOLBARCLASSNAME, nil, WS_CHILD or WS_VISIBLE or WS_SIZEBOX or WS_BORDER,
                            0, 0, 0, 0, hWnd, nil, nil, nil)
  if panel_bar == nil:
    echo "Failed to create toolbar: ", GetLastError()
  else:
    echo "Toolbar created"]#
  mia_crea_webview()
  echo "Updating window..."
  UpdateWindow(hWnd)
  echo "Entering message loop..."
  var msg: MSG
  while GetMessage(addr msg, nil, 0, 0) > 0:
    TranslateMessage(addr msg)
    DispatchMessage(addr msg)
  echo "Exiting message loop..."
  CoUninitialize()
  echo "COM uninitialized"
  return 0

when isMainModule:
  discard WinMain(GetModuleHandle(nil), nil, GetCommandLine(), SW_SHOW)