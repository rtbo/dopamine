# End to end tests for Dopamine

Ad-hoc test framework where each test is described in a *.test file

Each test define a DOP command to be run and make some assertions (EXPECT_*).

## *.test format

The test file format consist of entries in the form `KEY=VALUE`.
There can be one entry per line.
Lines starting with `#` are ignored and can be used for comments.

## Sandbox

Each test is run in a sandboxed environment.
The sandbox is meant to run the test in isolation from the running system.

For each test a RECIPE and a HOME is defined, both of which refer to a directory
in `recipes` and `homes` respectively.
Content of these two directories is copied in the sandbox dir:
 - `sandbox/[test name]/recipe` will be the `CWD` during.
 - `sandbox/[test name]/home` will correspond to `DOP_HOME`

The sandbox is however not a virtual machine. The end-to-end tests require some
tools to be present on the system, and the exact testing behavior can vary depending
on what tools are installed on the system and in which versions they are installed.

## Registry

TO BE DEFINED.
The remote registry will also be sandboxed by being run as localhost mock server
with the `$DOP_REGISTRY` environment variable. (one server instance per test)

## Assetions

 - `EXPECT_FAIL`
    - expect the command to fail
 - `EXPECT_MATCH[FILE]=regex`
    - expect to match a regex in the `FILE` content
    - `FILE` string can contain environment variable such as $DOP_HOME
    - `FILE` string can also be `"stdout"` or `"stderr"`
 - `EXPECT_NOT_MATCH[FILE]=regex`
    - expect to NOT match a regex in the `FILE` content
    - same rules regarding `FILE` apply than with `EXPECT_MATCH`
 - `EXPECT_FILE=path`
    - expect that path points to a file
 - `EXPECT_DIR=path`
    - expect that path points to a directory

## Skip rules

TO BE DEFINED.
Rules are needed to skip some tests depending on platform, or if an external
tool is not found or not in the right version.