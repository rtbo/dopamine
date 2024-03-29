module dopamine.registry.v1.packages;

import dopamine.registry.db;
import dopamine.registry.utils;

import dopamine.api.v1;

import pgd.maybe;
import pgd.conn;
import pgd.param;

import vibe.http.router;

import std.algorithm;
import std.datetime;
import std.format;
import std.string;

class PackagesApi
{
    DbClient client;

    this(DbClient client)
    {
        this.client = client;
    }

    void setupRoutes(URLRouter router)
    {
        setupRoute!GetPackage(router, &get);
        router.get("/v1/packages", genericHandler(&search));
    }

    PackageResource get(GetPackage req) @safe
    {
        @OrderedCols
        static struct PkgR
        {
            string name;
            string description;
        }

        @OrderedCols
        static struct RecR
        {
            int id;
            string ver;
            string rev;
            string archiveName;
        }

        return client.transac((scope DbConn db) {
            // getting first the recipes, then the package because
            // we can perform little work while the second request is flying.
            // TODO: add pipeline mode in PGD to send both requests at once
            const recRows = db.execRows!RecR(
                `
                    SELECT r.id, r.version, r.revision, a.name
                    FROM recipe r LEFT OUTER JOIN archive a ON r.archive_id = a.id
                    WHERE package_name = $1
                    ORDER BY semver_order_str(r.version) DESC, r.created DESC
                `, req.name,
            );
            db.send(
                `SELECT name, description FROM package WHERE name = $1`, req.name
            );

            PackageVersionResource[] versions;
            PackageRecipeResource[] recipes;
            string lastVer;
            foreach (rr; recRows)
            {
                if (lastVer && rr.ver != lastVer)
                {
                    versions ~= PackageVersionResource(lastVer, recipes);
                    recipes = null;
                }

                recipes ~= PackageRecipeResource(
                    rr.id, rr.rev, rr.archiveName,
                );
                lastVer = rr.ver;
            }

            if (recipes.length)
                versions ~= PackageVersionResource(lastVer, recipes);

            db.pollResult();
            const pkgRow = db.getRow!PkgR();
            return PackageResource(pkgRow.name, pkgRow.description, versions);
        });
    }

    void search(HTTPServerRequest httpReq, HTTPServerResponse resp) @safe
    {
        auto req = adaptRequest!SearchPackages(httpReq);

        enforceStatus(!(req.nameOnly && req.extended), 400, "'nameOnly' and 'extended' cannot be combined");

        @OrderedCols
        static struct R
        {
            string name;
            string description;
            string ver;
            string revision;
            int numVersions;
            int numRecipes;
        }

        PgParam[] params;
        int num = 1;

        // base selection
        string select = "DISTINCT ON (pc.counter, r.package_name) package_name, r.description, " ~
            "r.version, r.revision, pc.num_versions, pc.num_recipes";

        // build the where clause
        string where;
        if (req.pattern)
        {
            string operator;
            if (req.regex)
            {
                operator = req.caseSensitive ? "~" : "~*";
                params ~= pgParam(req.pattern);
            }
            else
            {
                operator = req.caseSensitive ? "LIKE" : "ILIKE";
                params ~= pgParam("%" ~ req.pattern.replace("%", "\\%").replace("_", "\\_") ~ "%");
            }

            string[] fields = ["r.package_name"];
            if (!req.nameOnly)
                fields ~= "r.description";
            if (req.extended)
                fields ~= ["r.recipe", "r.readme"];

            where = "WHERE " ~
                fields
                .map!(f => format!"%s %s $%s"(f, operator, num))
                .join(" OR ");
            num += 1;
        }

        // build limit clause
        string limit;
        if (req.limit)
        {
            params ~= pgParam(req.limit);
            limit = format!"LIMIT $%s"(num);
            num += 1;
        }

        // build offset clause
        string offset;
        if (req.offset)
        {
            params ~= pgParam(req.offset);
            offset = format!"OFFSET $%s"(num);
            num += 1;
        }

        string sql = format!`
            SELECT %s
            FROM recipe AS r
                LEFT OUTER JOIN "user" AS u ON r.created_by = u.id
                LEFT OUTER JOIN package_counter AS pc ON pc.name = r.package_name
            %s
            ORDER BY pc.counter DESC, r.package_name ASC, semver_order_str(r.version) DESC, r.created DESC
            %s %s
        `(select, where, limit, offset);

        auto rows = client.connect((scope db) {
            db.sendDyn(sql, params);
            db.enableRowByRow();
            db.pollResult();
            return db.getRowByRow!R();
        });

        resp.headers["Content-Type"] = "application/json";

        // potentially a big amount is returned, so we stream
        // everything row by row, building JSON strings ourselves
        auto output = resp.bodyWriter;

        void writePkg(const ref R row)
        {
            output.write(
                format!(`{"name":"%s","description":"%s","lastVersion":"%s","lastRecipeRev":"%s",` ~
                    `"numVersions":%s,"numRecipes":%s}`)(
                    row.name, row.description, row.ver, row.revision, row.numVersions, row
                    .numRecipes
            )
            );
        }

        output.write("[");
        bool needsComma;
        foreach (const ref R row; rows)
        {
            if (needsComma)
                output.write(",");
            needsComma = true;
            writePkg(row);
        }
        output.write("]");
        output.flush();
    }
}

version (unittest)
{
    import dopamine.registry.test;
    import unit_threaded.assertions;
}

@("semver_order_str")
unittest
{
    auto db = new PgConn(dbConnString());
    scope (exit)
        db.finish();

    db.execScalar!string(`SELECT semver_order_str('0.1.0')`)
        .shouldEqual("000000000100000zzzzzzzzzzzz");

    db.execScalar!string(`SELECT semver_order_str('12.1.5')`)
        .shouldEqual("000120000100005zzzzzzzzzzzz");

    db.execScalar!string(`SELECT semver_order_str('12.1.5-alpha.2')`)
        .shouldEqual("000120000100005alpha.2zzzzz");

    db.execScalar!string(`SELECT semver_order_str('12.1.5-alpha.2+buildmeta')`)
        .shouldEqual("000120000100005alpha.2zzzzz");
}

@("ORDER BY semver_order_str")
unittest
{
    import std.random;
    import std.range;

    auto db = new PgConn(dbConnString());
    scope (exit)
        db.finish();

    db.exec(`
        CREATE TABLE semver_test (
            version text
        )
    `);
    scope (exit)
        db.exec("DROP TABLE semver_test");

    string[] versions = [
        "0.1.0",
        "1.0.0",
        "12.0.0",
        "12.4.0",
        "12.4.2",
        "12.4.3-alpha.0+buildmeta",
        "12.4.3-alpha.1",
        "12.4.3-alpha.2",
        "12.4.3-beta.2",
        "12.4.3-rc.0",
        "12.4.3+buildmeta",
    ];

    string[] shuffled = versions.dup.randomShuffle();

    foreach (ver; shuffled)
    {
        db.exec(`INSERT INTO semver_test(version) VALUES ($1)`, ver);
    }

    const ordered = db.execScalars!string(`
        SELECT version FROM semver_test
        ORDER BY semver_order_str(version) ASC
    `);

    const reversed = db.execScalars!string(`
        SELECT version FROM semver_test
        ORDER BY semver_order_str(version) DESC
    `);

    ordered.shouldEqual(versions);
    reversed.shouldEqual(retro(versions));
}

@("GET /v1/packages/:name")
unittest
{
    auto client = new DbClient(dbConnString(), 1);
    scope (exit)
        client.finish();

    auto registry = TestRegistry(client);

    auto api = new PackagesApi(client);

    auto res = api.get(GetPackage("libcurl"));
    const expected1st = registry.recipes["libcurl/7.84.0/654321"];
    res.name.should == "libcurl";
    res.description.should == "The ubiquitous networking library";
    res.versions.map!(v => v.ver).should == ["7.84.0", "7.68.0"];
    res.versions[0].recipes.map!(r => r.revision).should == ["654321", "123456"];
    res.versions[0].recipes[0].recipeId.should == expected1st.id;
    res.versions[0].recipes[0].archiveName.should == "libcurl-7.84.0-654321.tar.xz";
}

@("GET /v1/packages (search)")
unittest
{
    import vibe.data.json;
    import vibe.inet.url;
    import vibe.stream.memory;
    import std.exception;

    auto client = new DbClient(dbConnString(), 1);
    scope (exit)
        client.finish();

    auto registry = TestRegistry(client);

    auto api = new PackagesApi(client);

    PackageSearchEntry[] performSearch(string query)
    {
        auto output = createMemoryOutputStream();
        auto req = createTestHTTPServerRequest(
            URL("https://api.dopamine-pm.org/v1/packages" ~ query));
        auto res = createTestHTTPServerResponse(output, null, TestHTTPResponseMode.bodyOnly);

        api.search(req, res);

        return deserializeJson!(PackageSearchEntry[])(cast(string) assumeUnique(output.data));
    }

    // empty query yields all packages, most popular first
    auto all = performSearch("");
    all.map!(p => p.name).should == [
        "libincredible", "libcurl", "pkga", "pkgb", "uselesslib", "http-over-ftp"
    ];

    // retrieve networking packages
    auto network = performSearch("?q=network");
    network.length.should == 2;
    // libcurl comes before because has higher download count
    network[0].name.should == "libcurl";
    network[0].lastVersion.should == "7.84.0";
    network[0].lastRecipeRev.should == "654321";
    network[0].numVersions.should == 2;
    network[0].numRecipes.should == 4;
    network[1].name.should == "http-over-ftp";
    network[1].lastVersion.should == "0.0.2";
    network[1].lastRecipeRev.should == "fedcba";
    network[1].numVersions.should == 5;
    network[1].numRecipes.should == 9;
}
