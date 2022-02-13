# Dopamine client specification

This document is a coding spec for dopamine CLI client `dop`.
The status marks indicated along the document have the following meaning:
 - :x: : Not coded
 - :white_check_mark: : Coded
 - :heavy_check_mark: : Covered by tests

## Basic usage

```
$ dop [global options] [command] [command options]
```

## Global options

- `-C|--change-dir [directory]` :white_check_mark:
  - Change to directory before executing the command
- `-v|--verbose` :white_check_mark:
  - Enable verbose mode
- `-c|--no-color` :x:
  - Disable colored output
- `--version` :white_check_mark:
  - Print client version and exit
- `--help` :white_check_mark:
  - Print help and exit

## Recipe file

Each package is decribed by a recipe file, which is a Lua script named `dopamine.lua` located at the package root.
There can be 2 sorts of recipe:
- A dependencies recipe (aka. light recipes).
    - This kind of recipe is used to install dependencies locally.
    - It is not meant to package a piece of software.
    - Expresses dependencies through the `dependencies` global variable.
- A package recipe.
    - Is a complete recipe that provide data and functions to build and package a piece of software.
    - It can express dependencies.
    - Recipe is defined by returning a table with various fields
    - Some fields are mandatory in the recipe table for the package to be published:
        - `name`
        - `version` (Semver compliant)
        - `license`
        - `build` function
        - TBD
    - When a recipe function is executed, it receives the recipe table as first argument

When a recipe function is executed, the current directory is always the package root directory.

### dop Lua library
In order to help packaging, a `dop` Lua library is provided by the client.
It is implicitely imported and available in every recipe
```lua
local dop = require('dop')
```
Recipes may import other libraries, but the `dop` library is the only one that is guaranteed to be always available.
It contains functions to run commands, concatenate paths, perform various file system operations, compute checksums...<br>
Documentation TBD, see `lib/src/dopamine/lua` source folder.

## Paths and Files

The following table contains paths, that may be referred to in the next sections.

| Symbol        | Path                  | Description                                 |
| ------------- | ----------------      | -------------------------------             |
| `$USR_DIR`    | Linux: `~/.dopamine`<br>Windows: `%LOCALAPPDATA%\Dopamine` | Local storage for Dopmaine    |
|               | `$USR_DIR/profiles`   | Local cache for profiles                    |
|               | `$USR_DIR/packages`   | Local package cache                         |
| `$PKG`        |                       | Refer to a package directory                |
|               | `$PKG/dopamine.lua`   | Package recipe file.
| `$DOP`        | `$PKG/.dop`           | Package working directory for `dop`         |
|               | `$PKG/dop.lock`       | Dependency lock file                        |
| `$PROF`       | `$DOP/[profile hash]` | Working directory for a profile             |
| `$INST`       | `$PROF/install`       | Install directory for a profile (optional)  |
| `$PKG_LCK`    | `$DOP/.lock`          | Lock file for the complete package          |
| `$BLD_LCK`    | `$PROF/.lock`         | Lock file for a profile                     |

### Lock files

Lock files are used to ensure atomicity and exclusive access to a package and also to keep track of the
state of the package between successive invocations of `dop`.
`dop` uses their modification date and if required their content to check for the validity of a previous operation.

## Commands summary

| Command      | Description                                      |
| ------------ | ------------------------------------------------ |
| `profile`    | Get, set or adjust the compilation profile.      |
| `options`    | Get, set or adjust the package build options.    |
| `resolve`    | Resolve an and lock dependencies.                |
| `depinstall` | Install dependencies.                            |
| `source`     | Download package source.                         |
| `build`      | Build package with selected compilation profile. |
| `package`    | Package binary for distribution.                 |
| `cache`      | Add a package in the local cache.                |
| `publish`    | Publish a package recipe on a repository.        |
| `upload`     | Upload a built package to a repository.          |

## Profile command

Set or get the compilation profile for the current package.
The selected profile of a package is saved in `$PACKDIR/.dop/profile.ini`

- `dop profile` :heavy_check_mark:
  - Print the name of the currently selected profile or `(no profile selected)`
- `dop profile --describe` :heavy_check_mark:
  - Print a detailed description of the current profile.
- `dop profile default` :white_check_mark:
  - Sets the default profile as current
  - Use only the languages of the current recipe
- `dop profile default-lang1[-lang2...]` :white_check_mark:
  - Sets the default profile as current
  - Use the languages of the current recipe in addition to the one(s) specified
- `dop profile [name]` :white_check_mark:
  - Sets the named profile as current
  - Use only the languages of the current recipe
- `dop profile --add-missing` :white_check_mark:
  - Add missing languages to the compilation profile
- `dop profile --set-[lang] [compiler]` :white_check_mark:
  - Change compiler for language `[lang]`
  - `[compiler]` is optional and can be a command (e.g. `dmd`) or a path
  - If `[compiler]` is omitted, the default for `[lang]` is picked.
- `dop profile --release` :white_check_mark:
  - Set profile in Release mode
- `dop profile --debug` :white_check_mark:
  - Set profile in Debug mode
- `dop profile --save [name]` :white_check_mark:
  - Saves the current profile to the user profile cache with name
  - Can be combined with other options that modify the profile.

For more sophisticated need, the profile INI files can be edited.

### Profile files

Profile files are INI files containing info about:

- the host (OS, architecture)
- build mode (Release or Debug)
- The compiler (one per language):
  - name (Gcc, Dmd...)
  - version
  - ABI

Profile files can be cached in `~/.dopamine/profiles`. <br>
The filename for profiles is `[basename]-[langlist].ini`.
For example:

- `~/.dopamine/profiles/default-d-c.ini`

## Options command

## Resolve command

Resolve and lock dependencies.<br>
_Prerequisite_: A profile must be chosen (dependencies can depend on profile)

- `dop resolve` :x:
  - Resolve dependencies and creates a dependency lockfile for the current package.
  - If one exists already, exits without alteration.
- `dop resolve -f|--force` :x:
  - Resolve dependencies and overwrite the dependency lockfile
- `dop resolve --prefer-system` :x:
  - Creates/reset a dependency lockfile using the `preferSystem` heuristic mode.
  - This is the default heuristic and therefore equivalent to `--force`.
- `dop resolve --prefer-cached` :x:
  - Creates/reset a dependency lockfile using the `preferCached` heuristic mode.
- `dop resolve --prefer-local` :x:
  - Creates/reset a dependency lockfile using the `preferLocal` heuristic mode.
- `dop resolve --pick-highest` :x:
  - Creates/reset a dependency lockfile using the `pickHighest` heuristic mode.
- `dop resolve --no-network` :x:
  - Disable access to network for the resolution of dependencies
- `dop resolve --no-system` :x:
  - Disable access to system installation for the resolution of dependencies.
- `dop resolve --use [dependency] [version]` :x:
  - Use the specified version of dependency package in the lock file.
  - If lock file exists, alter it.
  - If lock file does not exist, create it with this version.
  - `[dependency]` must be one of the dependencies (direct or indirect) of the current package.
  - `[version]` must be an exact and existing version of `[dependency]` and must be compatible with the version specification in the dependency tree.

### Dep-lock file

Dependency lock files are located in the package root in a file named `dop.lock`. <br>


## Depinstall command

Download and install dependencies of a package.<br>

_Prerequisite_: The dependencies must be locked.

_State_:
 - `$PROF/.lock` has a `dep` field to track where the dependencies were installed.
    If empty, deps were installed under `$USR_DIR/packages`, otherwise the content points to the dependencies prefix.

_Command invocations_:
- `dop depinstall` :x:
  - Download and install the dependencies
  - Dependencies that are not built for the chosen profile are built.
  - They are installed in a per-dependency and per-profile directory under the `~/.dopamine/packages` directory.
- `dop depinstall --stage [prefix]` :x:
  - Same as `dop depinstall` except that dependencies are staged in the given prefix.
  - The build process will use the dependencies installed in `[prefix]` instead of the ones in the `~/.dopamine/packages` directory.

## Source command

Download package source code.

_Requirements_:
- The `source` recipe function, if provided, must effectively download the package source code and return the path.
- If the `source` function returns successfully, the return value is written to `$SRC_FLG`.
- If the package embeds the source code, the `source` symbol may be a constant string, which is interpreted as a relative path from `$PKG` to the source directory.
- If the `source` symbol is omitted, `'.'` is assumed.

_Command options_:

- `dop source` :x:
  - Execute the `source` function of the recipe file.
  - If `source` symbol is a string, the source code is expected
    local with the package, `source` being the relative path to the source directory.
- ....

## Build command

Build the current package<br>
_Prerequisites_:

- The profile must be chosen.
- The dependencies must be locked.
- The dependencies must be installed.
- The source code must be available

_Requirements_:

- The `build` function of the Lua recipe must effectively compile the package using the build system provided by the package source code.
- The build must happen in a directory within the package that is unique for the build configuration. `dirs.build` is provided as a possible build directory, but other directory can be used if deemed necessary.
- The `build` function accepts three arguments in addition to `self` (the recipe table):
  1. `dirs`: a table containing paths:
     - `dirs.src` to the source directory
     - `dirs.config` is a working directory unique for the (profile + options) configuration
     - `dirs.build` is a recommended location to build
     - `dirs.install` is where to install (which is optional)
  2. `config`: the compilation config table:
     - `config.profile`: the compilation profile
     - `config.options`: the compilation options
     - `config.hash`: A unique hash for the configuration
     - `config.short_hash`: An abbreviation of the unique hash
  3. `depinfos`: a table containing one entry per dependency, each containing where it is installed.
- The `build` function may use the install functionality of the build system. If it does, it must install to the `dirs.install` directory.
- If the build is successful, `$BLD_FLG` is written.
- If the build is successful, the `build` function must return `true` if the install functionality was used.
  If so, `$INST` must exist and is the path is written to `$BLD_FLG`.

_Command options_:

- `dop build` :x:
  - Execute the `build` function of the recipe file.
- `dop build --profile [profile]` :x:
  - Execute the `build` function of the recipe file using `[profile]` as compilation profile instead of the one currently selected.
- `dop build --debug` :x:
  - Execute the `build` function of the recipe file using a debug variant of the currently selected profile.
- `dop build --release` :x:
  - Execute the `build` function of the recipe file using a release variant of the currently selected profile.

## Package command

Package the compiled package.

_Prerequisites_:

- The profile must be chosen.
- The dependencies must be locked.
- The dependencies must be installed.
- The source code must be available
- The package must be built.
- The recipe must have a `package` function, or have installed during the `build` command

_Requirements_:
- If the recipe uses the install functionality of the build system, it may or may not declare a `package` function.
- If the recipe does not use the install functionality of the build system, it must declare a `package` function.
- If `package` function does not exist and `$INST` and `$STAGE` are different directories, the content of `$INST` is copied to `$STAGE`.
- The `package` function takes three arguments in addition to `self` (the recipe table):
  1. `dirs`: a table containing paths:
     - `dirs.src` to the source directory
     - `dirs.config` is a working directory unique for the (profile + options) configuration
     - `dirs.build` is a recommended location to build, it may or may not have been used
     - `dirs.install` is where to install (which is optional)
     - `dirs.dest` is where to create the package
  2. `config`: the same as for the `build` function
  3. `depinfos`: the same as for the `build` function
- If the `dirs.install` and `dirs.dest` directories are identical and install functionality was used, the `package` function may only patch files in that directory.
- If the `dirs.install` and `dirs.dest` directories are different, the `package` function must effectively copy the necessary files to the `dirs.dest` directory, either from `dirs.install` or directly from where the build occurred.
- If the recipe declares a `patch_install` function, it is executed. The `patch_install` function has the same signature as the `package` function.

_Command options_:

- `dop package` :x:
  - Execute the `package` function of the recipe with the default destination.
  - If `package` symbol is `nil` and the package was installed, simply copy the installation to the destination directory.
- `dop package [dest]` :x:
  - Same as previous but package to `[dest]`.

## Cache command

Cache the built package to be reused in the current system as a pre-built dependency for other packages

## Publish command

Publish a recipe to the registry

## Upload command

Upload the built package to the registry to be reused as a pre-built dependency on other systems.
