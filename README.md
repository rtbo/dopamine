# Dopamine package manager

Package manager for compiled languages.

Dopamine is still under development and cannot be used yet.

## Goals

- Easy C / C++ / D interoperability (support for other languages can be brought later)
- Build-system agnosticity
- highly flexible package recipe
- Possibility to consume Dub packages as dependency
- Possibility to package 3rdparty code (packages not aware of Dopamine)
- Allows to look-up for installed dependency before downloading and build
- Lock dependency versions for a deterministic libraries/application dependencies
- Reduce compilation time by uploading/downloading built packages
- Make cross-compilation just as easy as compilation for the local system

## Design

This is still largely in progress, but in a nutshell:

 - The `dop` command line tool provide commands for all aspects of building and packaging.
    - Setup compilation profile
    - Get the source
    - Resolve and lock dependencies
    - Build (using the build system provided by the source package)
    - Package/publish
    - Upload a build
    - ...

 - Recipes are Lua scripts.
    - Recipes provide some descriptive fields and functions for:
        - downloading source (if the source is not packaged with the recipe)
        - patch (if needed)
        - build
        - package (ideally this is done by the install command of the build system)
    - Most of recipes tasks are helped by a comprehensive `dop` lua library, pre-loaded by the client.
    - Thanks to Lua's functional flexibility, most recipes can look purely declarative

 - Dependencies are resolved with a DAG. See [dag.d](https://github.com/rtbo/dopamine/blob/main/lib/src/dopamine/dep/dag.d).

 - Compilation profiles are saved in INI files, that can be saved user-wide and reused at will
    - The `dop` client provide helpers to edit them, but can also be done by hand.
    - Each profile gets a unique identifier based on the build options, platform, compilers versions and ABI etc.

 - Everything that can alter the build (profile id, resolved dependencies versions...) is reduced to a unique build identifier.
    - This identifier allows to upload a built package
    - A consumer can consume this pre-built package as dependency if the same ID is computed.
    - If no build is found, the recipe is used to build the package (and optionally upload it after the build).


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
Also you need to run both meson **and** ninja from a VS prompt.
If you have `[vswhere](https://github.com/microsoft/vswhere)` in your Path,
`win_env_vs.bat` is provided to setup the VS environment from your regular CMD prompt (do not work with powershell).
If you don't have `vswhere`, do yourself a favor and put `vswhere` in your Path.

```bat
win_env_vs.bat
rem Windows is so slow to compile, you are better off with a fast D compiler
set DC=dmd
meson setup build-dmd
cd build-dmd
ninja rem or meson compile
ninja test rem or meson test

rem you can now run the dop client
client\dop.exe -h
```
