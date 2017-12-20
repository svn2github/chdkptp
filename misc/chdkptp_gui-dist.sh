#!/bin/sh
# shell script wrapper for self contained GUI install
CHDKPTP_EXE=chdkptp_gui
# path where chdkptp is installed
CHDKPTP_DIR="$(dirname "$(readlink -f "$0")")"
# LD_LIBRARY_PATH for shared libraries, assumed to be in lib sudir
export LD_LIBRARY_PATH="$CHDKPTP_DIR/lib"
# set lua paths, double ; appends default
export LUA_PATH="$CHDKPTP_DIR/lua/?.lua;;"
export LUA_CPATH="$CHDKPTP_DIR/?.so;;"
"$CHDKPTP_DIR/$CHDKPTP_EXE" "$@"
