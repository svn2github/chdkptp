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
#include <lua.h>
#include <lualib.h>
#include <lauxlib.h>
#include "lbuf.h"
#include "rawimg.h"

unsigned raw_get_pixel_10l(const uint8_t *addr, unsigned x);
unsigned raw_get_pixel_10b(const uint8_t *addr, unsigned x);
uint8_t* raw_get_block_addr_10l(char *buf, unsigned len, unsigned row_bytes, unsigned x, unsigned y);
uint8_t* raw_get_block_addr_10b(char *buf, unsigned len, unsigned row_bytes, unsigned x, unsigned y);

unsigned raw_get_pixel_12l(const uint8_t *addr, unsigned x);
unsigned raw_get_pixel_12b(const uint8_t *addr, unsigned x);
uint8_t* raw_get_block_addr_12l(char *buf, unsigned len, unsigned row_bytes, unsigned x, unsigned y);
uint8_t* raw_get_block_addr_12b(char *buf, unsigned len, unsigned row_bytes, unsigned x, unsigned y);

unsigned raw_get_pixel_14l(const uint8_t *addr, unsigned x);
unsigned raw_get_pixel_14b(const uint8_t *addr, unsigned x);
uint8_t* raw_get_block_addr_14l(char *buf, unsigned len, unsigned row_bytes, unsigned x, unsigned y);
uint8_t* raw_get_block_addr_14b(char *buf, unsigned len, unsigned row_bytes, unsigned x, unsigned y);

#define RAW_ENDIAN_l 0
#define RAW_ENDIAN_b 1

typedef unsigned (*get_pixel_func_t)(const uint8_t *p, unsigned x);
typedef unsigned (*set_pixel_func_t)(uint8_t *p, unsigned x, unsigned value);
typedef uint8_t * (*get_block_addr_func_t)(char *buf, unsigned len, unsigned row_bytes, unsigned x, unsigned y);

typedef struct {
	int bpp;
	int endian;
	get_pixel_func_t get_pixel;
	get_block_addr_func_t get_block_addr;
} raw_format_t;

#define FMT_DEF_SINGLE(BPP,ENDIAN) \
{ \
	BPP, \
	RAW_ENDIAN_##ENDIAN, \
	raw_get_pixel_##BPP##ENDIAN, \
	raw_get_block_addr_##BPP##ENDIAN, \
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

unsigned raw_get_pixel_10l(const uint8_t *addr, unsigned x)
{
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

unsigned raw_get_pixel_10b(const uint8_t *addr, unsigned x)
{
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

unsigned raw_get_pixel_12l(const uint8_t *addr, unsigned x)
{
	switch (x&3) {
		case 0: return ((unsigned short)(addr[1]) << 4) | (addr[0] >> 4);
		case 1: return ((unsigned short)(addr[0] & 0x0F) << 8) | (addr[3]);
		case 2: return ((unsigned short)(addr[2]) << 4) | (addr[5] >> 4);
		case 3: return ((unsigned short)(addr[5] & 0x0F) << 8) | (addr[4]);
	}
	return 0;
}

unsigned raw_get_pixel_12b(const uint8_t *addr, unsigned x)
{
	if (x&1)
		return ((unsigned short)(addr[1] & 0x0F) << 8) | (addr[2]);
	return ((unsigned short)(addr[0]) << 4) | (addr[1] >> 4);
}

// TODO set unused / untested
/*
void raw_set_pixel_12l(uint8_t *addr, unsigned x, unsigned value)
{
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

void raw_set_pixel_12b(uint8_t *addr, unsigned x, unsigned value)
{
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

unsigned raw_get_pixel_14l(const uint8_t *addr, unsigned x)
{
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

unsigned raw_get_pixel_14b(const uint8_t *addr, unsigned x)
{
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
get the starting address for the block of bytes that includes x,y rounded to the size of the smallest repeating pattern
*/
uint8_t* raw_get_block_addr_10l(char *buf, unsigned len, unsigned row_bytes, unsigned x, unsigned y) {
	unsigned offset = y * row_bytes + (x/8) * 10;
	if(offset + 10 > len) {
		return NULL;
	}
	return (uint8_t *)buf + offset;
}

uint8_t* raw_get_block_addr_10b(char *buf, unsigned len, unsigned row_bytes, unsigned x, unsigned y) {
	unsigned offset = y * row_bytes + (x/4) * 5;
	if(offset + 5 > len) {
		return NULL;
	}
	return (uint8_t *)buf + offset;
}

uint8_t* raw_get_block_addr_12l(char *buf, unsigned len, unsigned row_bytes, unsigned x, unsigned y) {
	unsigned offset = y * row_bytes + (x/4) * 6;
	if(offset + 6 > len) {
		return NULL;
	}
	return (uint8_t *)buf + offset;
}

uint8_t* raw_get_block_addr_12b(char *buf, unsigned len, unsigned row_bytes, unsigned x, unsigned y) {
	unsigned offset = y * row_bytes + (x/2) * 3;
	if(offset + 3 > len) {
		return NULL;
	}
	return (uint8_t *)buf + offset;
}

uint8_t* raw_get_block_addr_14l(char *buf, unsigned len, unsigned row_bytes, unsigned x, unsigned y) {
	unsigned offset = y * row_bytes + (x/8) * 14;
	if(offset + 14 > len) {
		return NULL;
	}
	return (uint8_t *)buf + offset;
}

uint8_t* raw_get_block_addr_14b(char *buf, unsigned len, unsigned row_bytes, unsigned x, unsigned y) {
	unsigned offset = y * row_bytes + (x/4) * 7;
	if(offset + 7 > len) {
		return NULL;
	}
	return (uint8_t *)buf + offset;
}

static int raw_get_pixel_lua(lua_State *L) {
	raw_format_t* fmt = (raw_format_t *)lua_touserdata(L, lua_upvalueindex(1));
	lBuf_t *buf = (lBuf_t *)luaL_checkudata(L,1,LBUF_META);
	unsigned row_bytes = luaL_checknumber(L,2);
	unsigned x = luaL_checknumber(L,3);
	unsigned y = luaL_checknumber(L,4);
	const uint8_t *addr = fmt->get_block_addr(buf->bytes,buf->len,row_bytes,x,y);
	if(!addr) {
		return luaL_error(L,"coordinates out of range");
	}
	lua_pushnumber(L,fmt->get_pixel(addr,x));
	return 1;
}

/*
static const luaL_Reg rawimg_methods[] = {
	{NULL, NULL}
};
*/

void rawimg_open(lua_State *L) {
//	luaL_register(L, "rawimg", rawimg_methods);  
	lua_createtable(L, 0, raw_num_formats);

	int i;
	for(i=0; i<raw_num_formats; i++) {
		char name[64];
		raw_format_t *fmt = &raw_formats[i];
		lua_pushlightuserdata( L, fmt );
		lua_pushcclosure( L, raw_get_pixel_lua, 1 );
		sprintf(name,"get_pixel_%d%c",fmt->bpp,(fmt->endian == RAW_ENDIAN_l)?'l':'b');
		lua_setfield(L, -2, name);
	}
	lua_setglobal( L, "rawimg" );
}
