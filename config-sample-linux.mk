# configurable build settings
# these can be set on the command line or config.mk
# should IUP gui be built ?
IUP_SUPPORT=0
# should CD support be built
CD_SUPPORT=0
# enable "plus" context support with cairo, you will need libcairo2-dev or similar
#CD_USE_PLUS=cairo

# for CHDK ptp.h this intentionaly uses the ROOT of the CHDK tree, to avoid header name conflicts 
# so core/ptp.h should be found relative to this
# you do not need the whole chdk source, you can just copy ptp.h
CHDK_SRC_DIR=/path/to/chdk/source
LUA_INCLUDE_DIR=/usr/include/lua5.1
LUA_LIB=lua5.1

# compile with debug support 
DEBUG=1

# lib paths - only needed if you haven't installed in system directories
#IUP_LIB_DIR=/path/to/iup
#IUP_INCLUDE_DIR=/path/to/iup/include
#CD_LIB_DIR=/path/to/cd
#CD_INCLUDE_DIR=/path/to/cd/include

# include svn revision in build number
#USE_SVNREV=1
