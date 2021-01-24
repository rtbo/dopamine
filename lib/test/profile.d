module test.profile;

import test.util;

import dopamine.profile;

import std.file;

Profile ensureDefaultProfile()
{
    const path = testPath("gen/profile/default.ini");
    if (exists(path))
    {
        return Profile.loadFromFile(path);
    }
    auto profile = detectDefaultProfile([Lang.d, Lang.cpp, Lang.c]);
    profile.saveToFile(path, true, true);
    return profile;
}
