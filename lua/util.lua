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
common generic lua utilties
utilities that depend on the chdkptp api go in chdku
]]
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

--[[ 
copy members of source into target
by default, not deep so any tables will be copied as references
returns target so you can do x=extend_table({},...)
if deep, cycles result in an error
deep does not copy keys which are themselves tables
]]
util.extend_table_max_depth = 10
local extend_table_r
extend_table_r = function(target,source,seen,depth) 
	if not seen then
		seen = {}
	end
	if not depth then
		depth = 1
	end
	if depth > util.extend_table_max_depth then
		error('extend_table: max depth');
	end
	-- a source could have refernces to the target, don't want to do that
	seen[target]=true
	if seen[source] then
		error('extend_table: cycles');
	end
	seen[source]=true
	for k,v in pairs(source) do
		if type(v) == 'table' then
			if type(target[k]) ~= 'table' then
				target[k] = {}
			end
			extend_table_r(target[k],v,seen,depth+1)
		else
			target[k]=v
		end
	end
	return target
end

function util.extend_table(target,source,deep)
	if type(source) ~= 'table' then 
		error('extend_table: source not table')
	end
	if type(target) ~= 'table' then
		error('extend_table: target not table')
	end
	if source == target then
		error('extend_table: source == target')
	end
	if deep then
		return extend_table_r(target, source)
	else 
		for k,v in pairs(source) do
			target[k]=v
		end
		return target
	end
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
serialize_r = function(v,opts,seen,depth)
	local vt = type(v)
	if vt == 'nil' or  vt == 'boolean' or vt == 'number' then
		return tostring(v)
	elseif vt == 'string' then
		return string.format('%q',v)
	elseif vt == 'table' then
		if not depth then
			depth = 1
		end
		if depth >= opts.maxdepth then
			error('serialize: max depth')
		end
		if not seen then
			seen={}
		elseif seen[v] then 
			if opts.err_cycle then
				error('serialize: cycle')
			else
				return '"cycle:'..tostring(v)..'"'
			end
		end
		seen[v] = true;
		local r='{'
		for k,v1 in pairs(v) do
			if opts.pretty then
				r = r .. '\n' ..  string.rep(' ',depth)
			end
			-- more compact/friendly format simple string keys
			-- TODO we could make integers more compact by doing array part first
			if type(k) == 'string' and string.match(k,'^[_%a][%a%d_]*$') then
				r = r .. tostring(k)
			else
				r = r .. '[' .. serialize_r(k,opts,seen,depth+1) .. ']'
			end
			r = r .. '=' .. serialize_r(v1,opts,seen,depth+1) .. ','
		end
		if opts.pretty then
			r = r .. '\n' .. string.rep(' ',depth-1)
		end
		r = r .. '}'
		return r
	elseif opts.err_type then
		error('serialize: unsupported type ' .. vt, 2)
	else
		return '"'..tostring(v)..'"'
	end
end

util.serialize_defaults = {
	-- maximum nested depth
	maxdepth=10,
	-- ignore or error on various conditions
	err_type=true, -- bad type, e.g. function, userdata
	err_cycle=true, -- cyclic references
	pretty=true, -- indents and newlines
}

--[[
serialize lua values
TODO should have some options
- convert numbers to ints for camera
- pretty vs compact
- handling of unsupported types and cycles, ignore, error etc
- depth
]]
function util.serialize(v,opts_in)
	local opts = util.extend_table({},util.serialize_defaults)
	if type(opts_in) == 'table' then
		util.extend_table(opts,opts_in)
	end
	return serialize_r(v,opts)
end


--[[
turn string back into lua data by executing it. Not safe for untrusted data!
returns the resulting value, or false + an error message on failure
check the message, since the serialized value might be false or nil!
]]
function util.unserialize(s)
	local f,err=loadstring('return ' .. s)
	if not f then
		return false, err
	end
	local status,r=pcall(f)
	if status then
		return r
	end
	return false,r
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
