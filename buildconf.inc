# configurable build settings
# these can be set on the command line or in localbuildconf.inc
# should IUP gui be built ?
TOPDIR=.
IUP_SUPPORT=1

IUP_DIR=$(TOPDIR)/iup
# IUP binary packages have a weird layout, so you can set lib/include individuallly here
IUPLIB_DIR=$(IUP_DIR)/lib/mingw4
IUPINCLUDE_DIR=$(IUP_DIR)/include

# for CHDK ptp.h this intentionaly uses the ROOT of the CHDK tree, to avoid header name conflicts 
# so core/ptp.h should be found relative to this
# you do not need the whole chdk source, you can just copy ptp.h
CHDK_SRC_DIR=$(TOPDIR)/chdk
LUA_DIR=$(TOPDIR)/lua
LIBUSB_DIR=$(TOPDIR)/libusb-win32-bin-1.2.2.0

# compile with debug support 
DEBUG=1

