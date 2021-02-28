# Dopamine package manager

Package manager for compiled languages.

## Motivation

- Deterministic dependencies for libraries/application development/deployment
- Easier C / C++ / D interoperability
- Reduce compilation time by providing ready to use binary dependency packages
- Build-system agnostic PM

## Highlights

- Is a tool for **developers only**, not for end-users
- Source package (recipe) and binary packages
- Rely on build system provided by the package source. Currently supported:
  - meson
  - cmake
  - dub
- Possibility of _light_ recipes:
  - the _light_ recipe only specify dependencies that are downloaded and staged by the client
  - Dopamine do not get further in your way
- Non-invasive: can package 3rdparty code without necessity to patch
- Effort on providing easy Dub to Dopamine package translation
  - Consuming directly Dub packages is however not a goal
  - Automation of Dub to Dopamine for at least the simplest Dub packages
- Distributed
  - Web frontend and backend apps are provided and can be hosted privately or publically
  - Central repo exists but is entirely optional
- Deterministic
  - Compiler versions, compilation options, host, package options affect an identifier that ensure uniqueness of the build
  - The identifier is deterministic, therefore binary packages can be reused among different users
- Multiple revisions of the same package version can co-exist:
  - No ambiguity on the package version: it is always the version of the packaged source code
  - Recipes can be upgraded independently of the package version
- The design is inspired by [Conan](https://conan.io) in many aspects

## Implementation details

- Package recipes are written in Lua
  - The client provides a `dop` lua module with all necessary utilities - no lua library such as LFS is necessary on the user system
  - The package scripts are named `dopamine.lua`
  - The package scripts provide entry points for the client in a form of lua functions that perform special tasks:
    - `source`: download the package source code
    - `build`: build the package source code
    - `pack`: create the package
- Client `dop` is written in D
- Web frontend is a VueJs / Vuetify application
 - login only with provider:
   - only Github supported at this time
   - no management or storage of username/password
- Web backend is a NodeJs / MongoDb / KoaJs application

## Client

See the client [specification](client/SPEC.md) for details.

```
$ dop --help
dop - Dopamine package manager client

Usage
    dop [global options] command [command options]

Global options
    -C --change-dir  Change current directory before running command
    -v    --verbose  Enable verbose mode
          --version  Show dop version and exits
    -h       --help  This help information.

Commands:
         login  Register login credientials
       profile  Set compilation profile for the current package
       deplock  Lock dependencies
    depinstall  Install dependencies
        source  Download package source
         build  Build package
       package  Create package from build
         cache  Add package to local cache
       publish  Publish package to repository
For individual command help, type dop [command] --help
```
