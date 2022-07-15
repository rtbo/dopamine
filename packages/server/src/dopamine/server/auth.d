module dopamine.server.auth;

import dopamine.server.config;
import dopamine.server.db;
import dopamine.server.utils;

import crypto;
import jwt;
import pgd.conn;

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
import std.string;
import std.traits;
import std.typecons;

@safe:

alias Name = vibe.data.serialization.name;

@OrderedCols
struct UserInfo
{
    int id;
    string email;
    string name;
    string avatarUrl;
}

private alias UserRow = UserInfo;

struct JwtPayload
{
    string iss;
    int sub;
    long exp;
    string email;
    string name;
    string avatarUrl;
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

    void auth(scope HTTPServerRequest req, scope HTTPServerResponse resp)
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
            const userRow = db.execRow!UserRow(`
                INSERT INTO "user" (email, name, avatar_url)
                VALUES ($1, $2, $3)
                ON CONFLICT(email) DO
                UPDATE SET name = EXCLUDED.name, avatar_url = EXCLUDED.avatar_url
                WHERE "user".email = EXCLUDED.email
                RETURNING id, email, name, avatar_url
            `, userResp.email, userResp.name, userResp.avatarUrl);

            refreshToken = db.execScalar!string(`
                    INSERT INTO refresh_token (token, user_id, expiration, cli)
                    VALUES (GEN_RANDOM_BYTES($1), $2, $3, FALSE)
                    RETURNING ENCODE(token, 'base64')
                `, cast(uint) RefreshToken.length, userRow.id, refreshTokenExp
            );

            return userRow;
        });

        auto idToken = Jwt.sign(idPayload(row), Config.get.serverJwtSecret);

        auto json = Json([
            "idToken": Json(idToken.toString()),
            "refreshToken": Json(refreshToken),
            "refreshTokenExpJs": Json(refreshTokenExp.toUnixTime() * 1000)
        ]);
        resp.writeJsonBody(json);
    }

    UserResp authImpl(Provider provider)(Json req, ProviderConfig config)
    {
        const code = req.enforceProp!string("code");
        const redirectUri = req.enforceProp!string("redirectUri");

        TokenResp!provider token;

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
                    throw new StatusException(
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

    void token(scope HTTPServerRequest req, scope HTTPServerResponse resp)
    {
        @OrderedCols
        static struct Row
        {
            int userId;
            Nullable!SysTime exp;
            Nullable!SysTime revoked;
            string name;
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
            const revoked = !row.revoked.isNull;
            const now = Clock.currTime;
            if (revoked || (!row.exp.isNull && row.exp.get <= now))
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

            // for CLI, we keep the same expiration date
            Nullable!SysTime refreshTokenExp = row.cli ? row.exp
                : nullable(now + refreshTokenDuration);

            const userRow = db.execRow!UserRow(
                `SELECT id, email, name, avatar_url FROM "user" WHERE id = $1`,
                row.userId
            );

            const newToken = db.execScalar!string(
                `
                    INSERT INTO refresh_token (token, user_id, expiration, name, cli)
                    VALUES (GEN_RANDOM_BYTES($1), $2, $3, $4, $5)
                    RETURNING ENCODE(token, 'base64')
                `, cast(uint) RefreshToken.length, userRow.id, refreshTokenExp, row.name, row.cli,
            );

            auto idToken = Jwt.sign(idPayload(userRow), Config.get.serverJwtSecret);

            auto json = Json([
                "idToken": Json(idToken.toString()),
                "refreshToken": Json(newToken),
            ]);

            if (!refreshTokenExp.isNull)
            {
                json["refreshTokenExpJs"] = Json(refreshTokenExp.get.toUnixTime() * 1000);
            }

            resp.writeJsonBody(json);
        });
    }

    @OrderedCols
    static struct CliTokenRow
    {
        int id;
        const(ubyte)[] token;
        string name;
        Nullable!SysTime expiration;

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
            js["name"] = name;
            if (!expiration.isNull)
                js["expJs"] = Json(expiration.get.toUnixTime() * 1000);
            return js;
        }
    }

    void cliTokens(scope HTTPServerRequest req, scope HTTPServerResponse resp)
    {
        const userInfo = enforceAuth(req);

        const rows = client.connect((scope db) => CliTokenRow.byUserId(db, userInfo.id));
        auto json = rows.map!(r => r.toElidedJson()).array;

        resp.writeJsonBody(Json(json));
    }

    void cliTokensCreate(scope HTTPServerRequest req, scope HTTPServerResponse resp)
    {
        const userInfo = enforceAuth(req);

        const name = req.json["name"].opt!string(null);

        auto days = req.json["expDays"];
        Nullable!SysTime expiration;
        if (days.type == Json.Type.int_)
            expiration = Clock.currTime + dur!"days"(days.get!int);

        @OrderedCols
        static struct Row
        {
            string token;
            string name;
            Nullable!SysTime exp;
        }

        const row = client.connect((scope db) @safe {
            return db.execRow!Row(`
                INSERT INTO refresh_token (user_id, token, name, expiration, cli)
                VALUES($1, GEN_RANDOM_BYTES($2), $3, $4, TRUE)
                RETURNING ENCODE(token, 'base64'), name, expiration
            `, userInfo.id, cast(uint) RefreshToken.length, name, expiration);
        });

        auto json = Json.emptyObject;
        json["token"] = Json(row.token);
        if (row.name)
            json["name"] = Json(row.name);
        if (!row.exp.isNull)
            json["expJs"] = Json(row.exp.get.toUnixTime() * 1000);

        resp.writeJsonBody(json);
    }

    void cliTokensRevoke(scope HTTPServerRequest req, scope HTTPServerResponse resp)
    {
        import std.conv : to;

        const userInfo = enforceAuth(req);

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
        Config.get.serverHostname,
        row.id,
        toJwtTime(Clock.currTime + idTokenDuration),
        row.email,
        row.name,
        row.avatarUrl,
    );
    return serializeToJson(payload);
}

private struct UserResp
{
    string email;
    string name;
    string avatarUrl;
}

private struct GithubUserResp
{
    string email;
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
            deserializeJson(ghUser, resp.readJson());
        }
    );
    // dfmt on

    return UserResp(ghUser.email, ghUser.name, ghUser.avatarUrl);
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

    return UserResp(payload.email, payload.name, payload.picture);
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
        throw new StatusException(400, "Unknown provider: " ~ provider);
    }
}

UserInfo enforceAuth(scope HTTPServerRequest req) @safe
{
    const head = enforceStatus(
        req.headers.get("authorization"), 401, "Authorization required"
    );
    const bearer = "bearer ";
    enforceStatus(
        head.length > bearer.length && head[0 .. bearer.length].toLower() == bearer,
        400, "Ill-formed authorization header"
    );
    try
    {
        const conf = Config.get;
        const jwt = Jwt.verify(
            head[bearer.length .. $].strip(),
            conf.serverJwtSecret,
            Jwt.VerifOpts(Yes.checkExpired, [conf.serverHostname]),
        );
        auto payload = jwt.payload;
        return UserInfo(
            payload["sub"].get!int,
            payload["email"].get!string,
            payload["name"].opt!string,
            payload["avatarUrl"].opt!string,
        );
    }
    catch (JwtException ex)
    {
        final switch (ex.cause)
        {
        case JwtVerifFailure.structure:
            statusError(400, format!"Ill-formed authorization header: %s"(ex.msg));
        case JwtVerifFailure.payload:
            // 500 because it is checked after signature
            statusError(500, format!"Improper field in authorization header payload: %s"(ex.msg));
        case JwtVerifFailure.expired:
            statusError(403, "Expired authorization token");
        case JwtVerifFailure.signature:
            statusError(403, "Invalid authorization token");
        }
    }
}
