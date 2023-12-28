/*
  WebUI Library 2.4.2
  http://webui.me
  https://github.com/webui-dev/webui
  Copyright (c) 2020-2023 Hassan Draga.
  Licensed under MIT License.
  All rights reserved.
  Canada.
*/

#ifndef _WEBUI_H
#define _WEBUI_H

#define WEBUI_VERSION "2.4.2"

// Max windows, servers and threads
#define WEBUI_MAX_IDS (256)

// Max allowed argument's index
#define WEBUI_MAX_ARG (16)

// Dynamic Library Exports
#if defined(_MSC_VER) || defined(__TINYC__)
    #ifndef WEBUI_EXPORT
        #define WEBUI_EXPORT __declspec(dllexport)
    #endif
#else
    #ifndef WEBUI_EXPORT
        #define WEBUI_EXPORT extern
    #endif
#endif

// -- C STD ---------------------------
#include <assert.h>
#include <ctype.h>
#include <errno.h>
#include <inttypes.h>
#include <math.h>
#include <stdbool.h>
#include <stddef.h>
#include <stdint.h>
#include <stdio.h>
#include <stdlib.h>
#include <string.h>
#include <time.h>
#if defined(__GNUC__) || defined(__TINYC__)
    #include <dirent.h>
#endif

// -- Windows -------------------------
#ifdef _WIN32
    #ifndef WIN32_LEAN_AND_MEAN
        #define WIN32_LEAN_AND_MEAN
    #endif
    #include <windows.h>
    #include <winsock2.h>
    #include <ws2tcpip.h>

    #include <direct.h>
    #include <io.h>
    #include <shellapi.h>
    #include <tchar.h>
    #include <tlhelp32.h>
    #define WEBUI_GET_CURRENT_DIR _getcwd
    #define WEBUI_FILE_EXIST      _access
    #define WEBUI_POPEN           _popen
    #define WEBUI_PCLOSE          _pclose
    #define WEBUI_MAX_PATH        MAX_PATH
#endif

// -- Linux ---------------------------
#ifdef __linux__
    #include <dirent.h>
    #include <fcntl.h>
    #include <limits.h>
    #include <poll.h>
    #include <pthread.h>
    #include <signal.h>
    #include <sys/socket.h>
    #include <sys/time.h>
    #include <unistd.h>
    #define WEBUI_GET_CURRENT_DIR getcwd
    #define WEBUI_FILE_EXIST      access
    #define WEBUI_POPEN           popen
    #define WEBUI_PCLOSE          pclose
    #define WEBUI_MAX_PATH        PATH_MAX
#endif

// -- Apple ---------------------------
#ifdef __APPLE__
    #include <dirent.h>
    #include <fcntl.h>
    #include <limits.h>
    #include <poll.h>
    #include <pthread.h>
    #include <signal.h>
    #include <sys/socket.h>
    #include <sys/sysctl.h>
    #include <sys/syslimits.h>
    #include <sys/time.h>
    #include <unistd.h>
    #define WEBUI_GET_CURRENT_DIR getcwd
    #define WEBUI_FILE_EXIST      access
    #define WEBUI_POPEN           popen
    #define WEBUI_PCLOSE          pclose
    #define WEBUI_MAX_PATH        PATH_MAX
#endif

// -- Enums ---------------------------
enum webui_browsers {
    NoBrowser = 0,  // 0. No web browser
    AnyBrowser = 1, // 1. Default recommended web browser
    Chrome,         // 2. Google Chrome
    Firefox,        // 3. Mozilla Firefox
    Edge,           // 4. Microsoft Edge
    Safari,         // 5. Apple Safari
    Chromium,       // 6. The Chromium Project
    Opera,          // 7. Opera Browser
    Brave,          // 8. The Brave Browser
    Vivaldi,        // 9. The Vivaldi Browser
    Epic,           // 10. The Epic Browser
    Yandex,         // 11. The Yandex Browser
    ChromiumBased,  // 12. Any Chromium based browser
};

enum webui_runtimes {
    None = 0, // 0. Prevent WebUI from using any runtime for .js and .ts files
    Deno,     // 1. Use Deno runtime for .js and .ts files
    NodeJS,   // 2. Use Nodejs runtime for .js files
};

enum webui_events {
    WEBUI_EVENT_DISCONNECTED = 0, // 0. Window disconnection event
    WEBUI_EVENT_CONNECTED,        // 1. Window connection event
    WEBUI_EVENT_MOUSE_CLICK,      // 2. Mouse click event
    WEBUI_EVENT_NAVIGATION,       // 3. Window navigation event
    WEBUI_EVENT_CALLBACK,         // 4. Function call event
};

// -- Structs -------------------------
typedef struct webui_event_t {
    size_t window;       // The window object number
    size_t event_type;   // Event type
    char* element;       // HTML element ID
    size_t event_number; // Internal WebUI
    size_t bind_id;      // Bind ID
} webui_event_t;

// -- Definitions ---------------------

/**
 * @brief Create a new WebUI window object.
 *
 * @return Returns the window number.
 *
 * @example size_t myWindow = webui_new_window();
 */
WEBUI_EXPORT size_t webui_new_window(void);

/**
 * @brief Create a new webui window object using a specified window number.
 *
 * @param window_number The window number (should be > 0, and < WEBUI_MAX_IDS)
 *
 * @return Returns the window number.
 *
 * @example size_t myWindow = webui_new_window_id(123);
 */
WEBUI_EXPORT size_t webui_new_window_id(size_t window_number);

/**
 * @brief Get a free window number that can be used with
 * `webui_new_window_id()`.
 *
 * @return Returns the first available free window number. Starting from 1.
 *
 * @example size_t myWindowNumber = webui_get_new_window_id();
 */
WEBUI_EXPORT size_t webui_get_new_window_id(void);

/**
 * @brief Bind a specific html element click event with a function. Empty
 * element means all events.
 *
 * @param window The window number
 * @param element The HTML ID
 * @param func The callback function
 *
 * @return Returns a unique bind ID.
 *
 * @example webui_bind(myWindow, "myID", myFunction);
 */
WEBUI_EXPORT size_t webui_bind(size_t window, const char* element, void (*func)(webui_event_t* e));

/**
 * @brief Show a window using embedded HTML, or a file. If the window is already
 * open, it will be refreshed.
 *
 * @param window The window number
 * @param content The HTML, URL, Or a local file
 *
 * @return Returns True if showing the window is successed.
 *
 * @example webui_show(myWindow, "<html>...</html>"); | webui_show(myWindow,
 * "index.html"); | webui_show(myWindow, "http://...");
 */
WEBUI_EXPORT bool webui_show(size_t window, const char* content);

/**
 * @brief Same as `webui_show()`. But using a specific web browser.
 *
 * @param window The window number
 * @param content The HTML, Or a local file
 * @param browser The web browser to be used
 *
 * @return Returns True if showing the window is successed.
 *
 * @example webui_show_browser(myWindow, "<html>...</html>", Chrome); |
 * webui_show(myWindow, "index.html", Firefox);
 */
WEBUI_EXPORT bool webui_show_browser(size_t window, const char* content, size_t browser);

/**
 * @brief Set the window in Kiosk mode (Full screen)
 *
 * @param window The window number
 * @param status True or False
 *
 * @example webui_set_kiosk(myWindow, true);
 */
WEBUI_EXPORT void webui_set_kiosk(size_t window, bool status);

/**
 * @brief Wait until all opened windows get closed.
 *
 * @example webui_wait();
 */
WEBUI_EXPORT void webui_wait(void);

/**
 * @brief Close a specific window only. The window object will still exist.
 *
 * @param window The window number
 *
 * @example webui_close(myWindow);
 */
WEBUI_EXPORT void webui_close(size_t window);

/**
 * @brief Close a specific window and free all memory resources.
 *
 * @param window The window number
 *
 * @example webui_destroy(myWindow);
 */
WEBUI_EXPORT void webui_destroy(size_t window);

/**
 * @brief Close all open windows. `webui_wait()` will return (Break).
 *
 * @example webui_exit();
 */
WEBUI_EXPORT void webui_exit(void);

/**
 * @brief Set the web-server root folder path for a specific window.
 *
 * @param window The window number
 * @param path The local folder full path
 *
 * @example webui_set_root_folder(myWindow, "/home/Foo/Bar/");
 */
WEBUI_EXPORT bool webui_set_root_folder(size_t window, const char* path);

/**
 * @brief Set the web-server root folder path for all windows. Should be used
 * before `webui_show()`.
 *
 * @param path The local folder full path
 *
 * @example webui_set_default_root_folder("/home/Foo/Bar/");
 */
WEBUI_EXPORT bool webui_set_default_root_folder(const char* path);

/**
 * @brief Set a custom handler to serve files.
 *
 * @param window The window number
 * @param handler The handler function: `void myHandler(const char* filename,
 * int* length)`
 *
 * @return Returns a unique bind ID.
 *
 * @example webui_set_file_handler(myWindow, myHandlerFunction);
 */
WEBUI_EXPORT void webui_set_file_handler(size_t window, const void* (*handler)(const char* filename, int* length));

/**
 * @brief Check if the specified window is still running.
 *
 * @param window The window number
 *
 * @example webui_is_shown(myWindow);
 */
WEBUI_EXPORT bool webui_is_shown(size_t window);

/**
 * @brief Set the maximum time in seconds to wait for the browser to start.
 *
 * @param second The timeout in seconds
 *
 * @example webui_set_timeout(30);
 */
WEBUI_EXPORT void webui_set_timeout(size_t second);

/**
 * @brief Set the default embedded HTML favicon.
 *
 * @param window The window number
 * @param icon The icon as string: `<svg>...</svg>`
 * @param icon_type The icon type: `image/svg+xml`
 *
 * @example webui_set_icon(myWindow, "<svg>...</svg>", "image/svg+xml");
 */
WEBUI_EXPORT void webui_set_icon(size_t window, const char* icon, const char* icon_type);

/**
 * @brief Base64 encoding. Use this to safely send text based data to the UI. If
 * it fails it will return NULL.
 *
 * @param str The string to encode (Should be null terminated)
 *
 * @example webui_encode("Hello");
 */
WEBUI_EXPORT char* webui_encode(const char* str);

/**
 * @brief Base64 decoding. Use this to safely decode received Base64 text from
 * the UI. If it fails it will return NULL.
 *
 * @param str The string to decode (Should be null terminated)
 *
 * @example webui_decode("SGVsbG8=");
 */
WEBUI_EXPORT char* webui_decode(const char* str);

/**
 * @brief Safely free a buffer allocated by WebUI using `webui_malloc()`.
 *
 * @param ptr The buffer to be freed
 *
 * @example webui_free(myBuffer);
 */
WEBUI_EXPORT void webui_free(void* ptr);

/**
 * @brief Safely allocate memory using the WebUI memory management system. It
 * can be safely freed using `webui_free()` at any time.
 *
 * @param size The size of memory in bytes
 *
 * @example char* myBuffer = (char*)webui_malloc(1024);
 */
WEBUI_EXPORT void* webui_malloc(size_t size);

/**
 * @brief Safely send raw data to the UI.
 *
 * @param window The window number
 * @param function The JavaScript function to receive raw data: `function
 * myFunc(myData){}`
 * @param raw The raw data buffer
 * @param size The raw data size in bytes
 *
 * @example webui_send_raw(myWindow, "myJavascriptFunction", myBuffer, 64);
 */
WEBUI_EXPORT void webui_send_raw(size_t window, const char* function, const void* raw, size_t size);

/**
 * @brief Set a window in hidden mode. Should be called before `webui_show()`.
 *
 * @param window The window number
 * @param status The status: True or False
 *
 * @example webui_set_hide(myWindow, True);
 */
WEBUI_EXPORT void webui_set_hide(size_t window, bool status);

/**
 * @brief Set the window size.
 *
 * @param window The window number
 * @param width The window width
 * @param height The window height
 *
 * @example webui_set_size(myWindow, 800, 600);
 */
WEBUI_EXPORT void webui_set_size(size_t window, unsigned int width, unsigned int height);

/**
 * @brief Set the window position.
 *
 * @param window The window number
 * @param x The window X
 * @param y The window Y
 *
 * @example webui_set_position(myWindow, 100, 100);
 */
WEBUI_EXPORT void webui_set_position(size_t window, unsigned int x, unsigned int y);

/**
 * @brief Set the web browser profile to use. An empty `name` and `path` means
 * the default user profile. Need to be called before `webui_show()`.
 *
 * @param window The window number
 * @param name The web browser profile name
 * @param path The web browser profile full path
 *
 * @example webui_set_profile(myWindow, "Bar", "/Home/Foo/Bar"); |
 * webui_set_profile(myWindow, "", "");
 */
WEBUI_EXPORT void webui_set_profile(size_t window, const char* name, const char* path);

/**
 * @brief Get the full current URL.
 *
 * @param window The window number
 *
 * @return Returns the full URL string
 *
 * @example const char* url = webui_get_url(myWindow);
 */
WEBUI_EXPORT const char* webui_get_url(size_t window);

/**
 * @brief Allow a specific window address to be accessible from a public network
 *
 * @param window The window number
 * @param status True or False
 *
 * @example webui_set_public(myWindow, true);
 */
WEBUI_EXPORT void webui_set_public(size_t window, bool status);

/**
 * @brief Navigate to a specific URL
 *
 * @param window The window number
 * @param url Full HTTP URL
 *
 * @example webui_navigate(myWindow, "http://domain.com");
 */
WEBUI_EXPORT void webui_navigate(size_t window, const char* url);

/**
 * @brief Free all memory resources. Should be called only at the end.
 *
 * @example
 * webui_wait();
 * webui_clean();
 */
WEBUI_EXPORT void webui_clean();

/**
 * @brief Delete all local web-browser profiles folder. It should called at the
 * end.
 *
 * @example
 * webui_wait();
 * webui_delete_all_profiles();
 * webui_clean();
 */
WEBUI_EXPORT void webui_delete_all_profiles();

/**
 * @brief Delete a specific window web-browser local folder profile.
 *
 * @param window The window number
 *
 * @example
 * webui_wait();
 * webui_delete_profile(myWindow);
 * webui_clean();
 *
 * @note This can break functionality of other windows if using the same
 * web-browser.
 */
WEBUI_EXPORT void webui_delete_profile(size_t window);

/**
 * @brief Get the ID of the parent process (The web browser may re-create
 * another new process).
 *
 * @param window The window number
 *
 * @return Returns the the parent process id as integer
 *
 * @example size_t id = webui_get_parent_process_id(myWindow);
 */
WEBUI_EXPORT size_t webui_get_parent_process_id(size_t window);

/**
 * @brief Get the ID of the last child process.
 *
 * @param window The window number
 *
 * @return Returns the the child process id as integer
 *
 * @example size_t id = webui_get_child_process_id(myWindow);
 */
WEBUI_EXPORT size_t webui_get_child_process_id(size_t window);

/**
 * @brief Set a custom web-server network port to be used by WebUI.
 * This can be useful to determine the HTTP link of `webui.js` in case
 * you are trying to use WebUI with an external web-server like NGNIX
 *
 * @param window The window number
 * @param port The web-server network port WebUI should use
 *
 * @return Returns True if the port is free and usable by WebUI
 *
 * @example bool ret = webui_set_port(myWindow, 8080);
 */
WEBUI_EXPORT bool webui_set_port(size_t window, size_t port);

// -- SSL/TLS -------------------------

/**
 * @brief Set the SSL/TLS certificate and the private key content, both in PEM
 * format. This works only with `webui-2-secure` library. If set empty WebUI
 * will generate a self-signed certificate.
 *
 * @param certificate_pem The SSL/TLS certificate content in PEM format
 * @param private_key_pem The private key content in PEM format
 *
 * @return Returns True if the certificate and the key are valid.
 *
 * @example bool ret = webui_set_tls_certificate("-----BEGIN
 * CERTIFICATE-----\n...", "-----BEGIN PRIVATE KEY-----\n...");
 */
WEBUI_EXPORT bool webui_set_tls_certificate(const char* certificate_pem, const char* private_key_pem);

// -- JavaScript ----------------------

/**
 * @brief Run JavaScript without waiting for the response.
 *
 * @param window The window number
 * @param script The JavaScript to be run
 *
 * @example webui_run(myWindow, "alert('Hello');");
 */
WEBUI_EXPORT void webui_run(size_t window, const char* script);

/**
 * @brief Run JavaScript and get the response back.
 * Make sure your local buffer can hold the response.
 *
 * @param window The window number
 * @param script The JavaScript to be run
 * @param timeout The execution timeout
 * @param buffer The local buffer to hold the response
 * @param buffer_length The local buffer size
 *
 * @return Returns True if there is no execution error
 *
 * @example bool err = webui_script(myWindow, "return 4 + 6;", 0, myBuffer, myBufferSize);
 */
WEBUI_EXPORT bool webui_script(size_t window, const char* script, size_t timeout,
    char* buffer, size_t buffer_length);

/**
 * @brief Chose between Deno and Nodejs as runtime for .js and .ts files.
 *
 * @param window The window number
 * @param runtime Deno | Nodejs
 *
 * @example webui_set_runtime(myWindow, Deno);
 */
WEBUI_EXPORT void webui_set_runtime(size_t window, size_t runtime);

/**
 * @brief Get an argument as integer at a specific index
 *
 * @param e The event struct
 * @param index The argument position starting from 0
 *
 * @return Returns argument as integer
 *
 * @example long long int myNum = webui_get_int_at(e, 0);
 */
WEBUI_EXPORT long long int webui_get_int_at(webui_event_t* e, size_t index);

/**
 * @brief Get the first argument as integer
 *
 * @param e The event struct
 *
 * @return Returns argument as integer
 *
 * @example long long int myNum = webui_get_int(e);
 */
WEBUI_EXPORT long long int webui_get_int(webui_event_t* e);

/**
 * @brief Get an argument as string at a specific index
 *
 * @param e The event struct
 * @param index The argument position starting from 0
 *
 * @return Returns argument as string
 *
 * @example const char* myStr = webui_get_string_at(e, 0);
 */
WEBUI_EXPORT const char* webui_get_string_at(webui_event_t* e, size_t index);

/**
 * @brief Get the first argument as string
 *
 * @param e The event struct
 *
 * @return Returns argument as string
 *
 * @example const char* myStr = webui_get_string(e);
 */
WEBUI_EXPORT const char* webui_get_string(webui_event_t* e);

/**
 * @brief Get an argument as boolean at a specific index
 *
 * @param e The event struct
 * @param index The argument position starting from 0
 *
 * @return Returns argument as boolean
 *
 * @example bool myBool = webui_get_bool_at(e, 0);
 */
WEBUI_EXPORT bool webui_get_bool_at(webui_event_t* e, size_t index);

/**
 * @brief Get the first argument as boolean
 *
 * @param e The event struct
 *
 * @return Returns argument as boolean
 *
 * @example bool myBool = webui_get_bool(e);
 */
WEBUI_EXPORT bool webui_get_bool(webui_event_t* e);

/**
 * @brief Get the size in bytes of an argument at a specific index
 *
 * @param e The event struct
 * @param index The argument position starting from 0
 *
 * @return Returns size in bytes
 *
 * @example size_t argLen = webui_get_size_at(e, 0);
 */
WEBUI_EXPORT size_t webui_get_size_at(webui_event_t* e, size_t index);

/**
 * @brief Get size in bytes of the first argument
 *
 * @param e The event struct
 *
 * @return Returns size in bytes
 *
 * @example size_t argLen = webui_get_size(e);
 */
WEBUI_EXPORT size_t webui_get_size(webui_event_t* e);

/**
 * @brief Return the response to JavaScript as integer.
 *
 * @param e The event struct
 * @param n The integer to be send to JavaScript
 *
 * @example webui_return_int(e, 123);
 */
WEBUI_EXPORT void webui_return_int(webui_event_t* e, long long int n);

/**
 * @brief Return the response to JavaScript as string.
 *
 * @param e The event struct
 * @param n The string to be send to JavaScript
 *
 * @example webui_return_string(e, "Response...");
 */
WEBUI_EXPORT void webui_return_string(webui_event_t* e, const char* s);

/**
 * @brief Return the response to JavaScript as boolean.
 *
 * @param e The event struct
 * @param n The boolean to be send to JavaScript
 *
 * @example webui_return_bool(e, true);
 */
WEBUI_EXPORT void webui_return_bool(webui_event_t* e, bool b);

// -- Wrapper's Interface -------------

/**
 * @brief Bind a specific HTML element click event with a function. Empty element means all events.
 *
 * @param window The window number
 * @param element The element ID
 * @param func The callback as myFunc(Window, EventType, Element, EventNumber, BindID)
 *
 * @return Returns unique bind ID
 *
 * @example size_t id = webui_interface_bind(myWindow, "myID", myCallback);
 */
WEBUI_EXPORT size_t webui_interface_bind(size_t window, const char* element,
    void (*func)(size_t, size_t, char*, size_t, size_t));

/**
 * @brief When using `webui_interface_bind()`, you may need this function to easily set a response.
 *
 * @param window The window number
 * @param event_number The event number
 * @param response The response as string to be send to JavaScript
 *
 * @example webui_interface_set_response(myWindow, e->event_number, "Response...");
 */
WEBUI_EXPORT void webui_interface_set_response(size_t window, size_t event_number, const char* response);

/**
 * @brief Check if the app still running.
 *
 * @return Returns True if app is running
 *
 * @example bool status = webui_interface_is_app_running();
 */
WEBUI_EXPORT bool webui_interface_is_app_running(void);

/**
 * @brief Get a unique window ID.
 *
 * @param window The window number
 *
 * @return Returns the unique window ID as integer
 *
 * @example size_t id = webui_interface_get_window_id(myWindow);
 */
WEBUI_EXPORT size_t webui_interface_get_window_id(size_t window);

/**
 * @brief Get an argument as string at a specific index
 *
 * @param window The window number
 * @param event_number The event number
 * @param index The argument position
 *
 * @return Returns argument as string
 *
 * @example const char* myStr = webui_interface_get_string_at(myWindow, e->event_number, 0);
 */
WEBUI_EXPORT const char* webui_interface_get_string_at(size_t window, size_t event_number, size_t index);

/**
 * @brief Get an argument as integer at a specific index
 *
 * @param window The window number
 * @param event_number The event number
 * @param index The argument position
 *
 * @return Returns argument as integer
 *
 * @example long long int myNum = webui_interface_get_int_at(myWindow, e->event_number, 0);
 */
WEBUI_EXPORT long long int webui_interface_get_int_at(size_t window, size_t event_number, size_t index);

/**
 * @brief Get an argument as boolean at a specific index
 *
 * @param window The window number
 * @param event_number The event number
 * @param index The argument position
 *
 * @return Returns argument as boolean
 *
 * @example bool myBool = webui_interface_get_bool_at(myWindow, e->event_number, 0);
 */
WEBUI_EXPORT bool webui_interface_get_bool_at(size_t window, size_t event_number, size_t index);

/**
 * @brief Get the size in bytes of an argument at a specific index
 *
 * @param window The window number
 * @param event_number The event number
 * @param index The argument position
 *
 * @return Returns size in bytes
 *
 * @example size_t argLen = webui_interface_get_size_at(myWindow, e->event_number, 0);
 */
WEBUI_EXPORT size_t webui_interface_get_size_at(size_t window, size_t event_number, size_t index);

#endif /* _WEBUI_H */
