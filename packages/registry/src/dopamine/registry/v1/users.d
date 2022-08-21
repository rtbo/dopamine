module dopamine.registry.v1.users;

import dopamine.registry.auth;
import dopamine.registry.db;
import dopamine.registry.utils;

import dopamine.api.v1;

import pgd.conn;
import pgd.maybe;
import pgd.param;

import vibe.data.json;
import vibe.http.router;
import vibe.http.server;

import std.algorithm;
import std.array;
import std.format;

class UsersApi
{
    DbClient client;

    this(DbClient client)
    {
        this.client = client;
    }

    void setupRoutes(URLRouter router)
    {
        router.get("/v1/users/:pseudo", genericHandler(&get));
    }

    @OrderedCols
    static struct Row
    {
        int id;
        string pseudo;
        string email;
        MayBeText name;
        MayBeText avatarUrl;
        short privacyFlags;
    }

    void get(scope HTTPServerRequest req, scope HTTPServerResponse resp) @safe
    {
        auto userInfo = checkUserAuth(req);
        const pseudo = enforceStatus(req.params.get("pseudo"), 400, "missing pseudo parameter");

        const row = client.transac((scope DbConn db) {
            return db.execRow!Row(
                `
                    SELECT id, pseudo, email, name, avatar_url, privacy_flags
                    FROM "user" WHERE pseudo = $1
                `,
                pseudo
            );
        });

        const pflags = cast(PrivacyFlags)(
            userInfo
                .map!(ui => ui.id == row.id ? 0 : row.privacyFlags)
                .mayBe()
                .valueOr(row.privacyFlags)
        );

        Json json = Json.emptyObject;
        json["pseudo"] = row.pseudo;
        if (!pflags.emailPrivate)
            json["email"] = row.email;
        if (!pflags.namePrivate && row.name.valid)
            json["name"] = row.name.value;
        if (!pflags.avatarUrlPrivate && row.avatarUrl.valid)
            json["avatarUrl"] = row.avatarUrl.value;

        if (userInfo.valid && userInfo.value.id == row.id)
            json["privacyFlags"] = row.privacyFlags;

        resp.writeJsonBody(json);
    }

    void patch(scope HTTPServerRequest req, scope HTTPServerResponse resp) @safe
    {
        auto userInfo = enforceUserAuth(req);
        const pseudo = enforceStatus(req.params.get("pseudo"), 400, "missing pseudo parameter");

        enforceStatus(pseudo == userInfo.pseudo, 403, "Cannot modify someone else profile");

        PgParam[] params;
        string[] setList;

        {
            auto json = req.json;

            void check(T)(string propName, string sqlPropName = null)
            {
                auto prop = json[propName];
                if (prop.type != Json.Type.undefined)
                {
                    auto val = prop.to!T;
                    params ~= pgParam(val);
                    setList ~= format!`%s = $%s`(
                        sqlPropName ? sqlPropName : propName,
                        params.length
                    );
                }
            }

            check!string("pseudo");
            check!string("name");
            check!string("avatarUrl", "avatar_url");
            check!short("privacyFlags", "privacy_flags");

            enforceStatus(setList.length, 204, "Empty patch");

            params ~= pgParam(userInfo.id);
        }

        const row = client.transac((scope DbConn db) {
            auto rq =
                format!`
                    UPDATE "user" SET %s WHERE id = $%s
                    RETURNING id, pseudo, email, name, avatar_url, privacy_flags
                `(setList.join(", "), params.length);

            db.sendDyn(
                format!`
                    UPDATE "user" SET %s WHERE id = $%s
                    RETURNING id, pseudo, email, name, avatar_url, privacy_flags
                `(setList.join(", "), params.length),
                params
            );
            db.pollResult();
            return db.getRow!Row();
        });

        Json res = Json.emptyObject;
        res["pseudo"] = row.pseudo;
        res["email"] = row.email;
        if (row.name.valid)
            res["name"] = row.name.value;
        if (row.avatarUrl.valid)
            res["avatarUrl"] = row.avatarUrl.value;

        if (userInfo.id == row.id)
            res["privacyFlags"] = row.privacyFlags;

        resp.writeJsonBody(res);
    }
}

version (unittest)
{
    import dopamine.registry.test;
    import vibe.inet.url;
    import vibe.stream.memory;
    import unit_threaded.assertions;
    import std.exception;

    @("GET /v1/users/:other")
    unittest
    {
        auto client = new DbClient(dbConnString(), 1);
        scope (exit)
            client.finish();

        auto registry = TestRegistry(client);

        client.transac((scope db) {
            db.exec(`UPDATE "user" SET privacy_flags = 0 WHERE pseudo = 'one'`);
            db.exec(`UPDATE "user" SET privacy_flags = 1 WHERE pseudo = 'two'`);
            db.exec(`UPDATE "user" SET privacy_flags = 3 WHERE pseudo = 'three'`);
        });

        auto api = new UsersApi(client);

        UserResource getUser(string pseudo)
        {
            auto output = createMemoryOutputStream();
            auto req = createTestHTTPServerRequest(
                URL("https://api.dopamine-pm.org/v1/users/" ~ pseudo));
            req.params["pseudo"] = pseudo;
            auto res = createTestHTTPServerResponse(output, null, TestHTTPResponseMode.bodyOnly);

            api.get(req, res);

            return deserializeJson!UserResource(cast(string) assumeUnique(output.data));
        }

        auto one = getUser("one");
        auto two = getUser("two");
        auto three = getUser("three");

        one.pseudo.should == "one";
        one.email.should == "user.one@dop.test";
        one.name.should == "User One";
        one.privacyFlags.should == PrivacyFlags.none;

        two.pseudo.should == "two";
        two.email.shouldBeNull();
        two.name.should == "User Two";
        two.privacyFlags.should == PrivacyFlags.none;

        three.pseudo.should == "three";
        three.email.shouldBeNull();
        three.name.shouldBeNull();
        three.privacyFlags.should == PrivacyFlags.none;
    }

    @("GET /v1/users/:self")
    unittest
    {
        auto client = new DbClient(dbConnString(), 1);
        scope (exit)
            client.finish();

        auto registry = TestRegistry(client);

        client.transac((scope db) {
            db.exec(`UPDATE "user" SET privacy_flags = 0 WHERE pseudo = 'one'`);
            db.exec(`UPDATE "user" SET privacy_flags = 1 WHERE pseudo = 'two'`);
            db.exec(`UPDATE "user" SET privacy_flags = 3 WHERE pseudo = 'three'`);
        });

        auto api = new UsersApi(client);

        UserResource getUser(string pseudo)
        {
            auto output = createMemoryOutputStream();
            auto req = createTestHTTPServerRequest(
                URL("https://api.dopamine-pm.org/v1/users/" ~ pseudo));
            req.params["pseudo"] = pseudo;
            req.headers["Authorization"] = "Bearer " ~ registry.authTokenFor(pseudo);
            auto res = createTestHTTPServerResponse(output, null, TestHTTPResponseMode.bodyOnly);

            api.get(req, res);

            return deserializeJson!UserResource(cast(string) assumeUnique(output.data));
        }

        auto one = getUser("one");
        auto two = getUser("two");
        auto three = getUser("three");

        one.pseudo.should == "one";
        one.email.should == "user.one@dop.test";
        one.name.should == "User One";
        one.privacyFlags.should == PrivacyFlags.none;

        two.pseudo.should == "two";
        two.email.should == "user.two@dop.test";
        two.name.should == "User Two";
        two.privacyFlags.should == PrivacyFlags.email;

        three.pseudo.should == "three";
        three.email.should == "user.three@dop.test";
        three.name.should == "User Three";
        three.privacyFlags.should == (PrivacyFlags.email | PrivacyFlags.name);
    }

    @("PATCH /v1/users/:pseudo")
    unittest
    {
        import std.string : representation;
        import std.typecons : nullable;

        auto client = new DbClient(dbConnString(), 1);
        scope (exit)
            client.finish();

        auto registry = TestRegistry(client);

        auto api = new UsersApi(client);

        UserResource patchUser(string pseudo, UserPatch patch)
        {
            auto json = serializeToJsonString(patch);
            auto input = createMemoryStream(json.representation.dup, false);

            auto req = createTestHTTPServerRequest(
                URL("https://api.dopamine-pm.org/v1/users/" ~ pseudo),
                HTTPMethod.PATCH,
                input);
            req.params["pseudo"] = pseudo;
            req.headers["Authorization"] = "Bearer " ~ registry.authTokenFor("one");
            req.headers["Content-Type"] = "application/json";

            auto output = createMemoryOutputStream();
            auto res = createTestHTTPServerResponse(output, null, TestHTTPResponseMode.bodyOnly);

            api.patch(req, res);

            return deserializeJson!UserResource(cast(string) assumeUnique(output.data));
        }

        // try to patch other user
        patchUser("two", UserPatch(
                nullable("newyou"),
                nullable("New You"),
                nullable("https://newyou.picture.test"),
                nullable(PrivacyFlags.name)
        )).shouldThrowWithMessage("Cannot modify someone else profile");

        // patch self
        auto one = patchUser("one", UserPatch(
                nullable("newme"),
                nullable("New Me"),
                nullable("https://newme.picture.test"),
                nullable(PrivacyFlags.name)
        ));

        one.pseudo.should == "newme";
        one.email.should == "user.one@dop.test";
        one.name.should == "New Me";
        one.privacyFlags.should == PrivacyFlags.name;
    }
}
