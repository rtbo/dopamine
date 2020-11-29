# Dopamine package manager

A package manager (mainly) for D

## Features

- Rely on build system (Meson, CMake, Dub, Autotools...) to build
- Can build 3rd libraries in a non-invasive way
- Each build is associated with a profile (compiler, arch, os, options...)
- Resolve dependencies per profile
  - Download prebuilt if available
  - Otherwise build from source
- Package signature using GnuPG and web of trust (TBD)

