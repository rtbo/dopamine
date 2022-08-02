module app;

import xlsxreader;

import std.exception;
import std.format;
import std.range;
import std.stdio;

void main(string[] args)
{
	// testing main dependency
	enforce(args.length > 2, format!"usage: %s [excel file] [sheet name]"(args[0]));

	auto sheet = readSheet(args[1], args[2]);

	int i = 1;
	foreach (val; sheet.iterateColumnString(0, 0, 10))
	{
		writefln!"A%s = %s"(i++, val);
	}

	// testing sub-dependency
	version (Have_dxml)
	{
		import dxml.parser;
	}
	else
	{
		static assert(false, "missing sub-dependency version!");
	}

	auto xml = "<!-- comment -->\n" ~
		"<root>\n" ~
		"    <foo>some text<whatever/></foo>\n" ~
		"    <bar/>\n" ~
		"    <baz></baz>\n" ~
		"</root>";

	auto range = parseXML(xml);
	assert(range.front.type == EntityType.comment);
	assert(range.front.text == " comment ");
	range.popFront();

	assert(range.front.type == EntityType.elementStart);
	assert(range.front.name == "root");
	range.popFront();

	assert(range.front.type == EntityType.elementStart);
	assert(range.front.name == "foo");
	range.popFront();

	assert(range.front.type == EntityType.text);
	assert(range.front.text == "some text");
	range.popFront();

	assert(range.front.type == EntityType.elementEmpty);
	assert(range.front.name == "whatever");
	range.popFront();

	assert(range.front.type == EntityType.elementEnd);
	assert(range.front.name == "foo");
	range.popFront();

	assert(range.front.type == EntityType.elementEmpty);
	assert(range.front.name == "bar");
	range.popFront();

	assert(range.front.type == EntityType.elementStart);
	assert(range.front.name == "baz");
	range.popFront();

	assert(range.front.type == EntityType.elementEnd);
	assert(range.front.name == "baz");
	range.popFront();

	assert(range.front.type == EntityType.elementEnd);
	assert(range.front.name == "root");
	range.popFront();

	assert(range.empty);
}
