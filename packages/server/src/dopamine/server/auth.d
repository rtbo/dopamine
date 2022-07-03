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

        RefreshToken refreshToken;
        cryptoRandomBytes(refreshToken[]);
        const refreshTokenB64 = Base64.encode(refreshToken).idup;
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

            const rt = db.execScalar!RefreshToken(`
                    INSERT INTO refresh_token (token, user_id, expiration, cli)
                    VALUES ($1, $2, $3, FALSE)
                    RETURNING token
                `, refreshToken, userRow.id, refreshTokenExp
            );

            enforce(rt == refreshToken, "Could not store refresh token in DB");

            return userRow;
        });

        auto idToken = Jwt.sign(idPayload(row), Config.get.serverJwtSecret);

        auto json = Json([
            "idToken": Json(idToken.toString()),
            "refreshToken": Json(refreshTokenB64),
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

    @OrderedCols
    static struct TokenRow
    {
        int userId;
        Nullable!SysTime exp;
        Nullable!SysTime revoked;
        bool cli;
    }

    @OrderedCols
    static struct Row
    {
        const(ubyte)[] token;
        int userId;
        Nullable!SysTime exp;
        Nullable!SysTime revoked;
        bool cli;
    }

    void token(scope HTTPServerRequest req, scope HTTPServerResponse resp)
    {
        string refreshTokenB64 = req.json.enforceProp!string("refreshToken");
        RefreshToken refreshTokenBuf;
        auto refreshToken = Base64.decode(refreshTokenB64, refreshTokenBuf[]);

        client.transac((scope DbConn db) {

            auto rows = db.execRows!Row(`
                SELECT token, user_id, expiration, revoked, cli FROM refresh_token
            `);

            TokenRow tokRow;
            try
            {
                // update revoked but return previous value
                tokRow = db.execRow!TokenRow(`
                    UPDATE refresh_token new SET revoked = NOW()
                    FROM refresh_token old
                    WHERE new.token = old.token AND new.token = $1
                    RETURNING old.user_id, old.expiration, old.revoked, old.cli
                `, refreshToken);
            }
            catch (ResourceNotFoundException ex)
            {
                statusError(401, "Unknown token");
            }
            const revoked = !tokRow.revoked.isNull;
            const now = Clock.currTime.toUTC();
            if (revoked || (!tokRow.exp.isNull && tokRow.exp.get <= now))
            {
                // attempt to use a revoked or expired token.
                // possibly a token was stolen by XSS
                // invalidate all tokens from the user to force to re-authenticate
                db.exec(
                    `UPDATE refresh_token SET revoked = NOW() WHERE user_id = $1`,
                    tokRow.userId,
                );
                statusError(403, revoked ? "Attempt to use revoked token" : "expired token");
            }

            // all good let's generate a new Jwt and refresh token
            // FIXME: here we should re-authenticate to provider

            cryptoRandomBytes(refreshTokenBuf[]);
            refreshTokenB64 = Base64.encode(refreshTokenBuf);

            // for CLI, we keep the same expiration date
            Nullable!SysTime refreshTokenExp = tokRow.cli ? tokRow.exp
                : nullable(now + refreshTokenDuration);

            const userRow = db.execRow!UserRow(
                `SELECT id, email, name, avatar_url FROM "user" WHERE id = $1`,
                tokRow.userId
            );

            const rt = db.execScalar!(const(ubyte)[])(`
                    INSERT INTO refresh_token (token, user_id, expiration, cli)
                    VALUES ($1, $2, $3, $4)
                    RETURNING token
                `, refreshToken, userRow.id, refreshTokenExp, tokRow.cli,
            );
            enforce(rt == refreshToken, "Could not store refresh token in DB");

            auto idToken = Jwt.sign(idPayload(userRow), Config.get.serverJwtSecret);

            auto json = Json([
                "idToken": Json(idToken.toString()),
                "refreshToken": Json(refreshTokenB64),
            ]);

            if (!refreshTokenExp.isNull)
            {
                json["refreshTokenExpJs"] = Json(refreshTokenExp.get.toUnixTime() * 1000);
            }

            resp.writeJsonBody(json);
        });
    }
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
