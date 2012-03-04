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
/*
 * functions for handling remote camera display
 *
 */

#if !defined(CHDKPTP_LIVEVIEW)
#error "live view support not enabled"
#endif

#include <stdint.h>
#include <string.h>
#include <stdlib.h>
#include <lua.h>
#include <lualib.h>
#include <lauxlib.h>
#if defined(CHDKPTP_CD)
#include <cd.h>
#include <cdlua.h>
#endif
#include "core/live_view.h"
#include "lbuf.h"
#include "yuvutil.h"
#include "liveimg.h"
/*
planar img
TODO would make sense to use a CD bitmap for this but not public
also may want image handling without CD, but probably want packed rather than planar

TODO if we do packed, might want to make planar and packed use same struct with type flag
*/
typedef struct {
	unsigned width;
	unsigned height;
	uint8_t *data;
	uint8_t *r;
	uint8_t *g;
	uint8_t *b;
	uint8_t *a;
} liveimg_pimg_t;

typedef struct {
	uint8_t r;
	uint8_t g;
	uint8_t b;
	uint8_t a;
} palette_entry_rgba_t;

static void pimg_destroy(liveimg_pimg_t *im) {
	free(im->data);
	im->width = im->height = 0;
	im->data = im->r = im->g = im->b = im->a = NULL;
}
static int pimg_gc(lua_State *L) {
	liveimg_pimg_t *im = (liveimg_pimg_t *)luaL_checkudata(L,1,LIVEIMG_PIMG_META);
	pimg_destroy(im);
	return 0;
}

static int pimg_get_width(lua_State *L) {
	liveimg_pimg_t *im = (liveimg_pimg_t *)luaL_checkudata(L,1,LIVEIMG_PIMG_META);
	if(!im->data) {
		return luaL_error(L,"dead pimg");
	}
	lua_pushnumber(L,im->width);
	return 1;
}
static int pimg_get_height(lua_State *L) {
	liveimg_pimg_t *im = (liveimg_pimg_t *)luaL_checkudata(L,1,LIVEIMG_PIMG_META);
	if(!im->data) {
		return luaL_error(L,"dead pimg");
	}
	lua_pushnumber(L,im->height);
	return 1;
}

static int pimg_kill(lua_State *L) {
	liveimg_pimg_t *im = (liveimg_pimg_t *)luaL_checkudata(L,1,LIVEIMG_PIMG_META);
	pimg_destroy(im);
	return 0;
}

/*
create a new pimg and push it on the stack
TODO might want to pass in width, height or data, but need to handle rgb vs rgba
*/
int pimg_create(lua_State *L) {
	liveimg_pimg_t *im = (liveimg_pimg_t *)lua_newuserdata(L,sizeof(liveimg_pimg_t));
	if(!im) {
		return 0;
	}
	im->width = im->height = 0;
	im->data = im->r = im->g = im->b = im->a = NULL;
	luaL_getmetatable(L, LIVEIMG_PIMG_META);
	lua_setmetatable(L, -2);

	return 1;
}

int pimg_init_rgb(liveimg_pimg_t *im,unsigned width,unsigned height) {
	unsigned size = width*height;
	if(!size) {
		return 0;
	}
	im->data=malloc(size*3);
	if(!im->data) {
		return 0;
	}
	im->width = width;
	im->height = height;
	im->r=im->data;
	im->g=im->r+size;
	im->b=im->g+size;
	im->a=NULL;
	return 1;
}

/*
TODO stupid copy/paste
*/
int pimg_init_rgba(liveimg_pimg_t *im,unsigned width,unsigned height) {
	unsigned size = width*height;
	if(!size) {
		return 0;
	}
	im->data=malloc(size*4);
	if(!im->data) {
		return 0;
	}
	im->width = width;
	im->height = height;
	im->r=im->data;
	im->g=im->r+size;
	im->b=im->g+size;
	im->a=im->b+size;
	return 1;
}

/*
check whether given stack index is an pimg, and if so, return it
*/
liveimg_pimg_t * pimg_get(lua_State *L,int i) {
	if(!lua_isuserdata(L,i)) {
		return NULL;
	}
	if(lua_islightuserdata(L,i)) {
		return NULL;
	}
	if(!lua_getmetatable(L,i)) {
		return NULL;
	}
	lua_getfield(L,LUA_REGISTRYINDEX,LIVEIMG_PIMG_META);
	int r = lua_rawequal(L,-1,-2);
	lua_pop(L,2);
	if(r) {
		return lua_touserdata(L,i);
	}
	return NULL;
}

/*
convert viewport data to lbuf to RGB pimg
pimg=liveimg.get_viewport_pimg(pimg,base_info,vid_info,skip)
pimg: pimg to re-use, created if nil, replaced if size doesn't match
vid_info, base_info: from handler
skip: boolean - if true, each U Y V Y Y Y is converted to 2 pixels, otherwise 4
returns nil if info does not contain a live view
*/
static int liveimg_get_viewport_pimg(lua_State *L) {
	lv_vid_info *vi;
	lv_base_info *bi;
	liveimg_pimg_t *im = pimg_get(L,1);
	lBuf_t *base_lb = luaL_checkudata(L,2,LBUF_META);
	lBuf_t *vi_lb = luaL_checkudata(L,3,LBUF_META);
	int skip = lua_toboolean(L,4);
	// pixel aspect ratio
	int par = (skip == 1)?2:1;

	bi = (lv_base_info *)base_lb->bytes;
	vi = (lv_vid_info *)vi_lb->bytes;

	if(!vi->vp_buffer_start) {
		lua_pushnil(L);
		return 1;
	}

	unsigned vwidth = vi->vp_width/par;
	unsigned dispsize = vwidth*vi->vp_height;

	if(im && dispsize != im->width*im->height) {
		pimg_destroy(im);
		im = NULL;
	}
	if(im) {
		lua_pushvalue(L, 1); // copy im onto top for return
	} else { // create an new im 
		pimg_create(L);
		im = luaL_checkudata(L,-1,LIVEIMG_PIMG_META);
		if(!pimg_init_rgb(im,vwidth,vi->vp_height)) {
			return luaL_error(L,"failed to create image");
		}
	}

	yuv_live_to_cd_rgb(vi_lb->bytes+vi->vp_buffer_start,
						bi->vp_buffer_width,
						bi->vp_max_height,
						vi->vp_xoffset,
						vi->vp_yoffset,
						vi->vp_width,
						vi->vp_height,
						skip,
						im->r,im->g,im->b);
	return 1;
}

/*
convert bitmap data to RGBA pimg
pimg=liveimg.get_bitmap_pimg(pimg,base_info,vid_info,skip)
pimg: pimg to re-use, created if nil, replaced if size doesn't match
vid_info, base_info: from handler
skip: boolean - if true, every other pixel in the x axis is discarded (for viewports with a 1:2 par)
returns nil if info does not contain a bitmap
*/
static int liveimg_get_bitmap_pimg(lua_State *L) {
	palette_entry_rgba_t pal_rgba[256];

	lv_vid_info *vi;
	lv_base_info *bi;
	liveimg_pimg_t *im = pimg_get(L,1);
	lBuf_t *base_lb = luaL_checkudata(L,2,LBUF_META);
	lBuf_t *vi_lb = luaL_checkudata(L,3,LBUF_META);
	int skip = lua_toboolean(L,4);
	// pixel aspect ratio
	int par = (skip == 1)?2:1;

	bi = (lv_base_info *)base_lb->bytes;
	vi = (lv_vid_info *)vi_lb->bytes;

	if(!vi->bm_buffer_start) {
		lua_pushnil(L);
		return 1;
	}

	const char *pal=NULL;
	yuv_palette_to_rgba_fn fn=yuv_get_palette_to_rgba_fn(vi->palette_type);
	if(fn && vi->palette_buffer_start) {
		pal = ((char *)vi + vi->palette_buffer_start);
	} else {
		pal = yuv_default_type1_palette;
		fn = yuv_bmp_type1_set_rgba;
	}
	int i;
	for(i=0;i<255;i++) {
		fn(pal,i,&pal_rgba[i].r,&pal_rgba[i].g,&pal_rgba[i].b,&pal_rgba[i].a);
	}

	unsigned vwidth = bi->bm_max_width/par;
	unsigned dispsize = vwidth*bi->bm_max_height;

	if(im && dispsize != im->width*im->height) {
		pimg_destroy(im);
		im = NULL;
	}
	if(im) {
		lua_pushvalue(L, 1); // copy im onto top for return
	} else { // create an new im 
		pimg_create(L);
		im = luaL_checkudata(L,-1,LIVEIMG_PIMG_META);
		if(!pimg_init_rgba(im,vwidth,bi->bm_max_height)) {
			return luaL_error(L,"failed to create image");
		}
	}

	int y_inc = bi->bm_buffer_width;
	int x_inc = par;
	int x,y;
	int height = bi->bm_max_height;

	char *bmp = ((char *)vi + vi->bm_buffer_start);

	char *p=bmp + (height-1)*y_inc;

	uint8_t *r = im->r;
	uint8_t *g = im->g;
	uint8_t *b = im->b;
	uint8_t *a = im->a;

	for(y=0;y<height;y++,p-=y_inc) {
		for(x=0;x<bi->bm_max_width;x+=x_inc) {
			int c =*(p+x);
			*r++ = pal_rgba[c].r;
			*g++ = pal_rgba[c].g;
			*b++ = pal_rgba[c].b;
			*a++ = pal_rgba[c].a;
		}
	}
	return 1;
}

#if defined(CHDKPTP_CD)
/*
pimg:put_to_cd_canvas(canvas, x, y, width, height, xmin, xmax, ymin, ymax)
*/
static int pimg_put_to_cd_canvas(lua_State *L) {
	liveimg_pimg_t *im = (liveimg_pimg_t *)luaL_checkudata(L,1,LIVEIMG_PIMG_META);
	cdCanvas *cnv = cdlua_checkcanvas(L,2);
	if(!im->data) {
		return luaL_error(L,"dead pimg");
	}
	// left, bottom
	int x=luaL_optint(L,3,0);
	int y=luaL_optint(L,4,0);
	// target width, height. 0 = default
	int width=luaL_optint(L,5,0);
	int height=luaL_optint(L,6,0);
	// sub image
	int xmin=luaL_optint(L,7,0);
	int xmax=luaL_optint(L,8,0);
	int ymin=luaL_optint(L,9,0);
	int ymax=luaL_optint(L,10,0);
	cdCanvasPutImageRectRGB(cnv,
							im->width,im->height, // image size
							im->r,im->g,im->b, // data
							x,y,
							width,height,
							xmin,xmax,ymin,ymax);
	return 0;
}

/*
as above, but with alpha
*/
static int pimg_blend_to_cd_canvas(lua_State *L) {
	liveimg_pimg_t *im = (liveimg_pimg_t *)luaL_checkudata(L,1,LIVEIMG_PIMG_META);
	cdCanvas *cnv = cdlua_checkcanvas(L,2);
	if(!im->data) {
		return luaL_error(L,"dead pimg");
	}
	if(!im->a) {
		return luaL_error(L,"pimg has no alpha channel");
	}
	// left, bottom
	int x=luaL_optint(L,3,0);
	int y=luaL_optint(L,4,0);
	// target width, height. 0 = default
	int width=luaL_optint(L,5,0);
	int height=luaL_optint(L,6,0);
	// sub image
	int xmin=luaL_optint(L,7,0);
	int xmax=luaL_optint(L,8,0);
	int ymin=luaL_optint(L,9,0);
	int ymax=luaL_optint(L,10,0);
	cdCanvasPutImageRectRGBA(cnv,
							im->width,im->height, // image size
							im->r,im->g,im->b,im->a, // data
							x,y,
							width,height,
							xmin,xmax,ymin,ymax);
	return 0;
}

#endif

static const luaL_Reg liveimg_funcs[] = {
  {"get_bitmap_pimg", liveimg_get_bitmap_pimg},
  {"get_viewport_pimg", liveimg_get_viewport_pimg},
  {NULL, NULL}
};

static const luaL_Reg pimg_methods[] = {
#if defined(CHDKPTP_CD)
  {"put_to_cd_canvas", pimg_put_to_cd_canvas},
  {"blend_to_cd_canvas", pimg_blend_to_cd_canvas},
#endif
  {"width", pimg_get_width},
  {"height", pimg_get_height},
  {"kill", pimg_kill},
  {NULL, NULL}
};

static const luaL_Reg pimg_meta_methods[] = {
  {"__gc", pimg_gc},
  {NULL, NULL}
};

// TODO based on lbuf,
// would be nice to have a way to extend lbuf with additional custom bindings
void liveimg_open(lua_State *L) {
	luaL_newmetatable(L,LIVEIMG_PIMG_META);
	luaL_register(L, NULL, pimg_meta_methods);  

	/* use a table of methods for the __index method */
	lua_newtable(L);
	luaL_register(L, NULL, pimg_methods);  
	lua_setfield(L,-2,"__index");

	/* global lib */
	lua_newtable(L);
	luaL_register(L, "liveimg", liveimg_funcs);  
	lua_pop(L,3);
}

