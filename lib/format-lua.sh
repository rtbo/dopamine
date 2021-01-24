#! /bin/bash

LIBDIR="$( cd "$( dirname "${BASH_SOURCE[0]}" )" >/dev/null 2>&1 && pwd )"

find . -type f -name *.lua -exec lua-format -c "$LIBDIR/lua.format" -i {} \;
