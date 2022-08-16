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
        "latest-only|L", "Only display the latest and greatest version and recipe revision", &search.latestOnly,
        "limit|l", "Limit the number of recipes returned (implies --latest-only)", &search.recLimit,
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

    if (search.recLimit > 0)
        search.latestOnly = true;

    auto registry = new Registry();

    auto pkgEntries = registry.sendRequest(search).payload;

    bool first = true;
    foreach (pkg; pkgEntries)
    {
        if (!first)
            logInfo("");
        first = false;

        auto desc = breakLines(pkg.description, 60);
        if (desc.length == 0)
            desc = ["(no description)"];

        logInfo("%-18s %s", color(Color.cyan | Color.bright, pkg.name), desc[0]);
        foreach (d; desc[1 .. $])
            logInfo("%18s %s", "", d);

        logInfo(
            "     %-12s     %s",
            color(Color.white, format!"%s versions"(pkg.numVersions)),
            color(Color.white, format!"%s recipe revisions"(pkg.numRecipes))
        );

        foreach (vers; pkg.versions)
        {
            string ver = vers.ver; // shown only for first recipe
            foreach (rec; vers.recipes)
            {
                const created = rec.created.toLocalTime();
                const date = Date(created.year, created.month, created.day);

                logInfo(
                    "     %-14s %10s    %s %-20s on %s",
                    color(Color.green, ver), rec.revision, rec.createdBy ? "by" : "  ",
                    info(rec.createdBy), date.toSimpleString()
                );

                // only show version for first recipe
                ver = null;
            }
        }
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
