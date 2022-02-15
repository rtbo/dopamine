# Dopamine unit tests

This meson target is an executable that runs all the unit tests
of `lib/` and `client/` as well some additional tests.

Tests are driven by a modified version of `silly`.
`test/meson.build` runs a tool that scans all the `lib/` and `client/` source files
to find modules containing unit tests, and generate `all_mods.d` which is afterwards
used by `silly`.

