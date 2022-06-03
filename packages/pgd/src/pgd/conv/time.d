module pgd.conv.time;

package:

import std.datetime;

enum pgEpoch = Date(2000, 1, 1);
enum pgEpochJ = cast(int)pgEpoch.julianDay();
static assert(pgEpochJ == 2_451_545);

// postgres date is a int representing days since Date(2000, 1, 1)
// we use the julian routines from postgresql for conversions because
// they are more efficient than the gregorian based routines of phobos.

// FIXME check bounds

// this is from j2date from PostgreSQL source
// src/backend/utils/adt/datetime.c
Date julianToDate(uint julian) @safe
{
    julian += 32_044;
    uint quad = julian / 146_097;
    uint extra = (julian - quad * 146_097) * 4 + 3;
    julian += 60 + quad * 3 + extra / 146_097;
    quad = julian / 1461;
    julian -= quad * 1461;
    uint y = julian * 4 / 1461;
    julian = ((y != 0) ? ((julian + 305) % 365) : ((julian + 306) % 366))
        + 123;
    y += quad * 4;
    quad = julian * 2141 / 65_536;

    return Date(
        y - 4800,
        (quad + 10) % 12 + 1,
        julian - 7834 * quad / 256
    );
}

uint dateToJulian(Date date) @safe
{
    int y = date.year;
    int m = cast(int)date.month();
    int d = cast(int)date.day;

    if (m > 2)
    {
        m += 1;
        y += 4800;
    }
    else
    {
        m += 13;
        y += 4799;
    }

    const int century = y / 100;
    int julian = y * 365 - 32_167;
    julian += y / 4 - century + century / 4;
    julian += 7834 * m / 256 + d;

    return julian;
}
