
CREATE TABLE "user" (
    "id"            serial PRIMARY KEY,
    "email"         text NOT NULL,
    "avatar_url"    text
);

CREATE TABLE "user_clikey" (
    "clikey"        text PRIMARY KEY,
    "user_id"       integer NOT NULL,

    FOREIGN KEY ("user_id") REFERENCES "user"("id") ON DELETE CASCADE
);

CREATE TABLE "package" (
    "id"            serial PRIMARY KEY,
    "name"          text NOT NULL,
    "maintainer_id" integer,

    FOREIGN KEY ("maintainer_id") REFERENCES "user"("id") ON DELETE SET NULL
);

CREATE TABLE "recipe" (
    "id"            serial PRIMARY KEY,
    "package_id"    integer NOT NULL,
    "maintainer_id" integer,
    "version"       text NOT NULL,
    "revision"      text NOT NULL,
    "recipe"        text NOT NULL,
    "filename"      text NOT NULL,
    "filesha1"      text NOT NULL,

    FOREIGN KEY ("package_id") REFERENCES "package"("id") ON DELETE CASCADE,
    FOREIGN KEY ("maintainer_id") REFERENCES "user"("id") ON DELETE SET NULL
);

CREATE TABLE "recipe_file" (
    "id"            serial PRIMARY KEY,
    "recipe_id"     integer NOT NULL,
    "name"          text NOT NULL,
    "size"          integer NOT NULL,

    FOREIGN KEY ("recipe_id") REFERENCES "recipe"("id") ON DELETE CASCADE
);
