#! /bin/bash

THISDIR="$( cd "$( dirname "${BASH_SOURCE[0]}" )" >/dev/null 2>&1 && pwd )"
DOPROOT=$( dirname "$THISDIR" )

find "$DOPROOT" -type f -name *.lua -exec stylua --config-path "$DOPROOT/stylua.toml" {} \;
