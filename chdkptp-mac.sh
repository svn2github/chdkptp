#!/bin/sh
# copy this file to chdkptp.sh and adjust for your configuration
# to use the GUI build from a binary package that includes both CLI and GUI change to chdkptp_gui
CHDKPTP_EXE=chdkptp

# path where chdkptp is installed
# osx has no obvious shell way to get an absolute path
selfpath=$(python <<EOF
import os.path
print os.path.abspath('$0')
EOF
)
CHDKPTP_DIR=$(dirname "$selfpath")
# if you don't want to fire up python every time, you could hard-code it instead
#CHDKPTP_DIR=$HOME/CHDK/chdkptp


# path for shared libraries
export DYLD_LIBRARY_PATH="$CHDKPTP_DIR/lib"

export LUA_PATH="$CHDKPTP_DIR/lua/?.lua;;"
export LUA_CPATH="$CHDKPTP_DIR/?.so;;"

"$CHDKPTP_DIR/$CHDKPTP_EXE" "$@"
