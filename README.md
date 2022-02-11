# Dopamine package manager

Package manager for compiled languages.

Dopamine is still under development and cannot be used as a program yet.

## Goals

- Easy C / C++ / D interoperability (Rust and Fortran can be supported later)
- Build-system agnosticity
- highly flexible recipe (which are Lua scripts)
- Possibility to consume Dub packages as dependency
- Allows to look-up for installed dependency before downloading and build
- Lock dependency versions for a deterministic libraries/application dependencies
- Reduce compilation time by uploading/downloading built packages
- Make cross-compilation just as easy as compilation for the local system

## Build

Dopamine is built with `meson` and has no external dependency.
You need the following tools:
 - meson
 - ninja
 - a D compiler (either DMD or LDC)
 - a C compiler (Lua is compiled during the build).

### Linux

```sh
DC=ldc meson setup build-ldc
cd build-ldc
ninja # or meson compile
ninja test # or meson test

# you can now run the dop client
client/dop -h
```

### Windows

Windows is always more complex to setup.
Only MSVC is supported as C compiler, as D compilers do not link to MingW out of the box.
Also you need to run both meson and ninja from a VS prompt.
If you have `[vswhere](https://github.com/microsoft/vswhere)` in your Path,
`win_env_vs.bat` is provided to setup the VS environment from your regular CMD prompt (do not work with powershell).
If you don't have `vswhere`, do yourself a favor and put `vswhere` in your Path.

```bat
win_env_vs.bat
rem Windows is so slow to compile, you are better off with a fast compiler
set DC=dmd
meson setup build-dmd
cd build-dmd
ninja rem or meson compile
ninja test rem or meson test

rem you can now run the dop client
client\dop.exe -h
```
