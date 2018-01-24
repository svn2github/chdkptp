#!/bin/bash
# download and configure external sources and binaries
selfname=`basename "$0"`

# osx doesn't have readlink -f, want before main OS init...
# python should always be present
if [ "$(uname -s)" == 'Darwin' ] ; then
	selfdir=$(python <<EOF
import os.path
print os.path.abspath('$0')
EOF
)
	selfdir=$(dirname "$selfdir")
else
	selfdir="$(dirname "$(readlink -f "$0")")"
fi

error_exit() {
	echo "$selfname error: $1" >&2
	exit 1
}

warn() {
	echo "$selfname warning: $1" >&2
}

info_msg() {
	echo "### $1 ###" >&2
}

usage() {
	[ "$1" ] && warn "$1"
	cat >&2 <<EOF
This script attempts to download, configure and the build external dependencies
which are not typically available as OS packages.

Usage:
 $selfname [options]

General options:
 -pretend: print actions without doing them
 -d=<directory>: set root directory, default <chdkptp source>/extlibs
 -force-tec-src: build tecgraf libraries (IUP/CD) from source, even if binaries
                 available. Not supported on windows
 -nogui: do not download, extract, build GUI related files
 -redl: re-download files even if they exist

Options controlling which actions are performed:
 -nodl: skip downloads
 -noextract: do not extract / prepare source and binary archives
 -nobuild: do not build source components
 -nocopy: do not copy built components to locations expected by later build steps
 -nocopyrt: do not copy runtime libraries to chdkptp/lib

Misc tuning / debugging options
 -ignore-ssl-err: make wget ignore ssl errors on download
 -force-os=<os>: set OS to <os> instead of detecting. Supported values:
                 Linux, Windows, Darwin
 -force-arch=<arch>: set CPU arch to <arch>. Supported values:
                 i686, x86_64, armv6l
 -tec-linver=<ver>: set linux version for downloaded binary packages, e.g 313
                    for kernel 3.13. Valid values depend on what tecgraf built,
                    see tecgraf download pages
 -tec-freetype-src: Force using freetype from tecgraf source

Prerequisites: (Deb = Debian-ish package names, Fed=Fedora-ish, YMMV)
* Normal development stuff
 Deb: build-essential
 Fed: groups "Development Tools", "C Development Tools and Libraries"
* wget - You can download manually using URLs listed by pretend
* unzip (Info-ZIP compatible)
* On Windows, mingw MSYS or MSYS2 is assumed
* Development packages on *nix
 All builds
  Deb: libusb-dev, libreadline-dev
  Fed: libusb-devel, readline-devel
 CD/IUP precompiled
  Deb: libfreetype6-dev
  Fed: freetype-devel
 CD/IUP from source
  Deb: g++ libfreetype6-dev libgtk-3-dev libx11-dev libxpm-dev libxmu-dev libxft-dev
  Fed: gcc-c++ freetype-devel gtk3-devel libX11-devel libXpm-devel libXmu-devel libXft-devel
 Freetype may be built from source instead, using -tec-freetype-src
 Readline is optional in chdkptp, but expected by the default Lua build

EOF
	exit 1
}

init_vars() {
	CHDKPTP_DIR="$(dirname "$selfdir")"
	if [ -z "$opt_dir" ] ; then
		EXTDEP_DIR="$CHDKPTP_DIR/extlibs"
	else
		EXTDEP_DIR="$opt_dir"
	fi

	PKG_DIR="$EXTDEP_DIR/archive"
	SRC_DIR="$EXTDEP_DIR/src"
	BUILT_DIR="$EXTDEP_DIR/built"
	LOG_DIR="$BUILT_DIR"
	# versions expected current chdkptp builds
	LUA_VER="5.2.4"
	LUA_VER_SFX="52"
	LUA_VER_DIR="lua${LUA_VER_SFX}"
	# caps
	TEC_LUA_SFX="Lua${LUA_VER_SFX}"
	IUP_VER="3.21"
	CD_VER="5.11"
	# IM is not needed for the the CD/IUP features currently used
	# IM_VER="3.12"

	# TODO kernel version targeted for linux tec libs. Could base major on uname output
	# availability varies for 32 and 64 bit
	TEC_PKG_LINVER64="313"
	TEC_PKG_LINVER32="32"
	LIBUSBWIN32_VER="1.2.6.0"

	LUA_SRC_PKG="lua-${LUA_VER}.tar.gz"
	IUP_SRC_PKG="iup-${IUP_VER}_Sources.tar.gz"
	CD_SRC_PKG="cd-${CD_VER}_Sources.tar.gz"
	# only needed for OSX, can be forced on others
	FREETYPE_SRC_PKG="freetype-2.6.3_Sources.zip"
	if [ -z "$opt_tec_freetype_src" ] ; then
		USE_FREETYPE_SRC=""
	else
		USE_FREETYPE_SRC=1
	fi
	# IM_SRC_PKG="im-${IM_VER}_Sources.tar.gz"

	# platform requires IUP/CD built from source
	TEC_SOURCE_BUILD=""
	if [ ! -z "$opt_force_tec_src" ] ; then
		TEC_SOURCE_BUILD="1"
	fi
	if [ ! -z "$opt_tec_linver" ] ; then
		TEC_PKG_LINVER="$opt_tec_linver"
	fi
}

init_os() {
	if [ -z "$opt_force_os" ] ; then
		BUILD_OS="$(uname -s)"
		# mingw puts windows version after
		if [ ${BUILD_OS:0:5} == 'MINGW' ] ; then
			BUILD_OS="Windows"
		fi
	else
		BUILD_OS="$opt_force_os"
	fi
	if [ -z "$opt_force_arch" ] ; then
		# msys2 32 bit env still identifies as x64 in uname
		if [ "$BUILD_OS" == 'Windows'  -a ! -z "$MSYSTEM_CARCH" ] ; then
			BUILD_ARCH="$MSYSTEM_CARCH"
		else
			BUILD_ARCH="$(uname -m)"
		fi
	else
		BUILD_ARCH="$opt_force_arch"
	fi

	case "$BUILD_OS" in
	Windows)
		if [ "$BUILD_ARCH" == 'i686' ] ; then
			TEC_LIB_SFX="Win32_mingw4_lib.zip"
		elif [ "$BUILD_ARCH" == 'x86_64' ] ; then
			TEC_LIB_SFX="Win64_mingw4_lib.zip"
		else
			error_exit "Unsupported Windows arch $BUILD_ARCH"
		fi
		LIBUSBWIN32_PKG="libusb-win32-bin-${LIBUSBWIN32_VER}.zip"
		LUA_TARGET="mingw"
	;;
	Linux)
		LUA_TARGET="linux"
		# for built subdirs. Could try to use to guess TEC_PKG_LINVER
		KERN_MAJOR="$(uname -r | sed -e 's/^\([0-9]\+\).*/\1/')"
		KERN_MINOR="$(uname -r | sed -e 's/^\([0-9]\+\)\.\([0-9]\+\).*/\2/')"
		case "$BUILD_ARCH" in 
		i686)
			if [ -z "$TEC_PKG_LINVER" ] ; then
				TEC_PKG_LINVER="$TEC_PKG_LINVER32"
			fi
			TEC_LIB_SFX="Linux${TEC_PKG_LINVER}_lib.tar.gz"
			TEC_UNAME="Linux${KERN_MAJOR}${KERN_MINOR}"
		;;
		x86_64)
			if [ -z "$TEC_PKG_LINVER" ] ; then
				TEC_PKG_LINVER="$TEC_PKG_LINVER64"
			fi
			TEC_LIB_SFX="Linux${TEC_PKG_LINVER}_64_lib.tar.gz"
			TEC_UNAME="Linux${KERN_MAJOR}${KERN_MINOR}_64"
		;;
		armv6l)
			# TODO newer pis are 7l or aarch64?
			TEC_SOURCE_BUILD=1
			# for bin names
			TEC_UNAME="Linux${KERN_MAJOR}${KERN_MINOR}_arm"
		;;
		*)
			error_exit "Unsupported Linux arch $BUILD_ARCH"
		;;
		esac
	;;
	Darwin)
		# no particular reason 32 couldn't be supported, but all recent should be 64?
		if [ "$BUILD_ARCH" != 'x86_64' ] ; then
			error_exit "Unsupported Darwin arch $BUILD_ARCH"
		fi
		TEC_SOURCE_BUILD=1
		USE_FREETYPE_SRC=1
		LUA_TARGET="macosx"
		TEC_UNAME="MacOS$(sw_vers -productVersion | awk '{printf("%s%s\n",substr($1,1,2),substr($1,4,2))}')"
	;;
	*)
		error_exit "Unsupported OS $BUILD_OS"
	;;
	esac

	if [ -z "$TEC_SOURCE_BUILD" ] ; then
		IUP_PKG="iup-${IUP_VER}_${TEC_LIB_SFX}"
		IUP_LUA_PKG="iup-${IUP_VER}-${TEC_LUA_SFX}_${TEC_LIB_SFX}"
		CD_PKG="cd-${CD_VER}_${TEC_LIB_SFX}"
		CD_LUA_PKG="cd-${CD_VER}-${TEC_LUA_SFX}_${TEC_LIB_SFX}"
	fi

}

do_rm() {
	echo "rm $*"
	if [ -z "$pretend" ] ; then
		rm "$@" || error_exit "rm $*"
	fi
}

create_dir() {
	echo "mkdir -p $*"
	if [ -z "$pretend"  ]; then
		mkdir -p "$@"
	fi
}

remove_dir() {
	local dir="$1"
	# sanity check against bad variable names...
	if [ "$dir" == '/' -o "${#dir}" -lt 4 ] ; then
		error "refusing to remove $dir"
	fi
	if [ -d "$dir" ] ; then
		do_rm -rf "$dir"
	fi
}
recreate_dir() {
	local dir="$1"
	remove_dir "$dir"
	create_dir "$dir"
}

do_cp() {
	echo "cp $*"
	if [ -z "$pretend"  ]; then
		cp "$@"
	fi
}


change_dir() {
	if [ ! -z "$pretend" ] ; then
		echo "cd $1"
	else
		cd "$1" || error_exit "cd $1 failed"
	fi
}

do_dlltool() {
	if [ ! -z "$pretend" ] ; then
		echo "dlltool $*"
	else
		dlltool "$@" || error_exit "dlltool $* failed"
	fi
}

# extract zip or gzip'd tar to specified directory
extract() {
	local src="$1"
	local dst="$2"
	local cmd="tar -xzf"
	local dst_opt='-C'

	if [ -z "$dst" ] ; then
		dst="."
	fi
	if [ "${src##*.}" == 'zip' ] ; then
		# -o because iup / iuplua packages have duplicated etc content
		cmd='unzip -o'
		dst_opt="-d"
	fi
	if [ ! -d "$dst" ] ; then
		create_dir "$dst"
	fi
	# always echo to show status, tar is quiet
	echo "$cmd $src $dst_opt $dst"
	if [ -z "$pretend" ] ; then
		$cmd "$src" $dst_opt "$dst" || error_exit "extract $src"
	fi
}

create_tree() {
	create_dir "$EXTDEP_DIR"/{archive,src,built}
}

do_wget() {
	local url="$1"
	local fname="$2"

	if [ ! -z "$opt_ignore_ssl_err" ] ; then
		ssl_opt='--no-check-certificate'
	else
		ssl_opt=''
	fi
	# wget doesn't have a good "just clobber the damn file" option
	if [ -f "$PKG_DIR/$fname" ] ; then
		# TODO could do wget -N timestamping or md5sums of known files
		if [ -z "$opt_redl" ] ; then
			echo "skip download existing: $fname"
			return
		fi
		do_rm "$PKG_DIR/$fname"
	fi
	if [ -z "$pretend" ] ; then
		wget $ssl_opt -P "$PKG_DIR" "$url/$fname" || error_exit "do_wget $ssl_opt -P $PKG_DIR $url/$fname"
	else
		echo "wget $ssl_opt -P $PKG_DIR $url/$fname"
	fi
}

do_download() {
	info_msg "downloading packages"

	do_wget "https://www.lua.org/ftp" "$LUA_SRC_PKG"

	local SF_URL="https://sourceforge.net/projects"
	local CD_URL_ROOT="${SF_URL}/canvasdraw/files/${CD_VER}"
	local IUP_URL_ROOT="${SF_URL}/iup/files/${IUP_VER}"
	if [ "$TEC_SOURCE_BUILD" == '1' ] ; then
		if [ -z "$nogui" ] ; then
			do_wget "${CD_URL_ROOT}/Docs%20and%20Sources" "${CD_SRC_PKG}"
			do_wget "${IUP_URL_ROOT}/Docs%20and%20Sources" "${IUP_SRC_PKG}"
			# OSX needs freetype
			if [ ! -z "$USE_FREETYPE_SRC" ] ; then
				do_wget "${IUP_URL_ROOT}/Docs%20and%20Sources" "${FREETYPE_SRC_PKG}"
			fi
		fi
	else
		local TEC_SUBDIR="Linux%20Libraries"
		
	      	if [ "$BUILD_OS" == 'Windows' ] ; then
			do_wget "${SF_URL}/libusb-win32/files/libusb-win32-releases/${LIBUSBWIN32_VER}" \
				"${LIBUSBWIN32_PKG}"
			TEC_SUBDIR="Windows%20Libraries/Static"
		fi
		do_wget "${CD_URL_ROOT}/${TEC_SUBDIR}" "${CD_PKG}"
		do_wget "${CD_URL_ROOT}/${TEC_SUBDIR}/${TEC_LUA_SFX}" "${CD_LUA_PKG}"
		do_wget "${IUP_URL_ROOT}/${TEC_SUBDIR}" "${IUP_PKG}"
		do_wget "${IUP_URL_ROOT}/${TEC_SUBDIR}/${TEC_LUA_SFX}" "${IUP_LUA_PKG}"
	fi
}

extract_pkgs() {
	local LIBUSB_DEF="$CHDKPTP_DIR/misc/libusb-win32-${LIBUSBWIN32_VER}-libusb0.def"
	local LIBUSB_DIR="$BUILT_DIR/libusb-win32-bin-${LIBUSBWIN32_VER}"

	info_msg "unpacking downloads"
	remove_dir "$SRC_DIR/lua-${LUA_VER}"
	extract "$PKG_DIR/$LUA_SRC_PKG" "$SRC_DIR"
	if [ "$TEC_SOURCE_BUILD" == '1' ] ; then
		if [ -z "$nogui" ] ; then
			# each package has subdir
			remove_dir "$SRC_DIR/cd"
			extract "$PKG_DIR/$CD_SRC_PKG" "$SRC_DIR"
			remove_dir "$SRC_DIR/iup"
			extract "$PKG_DIR/$IUP_SRC_PKG" "$SRC_DIR"
			# OSX needs freetype
			if [ ! -z "$USE_FREETYPE_SRC" ] ; then
				remove_dir "$SRC_DIR/freetype"
				extract "$PKG_DIR/${FREETYPE_SRC_PKG}" "$SRC_DIR"
			fi
		fi
	else
		if [ "$BUILD_OS" == 'Windows' ] ; then
			# subdir is in zip
			remove_dir "$LIBUSB_DIR"
			extract "$PKG_DIR/$LIBUSBWIN32_PKG" "$BUILT_DIR"
			# libusbwin32 package doesn't contain a gcc x64 import lib
			if [ "$BUILD_ARCH" == 'x86_64' ] ; then
				if [ ! -f "$LIBUSB_DEF" ] ; then
					warn "missing ${LIBUSB_DEF} skipping import library"
				else
					recreate_dir "${LIBUSB_DIR}/lib/gcc_x64"
					do_dlltool -l "${LIBUSB_DIR}/lib/gcc_x64/libusb.a" -D libusb0.dll -d "$LIBUSB_DEF"
				fi
			fi
		fi
		if [ -z "$nogui" ] ; then
			remove_dir "$BUILT_DIR/cd"
			extract "$PKG_DIR/$CD_PKG" "$BUILT_DIR/cd"
			# lua libs extract to same dir as iup/cd, not luaxx subdir
			extract "$PKG_DIR/$CD_LUA_PKG" "$BUILT_DIR/cd"
			remove_dir "$BUILT_DIR/iup"
			extract "$PKG_DIR/$IUP_PKG" "$BUILT_DIR/iup"
			extract "$PKG_DIR/$IUP_LUA_PKG" "$BUILT_DIR/iup"
		fi
	fi
}

do_patch() {
	local srcdir="$1"
	local patchfile="$2"
	local stripdirs="$3"
	if [ -z "$stripdirs" ] ; then
		stripdirs="0"
	fi
	echo "patch -d $srcdir -p${stripdirs} < $patchfile"
	if [ -z "$pretend" ] ; then
		patch -d "$srcdir" -p${stripdirs} < "$patchfile" || error_exit "patch failed $srcdir $patchfile"
	fi
}

prepare_source() {
	if [ "$BUILD_OS" == 'Linux' -a "$BUILD_ARCH" == 'armv6l' -a -z "$nogui" ] ; then
		for d in cd iup ; do
			do_patch "$SRC_DIR/$d" "$CHDKPTP_DIR"/misc/armv6l-tecmake.mak.patch
		done
	fi
	if [ "$BUILD_OS" == 'Darwin' -a -z "$nogui" ] ; then
		for d in freetype cd iup ; do
			do_patch "$SRC_DIR/$d" "$CHDKPTP_DIR"/misc/macports-tecmake.mak.patch
		done
	fi
}

do_make() {
	local log="$LOG_DIR/$1"
	shift
	if [ -z "$pretend" ] ; then
		make "$@" > "$log" 2>&1 || error_exit "make $*"
	else
		echo "make $* > "$log" 2>&1"
	fi
}

do_slink() {
	echo "ln -s $*"
	if [ -z "$pretend" ] ; then
		ln -s "$@" || error_exit "ln -s $*"
	fi
}

build_lua() {
	info_msg "building Lua"
	change_dir "$SRC_DIR/lua-$LUA_VER"
	do_make build-lua.log "$LUA_TARGET"
}

copy_built_lua() {
	info_msg "configure Lua binaries"
	change_dir "$SRC_DIR/lua-$LUA_VER"
	remove_dir "$BUILT_DIR"/"$LUA_VER_DIR"
	do_make install-lua.log INSTALL_TOP="$BUILT_DIR"/"$LUA_VER_DIR" install
	# tec libs seem to require suffix, can't force empty
	if [ "$BUILD_OS" == 'Linux' ] ; then
		change_dir "$BUILT_DIR"/"${LUA_VER_DIR}"/lib
		do_slink -f liblua.a liblua"${LUA_VER_SFX}".a
	fi
	if [ "$BUILD_OS" == 'Darwin' ] ; then
		change_dir "$BUILT_DIR"/"${LUA_VER_DIR}"/lib
		if [ -z "$pretend" ] ; then
			g++ -fpic -shared -Wl,-all_load liblua.a -Wl,-noall_load -o liblua.dylib
		else
			echo "g++ -fpic -shared -Wl,-all_load liblua.a -Wl,-noall_load -o liblua.dylib"
		fi
		do_slink -f liblua.dylib liblua"${LUA_VER_SFX}".dylib
	fi
}

make_tec() {
	local log="$1"
	shift
	# common values
	local makevars=(
		USE_PKGCONFIG=Yes
		USE_LUA52=Yes
		LUA_SUFFIX="${LUA_VER_SFX}"
		LUA_INC="$BUILT_DIR/$LUA_VER_DIR/include"
		LUA_LIB="$BUILT_DIR/$LUA_VER_DIR/lib"
		LUA_BIN="$BUILT_DIR/$LUA_VER_DIR/bin"
	)
	if [ ! -z "$USE_FREETYPE_SRC" ] ; then
		makevars[${#makevars}]="FREETYPE_INC=${SRC_DIR}/freetype/include"
	fi

	if [ "$BUILD_OS" == 'Darwin' ] ; then
		# ftm script had USE_MACOS_OPENGL=Yes probably? not needed if not building ogl components?
		makevars[${#makevars}]='GTK_BASE=/opt/local'
		makevars[${#makevars}]='BUILD_DYLIB=Yes'
		makevars[${#makevars}]='USE_GTK3=Yes'
		makevars[${#makevars}]='CPATH=/opt/local/include/gtk-3.0/unix-print'
	else
		# TODO unix-print path might be distro specific
		makevars[${#makevars}]='CPATH=/usr/include/gtk-3.0/unix-print'
	fi
	do_make "$log" "${makevars[@]}" "$@"
}
# not needed at the moment
#build_im() {
#	change_dir "$SRC_DIR/im"
#	make_tec
#}

build_freetype() {
	info_msg "building freetype"
	change_dir "$SRC_DIR/freetype"
	make_tec build-freetype.log
}

build_cd() {
	info_msg "building CD"
	change_dir "$SRC_DIR/cd/src"
	make_tec build-cd.log cd
	make_tec build-cdcontextplus.log cdcontextplus
	make_tec build-cdlua5.log cdlua5
	make_tec build-cdluacontextplus5.log cdluacontextplus5
}

build_iup() {
	info_msg "building IUP"
	change_dir "$SRC_DIR/iup"
	make_tec build-iup.log iup
	make_tec build-iupcd.log iupcd
	change_dir "$SRC_DIR/iup/srclua5"
	make_tec build-iuplua.log iuplua
	make_tec build-iupcdlua.log iupluacd
}

build_tec_libs() {
	# build_im
	if [ ! -z "$USE_FREETYPE_SRC" ] ; then
		build_freetype
	fi
	build_cd
	build_iup
}

# copy built libs to a tree similar to unzipped tec binary
copy_built_tec_libs() {
	# don't support building from source on win
	if [ "$BUILD_OS" == 'Windows' ] ; then
		return
	fi
	local libs="cd iup"
	local so_ext="so"
	if [ "$BUILD_OS" == 'Darwin' ] ; then
		so_ext="dylib"
	fi
	for lib in $libs ; do
		info_msg "configure $lib binaries"
		recreate_dir "$BUILT_DIR"/"$lib"
		create_dir "$BUILT_DIR"/"$lib"/include
		do_cp "$SRC_DIR"/"$lib"/include/* "$BUILT_DIR"/"$lib"/include
		do_cp "$SRC_DIR"/"$lib"/lib/"$TEC_UNAME"/*."$so_ext" "$BUILT_DIR"/"$lib"
		do_cp "$SRC_DIR"/"$lib"/lib/"$TEC_UNAME"/"$TEC_LUA_SFX"/*."$so_ext" "$BUILT_DIR"/"$lib"
		do_cp "$SRC_DIR"/"$lib"/COPYRIGHT "$BUILT_DIR"/"$lib"
	done
}

copy_runtime() {
	# windows currently static
	if [ "$BUILD_OS" == 'Windows' ] ; then
		return
	fi
	local liblist
	if [ "$BUILD_OS" == 'Linux' ] ; then
		 liblist="$(cat "${CHDKPTP_DIR}"/misc/liblist-linux.txt)"
	elif [ "$BUILD_OS" == 'Darwin' ] ; then
		 liblist="$(cat "${CHDKPTP_DIR}"/misc/liblist-osx.txt)"
	fi
	create_dir "$CHDKPTP_DIR"/lib
	for f in $liblist ; do
		do_cp "$BUILT_DIR/$f" "$CHDKPTP_DIR"/lib
	done
}

arg="$1"
pretend=""
nodl=""
nogui=""
nobuild=""
noextract=""
nocopy=""
nocopyrt=""
opt_force_os=""
opt_force_arch=""
opt_force_tec_src=""
opt_tec_linver=""
opt_dir=""
opt_redl=""
while [ ! -z "$arg" ] ; do
	case $arg in
	-pretend)
		pretend=1
	;;
	-d=*)
		opt_dir="${arg#-d=}"
	;;
	-redl)
		opt_redl=1
	;;
	-nodl)
		nodl=1
	;;
	-nogui)
		nogui=1
	;;
	-noextract)
		noextract=1
	;;
	-nobuild)
		nobuild=1
	;;
	-nocopy)
		nocopy=1
	;;
	-nocopyrt)
		nocopyrt=1
	;;
	-ignore-ssl-err)
		opt_ignore_ssl_err=1
	;;
	-force-tec-src)
		opt_force_tec_src=1
	;;
	-force-os=*)
		opt_force_os="${arg#-force-os=}"
	;;
	-force-arch=*)
		opt_force_arch="${arg#-force-arch=}"
	;;
	-tec-linver=*)
		opt_tec_linver="${arg#-tec-linver=}"
	;;
	-tec-freetype-src)
		opt_tec_freetype_src="1"
	;;
	*)
		usage "unknown option $arg"
	;;
	esac
	shift
	arg="$1"
done
init_vars
init_os
create_tree
if [ -z "$nodl" ] ; then
	do_download
fi
if [ -z "$noextract" ] ; then
	extract_pkgs
	prepare_source
fi
if [ -z "$nobuild" ] ; then
	build_lua
fi
if [ -z "$nocopy" ] ; then
	copy_built_lua
fi
if [ ! -z "$TEC_SOURCE_BUILD" -a -z "$nogui" ] ; then
	if [ -z "$nobuild" ] ; then
		build_tec_libs
	fi
	if [ -z "$nocopy" ] ; then
		copy_built_tec_libs
	fi
fi
if [ -z "$nocopyrt" ] ; then
	copy_runtime
fi
