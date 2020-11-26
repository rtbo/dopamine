module dopamine.profile;

enum Arch
{
    x86_64,
    x86,
}

enum BuildType
{
    release,
    debug_,
}

enum Lang
{
    d,
    cpp,
    c,
}

enum OS
{
    linux,
    windows,
}

class Compiler
{
    Lang lang;
    string name;
    string desc;
    string ver;
}

class Profile
{
    Arch arch;
    OS os;
    BuildType buildType;
    Compiler dcomp;
    Compiler ccomp;
}
