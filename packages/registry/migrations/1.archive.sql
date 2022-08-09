-- support for archive download/upload

CREATE TABLE "archive" (
    "id"            serial PRIMARY KEY,
    "name"          text NOT NULL,
    "created"       timestamptz NOT NULL,
    "created_by"    integer,
    "counter"       integer NOT NULL,
    "upload_done"   boolean NOT NULL,
    "data"          bytea, -- may or may not be stored in database

    FOREIGN KEY ("created_by") REFERENCES "user"("id") ON DELETE SET NULL
);

-- Fast lookup with "name" is needed
CREATE INDEX "idx_archive_name" ON "archive" ("name");

-- archive data is received compressed, therefore the following will save CPU time on the server.
-- See https://www.cybertec-postgresql.com/en/binary-data-performance-in-postgresql/
ALTER TABLE "archive" ALTER COLUMN "data" SET STORAGE EXTERNAL;

CREATE TABLE "archive_file" (
    "archive_id"    integer,
    "name"          text,
    "size"          integer NOT NULL,

    FOREIGN KEY ("archive_id") REFERENCES "archive"("id") ON DELETE CASCADE
);
