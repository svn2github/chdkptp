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
#include <stdlib.h>
#include "yuvutil.h"

// from a540, playback mode
const char yuv_default_type1_palette[]={
0x00, 0x00, 0x00, 0x00, 0xff, 0xe0, 0x00, 0x00, 0xff, 0x60, 0xee, 0x62, 0xff, 0xb9, 0x00, 0x00,
0x7f, 0x00, 0x00, 0x00, 0xff, 0x7e, 0xa1, 0xb3, 0xff, 0xcc, 0xb8, 0x5e, 0xff, 0x5f, 0x00, 0x00,
0xff, 0x94, 0xc5, 0x5d, 0xff, 0x8a, 0x50, 0xb0, 0xff, 0x4b, 0x3d, 0xd4, 0x7f, 0x28, 0x00, 0x00,
0x7f, 0x00, 0x7b, 0xe2, 0xff, 0x30, 0x00, 0x00, 0xff, 0x69, 0x00, 0x00, 0xff, 0x00, 0x00, 0x00,
};

// type implied from index
struct {
	yuv_palette_to_rgb_fn to_rgb;
	yuv_palette_to_rgba_fn to_rgba;
} yuv_palette_funcs[] = {
	{NULL,NULL}, 					// type 0 - no palette, we could have a default func here
	{yuv_bmp_type1_blend_rgb,NULL}, // type 1 - ayuv
};

#define N_PALETTE_FUNCS (sizeof(yuv_palette_funcs)/sizeof(yuv_palette_funcs[0]))

yuv_palette_to_rgb_fn yuv_get_palette_to_rgb_fn(unsigned type) {
	if(type<N_PALETTE_FUNCS) {
		return yuv_palette_funcs[type].to_rgb;
	}
	return NULL;
}

static uint8_t clip_yuv(int v) {
	if (v<0) return 0;
	if (v>255) return 255;
	return v;
}

static uint8_t yuv_to_r(uint8_t y, int8_t v) {
	return clip_yuv(((y<<12) +          v*5743 + 2048)>>12);
}

static uint8_t yuv_to_g(uint8_t y, int8_t u, int8_t v) {
	return clip_yuv(((y<<12) - u*1411 - v*2925 + 2048)>>12);
}

static uint8_t yuv_to_b(uint8_t y, int8_t u) {
	return clip_yuv(((y<<12) + u*7258          + 2048)>>12);
}

static uint8_t blend(unsigned v1, unsigned v2,unsigned a) {
	return (v1*a + v2*(255 - a))/255;
}

static uint8_t clamp_uint8(unsigned v) {
	return (v>255)?255:v;
}

static int8_t clamp_int8(int v) {
	if(v>127) {
		return 127;
	}
	if(v<-128) {
		return -128;
	}
	return v;
}
/*
type 1 palette: 16 x 4 byte AYUV values
*/
void yuv_bmp_type1_blend_rgb(const char *palette, uint8_t pixel,uint8_t *r,uint8_t *g,uint8_t *b) {
	const yuv_palette_entry_ayuv_t *pal = (const yuv_palette_entry_ayuv_t *)palette;
	unsigned i1 = pixel & 0xF;
	unsigned i2 = (pixel & 0xF0)>>4;
	int8_t u,v;
	uint8_t y,a;
	a = (pal[i1].a + pal[i2].a)/2;
	y = clamp_uint8(pal[i1].y + pal[i2].y);
	u = clamp_int8(pal[i1].u + pal[i2].u);
	v = clamp_int8(pal[i1].v + pal[i2].v);
	*r = blend(yuv_to_r(y,v),*r,a);
	*g = blend(yuv_to_g(y,u,v),*g,a);
	*b = blend(yuv_to_b(y,u),*b,a);
}

void yuv_live_to_cd_rgb(const char *p_yuv,
						unsigned buf_width, unsigned buf_height,
						unsigned x_offset, unsigned y_offset,
						unsigned width,unsigned height,
						uint8_t *r,uint8_t *g,uint8_t *b) {
	unsigned x,y;
	unsigned y_inc = (buf_width*12)/8;
	const char *p;
	// flip for CD
	for(y=y_offset + height-1;y>y_offset;y--) {
		p = p_yuv + y * y_inc + (x_offset*12)/8;
		for(x=x_offset;x<width;x+=4,p+=6) {
			*r++ = yuv_to_r(p[1],p[2]);
			*g++ = yuv_to_g(p[1],p[0],p[2]);
			*b++ = yuv_to_b(p[1],p[0]);

			*r++ = yuv_to_r(p[3],p[2]);
			*g++ = yuv_to_g(p[3],p[0],p[2]);
			*b++ = yuv_to_b(p[3],p[0]);
		}
	}
}


