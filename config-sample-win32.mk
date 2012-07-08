# configurable build settings
# these can be set on the command line or in config.mk
# should IUP gui be built ?
IUP_SUPPORT=1
# should gui include CD
CD_SUPPORT=1
# use CD "plus" context. gdiplus on windows, may have better alpha support
#CD_USE_PLUS=gdiplus

# root directories of various packages, not used to set subdirs below.
# Not required by main makefile
IUP_DIR=/d/devel/iup
CD_DIR=/d/devel/cd
LIBUSB_DIR=/d/devel/libusb-win32-bin-1.2.4.0
LUA_DIR=/d/devel/lua

IUP_LIB_DIR=$(IUP_DIR)/lib/mingw4
IUP_INCLUDE_DIR=$(IUP_DIR)/include

CD_LIB_DIR=$(CD_DIR)/lib
CD_INCLUDE_DIR=$(CD_DIR)/include

# for CHDK ptp.h this intentionaly uses the ROOT of the CHDK tree, to avoid header name conflicts 
# so core/ptp.h should be found relative to this
# you do not need the whole chdk source, you can just copy ptp.h
CHDK_SRC_DIR=/d/chdk/trunk

LUA_LIB_DIR=$(LUA_DIR)/lib
LUA_INCLUDE_DIR=$(LUA_DIR)/include

LIBUSB_INCLUDE_DIR=$(LIBUSB_DIR)/include
LIBUSB_LIB_DIR=$(LIBUSB_DIR)/lib/gcc

# compile with debug support 
DEBUG=1

# include svn revision in build number
#USE_SVNREV=1
