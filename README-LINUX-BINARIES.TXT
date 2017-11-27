The linux binary packages include GUI and CLI executables, named chdkptp_gui
and chdkptp respectively. To run these, use the corresponding .sh scripts.

The CLI binary should have no external dependencies that aren't part of the
standard system.

These builds may or may not be compatible with distributions other different
from the ones used to build.

The GUI executable requires IUP and CD libraries. Since these are generally
not available in standard Linux repositories and are non-trivial to build, a 
minimum set of libraries is included in the binary packages.

The GUI libraries may depend on system libraries (x11, gtk etc) which are not
present on your system. You can use ldd to identify the missing libraries, and
your systems package manager to add the required packages.

The packages only include the shared library files. If you want to build
chdkptp from source, you need a full package.

The platforms and library packages used for the binary builds are listed below

Linux x86:
Built on Debian 8.9 (Jesse) 3.16.43-2+deb8u5 (2017-09-19) i686

CD 5.11
 https://sourceforge.net/projects/canvasdraw/files/5.11/Linux%20Libraries/cd-5.11_Linux32_lib.tar.gz
 https://sourceforge.net/projects/canvasdraw/files/5.11/Linux%20Libraries/Lua52/cd-5.11-Lua52_Linux32_lib.tar.gz

IUP 3.21
 https://sourceforge.net/projects/iup/files/3.21/Linux%20Libraries/iup-3.21_Linux32_lib.tar.gz
 https://sourceforge.net/projects/iup/files/3.21/Linux%20Libraries/Lua52/iup-3.21-Lua52_Linux32_lib.tar.gz

Linux x64:
Built on Debian 8.9 (Jesse) 3.16.43-2+deb8u5 (2017-09-19) x86_64

CD 5.11
 https://sourceforge.net/projects/canvasdraw/files/5.11/Linux%20Libraries/cd-5.11_Linux313_64_lib.tar.gz
 https://sourceforge.net/projects/canvasdraw/files/5.11/Linux%20Libraries/Lua52/cd-5.11-Lua52_Linux313_64_lib.tar.gz

 https://sourceforge.net/projects/canvasdraw/files/5.10/Linux%20Libraries/cd-5.10_Linux313_64_lib.tar.gz
 https://sourceforge.net/projects/canvasdraw/files/5.10/Linux%20Libraries/Lua52/cd-5.10-Lua52_Linux313_64_lib.tar.gz

IUP 3.21
 https://sourceforge.net/projects/iup/files/3.21/Linux%20Libraries/iup-3.21_Linux313_64_lib.tar.gz
 https://sourceforge.net/projects/iup/files/3.21/Linux%20Libraries/Lua52/iup-3.21-Lua52_Linux313_64_lib.tar.gz

Raspberry pi:
Raspbian 8 4.9.35+ armv6l
IUP and CD built locally, available in the chdkptp files area 
https://www.assembla.com/spaces/chdkptp/documents as chdkptp-raspbian-libs-20170305.zip

See README-RASPI-LIBS.TXT for the source packages used and build information.

Lua 5.2.4 is built from source and statically linked on all platforms, using
 https://www.lua.org/ftp/lua-5.2.4.tar.gz


