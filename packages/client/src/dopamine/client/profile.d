module dopamine.client.profile;

import dopamine.client.utils;

import dopamine.log;
import dopamine.paths;
import dopamine.profile;
import dopamine.recipe;

import std.algorithm;
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
Profile enforceProfileReady(RecipeDir dir, string name = null)
{
    Profile profile;
    if (!name)
    {
        enforce(exists(dir.profileFile),
            new ErrorLogException(
                "%s has no defined profile. Try to run %s.",
                info(dir.recipe.name), info("dop profile"),
        )
        );
        profile = Profile.loadFromFile(dir.profileFile);
    }
    else
    {
        profile = enforce(checkProfileName(dir.recipe, name),
            new ErrorLogException(
                "%s has no defined profile. Try to run %s",
                info(dir.recipe.name), info("dop profile")
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


    // Recipe is needed only in a few situations,
    // so we load it only if available.
    auto dir = RecipeDir.fromDir(getcwd());
    Recipe recipe = dir.recipe;
    if (!recipe)
        logVerbose("no recipe available");
    else
        logInfo("Recipe: %s", success("OK"));

    if (opt.discover)
    {
        string[] tools = recipe ? recipe.tools.dup : ["dc", "c++", "cc"];
        const allowMissing = recipe ? No.allowMissing : Yes.allowMissing;
        auto profile = detectDefaultProfile(tools, allowMissing);
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
                "No profile selected. Run %s to set an initial compilation profile.",
                info("dop profile --discover")
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
        enforce(recipe, new ErrorLogException(
                "recipe file is needed to know which languages are missing.",
        ));
        enforce(profile, new ErrorLogException(
                "no profile found.",
        ));

        const allTools = recipe.tools;
        const availTools = profile.tools.map!(t => t.id).array;

        foreach (t; allTools)
        {
            if (!availTools.canFind(t))
            {
                auto tool = Tool.detect(t);
                logInfo("Found tool %s: %s (%s)",
                    t, tool.displayName, tool.path,
                );
                auto tools = profile.tools.dup ~ tool;
                profile = profile.withTools(tools);
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
        const tools = recipe.tools;
        name = profileName(name, tools);
        pf = homeProfileFile(name);
        if (!exists(pf))
            return null;
    }

    return Profile.loadFromFile(pf);
}

private struct SetTool
{
    string toolId;
    string toolExe;
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
    SetTool[] setTools;
    bool setDebug;
    bool setRelease;
    string exportName;
    string profileName;

    @property Mode mode() const
    {
        if (addMissing || setTools.length || setDebug || setRelease ||
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
                string id;
                string exe;
                if (eq == -1)
                {
                    id = arg[start .. $];
                    if (i + 1 < args.length && !args[i + 1].startsWith("-"))
                    {
                        exe = args[++i];
                    }
                }
                else
                {
                    id = arg[start .. eq];
                    exe = arg[eq + 1 .. $];
                }
                opt.setTools ~= SetTool(id, exe);
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

    opt = ProfileOptions.parse(["--set-dc"]);
    assert(opt.isWrite);
    assert(opt.setTools.length == 1);
    assert(opt.setTools[0] == SetTool("dc", null));

    opt = ProfileOptions.parse(["--set-dc=dmd"]);
    assert(opt.isWrite);
    assert(opt.setTools.length == 1);
    assert(opt.setTools[0] == SetTool("dc", "dmd"));

    opt = ProfileOptions.parse(["--set-dc", "dmd"]);
    assert(opt.isWrite);
    assert(opt.setTools.length == 1);
    assert(opt.setTools[0] == SetTool("dc", "dmd"));

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
