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

## Registry

NOT IMPLEMENTED
The remote registry will also be sandboxed by being run as localhost mock server
with the `$DOP_REGISTRY` environment variable. (one server instance per test)

## Assetions

 - [X] `EXPECT_FAIL`
    - expect the command to fail
 - [X] `EXPECT_MATCH`
    - expect to match a regex on the command output
 - [X] `EXPECT_NOT_MATCH`
    - expect to NOT match a regex on the command output
 - [ ] `EXPECT_MATCH[FILE]`
    - expect to match a regex in the `FILE` content
    - `FILE` string can contain environment variable such as $DOP_HOME
    - `FILE` string can also be `"stdout"` or `"stderr"`
 - [ ] `EXPECT_NOT_MATCH[FILE]`
    - expect to NOT match a regex in the `FILE` content
    - same rules regarding `FILE` apply than with `EXPECT_MATCH`
