# WebUI C++ Examples

Examples of how to create a WebUI application in C++.

The only requirement to build the examples is a a C++11 compiler.

- `minimal`: Creates a minimal WebUI application.
- `call_c_from_js`: Calls C++ from JavaScript.
- `call_js_from_c`: Calls JavaScript from C++.
- `serve_a_folder`: Uses WebUI to serve a folder that contains multiple files.

To build an example, cd into its directory and run the make command.

- **Windows**

  ```sh
  # G++
  mingw32-make

  # MSVC
  nmake
  ```

- **Linux**

  ```sh
  # G++
  make

  # Clang
  make CXX=clang
  ```

- **macOS**
  ```sh
  make
  ```
