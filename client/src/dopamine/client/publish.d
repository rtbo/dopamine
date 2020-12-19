module dopamine.client.publish;

import dopamine.api;
import dopamine.paths;
import dopamine.profile;
import dopamine.recipe;
import dopamine.state;

import std.exception;
import std.file;
import std.format;
import std.getopt;
import std.stdio;

int publishMain(string[] args)
{
    string profileName;
    bool create;

    auto helpInfo = getopt(args, "profile", "override profile for this invocation",
            &profileName, "create|c", "create package on server if it doesn't exist", &create,);

    if (helpInfo.helpWanted)
    {
        defaultGetoptPrinter("dop build command", helpInfo.options);
        return 0;
    }

    const packageDir = PackageDir.enforced(".");

    writeln("parsing recipe");
    auto recipe = recipeParseFile(packageDir.dopamineFile());

    Profile profile;

    if (profileName)
    {
        const filename = userProfileFile(profileName);
        enforce(exists(filename), format("Profile %s does not exist", profileName));
        profile = Profile.loadFromFile(filename);
        writeln("loading profile " ~ profile.name);
    }
    else
    {
        const filename = packageDir.profileFile();
        enforce(exists(filename), "Profile not selected");
        profile = Profile.loadFromFile(filename);
        writeln("loading profile " ~ profile.name);
    }

    assert(profile);

    auto profileState = new UseProfileState(packageDir, recipe, profile);
    auto sourceState = new EnforcedSourceState(packageDir, recipe,
            "Source code not available. Try to run `dop source`");
    auto configState = new EnforcedConfigState(packageDir, recipe, profileState, sourceState,
            format("Package not configured for profile '%s'. Try to run `dop build`", profile.name));
    auto buildState = new EnforcedBuildState(packageDir, recipe, profileState, configState,
            format("Package not built for profile '%s'. Try to run `dop build`", profile.name));
    auto installState = new EnforcedInstallState(packageDir, recipe, profileState, buildState,
            format("Package not installed for profile '%s'. Try to run `dop build`", profile.name));
    auto archiveState = new EnforcedArchiveState(packageDir, recipe, profileState, installState);

    const archiveFile = packageDir.archiveFile(profile, recipe);

    enforce(archiveState.reached,
            format("The archive file %s does not exist or is not up-to-date.\n"
                ~ "Dop must check that the package actually builds with one profile before publishing.\n"
                ~ "Maybe run `dop package` before?", archiveFile));

    writefln("found archive file: %s", archiveFile);

    API api;
    api.readLogin();

    writefln("found login key: %s", api.login.keyName);

    auto packResp = api.getPackageByName(recipe.name);
    if (!packResp)
    {
        enforce(packResp.code == 404, format("Unexpected server response: %s", packResp.code));

        if (!create)
        {
            writefln("package '%s' does not exist on server. Try with `--create` option.",
                    recipe.name);
            return 1;
        }

        writefln("Will create package '%s' on server", recipe.name);

        packResp = api.postPackage(recipe.name);

        enforce(packResp, format("Could not create package on server: %s %s",
                packResp.code, packResp.reason));
    }
    else if (create)
    {
        writefln("Found package '%s' on server. Ignoring `--create` flag.", recipe.name);
    }

    const pack = packResp.payload;

    const luaDef = cast(string) assumeUnique(read(packageDir.dopamineFile()));

    const pver = PackageVersion(pack.id, pack.name, recipe.ver, luaDef, recipe);

    const resp = api.postPackageVersion(pver);

    enforce(resp, format(`Unexpected server response: %s - %s`, resp.code, resp.error));

    return 0;
}
