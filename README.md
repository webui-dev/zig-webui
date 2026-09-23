<div align="center">

![Logo](https://raw.githubusercontent.com/webui-dev/webui-logo/main/webui_zig.png)

# WebUI Zig v2.5.1

<!-- [build-status]: https://img.shields.io/github/actions/workflow/status/webui-dev/go-webui/ci.yml?branch=main&style=for-the-badge&logo=V&labelColor=414868&logoColor=C0CAF5 -->

[last-commit]: https://img.shields.io/github/last-commit/webui-dev/zig-webui?style=for-the-badge&logo=github&logoColor=C0CAF5&labelColor=414868
<!-- [release-version]: https://img.shields.io/github/v/tag/webui-dev/go-webui?style=for-the-badge&logo=webtrees&logoColor=C0CAF5&labelColor=414868&color=7664C6 -->
[license]: https://img.shields.io/github/license/webui-dev/zig-webui?style=for-the-badge&logo=opensourcehardware&label=License&logoColor=C0CAF5&labelColor=414868&color=8c73cc

<!-- [![][build-status]](https://github.com/webui-dev/go-webui/actions?query=branch%3Amain) -->

[![][last-commit]](https://github.com/webui-dev/zig-webui/pulse)
<!-- [![][release-version]](https://github.com/webui-dev/go-webui/releases/latest) -->
[![][license]](https://github.com/webui-dev/zig-webui/blob/main/LICENSE)

> Use any web browser or WebView as GUI, with Zig in the backend and modern web technologies in the frontend, all in a lightweight portable library.

![Screenshot](https://raw.githubusercontent.com/webui-dev/webui-logo/main/screenshot.png)

</div>

## Features

- Portable (*Needs only a web browser or a WebView at runtime*)
- One header file
- Lightweight (*Few Kb library*) & Small memory footprint
- Fast binary communication protocol
- Multi-platform & Multi-Browser
- Using private profile for safety
- Cross-platform WebView

<div align="center">

![GPT](https://github.com/user-attachments/assets/70455739-94c9-410e-9519-2b0318129b4a)

### _Ask AI Any Question About the Zig-WebUI_

### [WebUI GPT - Zig](https://chatgpt.com/g/g-69de5b9ed1488191828b8dbfa9873e2d-zig-webui)

</div>

## API Documentation

If you want a clearer architecture, you can check it out [here](https://deepwiki.com/webui-dev/zig-webui)

* [https://webui-dev.github.io/zig-webui/](https://webui-dev.github.io/zig-webui/)
* [https://webui.me/docs.html#/zig](https://webui.me/docs.html#/zig)

## Examples

There are several examples for newbies, they are in the `examples` directory.

You can use `zig build --help` to view all buildable examples.

Like `zig build run_minimal`, this will build and run the `minimal` example.

## Installation

### Zig `0.16.0` and later

This package targets Zig `0.16.0` and up. Nightly is
still not recommended — the build-system API can change between dev builds
and break the binding without warning.

1. Add to `build.zig.zon`

```sh
# It is recommended to replace the following branch with commit id
zig fetch --save https://github.com/webui-dev/zig-webui/archive/main.tar.gz
# Of course, you can also use git+https to fetch this package!
```

2. Config `build.zig`

Add this:

```zig
// To standardize development, maybe you should use `lazyDependency()` instead of `dependency()`
// more info to see: https://ziglang.org/download/0.12.0/release-notes.html#toc-Lazy-Dependencies
const zig_webui = b.dependency("zig_webui", .{
    .target = target,
    .optimize = optimize,
    .enable_tls = false, // whether enable tls support
    .is_static = true, // whether static link
});

// add module
exe.root_module.addImport("webui", zig_webui.module("webui"));
```

> It is not recommended to dynamically link libraries under Windows, which may cause some symbol duplication problems.
> see this issue: https://github.com/ziglang/zig/issues/15107

### Windows without console

For hide console window, you can set `exe.subsystem = .Windows;`!

### Embed an entire directory

The build-time `addEmbeddedDir` helper recursively embeds a directory from **your
project**, including subdirectories. The runtime `webui.EmbeddedFS` API provides
allocation-free lookups without filesystem access.

Import the package's build API at the top of your `build.zig`:

```zig
const webui_build = @import("zig_webui");
```

After adding the normal `webui` module to your executable, add this inside your
`build` function (which must return `!void`):

```zig
try webui_build.addEmbeddedDir(b, exe.root_module, .{
    .path = "assets",
    .import_name = "embedded_assets", // optional; this is the default
});
```

For a directory containing `assets/index.html` and `assets/css/main.css`:

```zig
const std = @import("std");
const webui = @import("webui");
const Assets = webui.EmbeddedFS(@import("embedded_assets"));

pub fn main() void {
    for (Assets.list()) |path| {
        std.debug.print("{s}: {d} bytes\n", .{ path, Assets.get(path).?.len });
    }
    const css = Assets.get("css/main.css").?;
    std.debug.print("{s}\n", .{css});
}
```

- `.path` is relative to the calling project's build root, not the shell's
  working directory. The directory must exist when the build script runs;
  directories produced by later build steps are not supported.
- Every regular file is included, including hidden files. Choose a dedicated
  resource directory without secrets. Symlinks and other non-regular entries
  are skipped.
- `get` accepts exact, case-sensitive relative paths with `/` separators. It
  does not normalize URLs, leading slashes, or `..`. Missing files return `null`;
  empty files return a non-null empty slice. Binary data is preserved.
- `list` returns file paths sorted bytewise. Paths and contents have static
  lifetime; do not free them. An empty directory is supported.
- Additions, removals, renames, and content changes are picked up on the next
  `zig build`. Use a different `.import_name` for each additional directory.
- Filenames containing newlines are not supported by Zig 0.16's build cache:
  a subsequent build can fail with `invalid manifest file format`.

This API returns raw file bytes; it does not install a WebUI HTTP handler.
If used with `setFileHandler`, your handler still needs to return a full HTTP
response, including headers.

Run `zig build run_embedded_folder` for a console example. Its installed binary,
`zig-out/bin/embedded_folder`, can also run outside the project without the
original resource directory.

Regression checks:

```sh
zig build test --summary all
python3 -B -m unittest discover -s tests -v
```

The integration test requires Python 3 and Zig on `PATH`, with no third-party
Python packages. It creates and removes a temporary downstream project to check
root-relative paths, resource-name collisions, empty and multiple directories,
binary contents, incremental rebuilds, and standalone execution without source
assets. Both commands are included in CI.

## UI & The Web Technologies

[Borislav Stanimirov](https://ibob.bg/) discusses using HTML5 in the web browser as GUI at the [C++ Conference 2019 (_YouTube_)](https://www.youtube.com/watch?v=bbbcZd4cuxg).

<!-- <div align="center">
  <a href="https://www.youtube.com/watch?v=bbbcZd4cuxg"><img src="https://img.youtube.com/vi/bbbcZd4cuxg/0.jpg" alt="Embrace Modern Technology: Using HTML 5 for GUI in C++ - Borislav Stanimirov - CppCon 2019"></a>
</div> -->

<div align="center">

![CPPCon](https://github.com/webui-dev/webui/assets/34311583/4e830caa-4ca0-44ff-825f-7cd6d94083c8)

</div>

Web application UI design is not just about how a product looks but how it works. Using web technologies in your UI makes your product modern and professional, And a well-designed web application will help you make a solid first impression on potential customers. Great web application design also assists you in nurturing leads and increasing conversions. In addition, it makes navigating and using your web app easier for your users.

### Why Use Web Browsers?

Today's web browsers have everything a modern UI needs. Web browsers are very sophisticated and optimized. Therefore, using it as a GUI will be an excellent choice. While old legacy GUI lib is complex and outdated, a WebView-based app is still an option. However, a WebView needs a huge SDK to build and many dependencies to run, and it can only provide some features like a real web browser. That is why WebUI uses real web browsers to give you full features of comprehensive web technologies while keeping your software lightweight and portable.

### How Does it Work?

<div align="center">

![Diagram](https://github.com/ttytm/webui/assets/34311583/dbde3573-3161-421e-925c-392a39f45ab3)

</div>

Think of WebUI like a WebView controller, but instead of embedding the WebView controller in your program, which makes the final program big in size, and non-portable as it needs the WebView runtimes. Instead, by using WebUI, you use a tiny static/dynamic library to run any installed web browser and use it as GUI, which makes your program small, fast, and portable. **All it needs is a web browser**.

### Runtime Dependencies Comparison

|                                 | Tauri / WebView   | Qt                         | WebUI               |
| ------------------------------- | ----------------- | -------------------------- | ------------------- |
| Runtime Dependencies on Windows | _WebView2_        | _QtCore, QtGui, QtWidgets_ | **_A Web Browser_** |
| Runtime Dependencies on Linux   | _GTK3, WebKitGTK_ | _QtCore, QtGui, QtWidgets_ | **_A Web Browser_** |
| Runtime Dependencies on macOS   | _Cocoa, WebKit_   | _QtCore, QtGui, QtWidgets_ | **_A Web Browser_** |

## Supported Web Browsers

| Browser         | Windows         | macOS         | Linux           |
| --------------- | --------------- | ------------- | --------------- |
| Mozilla Firefox | ✔️              | ✔️            | ✔️              |
| Google Chrome   | ✔️              | ✔️            | ✔️              |
| Microsoft Edge  | ✔️              | ✔️            | ✔️              |
| Chromium        | ✔️              | ✔️            | ✔️              |
| Yandex          | ✔️              | ✔️            | ✔️              |
| Brave           | ✔️              | ✔️            | ✔️              |
| Vivaldi         | ✔️              | ✔️            | ✔️              |
| Epic            | ✔️              | ✔️            | _not available_ |
| Apple Safari    | _not available_ | _coming soon_ | _not available_ |
| Opera           | _coming soon_   | _coming soon_ | _coming soon_   |

## Supported WebView

| WebView         | Status         |
| --------------- | --------------- |
| Windows WebView2 | ✔️ |
| Linux GTK WebView   | ✔️ |
| macOS WKWebView  | ✔️ |

### License

> Licensed under the MIT License.
