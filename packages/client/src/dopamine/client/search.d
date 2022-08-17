module dopamine.client.search;

import dopamine.log;
import dopamine.registry;
import dopamine.api.v1;

import std.datetime;
import std.exception;
import std.getopt;
import std.string;
import std.stdio;

int searchMain(string[] args)
{
    bool all;
    SearchPackages search;

    // dfmt off
    auto helpInfo = getopt(args,
        "regex|r", "Interpret pattern as a POSIX regular expression", &search.regex,
        "case|c", "Activates case-sensitve search", &search.caseSensitive,
        "name-only|N", "Seach only in package names", &search.nameOnly,
        "extended|E", "Search also in extended fields (other than name and description)", &search.extended,
        "limit|l", "Limit the number of recipes returned", &search.limit,
        "all|A", "If set, an empty search returns all packages", &all,
    );
    // dfmt on

    if (helpInfo.helpWanted)
    {
        defaultGetoptPrinter("dop search - Search for remote packages", helpInfo.options);
        return 0;
    }

    enforce(args.length <= 2, "Only a single search pattern is allowed");

    if (args.length == 2)
        search.pattern = args[1];
    else
        enforce(all, new ErrorLogException(
                "No search pattern provided. Use %s to return all packages.", info("--all")
        ));

    enforce(!(search.nameOnly && search.extended), new ErrorLogException(
            "Can't supply %s and %s in the same search.", info("--name-only"), info("--extended")
    ));

    auto registry = new Registry();

    auto pkgEntries = registry.sendRequest(search).payload;

    foreach (entry; pkgEntries)
    {
        enum maxWidth = 80;
        enum nameWidth = 18;
        enum verWidth = 14;
        enum descWidth = maxWidth - nameWidth - verWidth - 2;

        auto desc = breakLines(entry.description, descWidth);
        if (desc.length == 0)
            desc = ["(no description)"];

        logInfo(
            "%*s/%*s %s",
            nameWidth, color(Color.cyan | Color.bright, entry.name),
            -verWidth, color(Color.green, entry.lastVersion),
            desc[0]
        );

        foreach (d; desc[1 .. $])
            logInfo(
                "%*s %*s %s",
                nameWidth, "",
                -verWidth, "",
                d
            );
    }

    return 0;
}

string[] breakLines(string sentence, int maxWidth)
{
    string[] words = sentence.split();
    string[] lines;
    string line;
    while (words.length)
    {
        if (!line.length || (line.length + words[0].length + 1 < maxWidth))
        {
            if (line.length)
                line ~= " ";
            line ~= words[0];
            words = words[1 .. $];
        }
        else
        {
            lines ~= line;
            line = null;
        }
    }
    if (line)
        lines ~= line;
    return lines;
}
