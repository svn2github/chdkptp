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

based on code from chdk tools/rawconvert.c and core/raw.c
*/
#include <stdint.h>
#include <stdlib.h>
#include <string.h>
#include <lua.h>
#include <lualib.h>
#include <lauxlib.h>
#include "lbuf.h"
#include "rawimg.h"

#define RAWIMG_LIST "rawimg.rawimg_list" // keeps references to associated lbufs
#define RAWIMG_LIST_META "rawimg.rawimg_list_meta" // meta table

unsigned raw_get_pixel_10l(const uint8_t *p, unsigned row_bytes, unsigned x, unsigned y);
unsigned raw_get_pixel_10b(const uint8_t *p, unsigned row_bytes, unsigned x, unsigned y);

unsigned raw_get_pixel_12l(const uint8_t *p, unsigned row_bytes, unsigned x, unsigned y);
unsigned raw_get_pixel_12b(const uint8_t *p, unsigned row_bytes, unsigned x, unsigned y);

unsigned raw_get_pixel_14l(const uint8_t *p, unsigned row_bytes, unsigned x, unsigned y);
unsigned raw_get_pixel_14b(const uint8_t *p, unsigned row_bytes, unsigned x, unsigned y);

// funny case for macros
#define RAW_ENDIAN_l 0
#define RAW_ENDIAN_b 1

static const char *endian_strings[] = {
	"little",
	"big",
	NULL,
};

#define RAW_BLOCK_BYTES_10l 10
#define RAW_BLOCK_BYTES_10b 5

#define RAW_BLOCK_BYTES_12l 6
#define RAW_BLOCK_BYTES_12b 3

#define RAW_BLOCK_BYTES_14l 14
#define RAW_BLOCK_BYTES_14b 7

typedef unsigned (*get_pixel_func_t)(const uint8_t *p, unsigned row_bytes, unsigned x, unsigned y);
typedef unsigned (*set_pixel_func_t)(uint8_t *p, unsigned row_bytes, unsigned x, unsigned y, unsigned value);

typedef struct {
	unsigned bpp;
	unsigned endian;
	unsigned block_bytes;
	unsigned block_pixels;
	get_pixel_func_t get_pixel;
} raw_format_t;

typedef struct {
	raw_format_t *fmt;
	unsigned row_bytes;
	unsigned width;
	unsigned height;
	uint8_t cfa_pattern[4];
	unsigned active_top;
	unsigned active_left;
	unsigned active_bottom;
	unsigned active_right;
	uint8_t *data;
} raw_image_t;

#define FMT_DEF_SINGLE(BPP,ENDIAN) \
{ \
	BPP, \
	RAW_ENDIAN_##ENDIAN, \
	RAW_BLOCK_BYTES_##BPP##ENDIAN, \
	RAW_BLOCK_BYTES_##BPP##ENDIAN*8/BPP, \
	raw_get_pixel_##BPP##ENDIAN, \
}

#define FMT_DEF(BPP) \
	FMT_DEF_SINGLE(BPP,l), \
	FMT_DEF_SINGLE(BPP,b)

raw_format_t raw_formats[] = {
	FMT_DEF(10),
	FMT_DEF(12),
	FMT_DEF(14),
};

static const int raw_num_formats = sizeof(raw_formats)/sizeof(raw_format_t);

static raw_format_t* rawimg_find_format(unsigned bpp, unsigned endian) {
	int i;
	for(i=0; i<raw_num_formats; i++) {
		raw_format_t *fmt = &raw_formats[i];
		if(fmt->endian == endian && fmt->bpp == bpp) {
			return fmt;
		}
	}
	return NULL;
}


unsigned raw_get_pixel_10l(const uint8_t *p, unsigned row_bytes, unsigned x, unsigned y)
{
	const uint8_t *addr = p + y * row_bytes + (x/8) * 10;
	switch (x&7) {
		case 0: return ((0x3fc&(((unsigned short)addr[1])<<2)) | (addr[0] >> 6));
		case 1: return ((0x3f0&(((unsigned short)addr[0])<<4)) | (addr[3] >> 4));
		case 2: return ((0x3c0&(((unsigned short)addr[3])<<6)) | (addr[2] >> 2));
		case 3: return ((0x300&(((unsigned short)addr[2])<<8)) | (addr[5]));
		case 4: return ((0x3fc&(((unsigned short)addr[4])<<2)) | (addr[7] >> 6));
		case 5: return ((0x3f0&(((unsigned short)addr[7])<<4)) | (addr[6] >> 4));
		case 6: return ((0x3c0&(((unsigned short)addr[6])<<6)) | (addr[9] >> 2));
		case 7: return ((0x300&(((unsigned short)addr[9])<<8)) | (addr[8]));
	}
	return 0;
}

unsigned raw_get_pixel_10b(const uint8_t *p, unsigned row_bytes, unsigned x, unsigned y)
{
	const uint8_t *addr = p + y * row_bytes + (x/4) * 5;

	switch (x&3) {
		case 0: return ((0x3fc&(((unsigned short)addr[0])<<2)) | (addr[1] >> 6));
		case 1: return ((0x3f0&(((unsigned short)addr[1])<<4)) | (addr[2] >> 4));
		case 2: return ((0x3c0&(((unsigned short)addr[2])<<6)) | (addr[3] >> 2));
		case 3: return ((0x300&(((unsigned short)addr[3])<<8)) | (addr[4]));
	}
	return 0;
}

/*
void raw_set_pixel_10l(uint8_t *p, unsigned row_bytes, unsigned x, unsigned y, unsigned value)
{
	uint8_t* addr = p + y*row_bytes + (x>>3)*10;
	switch (x&7) {
		case 0:
			addr[0] = (addr[0]&0x3F)|(value<<6); 
			addr[1] = value>>2;
		break;
		case 1:
			addr[0] = (addr[0]&0xC0)|(value>>4);
			addr[3] = (addr[3]&0x0F)|(value<<4);
		break;
		case 2:
			addr[2] = (addr[2]&0x03)|(value<<2);
			addr[3] = (addr[3]&0xF0)|(value>>6);
		break;
		case 3:
			addr[2] = (addr[2]&0xFC)|(value>>8); 
			addr[5] = value;
		break;
		case 4:
			addr[4] = value>>2;
			addr[7] = (addr[7]&0x3F)|(value<<6);
		break;
		case 5:
			addr[6] = (addr[6]&0x0F)|(value<<4);
			addr[7] = (addr[7]&0xC0)|(value>>4);
		break;
		case 6:
			addr[6] = (addr[6]&0xF0)|(value>>6);
			addr[9] = (addr[9]&0x03)|(value<<2);
		break;
		case 7:
			addr[8] = value;
			addr[9] = (addr[9]&0xFC)|(value>>8);
		break;
	}
}
*/

unsigned raw_get_pixel_12l(const uint8_t *p, unsigned row_bytes, unsigned x, unsigned y)
{
	const uint8_t *addr = p + y * row_bytes + (x/4) * 6;
	switch (x&3) {
		case 0: return ((unsigned short)(addr[1]) << 4) | (addr[0] >> 4);
		case 1: return ((unsigned short)(addr[0] & 0x0F) << 8) | (addr[3]);
		case 2: return ((unsigned short)(addr[2]) << 4) | (addr[5] >> 4);
		case 3: return ((unsigned short)(addr[5] & 0x0F) << 8) | (addr[4]);
	}
	return 0;
}

unsigned raw_get_pixel_12b(const uint8_t *p, unsigned row_bytes, unsigned x, unsigned y)
{
	const uint8_t *addr = p + y * row_bytes + (x/2) * 3;
	if (x&1)
		return ((unsigned short)(addr[1] & 0x0F) << 8) | (addr[2]);
	return ((unsigned short)(addr[0]) << 4) | (addr[1] >> 4);
}

// TODO set unused / unfinished
/*
unsigned raw_set_pixel_12l(const uint8_t *p, unsigned row_bytes, unsigned x, unsigned y, unsigned value)
{
	const uint8_t *addr = p + y * row_bytes + (x/4) * 6;
 switch (x&3) {
  case 0: 
   addr[0] = (addr[0]&0x0F) | (unsigned char)(value << 4);
   addr[1] = (unsigned char)(value >> 4);
   break;
  case 1: 
   addr[0] = (addr[0]&0xF0) | (unsigned char)(value >> 8);
   addr[3] = (unsigned char)value;
   break;
  case 2: 
   addr[2] = (unsigned char)(value >> 4);
   addr[5] = (addr[5]&0x0F) | (unsigned char)(value << 4);
   break;
  case 3: 
   addr[4] = (unsigned char)value;
   addr[5] = (addr[5]&0xF0) | (unsigned char)(value >> 8);
   break;
 }
}

unsigned raw_set_pixel_12b(const uint8_t *p, unsigned row_bytes, unsigned x, unsigned y, unsigned value)
{
	const uint8_t *addr = p + y * row_bytes + (x/2) * 3;
 switch (x&1) {
  case 0: 
   addr[0] = (unsigned char)(value >> 4);
   addr[1] = (addr[1]&0x0F) | (unsigned char)(value << 4);
   break;
  case 1: 
   addr[1] = (addr[1]&0xF0) | (unsigned char)(value >> 8);
   addr[2] = (unsigned char)value;
   break;
 }
}
*/

unsigned raw_get_pixel_14l(const uint8_t *p, unsigned row_bytes, unsigned x, unsigned y)
{
	const uint8_t *addr = p + y * row_bytes + (x/8) * 14;
    switch (x%8) {
        case 0: return ((unsigned short)(addr[ 1])        <<  6) | (addr[ 0] >> 2);
        case 1: return ((unsigned short)(addr[ 0] & 0x03) << 12) | (addr[ 3] << 4) | (addr[ 2] >> 4);
        case 2: return ((unsigned short)(addr[ 2] & 0x0F) << 10) | (addr[ 5] << 2) | (addr[ 4] >> 6);
        case 3: return ((unsigned short)(addr[ 4] & 0x3F) <<  8) | (addr[ 7]);
        case 4: return ((unsigned short)(addr[ 6])        <<  6) | (addr[ 9] >> 2);
        case 5: return ((unsigned short)(addr[ 9] & 0x03) << 12) | (addr[ 8] << 4) | (addr[11] >> 4);
        case 6: return ((unsigned short)(addr[11] & 0x0F) << 10) | (addr[10] << 2) | (addr[13] >> 6);
        case 7: return ((unsigned short)(addr[13] & 0x3F) <<  8) | (addr[12]);
    }
	return 0;
}

unsigned raw_get_pixel_14b(const uint8_t *p, unsigned row_bytes, unsigned x, unsigned y)
{
	const uint8_t *addr = p + y * row_bytes + (x/4) * 7;
    switch (x%4) {
        case 0: return ((unsigned short)(addr[ 0])        <<  6) | (addr[ 1] >> 2);
        case 1: return ((unsigned short)(addr[ 1] & 0x03) << 12) | (addr[ 2] << 4) | (addr[ 3] >> 4);
        case 2: return ((unsigned short)(addr[ 3] & 0x0F) << 10) | (addr[ 4] << 2) | (addr[ 5] >> 6);
        case 3: return ((unsigned short)(addr[ 5] & 0x3F) <<  8) | (addr[ 6]);
    }
	return 0;
}

/*
set 14 le
    unsigned char* addr=(unsigned char*)rawadr+y*camera_sensor.raw_rowlen+(x/8)*14;
    switch (x%8) {
        case 0: addr[ 0]=(addr[0]&0x03)|(value<< 2); addr[ 1]=value>>6;                                                         break;
        case 1: addr[ 0]=(addr[0]&0xFC)|(value>>12); addr[ 2]=(addr[ 2]&0x0F)|(value<< 4); addr[ 3]=value>>4;                   break;
        case 2: addr[ 2]=(addr[2]&0xF0)|(value>>10); addr[ 4]=(addr[ 4]&0x3F)|(value<< 6); addr[ 5]=value>>2;                   break;
        case 3: addr[ 4]=(addr[4]&0xC0)|(value>> 8); addr[ 7]=value;                                                            break;
        case 4: addr[ 6]=value>>6;                   addr[ 9]=(addr[ 9]&0x03)|(value<< 2);                                      break;
        case 5: addr[ 8]=value>>4;                   addr[ 9]=(addr[ 9]&0xFC)|(value>>12); addr[11]=(addr[11]&0x0F)|(value<<4); break;
        case 6: addr[10]=value>>2;                   addr[11]=(addr[11]&0xF0)|(value>>10); addr[13]=(addr[13]&0x3F)|(value<<6); break;
        case 7: addr[12]=value;                      addr[13]=(addr[13]&0xC0)|(value>> 8);                                      break;
    }

*/

/*
pixel=img:get_pixel(x,y)
nil if out of bounds
*/
static int rawimg_lua_get_pixel(lua_State *L) {
	raw_image_t* img = (raw_image_t *)luaL_checkudata(L, 1, RAWIMG_META);
	unsigned x = luaL_checknumber(L,2);
	unsigned y = luaL_checknumber(L,3);
	if(x >= img->width || y >= img->height) {
		lua_pushnil(L);
	} else {
		lua_pushnumber(L,img->fmt->get_pixel(img->data,img->row_bytes,x,y));
	}
	return 1;
}

static int rawimg_lua_get_width(lua_State *L) {
	raw_image_t* img = (raw_image_t *)luaL_checkudata(L, 1, RAWIMG_META);
	lua_pushnumber(L,img->width);
	return 1;
}

static int rawimg_lua_get_height(lua_State *L) {
	raw_image_t* img = (raw_image_t *)luaL_checkudata(L, 1, RAWIMG_META);
	lua_pushnumber(L,img->height);
	return 1;
}

static int rawimg_lua_get_bpp(lua_State *L) {
	raw_image_t* img = (raw_image_t *)luaL_checkudata(L, 1, RAWIMG_META);
	lua_pushnumber(L,img->fmt->bpp);
	return 1;
}

static int rawimg_lua_get_endian(lua_State *L) {
	raw_image_t* img = (raw_image_t *)luaL_checkudata(L, 1, RAWIMG_META);
	if(img->fmt->endian == RAW_ENDIAN_l) {
		lua_pushstring(L,"little");
	} else if(img->fmt->endian == RAW_ENDIAN_b) {
		lua_pushstring(L,"big");
	} else {
		return luaL_error(L,"invalid endian");
	}
	return 1;
}

static int rawimg_lua_get_cfa_pattern(lua_State *L) {
	raw_image_t* img = (raw_image_t *)luaL_checkudata(L, 1, RAWIMG_META);
	lua_pushlstring(L, (const char *)img->cfa_pattern,4);
	return 1;
}

/*
make a simple, low quality thumbnail image
thumb=img:make_rgb_thumb(width,height)
*/
static int rawimg_lua_make_rgb_thumb(lua_State *L) {
	raw_image_t* img = (raw_image_t *)luaL_checkudata(L, 1, RAWIMG_META);
	unsigned width=luaL_checknumber(L,2);
	unsigned height=luaL_checknumber(L,3);

	// TODO active area or not should be optional
	// image active area width
	unsigned iw = img->active_right - img->active_left;
	unsigned ih = img->active_bottom - img->active_top;
	if(width > iw || height > ih) {
		return luaL_error(L,"thumb cannot be larger than active area");
	}
	if(!width  || !height) {
		return luaL_error(L,"zero dimensions not allowed");
	}
	unsigned size = width*height*3;
	uint8_t *thumb = malloc(size);
	if(!thumb) {
		return luaL_error(L,"malloc failed for thumb");
	}

	int rx=0,ry=0,gx=0,gy=0,bx=0,by=0;
	int i;
	for(i=0;i<4;i++) {
		switch(img->cfa_pattern[i]) {
			case 0: rx = i&1; ry = (i&2)>>1; break;
			case 1: gx = i&1; gy = (i&2)>>1; break; // will get hit twice, doesn't matter
			case 2: bx = i&1; by = (i&2)>>1; break;
		}
	}
	unsigned tx,ty;
	uint8_t *p = thumb;
	unsigned shift = img->fmt->bpp - 8;
	for(ty=0;ty<height;ty++) {
		for(tx=0;tx<width;tx++) {
			unsigned ix = (img->active_left + tx*iw/width)&~1;
			unsigned iy = (img->active_top + ty*ih/height)&~1;
			*p++=img->fmt->get_pixel(img->data,img->row_bytes,ix+rx,iy+ry)>>shift;
			*p++=img->fmt->get_pixel(img->data,img->row_bytes,ix+gx,iy+gy)>>shift;
			*p++=img->fmt->get_pixel(img->data,img->row_bytes,bx+gx,iy+by)>>shift;
		}
	}
	if(!lbuf_create(L, thumb, size, LBUF_FL_FREE)) {
		return luaL_error(L,"failed to create lbuf");
	}
	return 1;
}

/*
helper functions to get args from a table
should be a standalone utility library
throw error on incorrect type, return C value and pop off the stack
*/
static void *table_checkudata(lua_State *L, int narg, const char *fname, const char *tname) {
	lua_getfield(L, narg, fname);
	void *r = luaL_checkudata(L,-1,tname);
	lua_pop(L,1);
	return r;
}

static lua_Number table_checknumber(lua_State *L, int narg, const char *fname) {
	lua_getfield(L, narg, fname);
	lua_Number r = luaL_checknumber(L,-1);
	lua_pop(L,1);
	return r;
}

static lua_Number table_optnumber(lua_State *L, int narg, const char *fname, lua_Number d) {
	lua_getfield(L, narg, fname);
	lua_Number r = luaL_optnumber(L,-1,d);
	lua_pop(L,1);
	return r;
}

/*
static const char *table_checkstring(lua_State *L, int narg, const char *fname) {
	lua_getfield(L, narg, fname);
	const char *r = luaL_checkstring(L,-1);
	lua_pop(L,1);
	return r;
}
*/
static int table_checkoption(lua_State *L, int narg, const char *fname, const char *def, const char *lst[]) {
	lua_getfield(L, narg, fname);
	int r = luaL_checkoption(L,-1, def, lst);
	lua_pop(L,1);
	return r;
}

static const char *table_optlstring(lua_State *L, int narg, const char *fname, const char *d, size_t *l) {
	lua_getfield(L, narg, fname);
	const char *r = luaL_optlstring(L,-1,d,l);
	lua_pop(L,1);
	return r;
}

/*
img = rawimg.bind_lbuf(imgspec)
imgspec {
-- required fields
	data:lbuf
	width:number
	height:number
	bpp:number
	endian:string "little"|"big"
-- optional fields
	data_offset:number -- offset into data lbuf, default 0
	cfa_pattern:string -- 4 byte string
	active_area: { -- default 0,0,height,width
		top:number
		left:number
		bottom:number
		right:number
	} 
	color_matrix: -- TODO
}

*/
static int rawimg_lua_bind_lbuf(lua_State *L) {
	raw_image_t *img = (raw_image_t *)lua_newuserdata(L,sizeof(raw_image_t));
	if(!img) {
		return luaL_error(L,"failed to create userdata");;
	}

	if(!lua_istable(L,1)) {
		return luaL_error(L,"expected table");;
	}

	lBuf_t *buf = (lBuf_t *)table_checkudata(L,1,"data",LBUF_META);

	unsigned offset = table_optnumber(L,1,"data_offset",0);

	img->width = table_checknumber(L,1,"width");
	img->height = table_checknumber(L,1,"height");
	unsigned bpp = table_checknumber(L,1,"bpp");

	unsigned endian = table_checkoption(L,1,"endian",NULL,endian_strings);

	size_t cfa_size;
	const char *cfa_pattern = table_optlstring(L,1,"cfa_pattern",NULL,&cfa_size);
	if(!cfa_pattern) {
		memset(img->cfa_pattern,0,4);
	} else if(cfa_size != 4) {
		return luaL_error(L,"unknown cfa pattern");
	} else {
		memcpy(img->cfa_pattern,cfa_pattern,4);
	}

	// active area
	lua_getfield(L, 1, "active_area");
	if(lua_istable(L,-1)) {
		// if table present, all required
		img->active_top = table_checknumber(L,-1,"top");
		img->active_left = table_checknumber(L,-1,"left");
		img->active_bottom = table_checknumber(L,-1,"bottom");
		img->active_right = table_checknumber(L,-1,"right");
		if(img->active_top >= img->active_bottom) {
			return luaL_error(L,"active top >= bottom");
		}
		if(img->active_left >= img->active_right) {
			return luaL_error(L,"active left >= right");
		}
		if(img->active_left > img->width) {
			return luaL_error(L,"active right > width");
		}
		if(img->active_bottom > img->height) {
			return luaL_error(L,"active bottom > height");
		}
	} else {
		img->active_top = img->active_left = 0;
		img->active_right = img->width;
		img->active_bottom = img->height;
	}
	lua_pop(L,1); // pop off active area or nil
	

	img->fmt = rawimg_find_format(bpp,endian);
	if(!img->fmt) {
		return luaL_error(L,"unknown format");
	}
	
	if(img->width % img->fmt->block_pixels != 0) {
		return luaL_error(L,"width not a multiple of block size");
	}
	img->row_bytes = (img->width*img->fmt->bpp)/8;
	if(offset + img->row_bytes*img->height > buf->len) {
		return luaL_error(L,"size larger than data");
	}
	img->data = (uint8_t *)buf->bytes + offset;

	luaL_getmetatable(L, RAWIMG_META);
	lua_setmetatable(L, -2);
	
	// save a reference in the registry to keep lbuf from being collected until image goes away
	lua_getfield(L,LUA_REGISTRYINDEX,RAWIMG_LIST);
	lua_pushvalue(L, -2); // our user data, for use as key
	lua_pushvalue(L, 1); // lbuf, the value
	lua_settable(L, -3); //set t[img]=lbuf
	lua_pop(L,1); // done with t

	return 1;
}

static const luaL_Reg rawimg_lib[] = {
	{"bind_lbuf",rawimg_lua_bind_lbuf},
	{NULL, NULL}
};

// only for testing
/*
static int rawimg_gc(lua_State *L) {
	raw_image_t *img = (raw_image_t *)luaL_checkudata(L,1,RAWIMG_META);
	printf("collecting img %p:%dx%d\n",img->data,img->width,img->height);
	return 0;
}

static const luaL_Reg rawimg_meta_methods[] = {
  {"__gc", rawimg_gc},
  {NULL, NULL}
};
*/

static const luaL_Reg rawimg_methods[] = {
	{"get_pixel",rawimg_lua_get_pixel},
	/*
	{"set_pixel",rawimg_set_pixel},
	*/
	{"width",rawimg_lua_get_width},
	{"height",rawimg_lua_get_height},
	{"bpp",rawimg_lua_get_bpp},
	{"endian",rawimg_lua_get_endian},
	{"cfa_pattern",rawimg_lua_get_cfa_pattern},
	{"make_rgb_thumb",rawimg_lua_make_rgb_thumb},
	{NULL, NULL}
};

void rawimg_open(lua_State *L) {
	luaL_newmetatable(L,RAWIMG_META);

	/* use a table of methods for the __index method */
//	luaL_register(L, NULL, rawimg_meta_methods);  
	lua_newtable(L);
	luaL_register(L, NULL, rawimg_methods);  
	lua_setfield(L,-2,"__index");
	lua_pop(L,1); // done with meta table
	
	// create a table to keep track of lbufs referenced by raw images
	lua_newtable(L);
	// metatable for above
	luaL_newmetatable(L, RAWIMG_LIST_META);
	lua_pushstring(L, "k");  /* mode values: weak keys, strong values */
	lua_setfield(L, -2, "__mode");  /* metatable.__mode */
	lua_setmetatable(L,-2);
	lua_setfield(L,LUA_REGISTRYINDEX,RAWIMG_LIST);
	lua_pop(L,1); // done with list table

	luaL_register(L, "rawimg", rawimg_lib);  
}
