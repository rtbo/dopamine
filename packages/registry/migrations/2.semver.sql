CREATE FUNCTION semver_major(ver text)
RETURNS text
LANGUAGE plpgsql
IMMUTABLE
AS
$$
BEGIN
    RETURN split_part(ver, '.', 1);
END
$$;

CREATE FUNCTION semver_minor(ver text)
RETURNS text
LANGUAGE plpgsql
IMMUTABLE
AS
$$
BEGIN
    RETURN split_part(ver, '.', 2);
END
$$;

CREATE FUNCTION semver_patch(ver text)
RETURNS text
LANGUAGE plpgsql
IMMUTABLE
AS
$$
BEGIN
    RETURN (regexp_matches(ver, '(\d+)\.(\d+)\.(\d+)(-([^+]+))?(\+(.*))?'))[3];
END
$$;

CREATE FUNCTION semver_prerelease(ver text)
RETURNS text
LANGUAGE plpgsql
IMMUTABLE
AS
$$
BEGIN
    RETURN (regexp_matches(ver, '(\d+)\.(\d+)\.(\d+)(-([^+]+))?(\+(.*))?'))[5];
END
$$;

CREATE FUNCTION semver_order_str(ver text)
RETURNS text
LANGUAGE plpgsql
IMMUTABLE
AS
$$
DECLARE
    major text;
    minor text;
    patch text;
    prerelease text;
BEGIN
    major := semver_major(ver);
    minor := semver_minor(ver);
    patch := semver_patch(ver);
    prerelease := coalesce(semver_prerelease(ver), '');

    RETURN lpad(major, 5, '0') || lpad(minor, 5, '0') || lpad(patch, 5, '0') || rpad(prerelease, 10, 'z');
END
$$;
