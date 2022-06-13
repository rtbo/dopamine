module jwt;

import vibe.data.json;

import std.algorithm;
import std.base64;
import std.datetime.systime;
import std.digest.hmac;
import std.digest.sha;
import std.exception;
import std.string;

@safe:

enum Alg
{
    HS256,
}

struct Jwt
{
    string token;

    static Jwt sign(Json payload, string secret, Alg alg = Alg.HS256)
    {
        const header = format!`{"alg":"%s","typ":"JWT"}`(alg.algToString());
        const toBeSigned = format!"%s.%s"(
            encodeBase64(header.representation), encodeBase64(payload.toString().representation)
        );
        const signature = doSign(alg, toBeSigned, secret);
        return Jwt(format!"%s.%s"(toBeSigned, signature));
    }

    string toString() const
    {
        return token;
    }

    @property string headerBase64() const
    in (isToken)
    {
        return token[0 .. point1];
    }

    @property string headerString() const
    {
        return decodeBase64(headerBase64);
    }

    @property Json headerJson() const
    {
        return parseJsonString(headerString);
    }

    @property string payloadBase64() const
    in (isToken)
    {
        return token[point1 + 1 .. point2];
    }

    @property string payloadString() const
    {
        return decodeBase64(payloadBase64);
    }

    @property Json payloadJson() const
    {
        return parseJsonString(payloadString);
    }

    @property string signature() const
    in (isToken)
    {
        return token[point2 + 1 .. $];
    }

    /// verify the token
    bool verify(string secret) const
    in (isToken)
    {
        const header = headerJson;
        const typJson = header["typ"];
        const algJson = header["alg"];
        enforce(
            typJson.type != Json.Type.undefined && algJson.type != Json.Type.undefined,
            "Ill-formed JWT header"
        );
        enforce(
            typJson.get!string == "JWT",
            "Not a JWT",
        );

        const alg = stringToAlg(algJson.get!string);

        const toBeSigned = token[0 .. point2];
        return signature == doSign(alg, toBeSigned, secret);
    }

    private size_t point1() const
    {
        return indexOf(token, '.');
    }

    private @property size_t point2() const
    {
        return lastIndexOf(token, '.');
    }

    private bool isToken() const
    {
        if (!token.length)
            return false;
        if (token.count('.') != 2)
            return false;
        const p1 = point1;
        const p2 = point2;
        return p1 > 1 && p2 > (p1 + 1) && token.length > (p2 + 1);
    }
}

///
@("Jwt")
unittest
{
    const secret = "test-secret";

    auto payload = Json([
        "sub": Json(12),
        "email": Json("test@dopamine.org"),
        "exp": Json(1_655_064_678),
    ]);

    const jwt = Jwt.sign(payload, secret, Alg.HS256);

    assert(jwt.token ==
        "eyJhbGciOiJIUzI1NiIsInR5cCI6IkpXVCJ9." ~
            "eyJlbWFpbCI6InRlc3RAZG9wYW1pbmUub3JnIiwic3ViIjoxMiwiZXhwIjoxNjU1MDY0Njc4fQ" ~
            ".23Fpp0DtZvJeqjIQ1aenzd0RHpy6aGQJYjxjf1JuDLw"
    );
    assert(jwt.headerString == `{"alg":"HS256","typ":"JWT"}`);
    assert(jwt.payloadString == `{"email":"test@dopamine.org","sub":12,"exp":1655064678}`);
    assert(jwt.verify("test-secret"));
}

private @property string algToString(Alg alg)
{
    final switch (alg)
    {
    case Alg.HS256:
        return "HS256";
    }
}

private @property Alg stringToAlg(string alg)
{
    switch (alg)
    {
    case "HS256":
        return Alg.HS256;
    default:
        throw new Exception("Unsupported signature algorithm: " ~ alg);
    }
}

private string doSign(Alg alg, const(char)[] toBeSigned, const(char)[] secret)
{
    final switch (alg)
    {
    case Alg.HS256:
        return toBeSigned.representation
            .hmac!SHA256(secret.representation)
            .encodeBase64();
    }
}

private string decodeBase64(const(char)[] base64) @trusted
{
    return assumeUnique(cast(const(char)[]) Base64URLNoPadding.decode(base64));
}

private string encodeBase64(const(ubyte)[] data) @trusted
{
    return assumeUnique(cast(const(char)[]) Base64URLNoPadding.encode(data));
}
