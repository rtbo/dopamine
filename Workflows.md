# Dopamine PM Workflows

## Defintions

- In tree: `dopamine.lua` is in the source tree of the package.
- Out of tree: `dopamine.lua` is in a packaging repo for building 3rd party libraries.

## Packaging workflow

- Download source code (out of tree only)
  - Will be fetched in e.g. ~/.dop/pkgs
  - `dop source [package]`
- Select build profile
  - `dop profile [name|default]`
- Install dependencies (build them if needed)
  - `dop install`
- Build && Install
  - Uses a build system provided in the source code
  - This build the package and install it
  - Build directory and install prefix specific to a profile
  - `dop build`
- Package
  - Will simply tar the install root in an archive
  - `dop package`
- Sign
  - in tree: check if working dir is clean and has version tag
    (assumed for out of tree)
  - GnuPG is used. Web of trust to be established.
  - `dop sign`
- Upload
  - will fail if not signed
  - `dop upload`
