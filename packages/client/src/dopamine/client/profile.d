module dopamine.client.profile;

import dopamine.client.utils;

import dopamine.log;
import dopamine.paths;
import dopamine.profile;
import dopamine.recipe;

import std.array;
import std.exception;
import std.file;
import std.path;
import std.string;
import std.stdio;
import std.typecons;

/// Enforce the loading of a profile.
/// If name is null, will load the profile from the profile file in .dop/ directory
/// If name is not null (can be e.g. "default"), will load the profile from the user profile directory
Profile enforceProfileReady(RecipeDir dir, Recipe recipe, string name = null)
{
    Profile profile;
    if (!name)
    {
        enforce(exists(dir.profileFile),
            new ErrorLogException(
                "%s has no defined profile. Try to run %s.",
                info(recipe.name), info("dop profile"),
        )
        );
        profile = Profile.loadFromFile(dir.profileFile);
    }
    else
    {
        profile = enforce(checkProfileName(recipe, name),
            new ErrorLogException(
                "%s has no defined profile. Try to run %s",
                info(recipe.name), info("dop profile")
        )
        );
    }
    if (profile.name)
    {
        logInfo("%s: %s - %s (%s)", info("Profile"), success("OK"),
            info(profile.name), dir.profileFile());
    }
    else
    {
        logInfo("%s: %s - %s", info("Profile"), success("OK"), dir.profileFile());
    }
    return profile;
}

int profileMain(string[] args)
{
    ProfileOptions opt;
    try
    {
        opt = ProfileOptions.parse(args[1 .. $]);
    }
    catch (FormatLogException ex)
    {
        ex.log();
        return usage(1);
    }
    catch (Exception ex)
    {
        logError("%s Could not parse options: %s", error("Error:"), ex.msg);
        return usage(1);
    }

    if (opt.help)
    {
        return usage(0);
    }

    auto dir = RecipeDir(".");

    // Recipe is needed only in a few situations,
    // so we load it only if available.
    Recipe recipe;
    if (dir.hasRecipeFile)
    {
        recipe = parseRecipe(dir);
    }
    else
    {
        logVerbose("no recipe available");
    }

    if (opt.discover)
    {
        Lang[] langs = [Lang.d, Lang.cpp, Lang.c];
        auto profile = detectDefaultProfile(langs, Yes.allowMissing);
        const homeFile = homeProfileFile(profile.name);
        const dirFile = dir.profileFile;
        logInfo(
            "Discovered default profile %s",
            info(profile.name)
        );
        logInfo("Saving to %s", info(homeFile));
        profile.saveToFile(homeFile, true, true);
        logInfo("Saving to %s", info(dirFile));
        profile.saveToFile(dirFile, true, true);

        if (opt.describe)
        {
            profile.describe(stdout.lockingTextWriter);
        }

        return 0;
    }

    if (opt.isRead)
    {
        enforce(exists(dir.profileFile), new ErrorLogException(
                "No profile file to read from: %s: No such file",
                info(dir.profileFile)
        ));
        auto profile = Profile.loadFromFile(dir.profileFile);
        if (opt.describe)
        {
            profile.describe(stdout.lockingTextWriter());
        }
        else
        {
            stdout.writeln(profile.name);
        }
        return 0;
    }

    if (opt.profileName)
    {
        const newProfileFile = homeProfileFile(opt.profileName);

        enforce(exists(newProfileFile), new FormatLogException(
                "%s No such profile: %s (%s)",
                error("Error:"), info(opt.profileName), newProfileFile
        ));
        if (exists(dir.profileFile))
        {
            logInfo("Overwriting previous profile file");
        }
        mkdirRecurse(dirName(dir.profileFile));
        copy(newProfileFile, dir.profileFile);
    }

    // the remaining options are about modifying an existing profile

    Profile profile;
    if (exists(dir.profileFile))
    {
        profile = Profile.loadFromFile(dir.profileFile);
    }

    auto orig = profile;

    if (opt.addMissing)
    {
        enforce(cast(bool) recipe, new FormatLogException(
                "%s recipe file is needed to know which languages are missing.",
                error("Error:"),
        ));
        enforce(profile, new FormatLogException(
                "%s no profile found.",
                error("Error:"),
        ));

        const allLangs = recipe.langs;
        const availLangs = profile.langs;

        foreach (l; allLangs)
        {
            import std.algorithm : canFind;

            if (!availLangs.canFind(l))
            {
                auto cl = Compiler.detect(l);
                logInfo("Found %s compiler: %s (%s)",
                    l.to!string, cl.displayName, cl.path,
                );
                auto compilers = profile.compilers.dup ~ cl;
                profile = profile.withCompilers(compilers);
            }
        }
    }

    if (opt.setDebug || opt.setRelease)
    {
        enforce(profile, new FormatLogException(
                "%s no profile found.",
                error("Error:"),
        ));

        const newBt = opt.setDebug ? BuildType.debug_ : BuildType.release;
        logInfo("Setting profile build type to %s", info(newBt.to!string));
        profile = profile.withBuildType(newBt);
    }

    if (opt.exportName)
    {
        if (opt.exportName != profile.basename)
        {
            logInfo("Renaming profile from %s to %s", info(profile.basename), info(opt.exportName));
            profile = profile.withBasename(opt.exportName);
        }
        const file = homeProfileFile(profile);
        logInfo("Exporting profile to %s", file);
        profile.saveToFile(file);
    }

    if (profile !is orig)
    {
        logInfo("Saving updated profile to: %s", info(dir.profileFile));
        profile.saveToFile(dir.profileFile);

        if (opt.describe)
        {
            logInfo("Updated profile description:\n");
            // FIXME describe to logInfo rather than stdout
            profile.describe(stdout.lockingTextWriter());
        }
    }

    return 0;
}

private int usage(int code)
{
    if (code == 0)
    {
        logInfo("%s - Dopamine compilation profile management", info("dop profile"));
    }
    logInfo("");
    logInfo("%s", info("Usage"));
    return code;
}

// Check if a profile named [name] exists, and load it
private Profile checkProfileName(Recipe recipe, string name = "default")
{
    auto pf = homeProfileFile(name);
    if (!exists(pf))
    {
        const langs = recipe.langs;
        name = profileName(name, langs);
        pf = homeProfileFile(name);
        if (!exists(pf))
            return null;
    }

    return Profile.loadFromFile(pf);
}

private struct SetLang
{
    Lang lang;
    string compiler;
}

private struct ProfileOptions
{
    enum Mode
    {
        read,
        write,
    }

    bool help;
    bool discover;
    bool describe;
    bool addMissing;
    SetLang[] setLangs;
    bool setDebug;
    bool setRelease;
    string exportName;
    string profileName;

    @property Mode mode() const
    {
        if (addMissing || setLangs.length || setDebug || setRelease ||
            profileName.length || exportName.length || discover)
        {
            return Mode.write;
        }
        else
        {
            return Mode.read;
        }
    }

    bool isRead() const
    {
        return mode == Mode.read;
    }

    bool isWrite() const
    {
        return mode == Mode.write;
    }

    // parse options of the profile command
    // args[0] must be start of options, not executable name
    static ProfileOptions parse(string[] args)
    {
        ProfileOptions opt;

        // Flexible parsing that can't be done with getopt is needed,
        // so we go down the route of manual arg parsing.
        for (size_t i = 0; i < args.length; ++i)
        {
            string arg = args[i];

            if (arg == "--help" || arg == "-h")
            {
                opt.help = true;
                return opt;
            }
            else if (arg == "--discover")
            {
                opt.discover = true;
            }
            else if (arg == "--describe")
            {
                opt.describe = true;
            }
            else if (arg == "--add-missing")
            {
                opt.addMissing = true;
            }
            else if (arg.startsWith("--set-"))
            {
                enum start = "--set-".length;
                const eq = arg.indexOf('=');
                string lnam;
                string cl;
                if (eq == -1)
                {
                    lnam = arg[start .. $];
                    if (i + 1 < args.length && !args[i + 1].startsWith("-"))
                    {
                        cl = args[++i];
                    }
                }
                else
                {
                    lnam = arg[start .. eq];
                    cl = arg[eq + 1 .. $];
                }
                Lang lang = fromConfig!Lang(lnam);
                opt.setLangs ~= SetLang(lang, cl);
            }
            else if (arg == "--debug")
            {
                opt.setDebug = true;
            }
            else if (arg == "--release")
            {
                opt.setRelease = true;
            }
            else if (arg.startsWith("--export"))
            {
                enum start = "--export".length;
                if (arg.length > start && arg[start] == '=')
                {
                    opt.exportName = arg[start + 1 .. $];
                }
                else if (i + 1 < args.length && !args[i + 1].startsWith("-"))
                {
                    opt.exportName = args[++i];
                }
                if (!opt.exportName.length)
                {
                    throw new FormatLogException(
                        "%s --export must have a [name] argument",
                        error("Error:"),
                    );
                }
            }
            else
            {
                if (arg.startsWith("-"))
                {
                    throw new FormatLogException(
                        "%s Unknown option: %s",
                        error("Error:"), info(arg));
                }
                opt.profileName = arg;
            }
        }
        if (opt.setDebug && opt.setRelease)
        {
            throw new FormatLogException(
                "%s --debug and --release cannot be set in the same command",
                error("Error:"));
        }

        return opt;
    }
}

@("ProfileOptions.parse")
unittest
{
    import std.exception : assertThrown;

    assert(ProfileOptions.parse([]).isRead);

    auto opt = ProfileOptions.parse(["--describe"]);
    assert(opt.isRead);
    assert(opt.describe);

    opt = ProfileOptions.parse(["blah"]);
    assert(opt.isWrite);
    assert(opt.profileName == "blah");

    opt = ProfileOptions.parse(["--add-missing"]);
    assert(opt.isWrite);
    assert(opt.addMissing);

    opt = ProfileOptions.parse(["--set-d"]);
    assert(opt.isWrite);
    assert(opt.setLangs.length == 1);
    assert(opt.setLangs[0] == SetLang(Lang.d, null));

    opt = ProfileOptions.parse(["--set-d=dmd"]);
    assert(opt.isWrite);
    assert(opt.setLangs.length == 1);
    assert(opt.setLangs[0] == SetLang(Lang.d, "dmd"));

    opt = ProfileOptions.parse(["--set-d", "dmd"]);
    assert(opt.isWrite);
    assert(opt.setLangs.length == 1);
    assert(opt.setLangs[0] == SetLang(Lang.d, "dmd"));

    assertThrown(ProfileOptions.parse(["--set-x"]));

    opt = ProfileOptions.parse(["--set-d=dmd"]);
    assert(opt.isWrite);
    assert(opt.setLangs.length == 1);
    assert(opt.setLangs[0] == SetLang(Lang.d, "dmd"));

    assertThrown(ProfileOptions.parse(["--export"]));

    opt = ProfileOptions.parse(["--release", "--export", "name"]);
    assert(opt.isWrite);
    assert(opt.setRelease);
    assert(opt.exportName == "name");

    opt = ProfileOptions.parse(["--debug"]);
    assert(opt.isWrite);
    assert(opt.setDebug);

    assertThrown(ProfileOptions.parse(["--debug", "--release"]));
}
