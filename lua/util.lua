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
-- common misc utilties
-- loaded after lua libs and chdk.* low level ptp lib
local util={}
function util.fprintf(f,...)
	local args={...}
	if #args == 0 or type(args[1]) ~= 'string' then
		args[1]=''
	end
	f:write(string.format(unpack(args)))
end

function util.printf(...)
	fprintf(io.stdout,...)
end

function util.warnf(format,...)
	fprintf(io.stderr,"WARNING: " .. format,...)
end

function util.errf(format,...)
	fprintf(io.stderr,"ERROR: " .. format,...)
end

function util.hexdump(str,offset)
	local c, result, byte
	if not offset then
		offset = 0
	end
	c = 0
	result = ''
	for i=1,#str do
		if c == 0 then
			result = result .. string.format("%8x: ",offset)
		end
		result = result .. string.format("%02x ",string.byte(str,i))
		c = c + 1
		if c == 16 then
			c = 0
			offset = offset + 16
			result = result .. "| " .. string.gsub(string.sub(str,i-15,i),'[%c%z%s\128-\255]','.') .. '\n'
		end
	end
	if c ~= 0 then
		for i=1,16-c do
			result = result .. "-- "
		end
		result = result .. "| " .. string.gsub(string.sub(str,-c),'[%c%z%s\128-\255]','.')
	end
	return result
end

local serialize_r
serialize_r = function(v,sinfo)
	local vt = type(v)
	if vt == 'nil' or  vt == 'boolean' or vt == 'number' then
		return tostring(v)
	elseif vt == 'string' then
		return string.format('%q',v)
	elseif vt == 'table' then
		if type(sinfo) == 'nil' then
			sinfo = {level=0}
		else
			sinfo.level = sinfo.level+1
		end
		if sinfo.level >= 10 then
			error('serialize: table max depth exceeded')
		end
		if sinfo[v] then 
			error('serialize: cyclic table reference')
		end
		sinfo[v] = true;
		local r='{'
		for k,v1 in pairs(v) do
			r = r .. '\n' ..  string.rep(' ',sinfo.level+1)
			-- more compact/friendly format integer/simple string keys
			if type(k) == 'number' or (type(k) == 'string' and string.match(k,'^[_%a][%a%d_]*$')) then
				r = r .. tostring(k)
			else
				r = r .. '[' .. serialize_r(k,sinfo) .. ']'
			end
			r = r .. '=' .. serialize_r(v1,sinfo) .. ','
		end
		r = r .. '\n' .. string.rep(' ',sinfo.level) .. '}'
		if sinfo.level > 0 then
			sinfo.level = sinfo.level - 1
		end
		return r
	else
		error('serialize: unsupported type ' .. vt, 2)
	end
end

--[[
serialize lua values
TODO should have some options
- convert numbers to ints for camera
- pretty vs compact
- handling of unsupported types and cycles, ignore, error etc
- depth
--]]
function util.serialize(v)
	return serialize_r(v)
end

--[[
similar to unix basename
--]]
function util.basename(path,sfx)
	local s,e,bn=string.find(path,'([^\\/]+)[\\/]?$')
	if not s then
		return nil
	end
	if sfx and string.len(sfx) < string.len(bn) then
		if string.sub(bn,-string.len(sfx)) == sfx then
			bn=string.sub(bn,1,string.len(bn) - string.len(sfx))
		end
	end
	return bn
end

-- hacky hacky "import" values from a table into globals
function util.import(t,names)
	if names == nil then
		for name,val in pairs(t) do
			_G[name] = val
		end
		return
	end
	for i,name in ipairs(names) do
		if t[name] ~= nil then
			_G[name] = t[name]
		end
	end
end
return util
