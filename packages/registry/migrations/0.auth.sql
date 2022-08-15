-- support for user authentication

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
