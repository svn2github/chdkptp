#!/bin/bash
# build a snapshot zip 
name=`basename "$0"`

function error_exit {
	echo "$name error: $1" >&2
	exit 1
}

CHDKPTP_DIR=../chdkptp
LUA51_SRC=lua-5.1.5
LUA52_SRC=lua-5.2.3

ZIPNAME=chdkptp-raspbian-libs-`date +%Y%m%d`.zip

function warn {
	echo "$name warning: $1" >&2
}

function usage {
	[ "$1" ] && warn "$1"
	cat >&2 <<EOF
create a distribution tree and zip of Lua, IUP and CD binaries
usage:
	$name [-nozip]
options:
	-nozip: only create the stage directory, don't zip

EOF
	exit 1
}

arg="$1"
debug=""
while [ ! -z "$arg" ] ; do
	case $arg in
	-nozip)
		nozip=1
	;;
	*)
		usage "unknown option $arg"
	;;
	esac
	shift
	arg="$1"
done

for dir in lua5.1 lua52 im iup "$CHDKPTP_DIR" ; do
	if [ ! -d "$dir" ] ; then
		error_exit "missing dir: $dir"
	fi
done

if [ -z "$nozip" ] ; then
	echo $ZIPNAME
	if [ -f "$ZIPNAME" ] ; then
		echo "removing existing $ZIPNAME"
		rm -f "$ZIPNAME"
	fi
fi


if [ -d stage ] ; then
	echo "removing old stage"
	rm -rf stage
fi

mkdir stage

# include libs and includes to allow users to build their own chdkptp
for lib in cd iup ; do
	mkdir -p stage/$lib/{lib,include}
	cp $lib/COPYRIGHT stage/$lib
	echo "$lib lib"
	cp $lib/lib/Linux310/* stage/$lib/lib
	echo "$lib include"
	cp $lib/include/* stage/$lib/include
done

for lib in lua5.1 lua52 ; do
	mkdir -p stage/$lib/{lib,include,bin}
	echo "$lib lib"
	cp $lib/lib/*.a stage/$lib/lib
	echo "$lib include"
	cp $lib/include/* stage/$lib/include
	echo "$lib bin"
	cp $lib/bin/* stage/$lib/bin
done

cp "$LUA51_SRC"/COPYRIGHT stage/lua5.1

mkdir stage/lua52/doc
cp "$LUA51_SRC"/doc/* stage/lua52/doc

cp "$CHDKPTP_DIR"/README-RASPI-LIBS.TXT stage
cp "$CHDKPTP_DIR"/misc/tecmake.mak.patch stage

echo files copied

if [ -z "$nozip" ] ; then
	cd stage
	zip -r ../"$ZIPNAME" *
fi
