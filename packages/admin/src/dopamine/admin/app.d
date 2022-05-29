module dopamine.admin.app;

import dopamine.admin.config;
import dopamine.cache_dirs;
import pgd.conn;
import pgd.connstring;

import std.algorithm;
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
    string registryDir;

    static Options parse(string[] args)
    {
        Options opts;

        // dfmt off
        auto res = getopt(args,
            "create-db",        &opts.createDb,
            "run-migration",    &opts.migrationsToRun,
            "populate-from",    &opts.registryDir,
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
        return !createDb && !migrationsToRun.length && !registryDir;
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

    auto db = new PgConn(conf.dbConnString);
    scope (exit)
        db.finish();

    foreach (mig; opts.migrationsToRun)
    {
        writefln("Running migration \"%s\"", mig);
        db.exec(migrations[mig]);
    }

    if (opts.registryDir)
        populateRegistry(db, opts.registryDir);

    return 0;
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

enum adminEmail = "admin.tool@dop-test.org";

int createUserIfNotExist(PgConn db, string email)
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
    return userId;
}

void populateRegistry(PgConn db, string regDir)
{
    const adminId = createUserIfNotExist(db, adminEmail);

    foreach (packDir; dirEntries(regDir, SpanMode.shallow).filter!(e => e.isDir))
    {
        auto pkg = CachePackageDir(packDir.name);

        bool foundRecipe;
        verLoop: foreach (vdir; pkg.versionDirs)
        {
            foreach (rdir; vdir.revisionDirs)
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

        const pkgId = db.execScalar!int(
            `
                INSERT INTO "package" ("name", "maintainer_id")
                VALUES ($1, $2)
                RETURNING "id"
            `,
            pkg.name, adminId
        );
        writefln("Created package %s (%s)", pkg.name, pkgId);

        foreach (vdir; pkg.versionDirs)
            foreach (rdir; vdir.revisionDirs)
            {
                if (!exists(rdir.recipeFile))
                    continue;

                const recipe = cast(string)read(rdir.recipeFile);

                const recId = db.execScalar!int(
                    `
                        INSERT INTO "recipe" (
                            "package_id",
                            "maintainer_id",
                            "version",
                            "revision",
                            "recipe"
                        ) VALUES(
                            $1, $2, $3, $4, $5
                        )
                        RETURNING "id"
                    `,
                    pkgId, adminId, vdir.ver, rdir.revision, recipe
                );
                writefln("Created recipe %s/%s/%s (%s)", pkg.name, vdir.ver, rdir.revision, recId);
            }

    }
}
