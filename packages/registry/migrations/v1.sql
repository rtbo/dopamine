
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
    "archive_id"    integer NOT NULL,

    FOREIGN KEY ("package_name") REFERENCES "package"("name") ON DELETE CASCADE,
    FOREIGN KEY ("maintainer_id") REFERENCES "user"("id") ON DELETE SET NULL,
    FOREIGN KEY ("archive_id") REFERENCES "archive"("id") ON DELETE CASCADE,
    UNIQUE("package_name", "version", "revision")
);