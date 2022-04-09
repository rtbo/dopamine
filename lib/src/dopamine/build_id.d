module dopamine.build_id;

import dopamine.profile;
import dopamine.util;

import std.digest.sha;

@safe:

alias DopDigest = SHA1;

/// The build configuration
struct BuildConfig
{
    /// the build profile
    Profile profile;

    /// recipes declaring `stage = false` have the stage directory
    /// in the digest hash. Such packages cannot be uploaded as binaries.
    string stageFalseDest;

    @property string digestHash() const
    {
        DopDigest digest;

        profile.feedDigest(digest);
        if (stageFalseDest)
        {
            feedDigestData(digest, stageFalseDest);
        }

        return toHexString!(LetterCase.lower)(digest.finish()).idup;
    }
}
