module dopamine.client.options;

import dopamine.client.utils;

import dopamine.log;
import dopamine.recipe;

import std.algorithm;
import std.format;
import std.getopt;
import std.sumtype;

int optionsMain(string[] args)
{
    bool clear;
    bool print;

    // dfmt off
    auto helpInfo = getopt(args,
        "clear|c", "Clear currently set options before processing.", &clear,
        "print|p", "Print currently set options after processing.", &print,
    );
    // dfmt on

    if (helpInfo.helpWanted)
    {
        const text = format!`
  dop options - Set options for a package directory
  Usage:
    %s options [options] ['key=value' 'key=value' ...]
  Options:`(args[0]);

        defaultGetoptPrinter(text, helpInfo.options);
        return 0;
    }

    OptionVal[string] options;
    foreach (arg; args[1 .. $])
    {
        parseOptionSpec(options, arg);
    }

    auto rdir = enforceRecipe();

    if (clear)
        rdir.clearOptionFile();

    options = rdir.mergeOptionFile(options);

    if (print)
    {
        auto names = options.keys;
        sort(names);
        const longest = cast(int) names.map!(n => n.length).maxElement();
        foreach (n; names)
        {
            auto val = options[n];
            auto col = val.match!(
                (bool _) => Color.cyan,
                (int _) => Color.magenta,
                (string _) => Color.green,
            );
            logInfo(" - %*s = %s", -longest, info(n), color(col, val.toString()));
        }
    }
    return 0;
}
