#! /bin/bash

THISDIR="$( cd "$( dirname "${BASH_SOURCE[0]}" )" >/dev/null 2>&1 && pwd )"
DOPROOT=$( dirname "$THISDIR" )

find "$DOPROOT" -type f -name *.lua -exec lua-format -c "$THISDIR/lua.format" -i {} \;
