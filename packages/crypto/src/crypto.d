module crypto;

/// Interface to system cryptographic random generator
///
/// uses /dev/urandom on Posix and BCryptGenRandom on Windows
///
/// This function either fills completely buf or throws if not possible.
void cryptoRandomBytes(scope ubyte[] buf) @trusted
{
    import std.exception;

    version (Posix)
    {
        import std.stdio;

        auto rng = File("/dev/urandom", "rb");
        size_t read = 0;
        while (read != buf.length)
        {
            const rd = rng.rawRead(buf[read .. $]);
            enforce(
                rd.length != 0,
                "Could not read from /dev/urandom"
            );
            read += rd.length;
        }
    }
    else
    {
        auto res = BCryptGenRandom(null, buf.ptr, cast(ULONG) buf.length, BCRYPT_USE_SYSTEM_PREFERRED_RNG);
        enforce(NT_SUCCESS(res), "BCryptGenRandom failed");
    }
}

version (Windows)
{
    import core.sys.windows.windows;
    import core.sys.windows.ntdef;

    enum BCRYPT_USE_SYSTEM_PREFERRED_RNG = 0x0000_0002;

    alias BCRYPT_ALG_HANDLE = PVOID;

    extern (System) NTSTATUS BCryptGenRandom(
        BCRYPT_ALG_HANDLE hAlgorithm,
        PUCHAR pbBuffer,
        ULONG cbBuffer,
        ULONG dwFlags,
    );
}
