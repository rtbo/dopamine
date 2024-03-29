module dopamine.admin.app;

import dopamine.admin.config;
import dopamine.cache;
import pgd.conn;
import pgd.connstring;
import squiz_box;

import std.algorithm;
import std.array;
import std.datetime;
import std.digest.sha;
import std.exception;
import std.getopt;
import std.file;
import std.format;
import std.range;
import std.stdio;
import std.string;

immutable(string[string]) migrations;

shared static this()
{
    migrations["0.auth"] = import("0.auth.sql");
    migrations["1.archive"] = import("1.archive.sql");
    migrations["2.semver"] = import("2.semver.sql");
    migrations["v1"] = import("v1.sql");
}

// migrations run with create-db
const initMigs = ["0.auth", "1.archive", "2.semver", "v1"];

struct Options
{
    bool help;
    Option[] options;

    bool trace;
    bool createUser;
    bool createDb;
    string[] migrationsToRun;
    uint genCryptoPassword;

    string[] testCreateUser;
    string testPopulateRegistry;

    static Options parse(string[] args)
    {
        Options opts;

        // dfmt off
        auto res = getopt(args,
            "trace",                &   opts.trace,

            // admin tasks
            "create-user",              &opts.createUser,
            "create-db",                &opts.createDb,
            "run-migration|r",          &opts.migrationsToRun,
            "gen-crypto-password",      &opts.genCryptoPassword,

            // testing tasks
            "test-create-user",         &opts.testCreateUser,
            "test-populate-registry",   &opts.testPopulateRegistry,
        );
        // dfmt on

        opts.options = res.options;

        if (res.helpWanted)
            opts.help = true;

        return opts;
    }

    int printHelp()
    {
        defaultGetoptPrinter("Admin tool for dopamine registry", options);
        return 0;
    }

    bool noop() const
    {
        return !createUser &&
            !createDb &&
            !migrationsToRun.length &&
            !testPopulateRegistry &&
            !testCreateUser &&
            !genCryptoPassword;
    }

    int checkErrors() const
    {
        int errs;
        foreach (mig; migrationsToRun)
        {
            auto sql = mig in migrations;
            if (!sql)
            {
                stderr.writefln("%s: No such migration", mig);
                errs += 1;
            }
        }
        if (testPopulateRegistry && !isDir(testPopulateRegistry))
        {
            stderr.writefln("%s: No such directory", testPopulateRegistry);
            errs += 1;
        }
        return errs;
    }
}

version (DopAdminMain) int main(string[] args)
{
    auto opts = Options.parse(args);

    if (opts.help)
        return opts.printHelp();

    if (int errs = opts.checkErrors())
        return errs;

    if (opts.noop())
    {
        writeln("Nothing to do!");
        return 0;
    }

    if (opts.genCryptoPassword)
    {
        genCryptoPassword(opts.genCryptoPassword);
    }

    auto conf = Config.get;

    if (opts.createUser || opts.createDb)
    {
        auto db = new PgConn(conf.adminConnString);
        scope (exit)
            db.finish();

        if (opts.trace)
            db.trace(stdout);

        const connInfo = breakdownConnString(conf.dbConnString);

        if (opts.createUser)
            createDbUser(db, connInfo);

        if (opts.createDb)
        {
            createDatabase(db, connInfo);
            foreach (mig; initMigs)
            {
                if (!opts.migrationsToRun.canFind(mig))
                    opts.migrationsToRun ~= mig;
            }
        }

        const user = connInfo.get("user", null);
        const dbname = connInfo.get("dbname", null);
        if (user && dbname)
            db.exec(format!`GRANT ALL PRIVILEGES ON DATABASE %s TO %s`(
                    db.escapeIdentifier(dbname),
                    db.escapeIdentifier(user)
            ));
    }

    if (!opts.migrationsToRun && !opts.testCreateUser && !opts.testPopulateRegistry)
        return 0;

    auto db = new PgConn(conf.dbConnString);

    scope (exit)
        db.finish();

    if (opts.trace)
        db.trace(stdout);

    foreach (mig; opts.migrationsToRun)
    {
        writefln("Running migration \"%s\"", mig);
        db.exec(migrations[mig]);
    }

    foreach (usr; opts.testCreateUser)
        createTestUserIfNotExist(db, usr, Yes.withTestToken);

    if (opts.testPopulateRegistry)
        populateTestRegistry(db, opts.testPopulateRegistry);

    return 0;
}

void genCryptoPassword(uint len)
{
    import crypto;
    import std.base64;

    auto bytes = new ubyte[Base64.decodeLength(len) + 2];
    cryptoRandomBytes(bytes);
    auto b64 = Base64.encode(bytes);
    assert(b64.length >= len, "Base64 bug!");
    writeln(b64[0 .. len]);
}

void createDbUser(PgConn db, const(string[string]) connInfo)
{
    const user = *enforce("user" in connInfo, "Could not find USER name in " ~ Config
            .get.dbConnString);
    const pswd = connInfo.get("password", null);
    writefln(`creating user "%s%s"`, user, pswd ? " with password" : "");

    const ident = db.escapeIdentifier(user);

    db.exec("DROP ROLE IF EXISTS " ~ ident);
    if (pswd)
        db.exec(format!"CREATE ROLE %s WITH LOGIN PASSWORD '%s'"(ident, pswd));
    else
        db.exec(format!"CREATE ROLE %s WITH LOGIN PASSWORD NULL"(ident));
}

void createDatabase(PgConn db, const(string[string]) connInfo)
{
    const name = *enforce("dbname" in connInfo, "Could not find DB name in " ~ Config
            .get.dbConnString);

    writefln(`(Re)creating database "%s"`, name);

    const ident = db.escapeIdentifier(name);

    db.exec("DROP DATABASE IF EXISTS " ~ ident);
    db.exec("CREATE DATABASE " ~ ident);
}

int createTestUserIfNotExist(PgConn db, string pseudo, Flag!"withTestToken" tok = No.withTestToken)
{
    auto ids = db.execScalars!int(
        `SELECT "id" FROM "user" WHERE "pseudo" = $1`,
        pseudo
    );
    if (ids.length)
        return ids[0];

    const email = format!"%s@dop.test"(pseudo);

    const userId = db.execScalar!int(
        `
            INSERT INTO "user"(pseudo, email) VALUES($1, $2)
            RETURNING "id"
        `,
        pseudo, email
    );
    writefln("Created user @%s <%s> (%s)", pseudo, email, userId);
    if (tok)
    {
        const token = cast(const(ubyte)[]) email;
        db.exec(`
            INSERT INTO "refresh_token" ("token", "user_id", "cli")
            VALUES ($1, $2, TRUE)
        `, token, userId);
    }
    return userId;
}

void populateTestRegistry(PgConn db, string regDir)
{
    const adminId = createTestUserIfNotExist(db, "admin-tool");

    foreach (packDir; dirEntries(regDir, SpanMode.shallow).filter!(e => e.isDir))
    {
        auto pkg = CachePackageDir(packDir.name);

        bool foundRecipe;
        verLoop: foreach (vdir; pkg.versionDirs)
        {
            foreach (rdir; vdir.dopRevisionDirs)
            {
                if (exists(rdir.recipeFile))
                {
                    foundRecipe = true;
                    break verLoop;
                }
            }
        }

        if (!foundRecipe)
        {
            stderr.writefln("ignoring %s which doesn't seem to have any recipe", pkg.name);
            continue;
        }

        db.exec(
            `
                INSERT INTO "package" ("name", "description") VALUES ($1, $2)
            `,
            pkg.name, "Description of " ~ pkg.name
        );
        writefln("Created package %s", pkg.name);

        foreach (vdir; pkg.versionDirs)
            foreach (rdir; vdir.dopRevisionDirs)
            {
                if (!exists(rdir.recipeFile))
                    continue;

                const archiveName = format!"%s-%s-%s.tar.xz"(pkg.name, vdir.ver, rdir.revision);
                int archiveId = storeArchive(db, rdir.dir, archiveName, adminId);

                const recId = db.execScalar!int(
                    `
                        INSERT INTO "recipe" (
                            "package_name",
                            "created_by",
                            "created",
                            "version",
                            "revision",
                            "archive_id",
                            "description",
                            "upstream_url",
                            "license"
                        ) VALUES(
                            $1, $2, CURRENT_TIMESTAMP, $3, $4, $5, $6, $7, $8
                        )
                        RETURNING "id"
                    `,
                    pkg.name, adminId, vdir.ver, rdir.revision, archiveId,
                    "Description of " ~ pkg.name, "http://dop.test/" ~ pkg.name, "TEST"
                );

                writefln("Created recipe %s/%s/%s (%s)", pkg.name, vdir.ver, rdir.revision, recId);
            }

    }
}

version (DopRegistryFsStorage) int storeArchive(PgConn db, string dir, string archiveName, int userId)
{
    import std.path;

    const storageDir = Config.get.registryStorageDir;

    auto fileEntries = dirEntries(dir, SpanMode.breadth)
        .filter!(e => !e.isDir)
        .map!(e => fileEntry(e.name, dir))
        .array;

    fileEntries
        .boxTarXz()
        .writeBinaryFile(buildPath(storageDir, archiveName));

    return db.transac(() @trusted {
        const id = db.execScalar!int(
            `
                INSERT INTO archive (
                    name,
                    created,
                    created_by,
                    counter,
                    upload_done
                ) VALUES (
                    $1, CURRENT_TIMESTAMP, $2, 0, TRUE
                )
                RETURNING id
            `, archiveName, userId
        );
        foreach (entry; fileEntries)
            db.exec(
                `INSERT INTO archive_file (archive_id, path, size) VALUES ($1, $2, $3)`,
                id, entry.path, entry.size,
            );
        return id;
    });
}

version (DopRegistryDbStorage) int storeArchive(PgConn db, string dir, string archiveName, int userId)
{
    auto fileEntries = dirEntries(dir, SpanMode.breadth)
        .filter!(e => !e.isDir)
        .map!(e => fileEntry(e.name, dir))
        .array;

    const blob = fileEntries
        .boxTarXz()
        .join();

    const sha1 = sha1Of(blob);

    return db.transac(() @trusted {
        const id = db.execScalar!int(
            `
            INSERT INTO archive (
                name,
                created,
                created_by,
                counter,
                upload_done,
                data
            ) VALUES (
                $1, CURRENT_TIMESTAMP, $2, 0, TRUE, $3
            )
            RETURNING id
        `, archiveName, userId, blob
        );

        auto dbSha1 = db.execScalar!(ubyte[20])(
            `
                SELECT digest(data, 'sha1') FROM archive
                WHERE id = $1
            `, id
        );
        enforce(dbSha1 == sha1);

        foreach (entry; fileEntries)
            db.exec(
                `INSERT INTO archive_file (archive_id, path, size) VALUES ($1, $2, $3)`,
                id, entry.path, entry.size,
            );

        return id;
    });
}
