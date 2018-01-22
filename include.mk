# common macros and targets
#
# build-time configuration should be done in config.mk
# see the config-sameple*.mk files for examples

#TODO could pass to subdir makes to avoid shelling out
HOSTPLATFORM:=$(patsubst MINGW%,MINGW,$(shell uname -s))
ifeq ($(HOSTPLATFORM),MINGW)
OSTYPE=Windows
EXE=.exe
DLL=.dll
# Note may be freetype or freetype6 depending on CD version, zlib requried for 5.5 and later
CD_FREETYPE_LIB=freetype6 z
#CD_FREETYPE_LIB=freetype z
endif
ifeq ($(HOSTPLATFORM),Linux)
OSTYPE=Linux
EXE=
DLL=.so
CD_FREETYPE_LIB=freetype z
endif
ifeq ($(HOSTPLATFORM),Darwin)
OSTYPE=Darwin
EXE=
# TODO .dylib? only used for signal
DLL=.so
# TODO?
CD_FREETYPE_LIB=freetype z
endif

#extra suffix to add to executable name
EXE_EXTRA=

CC=gcc
CFLAGS=-DCHDKPTP_OSTYPE=\"$(OSTYPE)\" -Wall
LDFLAGS=
#LD=ld

#default lib names, can be overridden in config
#LUA_SFX will be set below and expanded correctly later
LUA_LIB=lua
IUP_LIB=iup
IUP_LUA_LIB=iuplua$(LUA_SFX)
LIBUSB_LIB=usb

READLINE_LIB=readline history

CD_LIB=cd
CD_LUA_LIB=cdlua$(LUA_SFX)
IUP_CD_LIB=iupcd
IUP_CD_LUA_LIB=iupluacd$(LUA_SFX)
CD_PLUS_LIB=cdcontextplus cdluacontextplus$(LUA_SFX)
GDI_PLUS_LIBS=gdiplus stdc++

#defaults, can be overridden by config or on command line
DEBUG=1

# use Lua 5.2 
# Lua 5.1 is no longer supported by chdkptp, but it might work
USE_LUA_52=1

ifeq ($(OSTYPE),Windows)
# enable CD "plus" context support, if GUI enabled
# better image scaling but slower / larger exe
# To actually render with contextplus, set gui_context_plus=true in your startup file
CD_USE_PLUS=gdiplus
GUI=1
GUI_SFX=
# define if you get unresolved externals on
# GdipFontFamilyCachedGenericSansSerif building with CD context plus
#CD_GDIP_FONT_HACK=1
LIBUSB_DIR=$(EXTLIB_DIR)/libusb-win32-bin-1.2.6.0
else
# older linux / CD combos?
#CD_USE_PLUS=cairo
CD_USE_PLUS=1
GUI=
# only needed when building both, e.g for dist zip
#GUI_SFX=_gui
# include gnu readline support (command history+editing)
# may require libreadline-dev or similar package
READLINE_SUPPORT=1
endif

# as created by setup-ext-libs.bash
# root directory for default paths below
EXTLIB_DIR=$(TOPDIR)/extlibs/built

LUA_INCLUDE_DIR=$(EXTLIB_DIR)/lua$(LUA_SFX)/include
LUA_LIB_DIR=$(EXTLIB_DIR)/lua$(LUA_SFX)/lib

# GUI lib paths - needed if building GUI and not on default search path
IUP_LIB_DIR=$(EXTLIB_DIR)/iup
IUP_INCLUDE_DIR=$(EXTLIB_DIR)/iup/include
CD_LIB_DIR=$(EXTLIB_DIR)/cd
CD_INCLUDE_DIR=$(EXTLIB_DIR)/cd/include

ifeq ($(OSTYPE),Windows)
LIBUSB_INCLUDE_DIR=$(LIBUSB_DIR)/include
ifeq ($(MSYSTEM_CARCH),x86_64)
LIBUSB_LIB_DIR=$(LIBUSB_DIR)/lib/gcc_x64
else
LIBUSB_LIB_DIR=$(LIBUSB_DIR)/lib/gcc
endif
endif
# build optional signal module, for automation applications
# not used by default, but source included and should build on any linux
# TODO possibly OK for OSX too?
ifeq ($(OSTYPE),Linux)
LUASIGNAL_SUPPORT=1
endif

# should expand to directory if it exists
USE_SVNREV:=$(wildcard $(TOPDIR)/.svn)

#user overrides
#see config-sample-*.mk
-include $(TOPDIR)/config.mk

ifdef GUI
IUP_SUPPORT=1
CD_SUPPORT=1
EXE_EXTRA=$(GUI_SFX)
endif


ifeq ("$(USE_LUA_52)","1")
LUA_SFX=52
# must also have been defined when built, is by default
CFLAGS+=-DLUA_COMPAT_ALL=1
else
LUA_SFX=51
endif

ifdef DEBUG
CFLAGS+=-g
LDFLAGS+=-g
else
CFLAGS+=-O2
endif

ifdef CD_GDIP_FONT_HACK
CFLAGS+=-DCHDKPTP_GDIP_FONT_HACK=1
endif

# use included headers if not specified
ifndef CHDK_SRC_DIR
CHDK_SRC_DIR=$(TOPDIR)/chdk_headers
endif

ifeq ("$(CD_USE_PLUS)","gdiplus")
CD_PLUS_SYS_LIBS=$(GDI_PLUS_LIBS)
endif
ifeq ("$(CD_USE_PLUS)","cairo")
CD_PLUS_LIB+=cairo cdcairo cdx11
endif

DEP_DIR=.dep

.PHONY: all
all: all-recursive

all-recursive:
	@for i in $(SUBDIRS); do \
		$(MAKE) -C $$i FOLDER="$(FOLDER)$$i/" || exit 1; \
	done

.PHONY: clean
clean: clean-one clean-recursive

.PHONY: cleand
cleand: cleand-one clean-one cleand-recursive

clean-one:
	rm -f $(EXES) *.o

cleand-one:
	rm -f $(DFILES)

%.o: %.c
	$(CC) -MMD $(CFLAGS) -c -o $@ $<
	@if [ ! -d $(DEP_DIR) ] ; then mkdir $(DEP_DIR) ; fi; \
		cp $*.d $(DEP_DIR)/$*.d; \
		sed -e 's/#.*//' -e 's/^[^:]*: *//' -e 's/ *\\$$//' \
				-e '/^$$/ d' -e 's/$$/ :/' < $*.d >> $(DEP_DIR)/$*.d; \
			rm -f $*.d

clean-recursive:
	@for i in $(SUBDIRS); do \
		echo \>\> Cleaning in $(FOLDER)$$i; \
		$(MAKE) -C $$i FOLDER="$(FOLDER)$$i/" clean || exit 1; \
	done

cleand-recursive:
	@for i in $(SUBDIRS); do \
		echo \>\> Cleaning dep in $(FOLDER)$$i; \
		$(MAKE) -C $$i FOLDER="$(FOLDER)$$i/" cleand || exit 1; \
	done

