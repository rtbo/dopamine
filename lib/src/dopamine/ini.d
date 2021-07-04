// INI files parsing and utility module
module dopamine.ini;

import std.range : ElementType, isInputRange;
import std.traits : isSomeString;
import std.typecons : Tuple;

/// Main structure for INI that contains sections.
/// Sections that can be iterated through the `sections` member.
/// Sections can also be indexed by name using the `[]` operator.
struct Ini
{
    Section[] sections;

    /// Get a section by name, or an empty section if not found
    inout(Section) get(in string name) inout
    {
        foreach (s; sections)
        {
            if (name == s.name) return s;
        }
        return Section(name, []);
    }

    /// Indexes a section by name, or throw RangeError if not found
    inout(Section) opIndex(in string name) inout
    {
        import core.exception : RangeError;

        foreach (s; sections)
        {
            if (name == s.name) return s;
        }
        throw new RangeError();
    }

    bool opCast(T : bool)() const
    {
        return sections.length != 0;
    }
}

struct Section
{
    /// the name of the section
    string name;

    /// the properties of this section
    Prop[] props;

    /// Get a property value by its name, or a default value if not found
    inout(string) get(in string name, lazy string defValue = null) inout
    {
        foreach (p; props)
        {
            if (name == p.name) return p.value;
        }
        return defValue;
    }

    /// Indexes a property value by its name, or throw RangeError if not found
    inout(string) opIndex(in string name) inout
    {
        import core.exception : RangeError;

        foreach (p; props)
        {
            if (name == p.name) return p.value;
        }
        throw new RangeError();
    }

    bool opCast(T : bool)() const
    {
        return props.length != 0;
    }
}

struct Prop
{
    string name;
    string value;
}

Ini parseIni(R)(R lines) if (isInputRange!R && isSomeString!(ElementType!R))
{
    import std.exception : enforce;
    import std.string : strip, stripRight, stripLeft;

    while (!lines.empty)
    {
        const l = lines.front.strip();

        if (l.length && !l.isComment())
            break;
        lines.popFront();
    }

    if (lines.empty)
        return Ini.init;

    auto sn = sectionName(lines.front);
    enforce(sn, "Expected a section, found \"" ~ lines.front.strip() ~ "\"");
    lines.popFront();

    Section[] sections;

    while (!lines.empty)
    {
        auto propsSn = parseProps(lines);
        sections ~= Section(sn, propsSn[0]);
        sn = propsSn[1];
    }

    if (sn)
    {
        sections ~= Section(sn, []);
    }

    return Ini(sections);
}

private bool isComment(in string line)
{
    import std.string : startsWith;

    return line.startsWith(';') || line.startsWith('#');
}

private string sectionName(in string line)
{
    import std.string : strip, startsWith, endsWith;

    const l = line.strip();

    if (l.startsWith('[') && l.endsWith(']'))
    {
        return l[1 .. $ - 1].strip();
    }

    return null;
}

private Tuple!(Prop[], string) parseProps(R)(ref R lines)
{
    import std.algorithm : findSplit;
    import std.exception : enforce;
    import std.string : strip, stripRight, stripLeft;
    import std.typecons : tuple;

    Prop[] props;

    while (!lines.empty)
    {
        const l = lines.front.strip();
        lines.popFront();
        if (!l.length || l.isComment())
            continue;

        const sn = sectionName(l);
        if (sn)
            return tuple(props, sn);

        const nv = l.findSplit("=");
        enforce(nv[1] == "=", `Expected a INI property, but didn't found "="`);

        const name = nv[0].stripRight();
        enforce(name.length > 0, "INI property name cannot be empty");

        const value = nv[2].stripLeft();
        enforce(value.length > 0, "INI property value cannot be empty");

        props ~= Prop(name, value);
    }

    return tuple(props, string.init);
}

@("Parses empty INI")
unittest
{
    import std.string : lineSplitter;

    const iniStr = ``;
    const ini = parseIni(lineSplitter(iniStr));
    assert(ini.sections.length == 0);
}

version(unittest)
{
    const string simpleIni =
`[some section]
aprop = a value
another prop= another value

[a second section]
yet another prop =another value`;
}

@("Parses simple INI")
unittest
{
    import std.string : lineSplitter;

    const ini = parseIni(lineSplitter(simpleIni));
    assert(ini.sections.length == 2);
    assert(ini.sections[0].name == "some section");
    assert(ini.sections[0].props == [
        Prop("aprop", "a value"),
        Prop("another prop", "another value"),
    ]);
    assert(ini.sections[1].name == "a second section");
    assert(ini.sections[1].props == [
        Prop("yet another prop", "another value"),
    ]);
}

@("Resilient to comments")
unittest
{
    import std.string : lineSplitter;

    const iniStr =
`;[a comment]
[some section]
# explanation of this section
aprop = a value
another prop= another value
; yet another comment
[a second section]
yet another prop =another value
#blablabla
`;
    const ini = parseIni(lineSplitter(iniStr));
    assert(ini.sections.length == 2);
    assert(ini.sections[0].name == "some section");
    assert(ini.sections[0].props == [
        Prop("aprop", "a value"),
        Prop("another prop", "another value"),
    ]);
    assert(ini.sections[1].name == "a second section");
    assert(ini.sections[1].props == [
        Prop("yet another prop", "another value"),
    ]);
}

@("Resilient to whitespaces")
unittest
{
    import std.string : lineSplitter;

    const iniStr =
`
   [some section]
  aprop = a value
                   another prop= another value



[a second section]


  yet another prop =another value
`;
    const ini = parseIni(lineSplitter(iniStr));
    assert(ini.sections.length == 2);
    assert(ini.sections[0].name == "some section");
    assert(ini.sections[0].props == [
        Prop("aprop", "a value"),
        Prop("another prop", "another value"),
    ]);
    assert(ini.sections[1].name == "a second section");
    assert(ini.sections[1].props == [
        Prop("yet another prop", "another value"),
    ]);
}

@("Index section and props by name")
unittest
{
    import std.string : lineSplitter;

    const ini = parseIni(lineSplitter(simpleIni));

    const sect1 = ini["some section"];
    assert(sect1.name == "some section");
    assert(sect1.props == [
        Prop("aprop", "a value"),
        Prop("another prop", "another value"),
    ]);

    const sect2 = ini["a second section"];
    assert(sect2.name == "a second section");
    assert(sect2.props == [
        Prop("yet another prop", "another value"),
    ]);

    assert(ini["some section"]["aprop"] == "a value");
    assert(ini["a second section"]["yet another prop"] == "another value");

}

@("Behaves if incorrect section or prop")
unittest
{
    import core.exception : RangeError;
    import std.exception : assertThrown;
    import std.string : lineSplitter;

    const ini = parseIni(lineSplitter(simpleIni));

    assertThrown!RangeError(ini["null section"]);
    assertThrown!RangeError(ini["some section"]["null prop"]);

    const ns = ini.get("null section");
    assert(ns.name == "null section");
    assert(ns.props == []);
    assert(ini.get("some section")["aprop"] == "a value");
    assert(ini.get("some section").get("null prop") == null);
    assert(ini.get("some section").get("null prop", "default value") == "default value");
}

@("Tests boolean nullity")
unittest
{
    import std.string : lineSplitter;

    assert(!Ini());
    assert(!Ini.init);

    assert(!Section());
    assert(!Section.init);

    const ini = parseIni(lineSplitter(simpleIni));
    assert(ini);
    assert(!ini.get("null section"));
    assert(ini.get("some section"));
}
