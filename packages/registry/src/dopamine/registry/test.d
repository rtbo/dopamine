module dopamine.registry.test;

version (unittest)
{
    import dopamine.registry.db;

    import pgd.conn;
    import pgd.connstring;

    import core.sync.mutex;
    import std.datetime;
    import std.format;
    import std.process;
    import std.string;

    string adminConnString() @safe
    {
        return environment.get("PGD_TEST_ADMIN_DB", "postgres:///postgres");
    }

    string dbConnString() @safe
    {
        return environment.get("PGD_TEST_DB", "postgres:///dop-registry-test");
    }

    shared Mutex registryMutex;

    shared static this()
    {
        import std.format : format;

        {
            const info = breakdownConnString(dbConnString());
            const dbName = info["dbname"];
            const user = info.get("user", null);

            auto db = new PgConn(adminConnString());
            scope (exit)
                db.finish();

            const dbIdent = db.escapeIdentifier(dbName);

            db.exec("DROP DATABASE IF EXISTS " ~ dbIdent);
            db.exec("CREATE DATABASE " ~ dbIdent);

            if (user && dbName)
                db.exec(format!`GRANT ALL PRIVILEGES ON DATABASE %s TO %s`(
                        db.escapeIdentifier(dbName),
                        db.escapeIdentifier(user)
                ));
        }

        {
            auto db = new PgConn(dbConnString());
            scope (exit)
                db.finish();

            db.exec(import("0.auth.sql"));
            db.exec(import("1.archive.sql"));
            db.exec(import("2.semver.sql"));
            db.exec(import("v1.sql"));
        }

        registryMutex = new shared Mutex();
    }

    struct TestUser
    {
        int id;
        string email;
        string pseudo;
        string name;
    }

    struct TestPkg
    {
        string name;
        string description;
    }

    @OrderedCols
    struct TestArchive
    {
        int id;
        string name;
        SysTime created;
        int createdBy;
        ubyte[] data;
    }

    @OrderedCols
    struct TestRecipe
    {
        int id;
        string pkgName;
        int createdBy;
        SysTime created;
        string ver;
        string revision;
        int archiveId;
        string description;
        string upstreamUrl;
        string license;
    }

    struct RevInsert
    {
        string rev;
        string createdBy;
        Date created;
        uint counter;
    }

    struct VerInsert
    {
        string ver;
        RevInsert[] revs;
    }

    struct PkgInsert
    {
        string name;
        string description;
        string license;
        VerInsert[] versions;
    }

    const registryInserts = [
        PkgInsert(
            "pkga", "The Package A", "MIT", [
                VerInsert(
                    "0.1.0", [
                        RevInsert("123456", "one", Date(2020, 2, 12), 1250),
                    ]
                ),
                VerInsert(
                    "0.2.0", [
                        RevInsert("123456", "one", Date(2020, 4, 12), 123),
                        RevInsert("654321", "two", Date(2021, 3, 1), 1520),
                    ]
                ),
            ]
        ),
        PkgInsert(
            "libincredible", "An incredible library", "Boost", [
                VerInsert(
                    "1.0.0", [
                        RevInsert("123456", "one", Date(2021, 2, 12), 50_210),
                        RevInsert("654321", "one", Date(2022, 5, 18), 1203),
                    ]
                ),
                VerInsert(
                    "1.2.0-beta.0", [
                        RevInsert("123456", "one", Date(2022, 3, 12), 123),
                    ]
                ),
                VerInsert(
                    "1.2.0-beta.1", [
                        RevInsert("123456", "one", Date(2022, 3, 18), 1233),
                    ]
                ),
                VerInsert(
                    "1.2.0", [
                        RevInsert("123456", "one", Date(2022, 4, 12), 798),
                        RevInsert("654321", "one", Date(2022, 5, 1), 12_450),
                    ]
                ),
            ]
        ),
        PkgInsert(
            "uselesslib", "A useless library", "Boost", [
                VerInsert(
                    "0.0.1", [
                        RevInsert("123456", "three", Date(2021, 2, 12), 12),
                        RevInsert("654321", "three", Date(2022, 5, 18), 21),
                    ]
                ),
                VerInsert(
                    "0.0.2-beta.1", [
                        RevInsert("123456", "three", Date(2022, 3, 12), 13),
                    ]
                ),
                VerInsert(
                    "0.0.2-beta.2", [
                        RevInsert("123456", "three", Date(2022, 3, 18), 2),
                    ]
                ),
                VerInsert(
                    "0.0.2-beta.3", [
                        RevInsert("123456", "three", Date(2022, 3, 18), 3),
                    ]
                ),
                VerInsert(
                    "0.0.2", [
                        RevInsert("abcdef", "three", Date(2022, 3, 18), 2),
                        RevInsert("123456", "three", Date(2022, 3, 19), 3),
                        RevInsert("654321", "three", Date(2022, 3, 20), 1),
                        RevInsert("fedcba", "three", Date(2022, 3, 21), 21),
                    ]
                ),
            ]
        ),
        PkgInsert(
            "pkgb", "The Package B", "MIT", [
                VerInsert(
                    "0.1.0", [
                        RevInsert("123456", "one", Date(2020, 2, 12), 450),
                    ]
                ),
                VerInsert(
                    "0.2.0", [
                        RevInsert("123456", "one", Date(2020, 4, 12), 38),
                        RevInsert("654321", "two", Date(2021, 3, 1), 512),
                    ]
                ),
            ]
        ),
        PkgInsert(
            "http-over-ftp", "The nonsense networking library", "Boost", [
                VerInsert(
                    "0.0.1", [
                        RevInsert("123456", "three", Date(2021, 2, 12), 0),
                        RevInsert("654321", "three", Date(2022, 5, 18), 1),
                    ]
                ),
                VerInsert(
                    "0.0.2-beta.1", [
                        RevInsert("123456", "three", Date(2022, 3, 12), 2),
                    ]
                ),
                VerInsert(
                    "0.0.2-beta.2", [
                        RevInsert("123456", "three", Date(2022, 3, 18), 1),
                    ]
                ),
                VerInsert(
                    "0.0.2-beta.3", [
                        RevInsert("123456", "three", Date(2022, 3, 18), 1),
                    ]
                ),
                VerInsert(
                    "0.0.2", [
                        RevInsert("abcdef", "three", Date(2022, 3, 18), 1),
                        RevInsert("123456", "three", Date(2022, 3, 19), 0),
                        RevInsert("654321", "three", Date(2022, 3, 20), 0),
                        RevInsert("fedcba", "three", Date(2022, 3, 21), 5),
                    ]
                ),
            ]
        ),
        PkgInsert(
            "libcurl", "The ubiquitous networking library", "Boost", [
                VerInsert(
                    "7.68.0", [
                        RevInsert("123456", "one", Date(2021, 2, 12), 798),
                        RevInsert("654321", "one", Date(2021, 5, 18), 1212),
                    ]
                ),
                VerInsert(
                    "7.84.0", [
                        RevInsert("123456", "one", Date(2022, 3, 12), 109),
                        RevInsert("654321", "two", Date(2022, 5, 18), 12_493),
                    ]
                ),
            ]
        ),
    ];

    struct TestRegistry
    {
        DbClient client;
        TestUser[string] users;
        TestPkg[string] pkgs;
        TestArchive[string] archives;
        TestRecipe[string] recipes;

        this(DbClient client)
        {
            this.client = client;
            registryMutex.lock();

            client.transac((scope db) {
                foreach (pkg; registryInserts)
                {
                    this.pkgs[pkg.name] = db.execRow!TestPkg(
                        `
                            INSERT INTO package (name, description) VALUES ($1, $2)
                            RETURNING name, description
                        `,
                        pkg.name, pkg.description
                    );

                    foreach (ver; pkg.versions)
                    {
                        foreach (rev; ver.revs)
                        {
                            if (!(rev.createdBy in this.users))
                            {
                                const email = format!`user.%s@dop.test`(rev.createdBy);
                                const name = format!`User %s`(rev.createdBy.capitalize());
                                this.users[rev.createdBy] = db.execRow!TestUser(
                                    `
                                    INSERT INTO "user"(email, pseudo, name) VALUES($1, $2, $3)
                                    RETURNING id, email, pseudo, name
                                `, email, rev.createdBy, name
                                );
                            }

                            const key = format!"%s/%s/%s"(pkg.name, ver.ver, rev.rev);
                            const createdBy = this.users[rev.createdBy].id;
                            const created = SysTime(rev.created, UTC());
                            const upstreamUrl = format!"https://%s.test"(pkg.name);
                            const archiveName = format!"%s-%s-%s.tar.xz"(pkg.name, ver.ver, rev.rev);
                            const archiveData = cast(immutable(ubyte)[]) archiveName;

                            this.archives[archiveName] = db.execRow!TestArchive(
                                `
                                INSERT INTO archive (name, created, created_by, counter, upload_done, data)
                                VALUES($1, $2, $3, $4, TRUE, $5)
                                RETURNING id, name, created, created_by, data
                            `, archiveName, created, createdBy, rev.counter, archiveData
                            );

                            const archiveId = this.archives[archiveName].id;

                            this.recipes[key] = db.execRow!TestRecipe(
                                `
                                INSERT INTO recipe (
                                    package_name, created_by, created, version, revision, archive_id,
                                    description, upstream_url, license
                                ) VALUES (
                                    $1, $2, $3, $4, $5, $6, $7, $8, $9
                                )
                                RETURNING id,
                                    package_name, created_by, created, version, revision, archive_id,
                                    description, upstream_url, license
                            `, pkg.name, createdBy, created, ver.ver, rev.rev, archiveId, pkg.description,
                                upstreamUrl, pkg.license
                            );
                        }
                    }
                }
            });
        }

        ~this()
        {
            client.transac((scope db) {
                db.exec(`DELETE FROM "recipe"`);
                db.exec(`DELETE FROM "package"`);
                db.exec(`DELETE FROM "archive"`);
                db.exec(`DELETE FROM "user"`);
            });

            registryMutex.unlock();
        }
    }
}
