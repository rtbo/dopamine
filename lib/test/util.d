module test.util;

import std.exception;
import std.file;
import std.path;

string testDataContent(string filename) @trusted
{
    const path = buildPath(dirName(__FILE_FULL_PATH__), "data", filename);
    return cast(string)assumeUnique(read(path));
}
