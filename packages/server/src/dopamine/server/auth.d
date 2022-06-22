module dopamine.server.auth;

import dopamine.server.config;
import dopamine.server.db;
import dopamine.server.utils;

import jwt;
import pgd.conn;

import vibe.data.json;
import vibe.data.serialization;
import vibe.http.client;
import vibe.http.server;

import std.format;
import std.string;
import std.traits;

@safe:

alias Name = vibe.data.serialization.name;

enum Provider
{
    github = 0,
}

struct ProviderConfig
{
    string tokenUrl;
    string clientId;
    string clientSecret;
}

ProviderConfig[] providers;

shared static this()
{
    const config = Config.get;

    providers = new ProviderConfig[(EnumMembers!Provider).length];
    providers[Provider.github] = ProviderConfig(
        "https://github.com/login/oauth/access_token",
        config.githubClientId,
        config.githubClientSecret,
    );
}

struct TokenReq
{
    @Name("client_id") string clientId;
    @Name("client_secret") string clientSecret;
    string code;
    string state;
}

struct TokenResp
{
    @Name("token_type") string tokenType;
    @Name("access_token") string accessToken;
    @optional @Name("error_description") string errorDesc;
}

struct UserResp
{
    string email;
    string name;
    string avatarUrl;
}

@OrderedCols
struct UserRow
{
    int id;
    string email;
    string name;
    string avatarUrl;
}

void handleAuth(scope HTTPServerRequest req, scope HTTPServerResponse resp)
{
    const provider = toProvider(req.json["provider"].get!string);
    const code = req.json["code"].get!string;
    const state = req.json["state"].get!string;

    const config = providers[provider];

    TokenResp token;
    // dfmt off
    requestHTTP(
        config.tokenUrl,
        (scope HTTPClientRequest req) {
            req.method = HTTPMethod.POST;
            req.headers["Accept"] = "application/json";
            req.writeJsonBody(TokenReq(
                config.clientId,
                config.clientSecret,
                code,
                state
            ));
        },
        (scope HTTPClientResponse resp) {
            enforceStatus(
                resp.statusCode < 400, 403,
                "Could not request token to " ~ config.tokenUrl
            );
            deserializeJson(token, resp.readJson());
            enforceStatus(token.tokenType.toLower() == "bearer", 500,
                "Unsupported token type: " ~ token.tokenType
            );
            enforceStatus(!token.errorDesc, 403, token.errorDesc);
            enforceStatus(token.accessToken, 403, format!"Did not receive token from %s"(provider));
        }
    );
    // dfmt on

    auto userResp = provider.getUser(token.accessToken);

    const row = client.connect((scope DbConn db) {
        return db.execRow!UserRow(`
            INSERT INTO "user" (email, name, avatar_url)
            VALUES ($1, $2, $3)
            ON CONFLICT(email) DO
            UPDATE SET name = EXCLUDED.name, avatar_url = EXCLUDED.avatar_url
            WHERE "user".email = EXCLUDED.email
            RETURNING id, email, name, avatar_url
        `, userResp.email, userResp.name, userResp.avatarUrl);
    });

    auto payload = Json([
        "id": Json(row.id),
        "email": Json(row.email),
        "name": Json(row.name),
        "avatarUrl": Json(row.avatarUrl),
    ]);

    auto jwt = Jwt.sign(payload, Config.get.serverJwtSecret);

    resp.headers["Content-Type"] = "text/plain";
    resp.writeBody(jwt.toString());
}

UserResp getUser(Provider provider, string accessToken)
{
    final switch (provider)
    {
    case Provider.github:
        return getGithubUser(accessToken);
    }
}

struct GithubUserResp
{
    string email;
    string name;
    @Name("avatar_url") string avatarUrl;
}

UserResp getGithubUser(string accessToken)
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

Provider toProvider(string provider)
{
    switch (provider)
    {
    case "github":
        return Provider.github;
    default:
        throw new StatusException(400, "Unknown provider: " ~ provider);
    }
}
