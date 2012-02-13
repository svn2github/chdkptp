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
#include "yuvutil.h"

static uint8_t clip_yuv(int v) {
	if (v<0) return 0;
	if (v>255) return 255;
	return v;
}

static uint8_t yuv_to_r(uint8_t y, int8_t v) {
	return clip_yuv(((y<<12) +          v*5743 + 2048)>>12);
}

static uint8_t yuv_to_b(uint8_t y, int8_t u, int8_t v) {
	return clip_yuv(((y<<12) - u*1411 - v*2925 + 2048)>>12);
}

static uint8_t yuv_to_g(uint8_t y, int8_t u) {
	return clip_yuv(((y<<12) + u*7258          + 2048)>>12);
}

void yuv_live_to_cd_rgb(const char *p_yuv,unsigned width,unsigned height,char *r,char *g,char *b) {
	unsigned x,y;
	unsigned y_inc = (width*12)/8;
	const char *p;
	// flip for CD
	for(y=height-1;y>0;y--) {
		p = p_yuv + y * y_inc;
		for(x=0;x<width;x+=4,p+=6) {
			*r++ = yuv_to_r(p[1],p[2]);
			*b++ = yuv_to_b(p[1],p[0],p[2]);
			*g++ = yuv_to_g(p[1],p[0]);

			*r++ = yuv_to_r(p[3],p[2]);
			*b++ = yuv_to_b(p[3],p[0],p[2]);
			*g++ = yuv_to_g(p[3],p[0]);
		}
	}
}


