module dopamine.build_id;

import dopamine.profile;

import std.digest.sha;

@safe:

alias DopDigest = SHA1;

/// The build configuration
struct BuildConfig
{
    // at the moment only the profile, but build options are to be added
    // as well as some dependencies options or checksum
    Profile profile;

    @property string digestHash() const
    {
        return profile.digestHash;
    }
}
