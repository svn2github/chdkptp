The chdkptp raspberry pi library package provides Lua 5.2, IUP and CD
compiled for the raspbian distribution. The latest package can be found
in the chdkptp files area as https://www.assembla.com/spaces/chdkptp/documents
named chdkptp-raspbian-libs-YYYYMMDD.zip

The chdkptp binary packages contain the minimum require libraries, so
this full library package is only required for development. 

Information about chdkptp can be found at:
http://www.assembla.com/wiki/show/chdkptp

For information about Lua, CD and IUP, see
http://www.lua.org/
http://www.tecgraf.puc-rio.br/iup/
http://www.tecgraf.puc-rio.br/cd/

The zip is arranged into directories for each library:
lua52, cd and iup respectively

See COPYRIGHT file or doc subdirectory in each directory for copyright
information.

These files are intended to allow you to build your own chdkptp without
building the GUI libraries.  Some files not required by CHDK may be included,
but these are not complete distributions of Lua, CD and IUP, and are not
thoroughly tested. 


Using the libraries to build chdkptp:
Add something like the following in your config.mk

TEC_LIBS=/path/to/zip/contents

LUA_INCLUDE_DIR=$(TEC_LIBS)/lua52/include
LUA_LIB_DIR=$(TEC_LIBS)/lua52/lib

IUP_LIB_DIR=$(TEC_LIBS)/iup/lib
IUP_INCLUDE_DIR=$(TEC_LIBS)/iup/include
CD_LIB_DIR=$(TEC_LIBS)/cd/lib
CD_INCLUDE_DIR=$(TEC_LIBS)/cd/include


Using the libraries with chdkptp:

To use these libraries with your own chdkptp build, ensure the iup/lib
and cd/lib directories are on your LD_LIBRARY_PATH


Build notes:
The libraries were built on Raspbian Jessie.
While there are a few pi specifics, the following may also be useful
building on other distros.

The build mostly follows the directions given at
http://www.tecgraf.puc-rio.br/iup/en/building.html
but several additional workarounds are required. The build was done
without using the distro provided Lua packages, and without using tecmake.

Only Lua 5.2 support was built.
It is strongly recommended that you build chdkptp with Lua 5.2

The following packages should be installed. Some may be automatically selected
as dependencies
libreadline-dev
g++
libfreeetype6-dev
libgl1-mesa-dev
libgtk3-dev
libx11-dev
libxpm-dev
libxmu-dev
libxft-dev
libglu1-mesa-dev
libwebkitgtk-3.0-dev
libftgl-dev

Note motif support was not built, so motif related libmotif-dev x11proto-print-dev
were not installed

Note some of the above packages may not be required for a minimal build

Download the source packages
$ wget http://www.lua.org/ftp/lua-5.2.4.tar.gz
$ wget https://sourceforge.net/projects/iup/files/3.21/Docs%20and%20Sources/iup-3.21_Sources.tar.gz
$ wget https://sourceforge.net/projects/imtoolkit/files/3.12/Docs%20and%20Sources/im-3.12_Sources.tar.gz
$ wget https://sourceforge.net/projects/canvasdraw/files/5.11/Docs%20and%20Sources/cd-5.11_Sources.tar.gz

$ tar -xzf lua-5.2.4.tar.gz
$ tar -xzf pkg/im-3.12_Sources.tar.gz
$ tar -xzf pkg/cd-5.11_Sources.tar.gz
$ tar -xzf pkg/iup-3.21_Sources.tar.gz

The default tekmake.mak files do not properly detect the raspbian as arm,
which in turn makes it define TEC_BIGENDIAN. Apply the included
tecmake.mak.patch patch with

$ for d in im cd iup ; do pushd $d ; patch -p0 </path/to/chdkptp/misc/tecmake.mak.patch ; popd ; done

Build Lua

$ cd lua-5.2.4
$ make linux

Make a Lua installation tree. Adjust /home/pi/teclibs/ if desired.

$ make INSTALL_TOP=/home/pi/teclibs/lua52 install

The IUP build expects a different sub-path than the above install creates.
Use the following to put symlinks in the required location

$ mkdir lua52/lib/Linux44_arm
$ ln -s ../liblua.a lua52/lib/Linux44_arm/liblua52.a

Several includes are not found correctly in the IUP and CD build processes.
Set the following before building. This is probably distro specific, adjust
if you continue to get include errors.

$ export CPATH=/usr/include/gtk-3.0/unix-print

Build IM (not directly required by chdkptp, but required by the other libs)

$ cd im && make USE_LUA52=1

Build CD

$ cd cd/src && make USE_PKGCONFIG=Yes

Build IUP

$ cd iup
$ make USE_LUA52=Yes USE_PKGCONFIG=Yes iup
$ make USE_LUA52=Yes USE_PKGCONFIG=Yes iupcd
$ make USE_LUA52=Yes USE_PKGCONFIG=Yes iupcontrols
$ cd srclua5
$ make USE_LUA52=Yes USE_PKGCONFIG=Yes iuplua
$ make USE_LUA52=Yes USE_PKGCONFIG=Yes iupluacd
$ make USE_LUA52=Yes USE_PKGCONFIG=Yes iupluacontrols

The above may build more than strictly required by chdkptp.
