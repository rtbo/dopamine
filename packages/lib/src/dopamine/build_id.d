module dopamine.build_id;

import dopamine.profile;
import dopamine.recipe;
import dopamine.semver;
import dopamine.util;

import std.algorithm;
import std.digest.sha;
import std.path;

@safe:

struct BuildId
{
    alias Digest = SHA1;

    /// Build a package Build-Id.
    /// Params:
    ///   recipe =      The package recipe
    ///   config =      The build configuration
    ///   depInfos =    The dependency build information (only the direct dependencies). No sorting is necessary.
    ///   stageDest =   The stage directory. Must be filled only if for recipes that declare `stage = false`
    this(const(Recipe) recipe, const(BuildConfig) config, DepBuildInfo[] depInfos, string stageDest = null)
    in (!stageDest || isAbsolute(stageDest))
    {
        Digest digest;

        feedDigestData(digest, recipe.name);
        feedDigestData(digest, recipe.isDub);
        feedDigestData(digest, recipe.ver.toString());
        feedDigestData(digest, recipe.revision);

        config.feedDigest(digest);

        depInfos.sort!((a, b) { return a.kind == b.kind ? a.name < b.name : a.kind < b.kind; });
        foreach (depInfo; depInfos)
        {
            feedDigestData(digest, depInfo.name);
            feedDigestData(digest, depInfo.kind);
            feedDigestData(digest, depInfo.buildId.toString());
        }

        // recipes that declare `stage = false` have the stage directory
        // in the build-id. Such recipes can be published, but the binaries
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
    string toString() const pure
    {
        return uniqueId;
    }

    /// ditto
    string opCast(T : string)() const pure
    {
        return uniqueId;
    }
}
