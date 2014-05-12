# configurable build settings
# these can be set on the command line or config.mk

# use Lua 5.2 
# Lua 5.1 is no longer supported by chdkptp, but it might work
USE_LUA_52=1

# should IUP gui be built ?
IUP_SUPPORT=0
# should CD support be built
CD_SUPPORT=0
# enable "plus" context support with cairo, you will need libcairo2-dev or similar
#CD_USE_PLUS=cairo
# should this build include PTP/IP (wifi camera) support
PTPIP_SUPPORT=0

# include gnu readline support (command history+editing)
# may require libreadline-dev or similar package
READLINE_SUPPORT=1

# the follwing may be set if your readline is not in a standard location
#READLINE_LIB_DIR=/path/to/readline/libs
# note code expects for find readline/readline.h
#READLINE_INCLUDE_DIR=/path/to/readline/headers
# library names for -llibfoo, only needed to override defaults
#READLINE_LIB=readline history

# for distro provided Lua, you probably want something like this
# exact paths may vary depending on distro and Lua version
LUA_INCLUDE_DIR=/usr/include/lua5.2
LUA_LIB=lua5.2

# for self built lua, use something like
#LUA_INCLUDE_DIR=/path/to/installed/lua/include
#LUA_LIB_DIR=/path/to/installed/lua/lib

# compile with debug support 
DEBUG=1

# GUI lib paths - only needed if building GUI 
# and you haven't installed libs in system directories
#IUP_LIB_DIR=/path/to/iup
#IUP_INCLUDE_DIR=/path/to/iup/include
#CD_LIB_DIR=/path/to/cd
#CD_INCLUDE_DIR=/path/to/cd/include

# include svn revision in build number
#USE_SVNREV=1

# You don't need to set this unless you are doing protocol development
# if not set, included copies in the chdk_headers directory will be used
# Used to locate CHDK ptp.h and live_view.h 
# this intentionaly uses the ROOT of the CHDK tree, to avoid header name conflicts 
# so core/ptp.h should be found relative to this
#CHDK_SRC_DIR=$(TOPDIR)/chdk_headers

