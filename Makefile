HOSTPLATFORM:=$(patsubst MINGW%,MINGW,$(shell uname -s))
ifeq ($(HOSTPLATFORM),MINGW)
OSTYPE=Windows
EXE=.exe
else
ifeq ($(HOSTPLATFORM),Linux)
OSTYPE=Linux
EXE= 
endif
endif

CC=gcc
CFLAGS=
LDFLAGS=
#LD=ld

ifeq ($(OSTYPE),Windows)
SYS_LIBS=-lws2_32 -lkernel32
IUP_SYS_LIBS=-lcomctl32 -lole32 -lgdi32 -lcomdlg32
endif

ifeq ($(OSTYPE),Linux)
# need 32 bit libs to do this
#TARGET_ARCH=-m32
endif

#default lib names, can be overridden in buildconf
LUA_LIB=lua
IUP_LIB=iup
IUP_LUA_LIB=iuplua51
LIBUSB_LIB=usb

#see config-sample-*.mk
-include config.mk

LINK_LIBS=-l$(LUA_LIB) -l$(LIBUSB_LIB)

ifdef LUA_LIB_DIR
LIB_PATHS+=-L$(LUA_LIB_DIR)
endif
ifdef LUA_INCLUDE_DIR
INC_PATHS+=-I$(LUA_INCLUDE_DIR)
endif

ifdef LIBUSB_LIB_DIR
LIB_PATHS+=-L$(LIBUSB_LIB_DIR)
endif
ifdef LIBUSB_INCLUDE_DIR
INC_PATHS+=-I$(LIBUSB_INCLUDE_DIR)
endif

ifeq ("$(IUP_SUPPORT)","1")
ifdef IUP_LIB_DIR
LIB_PATHS+=-L$(IUP_LIB_DIR)
endif
ifdef IUP_INCLUDE_DIR
INC_PATHS+=-I$(IUP_INCLUDE_DIR)
endif
CFLAGS+=-DCHDKPTP_IUP=1
SYS_LIBS+=$(IUP_SYS_LIBS)
LINK_LIBS=-l$(IUP_LUA_LIB) -l$(LUA_LIB) -l$(IUP_LIB) -l$(LIBUSB_LIB)
endif

INC_PATHS+=-I$(CHDK_SRC_DIR)
CFLAGS+=$(INC_PATHS)

DEP_DIR=.dep

LDFLAGS+=$(LIB_PATHS) $(LINK_LIBS) $(SYS_LIBS)

ifdef DEBUG
CFLAGS+=-g
LDFLAGS+=-g
endif

all: chdkptp$(EXE)

clean:
	@rm -f *.exe *.o

cleand: clean
	@rm -f $(DFILES)

%.o: %.c
	$(CC) -MMD $(CFLAGS) -c -o $@ $<
	@if [ ! -d $(DEP_DIR) ] ; then mkdir $(DEP_DIR) ; fi; \
		cp $*.d $(DEP_DIR)/$*.d; \
		sed -e 's/#.*//' -e 's/^[^:]*: *//' -e 's/ *\\$$//' \
				-e '/^$$/ d' -e 's/$$/ :/' < $*.d >> $(DEP_DIR)/$*.d; \
			rm -f $*.d

SRCS=myusb.c properties.c ptp.c chdkptp.c
OBJS=$(SRCS:.c=.o)

DFILES=$(SRCS:%.c=$(DEP_DIR)/%.d)

chdkptp$(EXE): $(OBJS)
	$(CC) -o $@ $^ $(LDFLAGS)

.PHONY: all clean cleand

-include $(DFILES)
