//! This file is direct exposure of webui C functions with Zig-ified signatures!

const webui = @import("webui.zig");

const Browser = webui.Browser;
const Config = webui.Config;
const Event = webui.Event;
const EventKind = webui.EventKind;
const Runtime = webui.Runtime;

/// @brief Create a new WebUI window object.
///
/// @return Returns the window number.
///
/// @example const my_window: usize = webui_new_window();
pub extern fn webui_new_window() callconv(.C) usize;

/// @brief Create a new webui window object using a specified window number.
///
/// @param window_number The window number (should be > 0, and < WEBUI_MAX_IDS)
///
/// @return Returns the same window number if success.
///
/// @example const my_window: usize = webui_new_window_id(123);
pub extern fn webui_new_window_id(window_number: usize) callconv(.C) usize;

/// @brief Get a free window number that can be used with `webui_new_window_id()`
///
/// @return Returns the first available free window number. Starting from 1.
///
/// @example const my_window: usize = webui_get_new_window_id();
pub extern fn webui_get_new_window_id() callconv(.C) usize;

/// @brief Bind an HTML element and a Javascript object with a backend function. Empty
/// element name means all events.
///
/// @param window The window number
/// @param element The HTML element / Javascript object
/// @param func The callback function
///
/// @return Returns a unique bind ID.
///
/// @example webui_bind(my_window, "myFunction", myFunction);
pub extern fn webui_bind(
    window: usize,
    element: [*:0]const u8,
    func: *const fn (e: *Event) callconv(.C) void,
) callconv(.C) usize;

/// @brief Use this API after using `webui_bind()` to add any user data to it that can be
/// read later using `webui_get_context()`.
///
/// @param window The window number
/// @param element The HTML element / JavaScript object
/// @param context Any user data
///
/// @example
/// webui_bind(myWindow, "myFunction", myFunction);
///
/// webui_set_context(myWindow, "myFunction", myData);
///
/// void myFunction(webui_event_t* e) {
///   void* myData = webui_get_context(e);
/// }
pub extern fn webui_set_context(
    window: usize,
    element: [*:0]const u8,
    context: *anyopaque,
) callconv(.C) void;

/// @brief Get user data that is set using `webui_set_context()`.
///
/// @param e The event struct
///
/// @return Returns user data pointer.
///
/// @example
/// webui_bind(myWindow, "myFunction", myFunction);
///
/// webui_set_context(myWindow, "myFunction", myData);
///
/// void myFunction(webui_event_t* e) {
///   void* myData = webui_get_context(e);
/// }
pub extern fn webui_get_context(
    e: *Event,
) callconv(.C) *anyopaque;

/// @brief Get the recommended web browser ID to use. If you
/// are already using one, this function will return the same ID.
///
/// @param The window number
///
/// @return Returns a web browser ID.
///
/// @example const browser_id: usize = webui_get_best_browser(my_window);
pub extern fn webui_get_best_browser(window: usize) callconv(.C) Browser;

/// @brief Show a window using embedded HTML, or a file. If the window is already
/// open, it will be refreshed. This will refresh all windows in multi-client mode.
///
/// @param window The window number
/// @param content The HTML, URL, Or a local file
///
/// @return Returns True if showing the window is successed.
///
/// @example webui_show(my_window, "<html>...</html>"); |
/// webui_show(my_window, "index.html"); | webui_show(my_window, "http://...");
pub extern fn webui_show(window: usize, content: [*:0]const u8) callconv(.C) bool;

/// @brief Show a window using embedded HTML, or a file. If the window is already
/// open, it will be refreshed. Single client.
///
/// @param e The event struct
/// @param content The HTML, URL, Or a local file
///
/// @return Returns True if showing the window is successed.
///
/// @example webui_show_client(e, "<html>...</html>"); |
/// webui_show_client(e, "index.html"); | webui_show_client(e, "http://...");
pub extern fn webui_show_client(e: *Event, content: [*:0]const u8) callconv(.C) bool;

/// @brief Same as `webui_show()`. But using a specific web browser.
///
/// @param window The window number
/// @param content The HTML, URL, Or a local file
/// @param browser The web browser to be used
///
/// @return Returns True if showing the window is successed.
///
/// @example webui_show_browser(my_window, "<html>...</html>", .Chrome); |
/// webui_show_browser(my_window, "index.html", .Firefox);
pub extern fn webui_show_browser(
    window: usize,
    content: [*:0]const u8,
    browser: Browser,
) callconv(.C) bool;

/// @brief Same as `webui_show()`. But start only the web server and return the URL.
/// No window will be shown.
///
/// @param window The window number
/// @param content The HTML, Or a local file
///
/// @return Returns the url of this window server.
///
/// @example const url: [*:0]const u8 = webui_start_server(my_window, "/full/root/path");
pub extern fn webui_start_server(
    window: usize,
    content: [*:0]const u8,
) callconv(.C) [*:0]const u8;

/// @brief Show a WebView window using embedded HTML, or a file. If the window is already
/// open, it will be refreshed. Note: Win32 need `WebView2Loader.dll`.
///
/// @param window The window number
/// @param content The HTML, URL, Or a local file
///
/// @return Returns True if showing the WebView window is successed.
///
/// @example webui_show_wv(my_window, "<html>...</html>"); | webui_show_wv(my_window,
/// "index.html"); | webui_show_wv(my_window, "http://...");
pub extern fn webui_show_wv(window: usize, content: [*:0]const u8) callconv(.C) bool;

/// @brief Set the window in Kiosk mode (Full screen).
///
/// @param window The window number
/// @param status True or False
///
/// @example webui_set_kiosk(my_window, true);
pub extern fn webui_set_kiosk(window: usize, status: bool) callconv(.C) void;

/// @brief Add a user-defined web browser's CLI parameters.
///
/// @param window The window number
/// @param params Command line parameters
///
/// @example webui_set_custom_parameters(myWindow, "--remote-debugging-port=9222");
pub extern fn webui_set_custom_parameters(window: usize, params: [*:0]const u8) callconv(.C) void;

/// @brief Set the window with high-contrast support. Useful when you want to
/// build a better high-contrast theme with CSS.
///
/// @param window The window number
/// @param status True or False
///
/// @example webui_set_high_contrast(my_window, true);
pub extern fn webui_set_high_contrast(window: usize, status: bool) callconv(.C) void;

/// @brief Get OS high contrast preference.
///
/// @return Returns True if OS is using high contrast theme
///
/// @example const hc: bool = webui_is_high_contrast();
pub extern fn webui_is_high_contrast() callconv(.C) bool;

/// @brief Check if a web browser is installed.
///
/// @return Returns True if the specified browser is available.
///
/// @example const status: bool = webui_browser_exist(.Chrome);
pub extern fn webui_browser_exist(browser: Browser) callconv(.C) bool;

/// @brief Wait until all opened windows get closed.
///
/// @example webui_wait();
pub extern fn webui_wait() callconv(.C) void;

/// @brief Close a specific window only. The window object will still exist.
/// All clients.
///
/// @param The window number
///
/// @example webui_close(my_window);
pub extern fn webui_close(window: usize) callconv(.C) void;

/// @brief Close a specific client.
///
/// @param e The event struct
///
/// @example webui_close_client(e);
pub extern fn webui_close_client(e: *Event) callconv(.C) void;

/// @brief Close a specific window and free all memory resources.
///
/// @param window The window number
///
/// @example webui_destroy(my_window);
pub extern fn webui_destroy(window: usize) callconv(.C) void;

/// @brief Close all open windows. `webui_wait()` will return (Break).
///
/// @example webui_exit();
pub extern fn webui_exit() callconv(.C) void;

/// @brief Set the web-server root folder path for a specific window.
///
/// @param window The window number
/// @param path The local folder full path
///
/// @example webui_set_root_folder(my_window, "/home/Foo/Bar/");
pub extern fn webui_set_root_folder(window: usize, path: [*:0]const u8) callconv(.C) bool;

/// @brief Set the web-server root folder path for all windows. Should be used
/// before `webui_show()`.
///
/// @param path The local folder full path
///
/// @example webui_set_default_root_folder("/home/Foo/Bar/");
pub extern fn webui_set_default_root_folder(path: [*:0]const u8) callconv(.C) bool;

/// @brief Set a custom handler to serve files. This custom handler should
/// return full HTTP header and body.
/// This deactivates any previous handler set with `webui_set_file_handler_window`
///
/// @param window The window number
/// @param handler The handler function: `void myHandler(filename: [*:0]const u8,
/// length: *c_int)`
///
/// @example webui_set_file_handler(my_window, myHandlerFunction);
pub extern fn webui_set_file_handler(
    window: usize,
    handler: *const fn (filename: [*:0]const u8, length: *c_int) callconv(.C) ?*const anyopaque,
) callconv(.C) void;

/// @brief Set a custom handler to serve files. This custom handler should
/// return full HTTP header and body.
/// This deactivates any previous handler set with `webui_set_file_handler`
///
/// @param window The window number
/// @param handler The handler function: `void myHandler(window: usize, filename: [*:0]const u8,
/// length: *c_int)`
///
/// @example webui_set_file_handler_window(my_window, myHandlerFunction);
pub extern fn webui_set_file_handler_window(
    window: usize,
    handler: *const fn (
        window: usize,
        filename: [*:0]const u8,
        length: *c_int,
    ) callconv(.C) ?*const anyopaque,
) callconv(.C) void;

///
/// @brief Use this API to set a file handler response if your backend need async
/// response for `webui_set_file_handler()`.
///
/// @param window The window number
/// @param response The response buffer
/// @param length The response size
///
/// @example webui_interface_set_response_file_handler(myWindow, buffer, 1024);
///
pub extern fn webui_interface_set_response_file_handler(
    window: usize,
    response: ?*const anyopaque,
    length: usize,
) callconv(.C) void;

/// @brief Check if the specified window is still running.
///
/// @param window The window number
///
/// @example webui_is_shown(my_window);
pub extern fn webui_is_shown(window: usize) callconv(.C) bool;

/// @brief Set the maximum time in seconds to wait for the window to connect.
/// This effect `show()` and `wait()`. Value of `0` means wait forever.
///
/// @param second The timeout in seconds
///
/// @example webui_set_timeout(30);
pub extern fn webui_set_timeout(second: usize) callconv(.C) void;

/// @brief Set the default embedded HTML favicon.
///
/// @param window The window number
/// @param icon The icon as string: `<svg>...</svg>`
/// @param icon_type The icon type: `image/svg+xml`
///
/// @example webui_set_icon(my_window, "<svg>...</svg>", "image/svg+xml");
pub extern fn webui_set_icon(
    window: usize,
    icon: [*:0]const u8,
    icon_type: [*:0]const u8,
) callconv(.C) void;

/// @brief Encode text to Base64. The returned buffer need to be freed.
///
/// @param str The string to encode (Should be null terminated)
///
/// @return Returns the base64 encoded string
///
/// @example const base64: [*:0]u8 = webui_encode("Foo Bar");
pub extern fn webui_encode(str: [*:0]const u8) callconv(.C) ?[*:0]u8;

/// @brief Decode a Base64 encoded text. The returned buffer need to be freed.
///
/// @param str The string to decode (Should be null terminated)
///
/// @return Returns the base64 decoded string
///
/// @example const str: [*:0]u8 = webui_decode("SGVsbG8=");
pub extern fn webui_decode(str: [*:0]const u8) callconv(.C) ?[*:0]u8;

/// @brief Safely free a buffer allocated by WebUI using `webui_malloc()`.
///
/// @param ptr The buffer to be freed
///
/// @example webui_free(my_buffer);
pub extern fn webui_free(ptr: *anyopaque) callconv(.C) void;

/// @brief Copy raw data.
///
/// @param dest Destination memory pointer
/// @param src Source memory pointer
/// @param count Bytes to copy
///
/// @example webui_memcpy(myBuffer, myData, 64);
pub extern fn webui_memcpy(
    dest: *anyopaque,
    src: *anyopaque,
    count: usize,
) callconv(.C) void;

/// @brief Safely allocate memory using the WebUI memory management system. It
/// can be safely freed using `webui_free()` at any time.
///
/// @param size The size of memory in bytes
///
/// @example var my_buffer: [*:0]u8 = @ptrCast(@alignCast(webui_malloc(1024)));
pub extern fn webui_malloc(size: usize) callconv(.C) ?*anyopaque;

/// @brief Safely send raw data to the UI. All clients.
///
/// @param window The window number
/// @param function The JavaScript function to receive raw data: `function
/// myFunc(my_data){}`
/// @param raw The raw data buffer
/// @param size The raw data size in bytes
///
/// @example webui_send_raw(my_window, "myJavaScriptFunc", my_buffer, 64);
pub extern fn webui_send_raw(
    window: usize,
    function: [*:0]const u8,
    raw: [*]const anyopaque,
    size: usize,
) callconv(.C) void;

/// @brief Safely send raw data to the UI. Single client.
///
/// @param e The event struct
/// @param function The JavaScript function to receive raw data: `function
/// myFunc(my_data){}`
/// @param raw The raw data buffer
/// @param size The raw data size in bytes
///
/// @example webui_send_raw_client(e, "myJavaScriptFunc", my_buffer, 64);
pub extern fn webui_send_raw_client(
    e: *Event,
    function: [*:0]const u8,
    raw: [*]const anyopaque,
    size: usize,
) callconv(.C) void;

/// @brief Set a window in hidden mode. Should be called before `webui_show()`.
///
/// @param window The window number
/// @param status The status: True or False
///
/// @example webui_set_hide(my_window, true);
pub extern fn webui_set_hide(window: usize, status: bool) callconv(.C) void;

/// @brief Set the window size.
///
/// @param window The window number
/// @param width The window width
/// @param height The window height
///
/// @example webui_set_size(my_window, 800, 600);
pub extern fn webui_set_size(window: usize, width: u32, height: u32) callconv(.C) void;

/// @brief Set the window minimum size.
///
/// @param window The window number
/// @param width The window width
/// @param height The window height
///
/// @example webui_set_minimum_size(my_window, 800, 600);
pub extern fn webui_set_minimum_size(
    window: usize,
    width: u32,
    height: u32,
) callconv(.C) void;

/// @brief Set the window position.
///
/// @param window The window number
/// @param x The window X
/// @param y The window Y
///
/// @example webui_set_position(my_window, 100, 100);
pub extern fn webui_set_position(window: usize, x: u32, y: u32) callconv(.C) void;

/// @brief Set the web browser profile to use. An empty `name` and `path` means
/// the default user profile. Need to be called before `webui_show()`.
///
/// @param window The window number
/// @param name The web browser profile name
/// @param path The web browser profile full path
///
/// @example webui_set_profile(my_window, "Bar", "/Home/Foo/Bar"); |
/// webui_set_profile(my_window, "", "");
pub extern fn webui_set_profile(
    window: usize,
    name: [*:0]const u8,
    path: [*:0]const u8,
) callconv(.C) void;

/// @brief Set the web browser proxy server to use. Need to be called before `webui_show()`.
///
/// @param window The window number
/// @param proxy_server The web browser proxy_server
///
/// @example webui_set_proxy(my_window, "http://127.0.0.1:8888");
pub extern fn webui_set_proxy(
    window: usize,
    proxy_server: [*:0]const u8,
) callconv(.C) void;

/// @brief Get current URL of a running window.
///
/// @param window The window number
///
/// @return Returns the full URL string
///
/// @example const url: [*:0]const u8 = webui_get_url(my_window);
pub extern fn webui_get_url(window: usize) callconv(.C) [*:0]const u8;

/// @brief Open an URL in the native default web browser.
///
/// @param url The URL to open
///
/// @example webui_open_url("https://webui.me");
pub extern fn webui_open_url(url: [*:0]const u8) callconv(.C) void;

/// @brief Allow a specific window address to be accessible from a public network.
///
/// @param window The window number
/// @param status True or False
///
/// @example webui_set_public(my_window, true);
pub extern fn webui_set_public(window: usize, status: bool) callconv(.C) void;

/// @brief Navigate to a specific URL. All clients.
///
/// @param window The window number
/// @param url Full HTTP URL
///
/// @example webui_navigate(my_window, "http://domain.com");
pub extern fn webui_navigate(window: usize, url: [*:0]const u8) callconv(.C) void;

/// @brief Navigate to a specific URL. Single client.
///
/// @param e The event struct
/// @param url Full HTTP URL
///
/// @example webui_navigate_client(e, "http://domain.com");
pub extern fn webui_navigate_client(e: *Event, url: [*:0]const u8) callconv(.C) void;

/// @brief Free all memory resources. Should be called only at the end.
///
/// @example
/// webui_wait();
/// webui_clean();
pub extern fn webui_clean() callconv(.C) void;

/// @brief Delete all local web-browser profiles folder. It should be called at the
/// end.
///
/// @example
/// webui_wait();
/// webui_delete_all_profiles();
/// webui_clean();
pub extern fn webui_delete_all_profiles() callconv(.C) void;

/// @brief Delete a specific window web-browser local folder profile.
///
/// @param window The window number
///
/// @example
/// webui_wait();
/// webui_delete_profile(my_window);
/// webui_clean();
///
/// @note This can break functionality of other windows if using the same
/// web-browser.
pub extern fn webui_delete_profile(window: usize) callconv(.C) void;

/// @brief Get the ID of the parent process (The web browser may re-create
/// another new process).
///
/// @param window The window number
///
/// @return Returns the parent process ID as integer
///
/// @example const id: usize = webui_get_parent_process_id(my_window);
pub extern fn webui_get_parent_process_id(window: usize) callconv(.C) usize;

/// @brief Get the ID of the last child process.
///
/// @param window The window number
///
/// @return Returns the child process ID as integer
///
/// @example const id: usize = webui_get_child_process_id(my_window);
pub extern fn webui_get_child_process_id(window: usize) callconv(.C) usize;

/// @brief Get the network port of a running window.
/// This can be useful to determine the HTTP link of `webui.js`
///
/// @param window The window number
///
/// @return Returns the network port of the window
///
/// @example const port: usize = webui_get_port(my_window);
pub extern fn webui_get_port(window: usize) callconv(.C) usize;

/// @brief Set a custom web-server/websocket network port to be used by WebUI.
/// This can be useful to determine the HTTP link of `webui.js` in case
/// you are trying to use WebUI with an external web-server like NGINX.
///
/// @param window The window number
/// @param port The web-server network port WebUI should use
///
/// @return Returns True if the port is free and usable by WebUI
///
/// @example const ret: bool = webui_set_port(my_window, 8080);
pub extern fn webui_set_port(window: usize, port: usize) callconv(.C) bool;

/// @brief Get an available usable free network port.
///
/// @return Returns a free port
///
/// @example const port: usize = webui_get_free_port();
pub extern fn webui_get_free_port() callconv(.C) usize;

/// @brief Control the WebUI behaviour. It's recommended to be called at the beginning.
///
/// @param option The desired option from `Config` enum
/// @param status The status of the option, `true` or `false`
///
/// @example webui_set_config(.show_wait_connection, false);
pub extern fn webui_set_config(option: Config, status: bool) callconv(.C) void;

/// @brief Control if UI events coming from this window should be processed
/// one at a time in a single blocking thread `True`, or process every event in
/// a new non-blocking thread `False`. This update single window. You can use
/// `webui_set_config(.ui_event_blocking, ...)` to update all windows.
///
/// @param window The window number
/// @param status The blocking status `true` or `false`
///
/// @example webui_set_event_blocking(my_window, true);
pub extern fn webui_set_event_blocking(window: usize, status: bool) callconv(.C) void;

/// @brief Get the HTTP mime type of a file.
///
/// @return Returns the HTTP mime string
///
/// @example const mime: [*:0]const u8 = webui_get_mime_type("foo.png");
pub extern fn webui_get_mime_type(file: [*:0]const u8) callconv(.C) [*:0]const u8;

// -- SSL/TLS -------------------------

/// @brief Set the SSL/TLS certificate and the private key content, both in PEM
/// format. This works only with `webui-2-secure` library. If set empty WebUI
/// will generate a self-signed certificate.
///
/// @param certificate_pem The SSL/TLS certificate content in PEM format
/// @param private_key_pem The private key content in PEM format
///
/// @return Returns True if the certificate and the key are valid.
///
/// @example const ret: bool = webui_set_tls_certificate("-----BEGIN
/// CERTIFICATE-----\n...", "-----BEGIN PRIVATE KEY-----\n...");
pub extern fn webui_set_tls_certificate(
    certificate_pem: [*:0]const u8,
    private_key_pem: [*:0]const u8,
) callconv(.C) bool;

// -- JavaScript ----------------------

/// @brief Run JavaScript without waiting for the response. All clients.
///
/// @param window The window number
/// @param script The JavaScript to be run
///
/// @example webui_run(my_window, "alert('Hello');");
pub extern fn webui_run(window: usize, script: [*:0]const u8) callconv(.C) void;

/// @brief Run JavaScript without waiting for the response. Single client.
///
/// @param e The event struct
/// @param script The JavaScript to be run
///
/// @example webui_run_client(e, "alert('Hello');");
pub extern fn webui_run_client(e: *Event, script: [*:0]const u8) callconv(.C) void;

/// @brief Run JavaScript and get the response back. Work only in single client mode.
/// Make sure your local buffer can hold the response.
///
/// @param window The window number
/// @param script The JavaScript to be run
/// @param timeout The execution timeout in seconds
/// @param buffer The local buffer to hold the response
/// @param buffer_length The local buffer size
///
/// @return Returns True if there is no execution error
///
/// @example const err: bool = webui_script(my_window, "return 4 + 6;", 0, my_buffer, my_buffer_size);
pub extern fn webui_script(
    window: usize,
    script: [*:0]const u8,
    timeout: usize,
    buffer: [*]u8,
    buffer_length: usize,
) callconv(.C) bool;

/// @brief Run JavaScript and get the response back. Single Client.
/// Make sure your local buffer can hold the response.
///
/// @param e The event struct
/// @param script The JavaScript to be run
/// @param timeout The execution timeout in seconds
/// @param buffer The local buffer to hold the response
/// @param buffer_length The local buffer size
///
/// @return Returns True if there is no execution error
///
/// @example const err: bool = webui_script_client(e, "return 4 + 6;", 0, my_buffer, my_buffer_size);
pub extern fn webui_script_client(
    e: *Event,
    script: [*:0]const u8,
    timeout: usize,
    buffer: [*]u8,
    buffer_length: usize,
) callconv(.C) bool;

/// @brief Choose between Deno and Nodejs as runtime for .js and .ts files.
///
/// @param window The window number
/// @param runtime .Deno | .Bun | .Nodejs | .None
///
/// @example webui_set_runtime(my_window, .Deno);
pub extern fn webui_set_runtime(window: usize, runtime: Runtime) callconv(.C) void;

/// @brief Get how many arguments there are in an event.
///
/// @param e The event struct
///
/// @return Returns the arguments count.
///
/// @example const count: usize = webui_get_count(e);
pub extern fn webui_get_count(e: *Event) callconv(.C) usize;

/// @brief Get an argument as integer at a specific index.
///
/// @param e The event struct
/// @param index The argument position starting from 0
///
/// @return Returns argument as integer
///
/// @example const my_num: i64 = webui_get_int_at(e, 0);
pub extern fn webui_get_int_at(e: *Event, index: usize) callconv(.C) i64;

/// @brief Get the first argument as integer.
///
/// @param e The event struct
///.
/// @return Returns argument as integer
///
/// @example const my_num: i64 = webui_get_int(e);
pub extern fn webui_get_int(e: *Event) callconv(.C) i64;

/// @brief Get an argument as float at a specific index.
///
/// @param e The event struct
/// @param index The argument position starting from 0
///
/// @return Returns argument as float
///
/// @example const my_num: f64 = webui_get_float_at(e, 0);
pub extern fn webui_get_float_at(e: *Event, index: usize) callconv(.C) f64;

/// @brief Get the first argument as float.
///
/// @param e The event struct
///
/// @return Returns argument as float
///
/// @example const my_num: f64 = webui_get_float(e);
pub extern fn webui_get_float(e: *Event) callconv(.C) f64;

/// @brief Get an argument as string at a specific index.
///
/// @param e The event struct
/// @param index The argument position starting from 0
///
/// @return Returns argument as string
///
/// @example const my_str: [*:0]const u8 = webui_get_string_at(e, 0);
pub extern fn webui_get_string_at(e: *Event, index: usize) callconv(.C) [*:0]const u8;

/// @brief Get the first argument as string.
///
/// @param e The event struct
///
/// @return Returns argument as string
///
/// @example const my_str: [*:0]const u8 = webui_get_string(e);
pub extern fn webui_get_string(e: *Event) callconv(.C) [*:0]const u8;

/// @brief Get an argument as boolean at a specific index.
///
/// @param e The event struct
/// @param index The argument position starting from 0
///
/// @return Returns argument as boolean
///
/// @example const my_bool: bool = webui_get_bool_at(e, 0);
pub extern fn webui_get_bool_at(e: *Event, index: usize) callconv(.C) bool;

/// @brief Get the first argument as boolean.
///
/// @param e The event struct
///
/// @return Returns argument as boolean
///
/// @example const my_bool: bool = webui_get_bool(e);
pub extern fn webui_get_bool(e: *Event) callconv(.C) bool;

/// @brief Get the size in bytes of an argument at a specific index.
///
/// @param e The event struct
/// @param index The argument position starting from 0
///
/// @return Returns size in bytes
///
/// @example const arg_len: usize = webui_get_size_at(e, 0);
pub extern fn webui_get_size_at(e: *Event, index: usize) callconv(.C) usize;

/// @brief Get size in bytes of the first argument.
///
/// @param e The event struct
///
/// @return Returns size in bytes
///
/// @example const arg_len: usize = webui_get_size(e);
pub extern fn webui_get_size(e: *Event) callconv(.C) usize;

/// @brief Return the response to JavaScript as integer.
///
/// @param e The event struct
/// @param n The integer to be send to JavaScript
///
/// @example webui_return_int(e, 123);
pub extern fn webui_return_int(e: *Event, n: i64) callconv(.C) void;

/// @brief Return the response to JavaScript as float.
///
/// @param e The event struct
/// @param f The float number to be send to JavaScript
///
/// @example webui_return_float(e, 123.456);
pub extern fn webui_return_float(e: *Event, f: f64) callconv(.C) void;

/// @brief Return the response to JavaScript as string.
///
/// @param e The event as struct
/// @param n The string to be send to JavaScript
///
/// @example webui_return_string(e, "Response...");
pub extern fn webui_return_string(e: *Event, s: [*:0]const u8) callconv(.C) void;

/// @brief Return the response to JavaScript as boolean.
///
/// @param e The event struct
/// @param n The boolean to be send to JavaScript
///
/// @example webui_return_bool(e, true);
pub extern fn webui_return_bool(e: *Event, b: bool) callconv(.C) void;

// -- Wrapper's Interface -------------

/// @brief Bind a specific HTML element click event with a function. Empty element means all events.
///
/// @param window The window number
/// @param element The element ID
/// @param func The callback as myFunc(Window, EventKind, Element, EventNumber, BindID)
///
/// @return Returns unique bind ID
///
/// @example const id: usize = webui_interface_bind(my_window, "myID", myCallback);
pub extern fn webui_interface_bind(
    window: usize,
    element: [*:0]const u8,
    func: *const fn (
        window_: usize,
        event: EventKind,
        element: [*:0]u8,
        event_number: usize,
        bind_id: usize,
    ) void,
) callconv(.C) usize;

/// @brief When using `webui_interface_bind()`, you may need this function to easily set a response.
///
/// @param window The window number
/// @param event_number The event number
/// @param response The response as string to be send to JavaScript
///
/// @example webui_interface_set_response(my_window, e.event_number, "Response...");
pub extern fn webui_interface_set_response(
    window: usize,
    event_number: usize,
    response: [*:0]const u8,
) callconv(.C) void;

/// @brief Check if the app is still running.
///
/// @return Returns True if app is running
///
/// @example const status: bool = webui_interface_is_app_running();
pub extern fn webui_interface_is_app_running() callconv(.C) bool;

/// @brief Get a unique window ID.
///
/// @param window The window number
///
/// @return Returns the unique window ID as integer
///
/// @example const id: usize = webui_interface_get_window_id(my_window);
pub extern fn webui_interface_get_window_id(window: usize) callconv(.C) usize;

/// @brief Get an argument as string at a specific index.
///
/// @param window The window number
/// @param event_number The event number
/// @param index The argument position
///
/// @return Returns argument as string
///
/// @example const my_str: [*:0]const u8 = webui_interface_get_string_at(my_window, e.event_number, 0);
pub extern fn webui_interface_get_string_at(
    window: usize,
    event_number: usize,
    index: usize,
) callconv(.C) [*:0]const u8;

/// @brief Get an argument as integer at a specific index.
///
/// @param window The window number
/// @param event_number The event number
/// @param index The argument position
///
/// @return Returns argument as integer
///
/// @example const my_num: i64 = webui_interface_get_int_at(my_window, e.event_number, 0);
pub extern fn webui_interface_get_int_at(
    window: usize,
    event_number: usize,
    index: usize,
) callconv(.C) i64;

/// @brief Get an argument as float at a specific index.
///
/// @param window The window number
/// @param event_number The event number
/// @param index The argument position
///
/// @return Returns argument as float
///
/// @example const my_float: f64 = webui_interface_get_float_at(my_window, e.event_number, 0);
pub extern fn webui_interface_get_float_at(
    window: usize,
    event_number: usize,
    index: usize,
) callconv(.C) f64;

/// @brief Get an argument as boolean at a specific index.
///
/// @param window The window number
/// @param event_number The event number
/// @param index The argument position
///
/// @return Returns argument as boolean
///
/// @example const my_bool: bool = webui_interface_get_bool_at(my_window, e.event_number, 0);
pub extern fn webui_interface_get_bool_at(
    window: usize,
    event_number: usize,
    index: usize,
) callconv(.C) bool;

/// @brief Get the size in bytes of an argument at a specific index.
///
/// @param window The window number
/// @param event_number The event number
/// @param index The argument position
///
/// @return Returns size in bytes
///
/// @example const arg_len: usize = webui_interface_get_size_at(my_window, e.event_number, 0);
pub extern fn webui_interface_get_size_at(
    window: usize,
    event_number: usize,
    index: usize,
) callconv(.C) usize;

/// @brief Show a window using embedded HTML, or a file. If the window is already
/// open, it will be refreshed. Single client.
///
/// @param window The window number
/// @param event_number The event number
/// @param content The HTML, URL, Or a local file
///
/// @return Returns True if showing the window is successed.
///
/// @example webui_show_client(e, "<html>...</html>"); |
/// webui_show_client(e, "index.html"); | webui_show_client(e, "http://...");
pub extern fn webui_interface_show_client(
    window: usize,
    event_number: usize,
    content: [*:0]const u8,
) callconv(.C) bool;

/// @brief Close a specific client.
///
/// @param window The window number
/// @param event_number The event number
///
/// @example webui_close_client(e);
pub extern fn webui_interface_close_client(
    window: usize,
    event_number: usize,
) callconv(.C) void;

/// @brief Safely send raw data to the UI. Single client.
///
/// @param window The window number
/// @param event_number The event number
/// @param function The JavaScript function to receive raw data: `function
/// myFunc(myData){}`
/// @param raw The raw data buffer
/// @param size The raw data size in bytes
///
/// @example webui_send_raw_client(e, "myJavaScriptFunc", myBuffer, 64);
pub extern fn webui_interface_send_raw_client(
    window: usize,
    event_number: usize,
    function: [*:0]const u8,
    raw: [*c]const u8,
    size: usize,
) callconv(.C) void;

/// @brief Navigate to a specific URL. Single client.
///
/// @param window The window number
/// @param event_number The event number
/// @param url Full HTTP URL
///
/// @example webui_navigate_client(e, "http://domain.com");
pub extern fn webui_interface_navigate_client(
    window: usize,
    event_number: usize,
    url: [*:0]const u8,
) callconv(.C) void;

/// @brief Run JavaScript without waiting for the response. Single client.
///
/// @param window The window number
/// @param event_number The event number
/// @param script The JavaScript to be run
///
/// @example webui_run_client(e, "alert('Hello');");
pub extern fn webui_interface_run_client(
    window: usize,
    event_number: usize,
    script: [*:0]const u8,
) callconv(.C) void;

/// @brief Run JavaScript and get the response back. Single client.
/// Make sure your local buffer can hold the response.
///
/// @param window The window number
/// @param event_number The event number
/// @param script The JavaScript to be run
/// @param timeout The execution timeout in seconds
/// @param buffer The local buffer to hold the response
/// @param buffer_length The local buffer size
///
/// @return Returns True if there is no execution error
///
/// @example bool err = webui_script_client(e, "return 4 + 6;", 0, myBuffer, myBufferSize);
pub extern fn webui_interface_script_client(
    window: usize,
    event_number: usize,
    script: [*:0]const u8,
    timeout: usize,
    buffer: [*c]u8,
    buffer_length: usize,
) callconv(.C) void;
