# Dopamine client specification

## Basic usage

```
$ dop [global options] [command] [command options]
```

## Paths

| Spec sym.  | Path linux    | Path Windows         | Desciption                 |
| ---------- | ------------- | -------------------- | -------------------------- |
| `USER_DIR` | `~/.dopamine` | `%APPDATA%\Dopamine` | Local storage for Dopmaine |

## Global options

- `-C|--change-dir [directory]` :heavy_check_mark:
  - Change to directory before executing the command
- `-v|--verbose` :heavy_check_mark:
  - Enable verbose mode
- `-c|--no-color`
  - Disable colored output
- `--version` :heavy_check_mark:
  - Print client version and exit
- `--help` :heavy_check_mark:
  - Print help and exit

## Commands summary

| Command      | Description                                      |
| ------------ | ------------------------------------------------ |
| `profile`    | Get, set or adjust the compilation profile       |
| `deplock`    | Resolve an and lock dependencies.                |
| `depinstall` | Install dependencies.                            |
| `source`     | Download package source.                         |
| `options`    | Get, set or adjust the package build options.    |
| `build`      | Build package with selected compilation profile. |
| `package`    | Package binary for distribution.                 |
| `cache`      | Add a package in the local cache.                |
| `publish`    | Publish a package recipe on a repository.        |
| `upload`     | Upload a built package on a repository.          |

## Profile command

Set or get the compilation profile for the current package.
The selected profile of a package is saved in `$PACKDIR/.dop/profile.ini`

- `dop profile`
  - Shows the currently selected profile
- `dop profile --describe`
  - Print a detailed description of the current profile.
- `dop profile default`  :heavy_check_mark:
  - Sets the default profile as current
  - Use only the languages of the current recipe
- `dop profile default-lang1[-lang2...]`
  - Sets the default profile as current
  - Use the languages of the current recipe in addition to the one(s) specified
- `dop profile [name]` :heavy_check_mark:
  - Sets the named profile as current
  - Use only the languages of the current recipe
- `dop profile --add-[lang] [compiler]`
  - Add language `[lang]` to the compilation profile
  - `[compiler]` is optional and can be a command (e.g. `dmd`) or a path
  - If `[compiler]` is omitted, the default for `[lang]` is picked.
- `dop profile --release`
  - Set profile in Release mode
- `dop profile --debug`
  - Set profile in Debug mode
- `dop profile --save [name]`
  - Saves the current profile to the profile cache with name

For more sophisticated need, the profile files can be edited.

### Profile files :heavy_check_mark:

Profile files are INI files containing info about:

- the host (OS, architecture)
- build mode (Release or Debug)
- The compiler (one per language):
  - name (Gcc, Dmd...)
  - version

Profile files can be cached in `~/.dopamine/profiles`. <br>
The filename for profiles is `[basename]-[langlist].ini`.
For example:

- `~/.dopamine/profiles/default-d-c.ini`

## Deplock command

Resolve and locks dependencies.<br>
_Prerequisite_: A profile must be chosen (dependencies can depend on profile)

- `dop deplock` :heavy_check_mark:
  - Creates a dependency lockfile for the current package.
  - If one exists already, exits without alteration.
- `dop deplock -f|--force` :heavy_check_mark:
  - Creates or reset a dependency lock file for the current package
- `dop deplock --prefer-cached`
  - Creates/reset a dependency lockfile using the `preferCached` heuristic.
  - This is the default heuristic and therefore equivalent to `--force`.
- `dop deplock --pick-highest`
  - Creates/reset a dependency lockfile using the `pickHighest` heuristic.
- `dop deplock --cache-only`
  - Creates/reset a dependency lockfile using the `cacheOnly` heuristic.
  - This resolution heuristic do not need network.
- `dop deplock --use [dependency] [version]`
  - Use the specified version of dependency package in the lock file.
  - If lock file exists, alter it.
  - If lock file does not exist, create it with this version.
  - `[dependency]` must be one of the dependencies (direct or indirect) of the current package.
  - `[version]` must be an exact and existing version of `[dependency]` and must be compatible with the version specification in the dependency tree.

### Lock-file

Lock files are located in the package root in a file named `dop.lock`.
The format is adhoc and implementation clumsy. It is likely to switch to a well establish standard (e.g. JSON).

## Depinstall command

Download and install dependencies of a package
_Prerequisite_: The dependencies must be locked.

- `dop depinstall`
  - Download and install the dependencies
  - Dependencies that are not built for the chosen profile are built.
  - They are installed in a per-dependency and per-profile directory under the `~/.dopamine/package` directory.
- `dop depinstall --stage [prefix]`
  - Same as `dop depinstall` except that dependencies are staged in the given prefix.
  - The build process will use the dependencies installed in `[prefix]` instead of the ones in the `~/.dopamine/package` directory.

## Source command

Download package source code.

- `dop source` :heavy_check_mark:
  - Execute the `source` function of the recipe file.
  - The function is always executed from the package directory.
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

- The `build` function of the recipe must effectively compile the package using the build system provided by the package source code.
- The `build` function accepts arguments:
  1. `dirs`: a table containing paths:
     - `dirs.src` to the source directory
     - `dirs.install` is where to install the compilation if installing
  2. `profile`: the compilation profile
  3. `depinfos`: a table containing one entry per dependency, each containing where it is installed.
- The `build` function may use the install functionality of the build system. If it does, it must install to the `dirs.install` directory.

_Command options_:

- `dop build` :heavy_check_mark:
  - Execute the `build` function of the recipe file.
- `dop build --profile [profile]` :heavy_check_mark:
  - Execute the `build` function of the recipe file using `[profile]` as compilation profile instead of the one currently selected.
- `dop build --debug`
  - Execute the `build` function of the recipe file using a debug variant of the currently selected profile.
- `dop build --release`
  - Execute the `build` function of the recipe file using a release variant of the currently selected profile.

## Package command

Package the compiled package.

_Prerequisites_:

- The profile must be chosen.
- The dependencies must be locked.
- The dependencies must be installed.
- The source code must be available
- The package must be built.

_Command options_:

- `dop package`
  - Execute the `package` function of the recipe with the default destination.
  - If `package` symbol is `nil` and the package was installed, simply copy the installation to the destination directory.
- `dop package [dest]`
  - Same as previous but package to `[dest]`.
