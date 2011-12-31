TOPDIR=.
include include.mk

ifeq ($(OSTYPE),Windows)
SYS_LIBS=-lws2_32 -lkernel32
IUP_SYS_LIBS=-lcomctl32 -lole32 -lgdi32 -lcomdlg32
endif

ifeq ($(OSTYPE),Linux)
# need 32 bit libs to do this
#TARGET_ARCH=-m32
endif

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

LDFLAGS+=$(LIB_PATHS) $(LINK_LIBS) $(SYS_LIBS)

SUBDIRS=lfs

EXES=chdkptp$(EXE)

all: $(EXES)

SRCS=myusb.c properties.c ptp.c chdkptp.c
OBJS=$(SRCS:.c=.o)

chdkptp$(EXE): $(OBJS)
	$(CC) -o $@ lfs/lfs.o $^ $(LDFLAGS)

include bottom.mk
