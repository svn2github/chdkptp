TOPDIR=..
include $(TOPDIR)/include.mk
ifdef LUA_INCLUDE_DIR
INC_PATHS+=-I$(LUA_INCLUDE_DIR)
endif
CFLAGS+=$(INC_PATHS) -fPIC
SRCS=lsignal.c
EXES=../signal$(DLL)
OBJS=$(SRCS:.c=.o)
ifeq ($(OSTYPE),Darwin)
LDFLAGS+=-Wl,-undefined -Wl,dynamic_lookup
else
LDFLAGS+=-shared
endif
all: $(EXES)

$(EXES): $(OBJS)
	$(CC) $(LDFLAGS) -o $@ $^

include $(TOPDIR)/bottom.mk
