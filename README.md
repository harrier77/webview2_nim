# webview2_nim

> **Based on [bung87/webview2](https://github.com/bung87/webview2)** — this project is a fork/adaptation of bung87's pure-Nim WebView2 COM wrapper. The low-level COM bindings, WebView2 loader, and environment/controller handlers originate from that repository.

**Minimal, pure Nim WebView2 wrapper for Windows. No Electron. No C dependencies. Just copy and use.**

`webview2_nim` is a thin wrapper around the WebView2 COM API built on top of [bung87/webview2](https://github.com/bung87/webview2) — nothing but the standard library and `winim`. It lets you build GUI applications using web technologies (HTML/CSS/JS) rendered by Microsoft Edge WebView2, without pulling in Electron, CEF, or even the otherwise excellent `webview` library by zserge (which depends on a C glue layer and external DLLs).

The philosophy: **import the code directly, call a few procs, and you're done.**

## Why this exists

This project builds upon [bung87/webview2](https://github.com/bung87/webview2), which provides pure-Nim COM bindings for the WebView2 API without any C glue layer.

The main differences from other Nim WebView2 wrappers:

- **No C intermediate library** — unlike `webview` by zserge, there's no external C layer or additional DLLs to ship.
- **No heavy frameworks** — just the WebView2 COM API wrapped in Nim with `winim`.
- **Copy and use** — drop `platforms/` into your project, `import miowv`, call `mio_new_webview` + `run`, and you have a window with a WebView2 inside.
- **Async bridge** — the `bindProcs` macro and callback infrastructure add optional Nim↔JS communication on top of the base wrapper.

## How it works

- **`static/index.html`** is compiled into your executable at build time via Nim's `staticRead`, and rendered with WebView2's `NavigateToString`. No file-system access needed at runtime: your UI is literally part of the binary.
- **Two‑way Nim ↔ JavaScript communication** uses a single callback proc (`externalInvokeCB`). JavaScript calls `window.chrome.webview.postMessage`, Nim receives the message, processes it, and sends a result back via `ExecuteScript` — simple, explicit, no magic.
- Everything runs on the Windows message loop. No async/await, no threads for the UI — just `GetMessage` / `DispatchMessage`.

## Quick start

```bash
# Compile and run the demo
nim c -r miowv.nim
```

A window opens showing an HTML page with an input box and a button. Type a message, click the button, and the text travels:

```
JS ──postMessage──→ Nim (prints "pippo")
Nim ──ExecuteScript──→ JS (logs result in browser console)
```

## Usage

Copy the entire `platforms/` directory into your project. Then:

```nim
import miowv

var w = mio_new_webview(width=1024, height=768)
# Loads static/index.html embedded in the exe by default.
# To load a URL instead:  mio_new_webview(path = "https://example.com")

w.externalInvokeCB = proc (w: Webview; arg: cstring) =
  # Handle messages from JavaScript
  let json = parseJson($arg)
  echo "Received: ", json["name"].getStr()
  # Send a result back:  w.eval("window.callbackId(result)")

w.run()
```

That's it. Your Nim proc is called from JavaScript, and you can push results back. No sockets, no HTTP servers, no JSON-RPC.

## API reference

### Core — enough for 90% of apps

| Proc | Purpose |
|------|---------|
| `mio_new_webview(path, title, width, height, resizable, debug, callback)` | Create a window with a WebView2 inside. If `path` is empty (default), the bundled `static/index.html` is used. Returns `nil` on failure. |
| `w.run()` | Start the Windows message loop — blocks until the window closes. |
| `w.externalInvokeCB = proc(w, arg)` | Set the callback that receives JSON messages from JavaScript. |
| `w.eval(js)` | Execute arbitrary JavaScript in the WebView (e.g. to send data back). |
| `w.setHtml(html)` | Replace the page content with raw HTML via `NavigateToString`. |
| `w.navigate(url)` | Navigate to a URL. |
| `w.setTitle(title)` | Change the window title. |
| `w.dispatch(fn)` | Run a proc on the UI thread (from any thread). |

### Advanced — for custom Win32 UI

If you want to add a native Win32 toolbar, custom menus, or integrate the WebView into a larger Win32 window:

| Proc | What it does |
|------|--------------|
| `miowebview_init(w)` | Registers the window class, creates the Win32 window, initialises OLE, sets DPI awareness, and calls `mio_embed`. Reuses the WebView if already created. |
| `mio_embed(w)` | Creates the WebView2 environment and controller, sets up the JS bridge script and the `WebMessageReceived` handler, then navigates to the initial URL or embedded HTML. Blocks synchronously until the controller is ready. |
| `mio_move_client(w, top)` | Resizes the WebView bounds inside the window. The `top` parameter (default 62) leaves space for a custom toolbar. Call after creating a toolbar or when the window resizes. |

For example, to add a Win32 toolbar:

```nim
w.miowebview_init()
var tb = CreateWindowEx(0, TOOLBARCLASSNAME, nil, ...)
ShowWindow(tb, SW_SHOW)
w.mio_move_client(w, 62)  # make room for the toolbar
```

### Utilities

| Proc | Purpose |
|------|---------|
| `w.css(css)` | Inject CSS at document start. |
| `w.addUserScriptAtDocumentStart(script)` | Inject JS that runs before any page script. |
| `w.addUserScriptAtDocumentEnd(script)` | Inject JS after DOMContentLoaded. |
| `w.mioMaximize()` | Maximise the window. |
| `w.bindProcs(scope, procs)` | Macro — auto-generates JS stubs for Nim procs (convenience helper, not required). |
| `w.destroy()` / `w.terminate()` | Clean up and quit. |

## Project structure

```
├── miowv.nim                 # Public API — import this
├── static/
│   └── index.html            # Bundled default UI (compiled into your exe)
├── platforms/
│   ├── win/
│   │   ├── miowebview2.nim   # Proc implementations (run, eval, navigate, …)
│   │   ├── dpi_util.nim      # DPI awareness helper
│   │   └── webview2/         # Low‑level COM wrappers for WebView2 (from bung87/webview2)
│   │       ├── types.nim     # WebViewObj, WebViewPrivObj
│   │       ├── controllers.nim # Environment & controller creation
│   │       ├── com/          # COM vtbl definitions for all WebView2 interfaces
│   │       ├── loader.nim    # WebView2 runtime loader
│   │       └── …
│   └── macos/                # macOS stubs (experimental, from bung87/webview2)
└── miowv.exe                 # Demo binary (not tracked)
```

## Dependencies

- **Windows 10+** with [WebView2 Runtime](https://developer.microsoft.com/en-us/microsoft-edge/webview2/) (included in Windows 11).
- **Nim ≥ 1.6**.
- **`winim`** — the only external Nim package (required for COM and Win32 types).
- Everything else is from Nim's standard library.

## License

MIT
