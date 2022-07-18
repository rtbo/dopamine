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
    - See the [client spec](https://github.com/rtbo/dopamine/blob/main/client/SPEC.md) for more details.

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

## Example of Recipe

Here is an example of recipe that would build and package `libpng`.
Because it is packaging a 3rd party library, it has to download the source,
and perform a few adjustement in the build options.

```lua
name = 'libpng'
version = '1.6.37'
description = 'The PNG reference library'
authors = {'The PNG Reference Library Authors'}
license = 'http://www.libpng.org/pub/png/src/libpng-LICENSE.txt'
copyright = 'Copyright (c) 1995-2019 The PNG Reference Library Authors'
langs = {'c'}

dependencies = {zlib = '>=1.2.5'}

function source()
    local folder = 'libpng-' .. version
    local archive = folder .. '.tar.xz'
    dop.download {
        'https://download.sourceforge.net/libpng/' .. archive,
        dest = archive,
    }
    dop.checksum {
        archive,
        sha256 = '505e70834d35383537b6491e7ae8641f1a4bed1876dbfe361201fc80868d88ca',
    }
    dop.extract_archive { archive, outdir = '.' }

    return folder
end

function build(dirs, config, dep_infos)

    local cmake = dop.CMake:new(config.profile)

    local defs = {
        ['PNG_TESTS'] = false,
    }
    -- if zlib is not in the system but in the dependency cache
    if dep_infos and dep_infos.zlib then
        local zlib = dep_infos.zlib.install_dir
        local libname = dop.windows and 'zlibstatic' or 'z'
        defs['ZLIB_INCLUDE_DIR'] = dop.path(zlib, 'include')
        defs['ZLIB_LIBRARY'] = dop.find_libfile(dop.path(zlib, 'lib'), libname, 'static')
    end

    cmake:configure({
        src_dir = dirs.src,
        install_dir = dirs.install,
        defs = defs,
    })
    cmake:build()
    cmake:install()
end
```

## Build

Dopamine is developed and built with `meson`.
You need the following tools:
 - meson (>= 0.63)
 - ninja
 - a D compiler (either DMD or LDC)
 - Dub (dopamine depends on vibe-d)
 - a C compiler
    - C libraries are compiled if not found on the system (Lua + compression libraries)

### Linux

```sh
DC=ldc meson setup build-ldc
cd build-ldc
ninja # or meson compile
ninja test # or meson test

# you can now run the dop client
packages/client/dop -h
```

### Windows

Windows is always more complex to setup.
Only MSVC is supported as C compiler, as D compilers do not link to MingW out of the box.
Also you need to run both meson **and** ninja from a VS prompt.
If you have `[vswhere](https://github.com/microsoft/vswhere)` in your Path,
`win_env_vs.bat` is provided to setup the VS environment from your regular CMD prompt (do not work with powershell).
Alternatively, the modern `Windows Terminal` app is also helpful.

```bat
win_env_vs.bat
rem Windows is so slow to compile, you are better off with a fast D compiler
set DC=dmd
meson setup build-dmd
cd build-dmd
ninja rem or meson compile
ninja test rem or meson test

rem you can now run the dop client
packages\client\dop.exe -h
```
