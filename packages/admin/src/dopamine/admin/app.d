module dopamine.admin.app;

import dopamine.admin.config;
import dopamine.cache_dirs;
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
import std.range;
import std.stdio;
import std.string;

immutable(string[string]) migrations;

shared static this()
{
    migrations["v1"] = import("v1.sql");
}

struct Options
{
    bool help;
    Option[] options;

    bool createDb;
    string[] migrationsToRun;
    bool createTestUsers;
    string registryDir;
    uint genCryptoPassword;

    static Options parse(string[] args)
    {
        Options opts;

        // dfmt off
        auto res = getopt(args,
            "create-db",            &opts.createDb,
            "run-migration",        &opts.migrationsToRun,
            "create-test-users",    &opts.createTestUsers,
            "populate-from",        &opts.registryDir,
            "gen-crypto-password",  &opts.genCryptoPassword,
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
        return !createDb && !migrationsToRun.length && !createTestUsers && !registryDir && !genCryptoPassword;
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
        if (registryDir && !isDir(registryDir))
        {
            stderr.writefln("%s: No such directory", registryDir);
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

    if (opts.noop())
    {
        writeln("Nothing to do!");
        return 0;
    }

    if (opts.genCryptoPassword)
    {
        genCryptoPassword(opts.genCryptoPassword);
    }

    if (int errs = opts.checkErrors())
        return errs;

    auto conf = Config.get;

    if (opts.createDb)
    {
        auto db = new PgConn(conf.adminConnString);
        scope (exit)
            db.finish();

        createDatabase(db, conf.dbConnString);
    }

    if (!opts.migrationsToRun && !opts.createTestUsers && !opts.registryDir)
        return 0;

    auto db = new PgConn(conf.dbConnString);

    scope (exit)
        db.finish();

    foreach (mig; opts.migrationsToRun)
    {
        writefln("Running migration \"%s\"", mig);
        db.exec(migrations[mig]);
    }

    if (opts.createTestUsers)
    {
        createUserIfNotExist(db, "user1@dop.test", Yes.withTestToken);
        createUserIfNotExist(db, "user2@dop.test", Yes.withTestToken);
    }

    if (opts.registryDir)
        populateRegistry(db, opts.registryDir);

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

void createDatabase(PgConn db, string connString)
{
    import std.format;

    const info = breakdownConnString(connString);

    const dbName = *enforce("dbname" in info, "Could not find DB name in " ~ connString);

    writefln(`(Re)creating database "%s"`, dbName);

    const dbIdent = db.escapeIdentifier(dbName);

    db.exec("DROP DATABASE IF EXISTS " ~ dbIdent);
    db.exec("CREATE DATABASE " ~ dbIdent);
}

struct User
{
    string id;

    string email;

    @ColName("avatar_url")
    string avatarUrl;
}

int createUserIfNotExist(PgConn db, string email, Flag!"withTestToken" tok=No.withTestToken)
{
    auto ids = db.execScalars!int(
        `SELECT "id" FROM "user" WHERE "email" = $1`,
        email
    );
    if (ids.length)
        return ids[0];

    const userId = db.execScalar!int(
        `
            INSERT INTO "user"("email") VALUES($1)
            RETURNING "id"
        `,
        email
    );
    writefln("Created user %s (%s)", email, userId);
    if (tok)
    {
        const token = cast(const(ubyte)[])email;
        db.exec(`
            INSERT INTO "refresh_token" ("token", "user_id", "cli")
            VALUES ($1, $2, TRUE)
        `, token, userId);
    }
    return userId;
}

void populateRegistry(PgConn db, string regDir)
{
    const adminId = createUserIfNotExist(db, "admin-tool@dopamine.org");

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
                INSERT INTO "package" ("name", "maintainer_id", "created")
                VALUES ($1, $2, CURRENT_TIMESTAMP)
            `,
            pkg.name, adminId
        );
        writefln("Created package %s", pkg.name);

        foreach (vdir; pkg.versionDirs)
            foreach (rdir; vdir.dopRevisionDirs)
            {
                if (!exists(rdir.recipeFile))
                    continue;

                const recipe = cast(string) read(rdir.recipeFile);

                auto fileEntries = dirEntries(rdir.dir, SpanMode.breadth)
                    .filter!(e => !e.isDir)
                    .map!(e => fileEntry(e.name, rdir.dir))
                    .array;

                auto recipeFileBlob = fileEntries
                    .boxTarXz()
                    .join();

                const sha1 = sha1Of(recipeFileBlob);

                const recId = db.transac(() @trusted {
                    const recId = db.execScalar!int(
                        `
                            INSERT INTO "recipe" (
                                "package_name",
                                "maintainer_id",
                                "version",
                                "revision",
                                "recipe",
                                "archive_data",
                                "created"
                            ) VALUES(
                                $1, $2, $3, $4, $5, $6, CURRENT_TIMESTAMP
                            )
                            RETURNING "id"
                        `,
                        pkg.name, adminId, vdir.ver, rdir.revision, recipe, recipeFileBlob
                    );
                    auto dbSha1 = db.execScalar!(ubyte[20])(
                        `
                            SELECT digest("archive_data", 'sha1') FROM "recipe"
                            WHERE "id" = $1
                        `,
                        recId
                    );
                    enforce(dbSha1 == sha1);

                    foreach (entry; fileEntries)
                        db.exec(
                            `INSERT INTO "recipe_file" ("recipe_id", "name", "size") VALUES ($1, $2, $3)`,
                            recId, entry.path, entry.size,
                        );

                    return recId;
                });

                writefln("Created recipe %s/%s/%s (%s)", pkg.name, vdir.ver, rdir.revision, recId);
            }

    }
}
