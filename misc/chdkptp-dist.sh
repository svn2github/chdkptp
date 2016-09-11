#!/bin/sh
# shell script wrapper for self contained CLI install
CHDKPTP_EXE=chdkptp
# path where chdkptp is installed
CHDKPTP_DIR="$(dirname "$(readlink "$0")")"
# set lua path
export LUA_PATH="$CHDKPTP_DIR/lua/?.lua"
"$CHDKPTP_DIR/$CHDKPTP_EXE" "$@"
