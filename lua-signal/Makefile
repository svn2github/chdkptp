TOPDIR=..
include $(TOPDIR)/include.mk
ifdef LUA_INCLUDE_DIR
INC_PATHS+=-I$(LUA_INCLUDE_DIR)
endif
CFLAGS+=$(INC_PATHS)
SRCS=lsignal.c
EXES=../signal.so
OBJS=$(SRCS:.c=.o)
all: $(EXES)

$(EXES): $(OBJS)
	$(CC) -shared -o $@ $^

include $(TOPDIR)/bottom.mk


