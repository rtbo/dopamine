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
        setupRoute!GetPackageLatestRecipe(router, &getLatestRecipe);
        setupRoute!GetPackageRecipe(router, &getRecipe);
        router.get("/v1/packages", genericHandler(&search));
    }

    @OrderedCols
    static struct Row
    {
        string name;
        string description;

        PackageResource toResource(string[] versions) const @safe
        {
            return PackageResource(name, description, versions);
        }
    }

    PackageResource get(GetPackage req) @safe
    {
        return client.connect((scope DbConn db) @safe {
            const row = db.execRow!Row(
                `SELECT name, description FROM package WHERE name = $1`,
                req.name
            );
            auto vers = db.execScalars!string(
                `
                    SELECT version FROM recipe WHERE package_name = $1
                    GROUP BY version
                    ORDER BY semver_order_str(version)
                `,
                row.name,
            );
            return row.toResource(vers);
        });
    }

    @OrderedCols
    static struct PkgRecipeRow
    {
        int recipeId;
        string name;
        string ver;
        string revision;
        string archiveName;
        string description;

        PackageRecipeResource toResource() const @safe
        {
            return PackageRecipeResource(
                name, ver, revision, recipeId, archiveName, description,
            );
        }
    }

    PackageRecipeResource getLatestRecipe(GetPackageLatestRecipe req) @safe
    {
        return client.connect((scope DbConn db) {
            const row = db.execRow!PkgRecipeRow(
                `
                    SELECT r.id, r.package_name, r.version, r.revision, a.name, r.description
                    FROM recipe AS r JOIN archive AS a ON a.id = r.archive_id
                    WHERE
                        r.package_name = $1 AND
                        r.version = $2
                    ORDER BY r.created DESC
                    LIMIT 1
                `,
                req.name, req.ver,
            );
            return row.toResource();
        });
    }

    PackageRecipeResource getRecipe(GetPackageRecipe req) @safe
    {
        return client.connect((scope DbConn db) {
            const row = db.execRow!PkgRecipeRow(
                `
                    SELECT r.id, r.package_name, r.version, r.revision, a.name, r.description
                    FROM recipe AS r JOIN archive AS a ON a.id = r.archive_id
                    WHERE
                        r.package_name = $1 AND
                        r.version = $2 AND
                        r.revision = $3
                `,
                req.name, req.ver, req.revision,
            );
            return row.toResource();
        });
    }

    PackageResource createIfNotExist(scope DbConn db, string name, string description, out string new_) @safe
    {
        auto prows = db.execRows!Row(
            `SELECT name, description FROM package WHERE name = $1`, name
        );
        string[] vers;
        if (prows.length == 0)
        {
            new_ = "package";

            prows = db.execRows!Row(
                `
                    INSERT INTO package (name, description)
                    VALUES ($1, $2)
                    RETURNING name, description
                `,
                name, description
            );
        }
        else
        {
            assert(prows.length == 1);

            vers = db.execScalars!string(
                `
                    SELECT version FROM recipe WHERE package_name = $1
                    GROUP BY version
                    ORDER BY semver_order_str(version)
                `, name
            );
        }
        return prows[0].toResource(vers);
    }

    void search(scope HTTPServerRequest httpReq, scope HTTPServerResponse resp) @safe
    {
        auto req = adaptRequest!SearchPackages(httpReq);

        enforceStatus(!(req.nameOnly && req.extended), 400, "'nameOnly' and 'extended' cannot be combined");

        @OrderedCols
        static struct R
        {
            string name;
            string description;
            MayBe!string createdBy;
            SysTime created;
            string ver;
            string revision;
            int numVersions;
            int numRecipes;
        }

        PgParam[] params;
        int num = 1;

        // base selection
        string select;
        if (req.latestOnly)
        {
            select = "DISTINCT ON (pc.counter, r.package_name) package_name, r.description, u.name, " ~
                    "r.created, r.version, r.revision, pc.num_versions, pc.num_recipes";
        }
        else
        {
            select = "r.package_name, r.description, u.name, r.created, r.version, r.revision, " ~
                    "pc.num_versions, pc.num_recipes";
        }

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

            where = "WHERE " ~ fields.map!(f => format!"%s %s $%s"(f, operator, num)).join(
                " OR ");
            num += 1;
        }

        // build a overall limit clause
        string limit;
        if (req.recLimit)
        {
            params ~= pgParam(req.recLimit);
            limit = format!" LIMIT $%s"(num);
            num += 1;
        }

        string sql = format!`
            SELECT %s
            FROM recipe AS r
                LEFT OUTER JOIN "user" AS u ON r.created_by = u.id
                LEFT OUTER JOIN package_counter AS pc ON pc.name = r.package_name
            %s
            ORDER BY pc.counter DESC, r.package_name ASC, semver_order_str(r.version) DESC, r.created DESC
            %s
        `(select, where, limit);

        auto rows = client.connect((scope db) {
            db.sendDyn(sql, params);
            db.enableRowByRow();
            db.pollResult();
            return db.getRowByRow!R();
        });

        resp.headers["Content-Type"] = "application/json";

        // potentially a big amount is returned, so we stream
        // everything row by row, building JSON strings ourselves
        // let's just assume that the following code is correct
        auto output = resp.bodyWriter;

        void openPkgEntry(const ref R row)
        {
            output.write(format!`{"name":"%s","description":"%s","numVersions":%s,"numRecipes":%s,"versions":[`(
                    row.name, row.description, row.numVersions, row.numRecipes)
            );
        }

        void openVersionEntry(const ref R row)
        {
            output.write(format!`{"version":"%s","recipes":[`(row.ver));
        }

        void writeRecipe(const ref R row)
        {
            // dfmt off
            const str = row.createdBy.valid ?
                format!`{"revision":"%s","createdBy":"%s","created":"%s"}`(
                    row.revision, row.createdBy.value, row.created.toISOExtString()
                ) :
                format!`{"revision":"%s","created":"%s"}`(
                    row.revision, row.created.toISOExtString()
                );
            // dfmt on
            output.write(str);
        }

        void closeVersionEntry()
        {
            output.write(`]}`);
        }

        void closePkgEntry()
        {
            output.write(`]}`);
        }

        output.write("[");
        string prevName;
        string prevVer;
        bool verNeedsComma;
        bool recNeedsComma;
        foreach (const ref R row; rows)
        {
            if (prevVer && (row.ver != prevVer || row.name != prevName))
            {
                closeVersionEntry();
            }
            if (row.name != prevName)
            {
                if (prevName)
                {
                    closePkgEntry();
                    output.write(",");
                }
                openPkgEntry(row);
                verNeedsComma = false;
                recNeedsComma = false;
            }
            if (row.ver != prevVer || row.name != prevName)
            {
                if (recNeedsComma)
                    output.write(",");
                openVersionEntry(row);
                verNeedsComma = true;
                recNeedsComma = false;
            }
            if (recNeedsComma)
                output.write(",");
            writeRecipe(row);
            recNeedsComma = true;
            prevName = row.name;
            prevVer = row.ver;
        }
        if (prevVer || prevName)
        {
            closeVersionEntry();
            closePkgEntry();
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

version (unittest)
{
    PackagesApi buildTestPackagesApi(DbClient client)
    {
        import vibe.http.router;

        auto router = new URLRouter();
        auto api = new PackagesApi(client);
        api.setupRoutes(router);
        return api;
    }
}

@("/v1/packages (search)")
unittest
{
    import vibe.data.json;
    import vibe.inet.url;
    import vibe.stream.memory;
    import std.exception;

    auto client = new DbClient(dbConnString(), 1);
    scope (exit)
        client.finish();

    auto registry = populateTestRegistry(client);
    scope (success)
        cleanTestRegistry(client);

    auto api = buildTestPackagesApi(client);

    PackageSearchEntry[] performSearch(string query)
    {
        auto output = createMemoryOutputStream();
        auto req = createTestHTTPServerRequest(
            URL("https://api.dopamine-pm.org/v1/packages" ~ query));
        auto res = createTestHTTPServerResponse(output, null, TestHTTPResponseMode.bodyOnly);

        api.search(req, res);

        return deserializeJson!(PackageSearchEntry[])(cast(string)assumeUnique(output.data));
    }

    // empty query yields all packages, most popular first
    auto all = performSearch("");
    all.map!(p => p.name).should == ["libincredible", "libcurl", "pkga", "pkgb", "uselesslib", "http-over-ftp"];

    // retrieve networking packages
    auto network = performSearch("?q=network");
    network.length.should == 2;
    // libcurl comes before because as higher download count
    network[0].name.should == "libcurl";
    network[0].versions.map!(v => v.ver).should == ["7.84.0", "7.68.0"];
    network[0].versions[0].recipes.length.should == 2;
    network[0].numVersions.should == 2;
    network[0].numRecipes.should == 4;
    network[1].name.should == "http-over-ftp";
    network[1].versions.map!(v => v.ver).should == ["0.0.2", "0.0.2-beta.3", "0.0.2-beta.2", "0.0.2-beta.1", "0.0.1"];
    network[1].versions[0].recipes.length.should == 4;
    network[1].numVersions.should == 5;
    network[1].numRecipes.should == 9;

    // retrieve network with latest versions only
    auto networkLatest = performSearch("?q=network&latestOnly");
    networkLatest[0].name.should == "libcurl";
    networkLatest[0].versions.map!(v => v.ver).should == ["7.84.0"];
    networkLatest[0].versions[0].recipes.length.should == 1;
    networkLatest[0].numVersions.should == 2;
    networkLatest[0].numRecipes.should == 4;
    networkLatest[1].name.should == "http-over-ftp";
    networkLatest[1].versions.map!(v => v.ver).should == ["0.0.2"];
    networkLatest[1].versions[0].recipes.length.should == 1;
    networkLatest[1].numVersions.should == 5;
    networkLatest[1].numRecipes.should == 9;
}
