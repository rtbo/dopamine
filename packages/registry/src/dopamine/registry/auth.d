module dopamine.registry.auth;

import dopamine.registry.config;
import dopamine.registry.db;
import dopamine.registry.utils;

import jwt;
import pgd.conn;
import pgd.maybe;

import vibe.core.log;
import vibe.data.json;
import vibe.data.serialization;
import vibe.http.client;
import vibe.http.router;
import vibe.http.server;

import std.algorithm;
import std.array;
import std.base64;
import std.datetime;
import std.exception;
import std.format;

// import std.net.curl;
import std.string;
import std.traits;

@safe:

alias Name = vibe.data.serialization.name;

struct UserInfo
{
    int id;
    string pseudo;
}

@OrderedCols
    struct UserRow
    {
        int id;
        string pseudo;
        string email;
        MayBeText name;
        MayBeText avatarUrl;
    }

struct JwtPayload
{
    string iss;
    int sub;
    long exp;
    string pseudo;
}

enum Provider
{
    github = 0,
    google,
}

struct ProviderConfig
{
    string tokenUrl;
    string clientId;
    string clientSecret;
}

struct TokenReq
{
    @Name("client_id") string clientId;
    @Name("client_secret") string clientSecret;
    string code;
    @Name("redirect_uri") string redirectUri;
    @Name("grant_type") string grantType;
}

struct GithubTokenResp
{
    @Name("token_type") string tokenType;
    @Name("access_token") string accessToken;
    @Name("scope") string scope_;
}

struct GoogleTokenResp
{
    @Name("token_type") string tokenType;
    @Name("access_token") string accessToken;
    @Name("scope") string scope_;
    @Name("id_token") string idToken;
    @Name("expires_in") int expiresIn;
}

template TokenResp(Provider provider)
{
    static if (provider == Provider.github)
        alias TokenResp = GithubTokenResp;

    else static if (provider == Provider.google)
        alias TokenResp = GoogleTokenResp;
}

enum idTokenDuration = dur!"seconds"(900);
enum refreshTokenDuration = dur!"days"(2);

alias RefreshToken = ubyte[32];

class AuthApi
{
    DbClient client;
    ProviderConfig[] providers;

    this(DbClient client)
    {
        this.client = client;

        const config = Config.get;

        providers = new ProviderConfig[(EnumMembers!Provider).length];
        providers[Provider.github] = ProviderConfig(
            "https://github.com/login/oauth/access_token",
            config.githubClientId,
            config.githubClientSecret,
        );
        providers[Provider.google] = ProviderConfig(
            "https://oauth2.googleapis.com/token",
            config.googleClientId,
            config.googleClientSecret,
        );
    }

    void setupRoutes(URLRouter router)
    {
        router.post("/auth", genericHandler(&auth));
        router.post("/auth/token", genericHandler(&token));
        router.get("/auth/cli-tokens", genericHandler(&cliTokens));
        router.post("/auth/cli-tokens", genericHandler(&cliTokensCreate));
        router.delete_("/auth/cli-tokens/:id", genericHandler(&cliTokensRevoke));
    }

    void auth(HTTPServerRequest req, HTTPServerResponse resp)
    {
        const provider = toProvider(req.json.enforceProp!string("provider"));
        const config = providers[provider];

        UserResp userResp;

        final switch (provider)
        {
        case Provider.github:
            userResp = authImpl!(Provider.github)(req.json, config);
            break;
        case Provider.google:
            userResp = authImpl!(Provider.google)(req.json, config);
            break;
        }

        string refreshToken;
        const refreshTokenExp = Clock.currTime + refreshTokenDuration;

        const row = client.transac((scope DbConn db) {

            // get a unique pseudo if already used by another user
            string pseudoBase = userResp.pseudo;
            int pseudoN = 2;
            while(true)
            {
                const exists = db.execScalar!bool(
                    `
                        SELECT count(pseudo) <> 0 FROM "user"
                        WHERE email <> $1 AND pseudo = $2
                    `,
                    userResp.email, userResp.pseudo
                );
                if (exists)
                    userResp.pseudo = format!"%s%s"(pseudoBase, pseudoN++);
                else
                    break;
            }

            // upsert user in database
            const userRow = db.execRow!UserRow(
                `
                    INSERT INTO "user" (pseudo, email, name, avatar_url)
                    VALUES ($1, $2, $3, $4)
                    ON CONFLICT(email) DO UPDATE
                        SET pseudo=EXCLUDED.pseudo, name=EXCLUDED.name, avatar_url=EXCLUDED.avatar_url
                    RETURNING id, pseudo, email, name, avatar_url
                `, userResp.pseudo, userResp.email, userResp.name, userResp.avatarUrl
            );

            refreshToken = db.execScalar!string(
                `
                    INSERT INTO refresh_token (token, user_id, expiration, cli)
                    VALUES (GEN_RANDOM_BYTES($1), $2, $3, FALSE)
                    RETURNING ENCODE(token, 'base64')
                `, cast(uint) RefreshToken.length, userRow.id, refreshTokenExp
            );

            return userRow;
        });

        auto idToken = Jwt.sign(idPayload(row), Config.get.registryJwtSecret);

        auto json = Json([
            "idToken": Json(idToken.toString()),
            "refreshToken": Json(refreshToken),
            "refreshTokenExpJs": Json(refreshTokenExp.toUnixTime() * 1000),
            "email": Json(row.email),
        ]);
        if (row.name.valid)
            json["name"] = row.name.value;
        if (row.avatarUrl.valid)
            json["avatarUrl"] = row.avatarUrl.value;

        resp.writeJsonBody(json);
    }

    UserResp authImpl(Provider provider)(Json req, ProviderConfig config) @trusted
    {
        const code = req.enforceProp!string("code");
        const redirectUri = req.enforceProp!string("redirectUri");

        TokenResp!provider token;

        // const tokReq = TokenReq(
        //     config.clientId,
        //     config.clientSecret,
        //     code,
        //     redirectUri,
        //     "authorization_code",
        // );
        // const tokJson = serializeToJsonString(tokReq);
        // logInfo("%s", config.tokenUrl);
        // logInfo("%s", tokJson);
        // auto http = HTTP();
        // http.addRequestHeader("Accept", "application/json");
        // http.addRequestHeader("Content-Type", "application/json");
        // const resp = post(config.tokenUrl, tokJson, http);
        // auto json = parseJsonString(resp.idup);
        // deserializeJson(token, json);

        // dfmt off
        requestHTTP(
            config.tokenUrl,
            (scope HTTPClientRequest req) {
                req.method = HTTPMethod.POST;
                req.headers["Accept"] = "application/json";
                const tokReq = TokenReq(
                    config.clientId,
                    config.clientSecret,
                    code,
                    redirectUri,
                    "authorization_code",
                );
                req.writeJsonBody(tokReq);
            },
            (scope HTTPClientResponse resp) {
                if (resp.statusCode >= 400)
                {
                    import vibe.stream.operations;
                    throw new HTTPStatusException(
                        403,
                        format!"Could not request token to %s: %s"(config.tokenUrl, resp.bodyReader().readAllUTF8()),
                    );
                }
                auto json = resp.readJson();
                string error;
                if (json["error"].type != Json.Type.undefined)
                    error = json["error"].get!string;
                else if (json["error_description"].type != Json.Type.undefined)
                    error = json["error_description"].get!string;
                enforceStatus (!error, 403, error);
                deserializeJson(token, json);
                enforceStatus(token.tokenType.toLower() == "bearer", 500,
                    "Unsupported token type: " ~ token.tokenType
                );
                enforceStatus(token.accessToken, 403, format!"Did not receive token from %s"(provider));
            }
        );
        // dfmt on

        static if (provider == Provider.github)
            return getGithubUser(token.accessToken);
        else static if (provider == Provider.google)
            return getGoogleUser(token.idToken);
    }

    void token(HTTPServerRequest req, HTTPServerResponse resp)
    {
        @OrderedCols
        static struct Row
        {
            int userId;
            MayBeTimestamp exp;
            MayBeTimestamp revoked;
            MayBeText name;
            bool cli;
        }

        const refreshTokenB64 = req.json.enforceProp!string("refreshToken");
        RefreshToken refreshTokenBuf;
        auto refreshToken = Base64.decode(refreshTokenB64, refreshTokenBuf[]);

        client.transac((scope DbConn db) {

            Row row;
            try
            {
                // update revoked but return previous value
                row = db.execRow!Row(`
                    UPDATE refresh_token new SET revoked = NOW()
                    FROM refresh_token old
                    WHERE new.token = old.token AND new.token = $1
                    RETURNING old.user_id, old.expiration, old.revoked, old.name, old.cli
                `, refreshToken);
            }
            catch (ResourceNotFoundException ex)
            {
                statusError(401, "Unknown token");
            }
            const revoked = row.revoked.valid;
            const now = Clock.currTime;
            if (revoked || (row.exp.valid && row.exp.value <= now))
            {
                logTrace("Revoking all tokens of user %s", row.userId);

                // attempt to use a revoked or expired token.
                // possibly a token was stolen by XSS
                // invalidate all tokens from the user to force to re-authenticate
                db.exec(
                    `UPDATE refresh_token SET revoked = NOW() WHERE user_id = $1`,
                    row.userId,
                );
                resp.statusCode = 403;
                resp.writeBody(revoked ? "Attempt to use revoked token" : "expired token");
                return;
            }

            // all good let's generate a new Jwt and refresh token
            // FIXME: should we here re-authenticate to provider?

            const userRow = db.execRow!UserRow(
                `SELECT id, pseudo, email, name, avatar_url FROM "user" WHERE id = $1`,
                row.userId
            );

            // for CLI, we keep the same expiration date
            auto refreshTokenExp = row.cli ? row.exp : mayBeTimestamp(now + refreshTokenDuration);

            const newToken = db.execScalar!string(
                `
                    INSERT INTO refresh_token (token, user_id, expiration, name, cli)
                    VALUES (GEN_RANDOM_BYTES($1), $2, $3, $4, $5)
                    RETURNING ENCODE(token, 'base64')
                `, cast(uint) RefreshToken.length, userRow.id, refreshTokenExp, row.name, row.cli,
            );

            auto idToken = Jwt.sign(idPayload(userRow), Config.get.registryJwtSecret);

            auto json = Json([
                "idToken": Json(idToken.toString()),
                "refreshToken": Json(newToken),
                "email": Json(userRow.email),
            ]);

            if (refreshTokenExp.valid)
                json["refreshTokenExpJs"] = refreshTokenExp.value.toUnixTime() * 1000;
            if (userRow.name.valid)
                json["name"] = userRow.name.value;
            if (userRow.avatarUrl.valid)
                json["avatarUrl"] = userRow.avatarUrl.value;

            resp.writeJsonBody(json);
        });
    }

    @OrderedCols
    static struct CliTokenRow
    {
        int id;
        const(ubyte)[] token;
        MayBeText name;
        MayBeTimestamp expiration;

        static CliTokenRow[] byUserId(scope DbConn db, int userId)
        {
            return db.execRows!CliTokenRow(
                `
                    SELECT id, token, name, expiration FROM refresh_token
                    WHERE user_id = $1 AND cli AND revoked IS NULL AND expiration > NOW()
                `, userId,
            );
        }

        Json toElidedJson() const
        {
            auto js = Json.emptyObject;
            js["id"] = id;
            js["elidedToken"] = elidedToken(Base64.encode(token).idup);
            if (name.valid)
                js["name"] = name.value;
            if (expiration.valid)
                js["expJs"] = Json(expiration.value.toUnixTime() * 1000);
            return js;
        }
    }

    void cliTokens(HTTPServerRequest req, HTTPServerResponse resp)
    {
        const userInfo = enforceUserAuth(req);

        const rows = client.connect((scope db) => CliTokenRow.byUserId(db, userInfo.id));
        auto json = rows.map!(r => r.toElidedJson()).array;

        resp.writeJsonBody(Json(json));
    }

    void cliTokensCreate(HTTPServerRequest req, HTTPServerResponse resp)
    {
        const userInfo = enforceUserAuth(req);

        const name = req.json["name"].opt!string(null);

        MayBe!(int, -1) days = req.json["expDays"].opt!int(-1);
        const expiration = days
            .map!(d => Clock.currTime + dur!"days"(d))
            .mayBeTimestamp();

        @OrderedCols
        static struct Row
        {
            string token;
            MayBeText name;
            MayBeTimestamp exp;
        }

        auto row = client.connect((scope db) @safe {
            return db.execRow!Row(`
                INSERT INTO refresh_token (user_id, token, name, expiration, cli)
                VALUES($1, GEN_RANDOM_BYTES($2), $3, $4, TRUE)
                RETURNING ENCODE(token, 'base64'), name, expiration
            `, userInfo.id, cast(uint) RefreshToken.length, name, expiration);
        });

        auto json = Json.emptyObject;
        json["token"] = Json(row.token);
        row.name.each!(n => json["name"] = n);
        row.exp.each!(t => json["expJs"] = t.toUnixTime() * 1000);

        resp.writeJsonBody(json);
    }

    void cliTokensRevoke(HTTPServerRequest req, HTTPServerResponse resp)
    {
        import std.conv : to;

        const userInfo = enforceUserAuth(req);

        const tokenId = req.params["id"].to!int;

        const json = client.transac((scope db) {
            const revoked = db.execScalar!string(`
                UPDATE refresh_token SET revoked = NOW()
                WHERE id = $1 AND revoked IS NULL AND user_id = $2
                RETURNING ENCODE(token, 'base64')
            `, tokenId, userInfo.id);

            logTrace("Revoking token %s (%s)", tokenId, revoked);

            const rows = CliTokenRow.byUserId(db, userInfo.id);
            auto json = rows.map!(r => r.toElidedJson()).array;
            return Json(json);
        });

        resp.writeJsonBody(json);
    }
}

private string elidedToken(string token)
{
    const chars = max(4, token.length / 5);
    return token[0 .. chars] ~ " ... " ~ token[$ - chars .. $];
}

private Json idPayload(UserRow row)
{
    const payload = JwtPayload(
        Config.get.registryHostname,
        row.id,
        toJwtTime(Clock.currTime + idTokenDuration),
        row.pseudo,
    );
    return serializeToJson(payload);
}

private struct UserResp
{
    string email;
    string pseudo;
    string name;
    string avatarUrl;
}

private struct GithubUserResp
{
    string email;
    string login;
    string name;
    @Name("avatar_url") string avatarUrl;
}

private UserResp getGithubUser(string accessToken)
{
    GithubUserResp ghUser;

    // dfmt off
    requestHTTP(
        "https://api.github.com/user",
        (scope HTTPClientRequest req) {
            req.method = HTTPMethod.GET;
            req.headers["Authorization"] = format!"token %s"(accessToken);
        },
        (scope HTTPClientResponse resp) {
            enforceStatus(
                resp.statusCode < 400, 403,
                "Could not access user from github API"
            );
            auto json = resp.readJson();
            deserializeJson(ghUser, json);
        }
    );
    // dfmt on

    return UserResp(ghUser.email, ghUser.login, ghUser.name, ghUser.avatarUrl);
}

private struct GoogleUserPayload
{
    @optional string name;
    @optional string picture;
    string email;
}

private UserResp getGoogleUser(string idToken)
{
    const jwt = ClientJwt(idToken);
    GoogleUserPayload payload;
    deserializeJson(payload, jwt.payload);

    const at = payload.email.indexOf('@');
    enforceStatus(at > 0, 400, "invalid email address: " ~ payload.email);
    string pseudo = payload.email[0 .. at];

    return UserResp(payload.email, pseudo, payload.name, payload.picture);
}

private Provider toProvider(string provider)
{
    switch (provider)
    {
    case "github":
        return Provider.github;
    case "google":
        return Provider.google;
    default:
        throw new HTTPStatusException(400, "Unknown provider: " ~ provider);
    }
}

UserInfo enforceUserAuth(HTTPServerRequest req) @safe
{
    auto payload = enforceAuth(req);

    return UserInfo(
        payload["sub"].get!int,
        payload["pseudo"].get!string,
    );
}

MayBe!UserInfo checkUserAuth(HTTPServerRequest req) @safe
{
    auto payload = checkAuth(req);

    return payload.map!(p => UserInfo(
        p["sub"].get!int,
        p["pseudo"].get!string,
    )).mayBe();
}
