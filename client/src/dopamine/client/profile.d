module dopamine.client.profile;

import dopamine.client.utils;

import dopamine.log;
import dopamine.paths;
import dopamine.profile;
import dopamine.recipe;

import std.exception;
import std.file;
import std.string;
import std.stdio;

struct SetLang
{
    Lang lang;
    string compiler;
}

struct ProfileOptions
{
    enum Mode
    {
        read,
        write,
    }

    bool help;
    bool describe;
    bool addMissing;
    SetLang[] setLangs;
    bool setDebug;
    bool setRelease;
    string saveName;
    string profileName;

    @property Mode mode() const
    {
        if (addMissing || setLangs.length ||
            setDebug || setRelease || profileName.length)
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
            else if (arg.startsWith("--save"))
            {
                enum start = "--save".length;
                if (arg.length > start && arg[start] == '=')
                {
                    opt.saveName = arg[start + 1 .. $];
                }
                else if (i + 1 < args.length && !args[i + 1].startsWith("-"))
                {
                    opt.saveName = args[++i];
                }
                if (!opt.saveName.length)
                {
                    throw new FormatLogException(
                        "%s --save must have a [name] argument",
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

    assertThrown(ProfileOptions.parse(["--save"]));

    opt = ProfileOptions.parse(["--save", "name"]);
    // Mode.read is not intuitive, but is correct:
    // we save into user cache, not in the local profile.
    assert(opt.isRead);

    opt = ProfileOptions.parse(["--release", "--save", "name"]);
    assert(opt.isWrite);
    assert(opt.setRelease);
    assert(opt.saveName == "name");

    opt = ProfileOptions.parse(["--debug"]);
    assert(opt.isWrite);
    assert(opt.setDebug);

    assertThrown(ProfileOptions.parse(["--debug", "--release"]));
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

    auto dir = PackageDir(".");
    if (!dir.hasDopamineFile)
    {
        logWarning(
            "%s This does not seem to be a dopamine package directory.",
            warning("Warning:"));
    }

    if (opt.isRead)
    {
        enforce(exists(dir.profileFile), new FormatLogException(
                "%s No profile file to read from",
                error("Error:")
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

    Recipe recipe = parseRecipe(dir);

    return 0;
}

int usage(int code)
{
    if (code == 0)
    {
        logInfo("%s - Dopamine compilation profile management", info("dop profile"));
    }
    logInfo("");
    logInfo("%s", info("Usage"));
    return code;
}
