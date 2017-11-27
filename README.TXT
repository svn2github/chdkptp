=Introduction=
chdkptp is a tool to access the custom PTP extension of the CHDK firmware addon
for Canon cameras. 

chdkptp builds are labeled "alpha", but it is stable enough for everyday use.
Protocol, functionality, APIs, commands, command line options are
all subject to change.

Source is available from http://subversion.assembla.com/svn/chdkptp/
Binary snapshot builds are available from http://www.assembla.com/spaces/chdkptp/documents
Changelog is at http://www.assembla.com/wiki/show/chdkptp/Changelog

This README is primarily intended for developers.

See INSTALL.TXT for installation information

See USAGE.TXT for end-user documentation

See README-LINUX-BINARIES.TXT for information about the linux builds (including raspberry pi) 

For information about CHDK, see http://chdk.wikia.com/wiki/CHDK
For information about the CHDK PTP extension, see http://chdk.wikia.com/wiki/PTP_Extension

chdkptp is forked from libptp and ptpcam, as modified by mweerden, the chdkde project
developers and others. All source is released under GPL or MIT licenses

The original ptpcam source, written by Mariusz Woloszyn < emsi[A@T]ipartners.pl >
is available from http://libptp.sourceforge.net/

mweerdens modified version can be found at https://github.com/mweerden/CHDK/tree/ptp

The CHDKDE ptpcam source may be found at http://tools.assembla.com/chdkde/browser/trunk/tools/ptpcam

chdkptp includes software from several other projects, see THANKS.TXT for details.

=Dependencies=
- IUP version 3.21 http://www.tecgraf.puc-rio.br/iup/ 
  Optional, edit config.mk to build without IUP GUI support
  (earlier 3.x versions may also work, but 3.21 or later is required on linux with GTK newer than 3.18)
- CD Version 5.11 http://www.tecgraf.puc-rio.br/cd/
  Optional, used for remote display
  (earlier 5.x versions may also work)
- Lua version 5.2 http://www.lua.org/
  Lua 5.1 is not supported, although it may work
  Lua 5.3 is not supported, and is known to cause problems
- LibUSB (libusb-win32 on windows)
- GNU readline
  Optional, recommended on Linux

=Windows development environment=
Mingw with gcc 4.8+ is the primary development environment. 
All instructions below assume you are using this.
Using a mingw bash shell for development is suggested.

==Installing mingw==
http://www.mingw.org/
Download the gui installer. Install at least mingw C compiler.
C++ support is required to use CD "context plus", not required or used by default.
Msys is suggested, and may be required

==Installing IUP libraries==
Get the mingw4 binary packages from
http://sourceforge.net/projects/iup/files/

Note, this package has the libraries in the root, with etc/ and include/ subdirectories.
You may want to put the libraries in /lib to match the IUP recommended filesystem layout
The examples and win32 binaries are not required, but may be helpful

You must get both the main IUP file, and the corresponding Lua52 file.
They should be unzipped in the same directory.

==Installing CD libraries==
Similar to IUP, from http://sourceforge.net/projects/canvasdraw/files/

==Installing and building Lua==
Get the lua 5.2.x source from http://www.lua.org/download.html
In a msys shell, go to the lua directory and type
make mingw
make local

NOTE:
it's very important that Lua be linked to exactly the same C runtime library
as chdkptp itself. The lbuf file routines expect to be able to fread and fwrite on
a FILE * opened by lua io.open()

This condition probably won't be met if you use a pre-compiled Lua dll on windows.
It's probably OK with a shared lua in typical linux environments. 
If in doubt, build your own Lua with the same compiler you build chdkptp with.

==Installing LibUSB development package==
https://sourceforge.net/projects/libusb-win32/files/libusb-win32-releases/1.2.6.0/
libusb-win32-bin-1.2.6.0.zip
Unzip somewhere convenient

Some earlier and later versions will also probably work, however versions
before 1.2.4.6 used a different name for the header file.

The above installs the development files only. To use libusb-win32 programs,
the driver must be installed. Using Zadig (http://zadig.akeo.ie/) as
described on http://chdk.wikia.com/wiki/PTP_Extension#Installing_LibUSB_using_Zadig
is the way to do this.

=Linux development environment=
A fully working gcc C build environment is required.

==LibUSB==
Install libusb development package, typically called something like
libusb-dev or libusb-1.0-dev, along with any dependencies.

==Lua==
The recommended approach is to download and build the lua 5.2 source, as this
avoids any incompatibility with distro provided packages.

If do you want to use the distro provided packages, they will be called something
like liblua5.2-dev and liblua5.2.

==GNU readline==
You need the development package, usually called something like
libreadline6-dev

==GUI Libraries: CD and IUP==
Where available, using pre-built libraries is recommended.

Pre-built IUP libraries are available from
http://sourceforge.net/projects/iup/files/

Pre-built CD libraries are available from
http://sourceforge.net/projects/canvasdraw/files/

For each package, you must download the main library package, called something
like iup-3.21_Linux313_64_lib.tar.gz and the Lua library from the LuaNN
subdirectory of the Lua version you want to use, called something like
iup-3.21-Lua52_Linux313_64_lib.tar.gz

The LinuxNNN number refers to the kernel version. An exact match for the kernel
you are running is generally not required.

Unpack all the packages, with both the main library and Lua contents in the
same directory. 

Adjust the IUP_LIB_DIR, IUP_INCLUDE_DIR, CD_LIB_DIR and CD_INCLUDE_DIR in
config.mk to point to where you unpacked the packages

==Building IUP and CD==
If available, using pre-compiled libraries is suggested, but if you want to
build from source some notes can be found in README-RASPI-LIBS.TXT

=Configuring the source (all platforms)=
Copy config-sample-<platform>.mk to config.mk and edit the values to to reflect
the installation directories of the above packages and desired compile time
options.

Paths for library and include directories should be absolute, not relative.

==Mac development==
See README-OSX.TXT

=Building=
make

On windows, link occasionally fails with something like
 /mingw/bin/../lib/gcc/mingw32/4.8.1/../../../../mingw32/bin/ld.exe: reopening chdkptp.exe: Permission denied

Rebuilding seems to work around the problem

=Testing your build=
To test some internal functions use
chdkptp -e"exec require'tests':runall()"
note, this should be run from the same directory as the CHDKPTP executable

This will create (or overwrite) a file called lbuftest.dat in the current
directory, and delete it when the test completes.

To test functions that connect to the camera, use
chdkptp -e"exec require'camtests'.runbatch{bench=true,filexfer=true}"

If more than one camera is connected to the system, a random one will be used
unless you also specify devspec={dev="device name",bus="bus id"}

The filexfer tests will create and delete a local directory called camtests
in the current working directory. If you already have a directory of this name,
it will be deleted when the test completes.

You can add shoot=true to the camtests command to test some shooting related
functions. This will attempt to switch to record mode and shoot. It may fail
on some cameras which have issues with CHDK remoteshoot. Some files
will be created on the camera.

Camtests will also create and delete some files and directories on the camera.

The final line of output from both test modules should be 
failed 0

None of the above is a comprehensive test of chdkptp functionality.

=Running=
See USAGE.TXT
