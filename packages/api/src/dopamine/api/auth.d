module dopamine.api.auth;

import dopamine.api.attrs;

import vibe.data.serialization;

import std.datetime;
import std.typecons;

struct AuthToken
{
    string idToken;
    string refreshToken;
    @optional long refreshTokenExpJs;

    string email;
    @optional string name;
    @optional string avatarUrl;
}

@Request(Method.POST, "/auth/token")
@Response!AuthToken
struct PostAuthToken
{
    string refreshToken;
}
