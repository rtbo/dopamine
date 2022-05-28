# Dopamine unit tests

This meson target is an executable that runs all the unit tests
of all the packages.

Tests are driven by a modified version of `silly`.
`test/meson.build` runs a tool that scans all the packages source files
to find modules containing unit tests, and generate `all_mods.d` which is afterwards
used by `silly`.

