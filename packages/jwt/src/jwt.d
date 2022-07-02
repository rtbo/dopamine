/// Simple JWT implementation.
///
/// Only the HMAC-SHA256 signature / verify algorithm is provided.
///
/// Two main types are provided:
///  - Jwt: to be used on a server to sign a Json payload, or verify a JWT allegedly signed on the same server.
///  - ClientJwt: to be used on a client that received a JWT from a server and only want to read the payload.
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
    /// Some field in the payload is missing or has an unexpected value
    payload,
    /// The signature could not be verified
    signature,
}

/// Exception thrown when `Jwt.verify` fails, or if ill-formed token is passed to `ClientJwt`
class JwtException : Exception
{
    JwtVerifFailure cause;

    private this(string token, JwtVerifFailure cause, string reason, string file = __FILE__, size_t line = __LINE__)
    {
        import std.format : format;

        this.cause = cause;
        super(format!"Invalid token: %s\n%s"(reason, token));
    }

    private this(JwtVerifFailure cause, string msg, string file = __FILE__, size_t line = __LINE__)
    {
        this.cause = cause;
        super(msg);
    }
}

struct Jwt
{
    private string _token;

    private this(string token) nothrow
    {
        _token = token;
    }

    static Jwt sign(Json payload, string secret, Alg alg = Alg.HS256) nothrow
    {
        // in this function, only Json.toString() is not nothrow, probably due to the use
        // of Formatted write. But toString should not throw for any well constructed Json value
        string payloadString;
        auto ex = collectException!Exception(payload.toString(), payloadString);
        if (ex)
            assert(false);

        const header = `{"alg":"` ~ alg.algToString() ~ `","typ":"JWT"}`;
        const toBeSigned = encodeBase64(header.representation) ~ "." ~ encodeBase64(payloadString.representation);
        const signature = doSign(alg, toBeSigned, secret);
        return Jwt(toBeSigned ~ "." ~ signature);
    }

    ///
    static struct VerifOpts
    {
        /// checks that "exp" field of payload is in the future
        Flag!"checkExpired" checkExpired;

        /// if not empty, checks the "iss" field is one of the listed issuers
        string[] issuers;
    }

    /// Verify the token in the first argument using `secret` and options `opts`
    /// If verification fails a JwtException is thrown
    static Jwt verify(string token, string secret, VerifOpts opts = VerifOpts.init)
    {
        try
        {
            const p1 = indexOf(token, '.');
            const p2 = lastIndexOf(token, '.');

            enforce(
                p1 > 0 && (p2 - p1) > 0 && (token.length - p2) > 0,
                new JwtException(JwtVerifFailure.structure, "Could not parse 3 parties of JWT")
            );

            const header = parseJsonString(decodeBase64(token[0 .. p1]));
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
            auto payload = parseJsonString(decodeBase64(token[p1 + 1 .. p2]));

            const toBeSigned = token[0 .. p2];
            const signature = token[p2 + 1 .. $];

            enforce(
                signature == doSign(alg, toBeSigned, secret),
                new JwtException(JwtVerifFailure.signature, "JWT verification failed: signature mismatch")
            );

            if (opts.checkExpired)
            {
                auto exp = payload["exp"];
                enforce(
                    exp.type != Json.Type.undefined,
                    new JwtException(JwtVerifFailure.payload, `missing "exp" field in payload`)
                );
                enforce(
                    exp.type == Json.Type.int_,
                    new JwtException(JwtVerifFailure.payload, `invalid "exp" field in payload`)
                );
                const expTime = exp.get!long;
                enforce(
                    expTime > jwtNow(),
                    new JwtException(JwtVerifFailure.expired, "JWT verification failed: expired")
                );
            }

            if (opts.issuers)
            {
                auto iss = payload["iss"];
                enforce(
                    iss.type != Json.Type.undefined,
                    new JwtException(JwtVerifFailure.payload, `missing "iss" field in payload`),
                );
                enforce(
                    iss.type == Json.Type.string,
                    new JwtException(JwtVerifFailure.payload, `invalid "iss" field in payload`)
                );
                const issuer = iss.get!string;
                enforce(
                    opts.issuers.canFind(issuer),
                    new JwtException(JwtVerifFailure.payload, "JWT verification failed: invalid issuer")
                );
            }

            return Jwt(token);
        }
        catch (JwtException ex)
        {
            throw ex;
        }
        catch (Exception ex)
        {
            // this will be either Json or Base64 exceptions
            throw new JwtException(JwtVerifFailure.structure, ex.msg);
        }
    }

    @property string token() const nothrow
    {
        return _token;
    }

    string toString() const nothrow
    {
        return _token;
    }

    @property string headerBase64() const nothrow
    {
        return _token[0 .. point1];
    }

    // this function and some others can be nothrow because
    // Jwt is built with verified token string and because
    // constructor is private

    @property string headerString() const nothrow
    {
        scope (failure)
            assert(false);
        return decodeBase64(headerBase64);
    }

    @property Json header() const nothrow
    {
        scope (failure)
            assert(false);
        return parseJsonString(decodeBase64(headerBase64));
    }

    @property string payloadBase64() const nothrow
    {
        return _token[point1 + 1 .. point2];
    }

    @property string payloadString() const nothrow
    {
        scope (failure)
            assert(false);
        return decodeBase64(payloadBase64);
    }

    @property Json payload() const nothrow
    {
        scope (failure)
            assert(false);
        return parseJsonString(decodeBase64(payloadBase64));
    }

    @property string signature() const nothrow
    {
        return _token[point2 + 1 .. $];
    }

    private size_t point1() const nothrow
    {
        return indexOf(_token, '.');
    }

    private @property size_t point2() const nothrow
    {
        scope (failure)
            assert(false);
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

/// Similar to Jwt, but can be constructed directly from a string.
/// The token cannot be verified, thus some functions may throw exceptions
/// if the token is not a conform JWT.
struct ClientJwt
{
    private string _token;

    this(string token)
    {
        _token = token;

        const p1 = point1;
        const p2 = point2;

        enforce (
            p1 >= 1,
            new JwtException(token, JwtVerifFailure.structure, "No header found")
        );

        enforce (
            p2 < _token.length - 1,
            new JwtException(token, JwtVerifFailure.structure, "No signature found")
        );

        enforce (
            p1 < p2 - 1,
            new JwtException(token, JwtVerifFailure.structure, "No payload found")
        );
    }

    @property string token() const nothrow
    {
        return _token;
    }

    string toString() const nothrow
    {
        return _token;
    }

    @property string headerBase64() const nothrow
    {
        return _token[0 .. point1];
    }

    // this function and some others can be nothrow because
    // Jwt is built with verified token string and because
    // constructor is private

    @property string headerString() const
    {
        return decodeBase64(headerBase64);
    }

    @property Json header() const
    {
        return parseJsonString(decodeBase64(headerBase64));
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
        return parseJsonString(decodeBase64(payloadBase64));
    }

    @property string signature() const
    {
        return _token[point2 + 1 .. $];
    }

    private size_t point1() const nothrow
    {
        return indexOf(_token, '.');
    }

    private @property size_t point2() const
    {
        return lastIndexOf(_token, '.');
    }
}

private @property string algToString(Alg alg) nothrow
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

private string doSign(Alg alg, const(char)[] toBeSigned, const(char)[] secret) nothrow
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

private string encodeBase64(const(ubyte)[] data) @trusted nothrow
{
    return assumeUnique(cast(const(char)[]) Base64URLNoPadding.encode(data));
}
