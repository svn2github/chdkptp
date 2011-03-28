CC=gcc
#LD=ld

# should IUP gui be built ?
IUP_SUPPORT=1
IUP_DIR=/j/devel/iup
# IUP binary packages have a weird layout, so you can set lib/include individuallly here
IUPLIB_DIR=$(IUP_DIR)/lib/mingw4
IUPINCLUDE_DIR=$(IUP_DIR)/include
# for CHDK ptp.h this intentionaly uses the ROOT of the CHDK tree, to avoid header name conflicts 
CHDK_SRC_DIR=/k/home/chdk/juciphox
LUA_DIR=/j/devel/lua
LIBUSB_DIR=/j/devel/libusb-win32-bin-1.2.2.0
DEP_DIR=.dep
DEBUG=1

CFLAGS=-I$(LUA_DIR)/include -I$(LIBUSB_DIR)/include -I$(CHDK_SRC_DIR)
LDFLAGS=-L$(LUA_DIR)/lib -L$(LIBUSB_DIR)/lib/gcc -llua -lusb -lws2_32 -lkernel32
ifeq ("$(IUP_SUPPORT)","1")
CFLAGS+=-I$(IUPINCLUDE_DIR) -DCHDKPTP_IUP=1
# TODO order matters so we just set the whole thing
LDFLAGS=-L$(IUPLIB_DIR) -L$(LUA_DIR)/lib -L$(LIBUSB_DIR)/lib/gcc -liuplua51 -llua -liup -lusb -lws2_32 -lkernel32 -lcomctl32 -lole32 -lgdi32 -lcomdlg32
endif

ifdef DEBUG
CFLAGS+=-g
LDFLAGS+=-g
endif

all: chdkptp.exe

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

chdkptp.exe: $(OBJS)
	$(CC) -o $@ $^ $(LDFLAGS)

.PHONY: all clean cleand

-include $(DFILES)
