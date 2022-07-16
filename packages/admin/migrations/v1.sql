CREATE EXTENSION "pgcrypto";

CREATE TABLE "user" (
    "id"            serial PRIMARY KEY,
    "email"         text NOT NULL,
    "name"          text,
    "avatar_url"    text,

    UNIQUE("email")
);

CREATE TABLE "refresh_token" (
    "id"            serial PRIMARY KEY,
    "token"         bytea NOT NULL,
    "user_id"       integer NOT NULL,
    "expiration"    timestamptz,
    "revoked"       timestamptz, -- null if valid
    "name"          text, -- only for CLI tokens
    "cli"           boolean NOT NULL,

    FOREIGN KEY ("user_id") REFERENCES "user"("id") ON DELETE CASCADE,
    UNIQUE("token")
);

-- Fast lookup with "token" is needed
CREATE INDEX "idx_refresh_token_token" ON "refresh_token" ("token");

CREATE TABLE "user_clikey" (
    "clikey"        text PRIMARY KEY,
    "user_id"       integer NOT NULL,

    FOREIGN KEY ("user_id") REFERENCES "user"("id") ON DELETE CASCADE
);

CREATE TABLE "package" (
    "name"          text PRIMARY KEY,
    "maintainer_id" integer,
    "created"       timestamptz NOT NULL,

    FOREIGN KEY ("maintainer_id") REFERENCES "user"("id") ON DELETE SET NULL
);

CREATE TABLE "recipe" (
    "id"            serial PRIMARY KEY,
    "package_name"  text NOT NULL,
    "maintainer_id" integer,
    "created"       timestamptz NOT NULL,
    "version"       text NOT NULL,
    "revision"      text NOT NULL,
    "recipe"        text NOT NULL,
    "archive_data"  bytea NOT NULL,

    FOREIGN KEY ("package_name") REFERENCES "package"("name") ON DELETE CASCADE,
    FOREIGN KEY ("maintainer_id") REFERENCES "user"("id") ON DELETE SET NULL,
    UNIQUE("package_name", "version", "revision")
);

-- recipe file data is received compressed, therefore the following will save CPU time on the server.
-- See https://www.cybertec-postgresql.com/en/binary-data-performance-in-postgresql/
ALTER TABLE "recipe" ALTER COLUMN "archive_data" SET STORAGE EXTERNAL;

CREATE TABLE "recipe_file" (
    "recipe_id"     integer,
    "name"          text,
    "size"          integer NOT NULL,

    FOREIGN KEY ("recipe_id") REFERENCES "recipe"("id") ON DELETE CASCADE,
    PRIMARY KEY("recipe_id", "name")
);
