#!/bin/bash
# build a snapshot zip 
OSTYPE=`uname -o`
if [ "$OSTYPE" = "Msys" ] ; then
	OS="win32"
	EXE=".exe"
else 
	OS=`uname -sm | sed -e 's/ /-/'`
	EXE=""
fi
REV=`svnversion  . | sed -e 's/:/-/'`
ZIPNAME="chdkptp-r$REV-$OS.zip"
echo $ZIPNAME
if [ -f "$ZIPNAME" ] ; then
	rm -f "$ZIPNAME"
fi

PROG="chdkptp$EXE"
make DEBUG="" clean all
strip "$PROG"
zip "$ZIPNAME" "$PROG" chdkptp-sample.sh \
	lua/chdku.lua lua/cli.lua lua/gui.lua lua/main.lua lua/util.lua lua/fsutil.lua lua/rlibs.lua \
	README.TXT USAGE.TXT COPYING THANKS.TXT
