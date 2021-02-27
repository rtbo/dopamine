module test.depcache;

import dopamine.depdag;
import dopamine.recipe;
import dopamine.semver;

import test.recipe;

class DepCacheMock : CacheRepo
{
    Recipe packRecipe(string packname, Semver, string = null) @trusted
    {
        return pkgRecipe(packname);
    }

    Semver[] packAvailVersions(string) @safe
    {
        return [Semver("1.0.0")];
    }

    bool packIsCached(string, Semver, string = null) @safe
    {
        return true;
    }
}
