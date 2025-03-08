<div align="center">

![Logo](https://raw.githubusercontent.com/webui-dev/webui-logo/main/webui_zig.png)

# WebUI Zig v2.5.0-beta.2

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

## API Documentation

* [https://webui-dev.github.io/zig-webui/](https://webui-dev.github.io/zig-webui/)
* [https://webui.me/docs/2.5/#/](https://webui.me/docs/2.5/#/)

## Examples

There are several examples for newbies, they are in the `examples` directory.

You can use `zig build --help` to view all buildable examples.

Like `zig build run_minimal`, this will build and run the `minimal` example.

## Installation

> note: for `0.13.0` and previous version, please use tag `2.5.0-beta.2`

### Zig `0.14.0` \ `nightly`

> To be honest, I don’t recommend using the nightly version because the API of the build system is not yet stable, which means that there may be problems with not being able to build after nightly is updated.

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
const zig_webui = b.dependency("zig-webui", .{
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
