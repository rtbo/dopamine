
CREATE TABLE "package" (
    "name"          text PRIMARY KEY,
    "description"   text NOT NULL
);

CREATE TABLE "recipe" (
    "id"            serial PRIMARY KEY,
    "package_name"  text NOT NULL,
    "created_by"    integer,
    "created"       timestamptz NOT NULL,
    "version"       text NOT NULL,
    "revision"      text NOT NULL,
    "archive_id"    integer NOT NULL,

    "description"   text NOT NULL,
    "upstream_url"  text NOT NULL,
    "license"       text NOT NULL,
    "recipe"        text,
    "readme_mt"     text, -- mimetype
    "readme"        text,

    FOREIGN KEY ("package_name") REFERENCES "package"("name") ON DELETE CASCADE,
    FOREIGN KEY ("created_by") REFERENCES "user"("id") ON DELETE SET NULL,
    FOREIGN KEY ("archive_id") REFERENCES "archive"("id") ON DELETE CASCADE,
    UNIQUE("package_name", "version", "revision")
);

-- index on server_order_map to quickly perform order by clause with this function
CREATE INDEX "idx_recipe_version" ON "recipe" (semver_order_str("version"));

CREATE VIEW "package_counter" AS
    SELECT p.name AS name, sum(a.counter)::integer AS counter, count(DISTINCT r.version)::integer AS num_versions, count(r.id)::integer AS num_recipes
    FROM "archive" AS a
        LEFT OUTER JOIN "recipe" AS r ON r.archive_id = a.id
        LEFT OUTER JOIN "package" AS p ON p.name = r.package_name
    GROUP BY p.name;
