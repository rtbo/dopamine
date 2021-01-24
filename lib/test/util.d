module test.util;

import std.file;
import std.path;

string testPath(Args...)(Args args)
{
    return buildPath(dirName(__FILE_FULL_PATH__), args);
}
