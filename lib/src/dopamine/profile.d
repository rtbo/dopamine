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

enum DCompiler
{
    ldc,
    dmd,
}

enum CppCompiler
{
    gcc,
    clang,
    vs, // version?
}

enum OS
{
    linux,
    windows,
}

class Profile
{
    Arch arch;
    OS os;
    BuildType buildType;
    Lang lang;
    string compilerVersion;
}

class DProfile : Profile
{
    DCompiler compiler;
}

class CppProfile : Profile
{
    CppCompiler compiler;
}
