module dopamine.build_id;

import dopamine.profile;
import dopamine.recipe;
import dopamine.semver;
import dopamine.util;

import std.digest.sha;
import std.path;

// FIXME: make @safe when recipe.revision is @safe
// FIXME: make const(Recipe) when recipe.revision is const

struct BuildId
{
    alias Digest = SHA1;

    this(Recipe recipe, const(BuildConfig) config, string stageDest = null)
    in (!stageDest || isAbsolute(stageDest))
    {
        Digest digest;

        feedDigestData(digest, recipe.name);
        feedDigestData(digest, recipe.ver.toString());
        feedDigestData(digest, recipe.revision);

        config.feedDigest(digest);

        // recipes that declare `stage = false` have the stage directory
        // in the build-id. Such recipes can be publised, but the binaries
        // can't be uploaded
        if (stageDest && !recipe.canStage)
        {
            feedDigestData(digest, stageDest);
        }

        uniqueId = toHexString!(LetterCase.lower)(digest.finish()).idup;
    }

    /// The unique Id of the build
    string uniqueId;

    /// ditto
    @property string toString() const
    {
        return uniqueId;
    }

    /// ditto
    string opCast(T : string)() const
    {
        return uniqueId;
    }
}
