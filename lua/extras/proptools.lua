--[[
 Copyright (C) 2016 <reyalp (at) gmail dot com>

  This program is free software; you can redistribute it and/or modify
  it under the terms of the GNU General Public License version 2 as
  published by the Free Software Foundation.

  This program is distributed in the hope that it will be useful,
  but WITHOUT ANY WARRANTY; without even the implied warranty of
  MERCHANTABILITY or FITNESS FOR A PARTICULAR PURPOSE.  See the
  GNU General Public License for more details.

  You should have received a copy of the GNU General Public License
  along with this program; if not, write to the Free Software
  Foundation, Inc., 59 Temple Place, Suite 330, Boston, MA  02111-1307  USA

simple module for propcase testing

example
!pt=require'extras/proptools'
!p1=pt.get(0,600)
!pt.comp(p1,pt.get(0,600,"press'shoot_half' sleep(500)"))
]]
local m={}
--[[
get a range of propcase values, as shorts from get_prop
returns a table indexed by prop id. Use _min, _max to iterate, not ipairs!
]]
function m.get(start,count,init_code)
	if not start then
		start=0
	end
	if not count then
		count=1
	end
	if not init_code then
		init_code=''
	end
	local max=start+count
	local code = init
	local t={}
	con:execwait(string.format([[
%s
local min=%d
local max=%s
]],init_code,start,max)..[[
local b=msg_batcher()

for i=min,max do
	b:write(get_prop(i))
end
b:flush()
]],{libs='msg_batcher',msgs=chdku.msg_unbatcher(t)})
	local props={_min=start,_max=max}
	-- remap to prop IDs
	for i,v in ipairs(t) do
		props[start+i-1]=v
	end
	return props
end

function m.fmt(props,i)
	-- bit32.extract to handle negatives, otherwise error with %x
	local v=props[i];
	return string.format("%4d %04x %6d",i,bit32.extract(v,0,16),v)
end

-- print an array returned by get
function m.print(props)
	for i=props._min,props._max do
		printf("%s\n",m.fmt(props,i))
	end
end
function m.write(props,filename)
	local fh=fsutil.open_e(filename,'wb')
	for i=props._min,props._max do
		fh:write(string.format("%s\n",m.fmt(props,i)))
	end
	fh:close()
end
-- compare arrays returned by get
function m.comp(old,new)
	for i=new._min,new._max do
		if new[i] ~= old[i] then
			if old[i] then
				printf("< %s\n",m.fmt(old,i))
			else
				printf("< (missing)\n")
			end
			printf("> %s\n",m.fmt(new,i))
		end
	end
end
return m
