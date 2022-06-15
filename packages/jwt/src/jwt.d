module jwt;

import vibe.data.json;

import std.algorithm;
import std.base64;
import std.datetime;
import std.digest.hmac;
import std.digest.sha;
import std.exception;
import std.string;
import std.typecons;

@safe:

enum Alg
{
    HS256,
}

long toJwtTime(SysTime time)
{
    return time.toUnixTime!long();
}

SysTime fromJwtTime(long jwtTime)
{
    return SysTime.fromUnixTime(jwtTime, UTC());
}

@("toJwtTime/fromJwtTime")
unittest
{
    const st = SysTime(DateTime(Date(2022, 06, 12), TimeOfDay(20, 11, 18)), UTC());
    const jt = 1_655_064_678;

    assert(fromJwtTime(jt) == st);
    assert(toJwtTime(st) == jt);
}

long jwtNow()
{
    return toJwtTime(Clock.currTime(UTC()));
}

/// Cause if failure verification
enum JwtVerifFailure
{
    /// The global structure of the token is not valid. E.g:
    /// - could not split in 3 parts `header.payload.signature`
    /// - base 64 decoding fails
    /// - JSON deserialization fails
    /// - the header does not have the expected fields
    structure,
    /// The `exp` field is now or in the past
    expired,
    /// The signature could not be verified
    signature,
}

/// Exception thrown when verification fails
class JwtException : Exception
{
    JwtVerifFailure cause;

    private this(JwtVerifFailure cause, string msg, string file = __FILE__, size_t line = __LINE__)
    {
        this.cause = cause;
        super(msg);
    }
}

struct Jwt
{
    private string _token;

    private this(string token)
    {
        _token = token;
    }

    static Jwt sign(Json payload, string secret, Alg alg = Alg.HS256)
    {
        const header = format!`{"alg":"%s","typ":"JWT"}`(alg.algToString());
        const toBeSigned = format!"%s.%s"(
            encodeBase64(header.representation), encodeBase64(payload.toString().representation)
        );
        const signature = doSign(alg, toBeSigned, secret);
        return Jwt(format!"%s.%s"(toBeSigned, signature));
    }

    /// Verify the token in the first argument using `secret` and options `opts`
    /// If verification fails a JwtException is thrown
    static Jwt verify(string token, string secret, VerifOpts opts = VerifOpts.init)
    {
        try
        {
            const jwt = Jwt(token);
            const header = jwt.header;
            const typJson = header["typ"];
            const algJson = header["alg"];
            enforce(
                typJson.type != Json.Type.undefined && algJson.type != Json.Type.undefined,
                new JwtException(
                    JwtVerifFailure.structure,
                    `Invalid JWT header: "typ" and "alg" fields are mandatory`),
            );
            enforce(
                typJson.get!string == "JWT",
                new JwtException(JwtVerifFailure.structure, "Invalid JWT header: not a JWT typ"),
            );

            const alg = stringToAlg(algJson.get!string);

            // decode the payload in all cases to generate an exception if JSON or base64 is invalid
            auto payload = jwt.payload;

            if (opts.checkExpired)
            {
                auto exp = payload["exp"];
                enforce(
                    exp.type != Json.Type.undefined,
                    new JwtException(JwtVerifFailure.structure, `missing "exp" field in payload`)
                );
                enforce(
                    exp.type == Json.Type.int_,
                    new JwtException(JwtVerifFailure.structure, `invalid "exp" field in payload`)
                );
                const expTime = exp.get!long;
                enforce(
                    expTime > jwtNow(),
                    new JwtException(JwtVerifFailure.expired, "JWT verification failed: expired")
                );
            }

            const toBeSigned = jwt._token[0 .. jwt.point2];

            enforce(
                jwt.signature == doSign(alg, toBeSigned, secret),
                new JwtException(JwtVerifFailure.signature, "JWT verification failed: signature mismatch")
            );

            return jwt;
        }
        catch (JwtException ex)
        {
            throw ex;
        }
        catch (Exception ex)
        {
            throw new JwtException(JwtVerifFailure.structure, ex.msg);
        }
    }

    @property string token() const
    {
        return _token;
    }

    string toString() const
    {
        return _token;
    }

    @property string headerBase64() const
    {
        return _token[0 .. point1];
    }

    @property string headerString() const
    {
        return decodeBase64(headerBase64);
    }

    @property Json header() const
    {
        return parseJsonString(headerString);
    }

    @property string payloadBase64() const
    {
        return _token[point1 + 1 .. point2];
    }

    @property string payloadString() const
    {
        return decodeBase64(payloadBase64);
    }

    @property Json payload() const
    {
        return parseJsonString(payloadString);
    }

    @property string signature() const
    {
        return _token[point2 + 1 .. $];
    }

    static struct VerifOpts
    {
        Flag!"checkExpired" checkExpired;
    }

    private size_t point1() const
    {
        return indexOf(_token, '.');
    }

    private @property size_t point2() const
    {
        return lastIndexOf(_token, '.');
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

    /// Warning: assume ordering of the json fields which is not guaranteed
    /// for the payload

    assert(jwt.token ==
            "eyJhbGciOiJIUzI1NiIsInR5cCI6IkpXVCJ9." ~
            "eyJlbWFpbCI6InRlc3RAZG9wYW1pbmUub3JnIiwic3ViIjoxMiwiZXhwIjoxNjU1MDY0Njc4fQ" ~
            ".23Fpp0DtZvJeqjIQ1aenzd0RHpy6aGQJYjxjf1JuDLw"
    );
    assert(jwt.headerString == `{"alg":"HS256","typ":"JWT"}`);
    assert(jwt.payloadString == `{"email":"test@dopamine.org","sub":12,"exp":1655064678}`);

    assertNotThrown(Jwt.verify(jwt.token, "test-secret"));
    assertThrown(Jwt.verify(jwt.token, "test-secret", Jwt.VerifOpts(Yes.checkExpired)));
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
