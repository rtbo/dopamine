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

@safe:

alias Name = vibe.data.serialization.name;

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

enum idTokenDuration = dur!"seconds"(3600);
enum refreshTokenDuration = dur!"days"(2);

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
    }

    void auth(scope HTTPServerRequest req, scope HTTPServerResponse resp)
    {
        const provider = toProvider(req.json["provider"].get!string);

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

        auto refreshToken = Base64.encode(cryptoRandomBytes(32)).idup;
        auto refreshTokenExp = Clock.currTime + refreshTokenDuration;

        const row = client.transac((scope DbConn db) {
            const userRow = db.execRow!UserRow(`
                INSERT INTO "user" (email, name, avatar_url)
                VALUES ($1, $2, $3)
                ON CONFLICT(email) DO
                UPDATE SET name = EXCLUDED.name, avatar_url = EXCLUDED.avatar_url
                WHERE "user".email = EXCLUDED.email
                RETURNING id, email, name, avatar_url
            `, userResp.email, userResp.name, userResp.avatarUrl);

            const rt = db.execScalar!string(`
                    INSERT INTO refresh_token (token, user_id, expiration, revoked)
                    VALUES ($1, $2, $3, FALSE)
                    RETURNING token
                `, refreshToken, userRow.id, refreshTokenExp
            );

            enforce(rt == refreshToken, "Could not store refresh token in DB");

            return userRow;
        });

        auto payload = Json([
            "iss": Json(Config.get.serverHostname),
            "sub": Json(row.id),
            "exp": Json((Clock.currTime + idTokenDuration).toUTC().toISOExtString()),
            "email": Json(row.email),
            "name": Json(row.name),
            "avatarUrl": Json(row.avatarUrl),
        ]);

        auto idToken = Jwt.sign(payload, Config.get.serverJwtSecret);

        resp.writeJsonBody(Json([
            "idToken": Json(idToken.toString()),
            "refreshToken": Json(refreshToken),
            "refreshTokenExp": Json(refreshTokenExp.toUTC().toISOExtString()),
        ]));
    }

    UserResp authImpl(Provider provider)(Json req, ProviderConfig config)
    {
        const code = req["code"].get!string;
        const redirectUri = req["redirectUri"].get!string;

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
}

private struct UserResp
{
    string email;
    string name;
    string avatarUrl;
}

@OrderedCols
private struct UserRow
{
    int id;
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

int enforceAuth(scope HTTPServerRequest req) @safe
{
    const config = Config.get;

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
        const jwt = Jwt.verify(head[bearer.length .. $].strip(), config.serverJwtSecret);
        return jwt.payload["sub"].get!int;
    }
    catch (JwtException ex)
    {
        if (ex.cause == JwtVerifFailure.structure)
            statusError(400, "Ill-formed authorization header");
        else
            statusError(403, "Invalid or expired authorization token");
    }
}