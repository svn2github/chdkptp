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
!p1=pt.get(0,300)
=press'shoot_half' repeat sleep(10) until get_shooting()
!p2=pt.get(0,300)
!pt.comp(p1,p2)
]]
local m={}
--[[
get a range of propcase values (as shorts with get_prop)
returns an array (index starts at 1) so use i-1 for propcase number
]]
function m.get(start,count)
	if not start then
		start=0
	end
	if not count then
		count=1
	end
	local props={}
	con:execwait(string.format([[
local min=%d
local max=%s
]],start,start+count)..[[
local b=msg_batcher()

for i=min,max do
	b:write(get_prop(i))
end
b:flush()
]],{libs='msg_batcher',msgs=chdku.msg_unbatcher(props)})
	return props
end

function m.fmt(i,v)
	-- bit32.extract to handle negatives, otherwise error with %x
	return string.format("%4d %04x %6d",i-1,bit32.extract(v,0,16),v)
end

-- print an array returned by get
function m.print(props)
	for i,v in ipairs(props) do
		printf("%s\n",m.fmt(i,v))
	end
end
-- compare arrays returned by get
function m.comp(old,new)
	for i,v in ipairs(new) do
		if v ~= old[i] then
			if old[i] then
				printf("< %s\n",m.fmt(i,old[i]))
			else
				printf("< (missing)\n")
			end
			printf("> %s\n",m.fmt(i,v))
		end
	end
end
return m
