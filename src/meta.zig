/// Browsers for webui
pub const Browsers = enum(u8) {
    /// 0. No web browser
    NoBrowser = 0,
    /// 1. Default recommended web browser
    AnyBrowser,
    /// 2. Google Chrome
    Chrome,
    /// 3. Mozilla Firefox
    Firefox,
    /// 4. Microsoft Edge
    Edge,
    /// 5. Apple Safari
    Safari,
    /// 6. The Chromium Project
    Chromium,
    /// 7. Opera Browser
    Opera,
    /// 8. The Brave Browser
    Brave,
    /// 9. The Vivaldi Browser
    Vivaldi,
    /// 10. The Epic Browser
    Epic,
    /// 11. The Yandex Browser
    Yandex,
    /// 12. Any Chromium based browser
    ChromiumBased,
    /// 13. WebView (Non-web-browser)
    Webview,
};

/// runtime for js
pub const Runtimes = enum(u8) {
    /// 0. Prevent WebUI from using any runtime for .js and .ts files
    None = 0,
    /// 1. Use Deno runtime for .js and .ts files
    Deno,
    /// 2. Use Nodejs runtime for .js files
    NodeJS,
    /// 3. Use Bun runtime for .js and .ts files
    Bun,
};

/// Events for webui
pub const Events = enum(u8) {
    /// 0. Window disconnection event
    EVENT_DISCONNECTED = 0,
    /// 1. Window connection event
    EVENT_CONNECTED,
    /// 2. Mouse click event
    EVENT_MOUSE_CLICK,
    /// 3. Window navigation event
    EVENT_NAVIGATION,
    /// 4. Function call event
    EVENT_CALLBACK,
};

/// config for webui behavior
pub const Config = enum(u8) {
    /// Control if `show()`,`webui_show_browser`,`webui_show_wv` should wait
    /// for the window to connect before returns or not.
    /// Default: True
    show_wait_connection = 0,
    /// Control if WebUI should block and process the UI events
    /// one a time in a single thread `True`, or process every
    /// event in a new non-blocking thread `False`. This updates
    /// all windows. You can use `setEventBlocking()` for
    /// a specific single window update.
    /// Default: False
    ui_event_blocking = 1,
    /// Automatically refresh the window UI when any file in the
    /// root folder gets changed.
    /// Default: False
    folder_monitor,
    /// Allow multiple clients to connect to the same window,
    /// This is helpful for web apps (non-desktop software),
    /// Please see the documentation for more details.
    /// Default: False
    multi_client,
    /// Allow multiple clients to connect to the same window,
    /// This is helpful for web apps (non-desktop software),
    /// Please see the documentation for more details.
    /// Default: False
    use_cookies,
};
