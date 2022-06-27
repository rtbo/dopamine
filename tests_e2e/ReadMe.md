# End to end tests for Dopamine

Ad-hoc test framework where each test is described in a *.test file

Each test define a DOP command to be run and make some assertions (EXPECT_*).

## *.test format

The test file format consist of entries in the form `KEY=VALUE`.
There can be one entry per line.
Lines starting with `#` are ignored and can be used for comments.

## Sandbox

Each test is run in a sandboxed environment.
The sandbox system does its best to run the tests in isolation from the system,
but is not a virual machine. It require some tools to be present on the system,
as well as a running PostgreSQL instance.
Depending on the tools installed and their version, the test results may differ.

For each test a RECIPE and a HOME is defined, both of which refer to a directory
in `recipes` and `homes` respectively.
Content of these two directories is copied in the sandbox dir:
 - `sandbox/[test name]/recipe` will be the `CWD` during.
 - `sandbox/[test name]/home` will correspond to `DOP_HOME`

## Registry

To communicate with the registry, the test specifies `REGISTRY=[identifier]` where `[identifier]`
is one of the registry identifiers in `definitions.json`.
A postgresql database is created and populated with the `dop-admin` tool.
Environment variables `$PGUSER` and `$PGPSWD` can be defined to set postgresql user and password.
The `dop-server` application is spawned and setup to connect to this database.
The client is spawned with the `$DOP_REGISTRY` environment variable set
to connect to the right server instance.

## Assertions

The following assertions are supported.
For each entry, `EXPECT` can be replaced by `ASSERT`.
Unlike `EXPECT`, in case of `ASSERT` failure, the execution stops right away and
subsequent assertions are not checked.

- `EXPECT_FAIL`
  - expect the command to fail
  - if not present, the command is expected to succeed
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
- `EXPECT_LIB=dirname/libname`
  - expect to find a library named `libname` in the directory `dirname`
- `EXPECT_STATIC_LIB=dirname/libname`
  - expect to find a static library named `libname` in the directory `dirname`
- `EXPECT_SHARED_LIB=dirname/libname`
  - expect to find a shared library named `libname` in the directory `dirname`

## Skip rules

TO BE DEFINED.
Rules are needed to skip some tests depending on platform, or if an external
tool is not found or not in the right version.