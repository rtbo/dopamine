module dopamine.server.loadenv;

import std.algorithm;
import std.exception;
import std.process;
import std.stdio;
import std.string;

/// Load environment variables from a file
void loadEnv(string filename) @trusted
{
    File(filename, "r").byLineCopy().map!(l => l.strip())
        .filter!(l => !l.startsWith("#"))
        .filter!(l => l.length != 0)
        .each!((l) {
            const eq = l.indexOf('=');
            enforce(eq > 0, "ill-formed variable definition: %s", l);
            const name = l[0 .. eq].strip();
            const val = l[eq + 1 .. $].strip();
            environment[name] = val;
        });
}

///
unittest
{
    void process(string content)
    {
        import std.file : write, remove;

        write("deleteMe", content);
        loadEnv("deleteMe");
        remove("deleteMe");
    }

    void cleanup()
    {
        environment.remove("TEST_COMMENT");
        environment.remove("TEST_VAR1");
        environment.remove("TEST_VAR2");
    }

    cleanup();
    scope (exit)
        cleanup();

    const testStr = `
# TEST_COMMENT = comment
TEST_VAR1 = value
TEST_VAR2 = value with spaces
    `;

    process(testStr);

    assert(environment.get("TEST_COMMENT") is null);
    assert(environment.get("TEST_VAR1") == "value");
    assert(environment.get("TEST_VAR2") == "value with spaces");
}
