--[[
 Copyright (C) 2010-2011 <reyalp (at) gmail dot com>

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
--]]
--[[
utilities for working with microsecond time provided by sys.gettimeofday
depends on chdkpt sys
]]

local proto={}

local mt={
	__index=function(t,key)
		return proto[key];
	end,
	-- TODO can add some more methods so regular operators work
}
local ustime={}
--[[
create a new ustime, defaulting to current time
]]
function ustime.new(sec,usec)
-- TODO user values are not normalized
	local t={sec=sec,usec=usec}
	setmetatable(t,mt)
	if not sec then
		t:get()
	elseif not usec then
		t.usec=0
	end
	return t;
end
--[[
return difference as number of microseconds
if only one time is given, subtract from current time
no provision is made for overflow
]]
function ustime.diff(t1,t0)
	if not t0 then
		t0 = t1
		t1 = ustime.new()
	end
	return (t1.sec - t0.sec)*1000000 + t1.usec - t0.usec
end

--[[
difference in ms
]]
function ustime.diffms(t1,t0)
	return ustime.diff(t1,t0)/1000
end

function proto:get()
	self.sec,self.usec = sys.gettimeofday()
end

return ustime
