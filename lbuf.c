/*
 *
 * Copyright (C) 2010-2012 <reyalp (at) gmail dot com>
 *
 *  This program is free software; you can redistribute it and/or modify
 *  it under the terms of the GNU General Public License as published by
 *  the Free Software Foundation; either version 2 of the License, or
 *  (at your option) any later version.
 *
 *  This program is distributed in the hope that it will be useful,
 *  but WITHOUT ANY WARRANTY; without even the implied warranty of
 *  MERCHANTABILITY or FITNESS FOR A PARTICULAR PURPOSE.  See the
 *  GNU General Public License for more details.
 *
 *  You should have received a copy of the GNU General Public License
 *  along with this program; if not, write to the Free Software
 *  Foundation, Inc., 59 Temple Place, Suite 330, Boston, MA  02111-1307  USA
 */
#include <stdint.h>
#include <string.h>
#include <stdlib.h>
#include <lua.h>
#include <lualib.h>
#include <lauxlib.h>
#include "lbuf.h"
/*
create a new lbuf and push it on the stack
*/
int lbuf_create(lua_State *L,void *data,unsigned len,unsigned flags) {
	lBuf_t *buf = (lBuf_t *)lua_newuserdata(L,sizeof(lBuf_t));
	if(!buf) {
		return 0;
	}
	buf->len=len;
	buf->bytes=data;
	buf->flags=flags;
	luaL_getmetatable(L, LBUF_META);
	lua_setmetatable(L, -2);
	return 1;
}

/*
check whether given stack index is an lbuf, and if so, return it
*/
lBuf_t* lbuf_getlbuf(lua_State *L,int i) {
	if(!lua_isuserdata(L,i)) {
		return NULL;
	}
	if(lua_islightuserdata(L,i)) {
		return NULL;
	}
	if(!lua_getmetatable(L,i)) {
		return NULL;
	}
	lua_getfield(L,LUA_REGISTRYINDEX,LBUF_META);
	int r = lua_rawequal(L,-1,-2);
	lua_pop(L,2);
	if(r) {
		return lua_touserdata(L,i);
	}
	return NULL;
}

/*
nbytes=buf:len()
*/
static int lbuf_len(lua_State *L) {
	lBuf_t *buf = (lBuf_t *)luaL_checkudata(L,1,LBUF_META);
	lua_pushnumber(L,buf->len);
	return 1;
}

static int get_index_arg(lua_State *L,lBuf_t *buf,int i,int def) {
	int val=luaL_optint(L,i,def);
	if(val < 0) {
		val = buf->len + val + 1;
	}
	if(val < 0) {
		val = 0;
	}
	return val;
}
/*
s=buf:string([i[,j])
return part or all of the buffer as a lua string. i and j behave like string.sub
*/
static int lbuf_string(lua_State *L) {
	lBuf_t *buf = (lBuf_t *)luaL_checkudata(L,1,LBUF_META);
	int start=get_index_arg(L,buf,2,1);
	int end=get_index_arg(L,buf,3,buf->len);
	if(end > buf->len) {
		end = buf->len;
	}
	if(!buf->len || end < start) {
		lua_pushlstring(L,"",0);
		return 1;
	}
	// convert 1 based index to offset, note lua string.sub accepts 0
	if(start > 0) {
		start--;
	}
	lua_pushlstring(L,buf->bytes+start,end-start);
	return 1;
}

/*
byte,...=buf:byte([i[,j])
return bytes of buffer as numbers. i and j behave like string.byte
*/
static int lbuf_byte(lua_State *L) {
	lBuf_t *buf = (lBuf_t *)luaL_checkudata(L,1,LBUF_META);
	int start=get_index_arg(L,buf,2,1);
	int end=get_index_arg(L,buf,3,start);
	if(end > buf->len) {
		end = buf->len;
	}
	if(!buf->len || end < start) {
		lua_pushnil(L);
		return 1;
	}
	// convert 1 based index to offset, note lua string.sub accepts 0
	if(start > 0) {
		start--;
	}
	int count = end-start;
	if(!lua_checkstack(L,count)) {
		return luaL_error(L,"insufficient stack space for lbuf:byte");
	}
	int i;
	for(i=start;i<end;i++) {
		lua_pushnumber(L,*(uint8_t *)(buf->bytes+i));
	}
	return count;
}

typedef void (*get_vals_fn)(lua_State *L,void *p);

void get_vals_int32(lua_State *L,void *p) {
	int32_t v;
	memcpy(&v,p,4); // p might not be aligned
	lua_pushnumber(L,v);
}

void get_vals_uint32(lua_State *L,void *p) {
	uint32_t v;
	memcpy(&v,p,4); // p might not be aligned
	lua_pushnumber(L,v);
}

/*
v,...=buf:<get_vals_func>([offset[,count]])
return elements of buff in starting at offset in chunks, exact format depending on functions
not symmetric with byte(), due to complexity of dealing with > 1 size, alignment etc

offset is offset in bytes, default 0, negative not currently allowed
if offset is larger than buffer size, nothing is returned
count defaults to 1, is rounded down to the largest valid value
negative count means all
*/
static int get_vals(lua_State *L,unsigned size,get_vals_fn f) {
	lBuf_t *buf = (lBuf_t *)luaL_checkudata(L,1,LBUF_META);
	int off=luaL_optint(L,2,0);
	int count=luaL_optint(L,3,1);
	// may give these special meaning later
	if(off < 0) {
		return luaL_error(L,"negative offset not allowed");
	}
	if(off > buf->len - size) {
		return 0;
	}
	if(count < 0 || (off + count*size) > buf->len) {
		count = (buf->len - off)/size;
	}
	if(!lua_checkstack(L,count)) {
		return luaL_error(L,"insufficient stack space");
	}
	char *p;
	int i;
	for(i=0, p=buf->bytes + off;i<count;i++, p+=size) {
		f(L,p);
	}

	return count;
}
static int lbuf_get_i32(lua_State *L) {
	return get_vals(L,4,get_vals_int32);
}
static int lbuf_get_u32(lua_State *L) {
	return get_vals(L,4,get_vals_uint32);
}

/*
bool=lbuf:fread(file)
read lbuf from file (using existing size)
TODO may added partial read with size+offset later
*/
static int lbuf_fread(lua_State *L) {
	lBuf_t *buf = (lBuf_t *)luaL_checkudata(L,1,LBUF_META);
	FILE **pf = ((FILE **)luaL_checkudata(L, 2, LUA_FILEHANDLE));
	if(!*pf) {
		return luaL_error(L,"attempt to access closed file");
	}
	size_t r = fread(buf->bytes,buf->len,1,*pf);
	if(r != 1) {
		return luaL_error(L,"read failed");
	}
	lua_pushboolean(L,1);
	return 1;
}

/*
bool=lbuf:fwrite(file)
write lbuf to file
TODO may added partial write with size+offset later
*/
static int lbuf_fwrite(lua_State *L) {
	lBuf_t *buf = (lBuf_t *)luaL_checkudata(L,1,LBUF_META);
	FILE **pf = ((FILE **)luaL_checkudata(L, 2, LUA_FILEHANDLE));
	if(!*pf) {
		return luaL_error(L,"attempt to access closed file");
	}
	size_t r = fwrite(buf->bytes,buf->len,1,*pf);
	if(r != 1) {
		return luaL_error(L,"write failed");
	}
	lua_pushboolean(L,1);
	return 1;
}

static const luaL_Reg lbuf_methods[] = {
  {"len", lbuf_len},
  {"string", lbuf_string},
  {"byte", lbuf_byte},
  {"get_i32", lbuf_get_i32},
  {"get_u32", lbuf_get_u32},
  {"fread",lbuf_fread},
  {"fwrite",lbuf_fwrite},
  {NULL, NULL}
};

/*
lbuf=lbuf.new(<string|size>)
TODO accept lbuf to clone ?
*/
static int lbuf_new(lua_State *L) {
	size_t len;
	unsigned flags;
	const char *s=NULL;
	char *data;
	switch(lua_type(L,1)) {
		case LUA_TSTRING:
			s=lua_tolstring(L,1,&len);
			break;
		case LUA_TNUMBER:
			len=lua_tonumber(L,1);
			break;
		default:
			return luaL_error(L,"invalid argument");
	}
	if(len) {
		data=malloc(len);
		if(!data) {
			return luaL_error(L,"malloc failed");
		}
		if(s) {
			memcpy(data,s,len);
		} else {
			memset(data,0,len);
		}
		flags = LBUF_FL_FREE;
	} else { // might want to make zero size an error
		data=NULL;
		flags=0;
	}
	if(!lbuf_create(L,data,len,flags)) {
		return luaL_error(L,"create lbuf failed");
	}
	return 1;
}

static const luaL_Reg lbuf_funcs[] = {
  {"new", lbuf_new},
  {NULL, NULL}
};

static int lbuf_gc(lua_State *L) {
	lBuf_t *buf = (lBuf_t *)luaL_checkudata(L,1,LBUF_META);
	//printf("collecting lbuf %p:%d\n",buf->bytes,buf->len);
	if(buf->flags & LBUF_FL_FREE) {
		//printf("free\n",buf->len);
		free(buf->bytes);
		// ensure anything on the C side sees this as empty before final gc
		buf->len=0;
		buf->bytes=NULL;
	}	
	return 0;
}

static const luaL_Reg lbuf_meta_methods[] = {
  {"__gc", lbuf_gc},
  {NULL, NULL}
};

void lbuf_open(lua_State *L) {
	luaL_newmetatable(L,LBUF_META);
	luaL_register(L, NULL, lbuf_meta_methods);  
	/* use a table of methods for the __index method */
	lua_newtable(L);
	luaL_register(L, NULL, lbuf_methods);  
	lua_setfield(L,-2,"__index");
	/* global lib (mostly for testing*/
	lua_newtable(L);
	luaL_register(L, "lbuf", lbuf_methods);  
	luaL_register(L, NULL, lbuf_funcs);  
	lua_pop(L,3);
}
