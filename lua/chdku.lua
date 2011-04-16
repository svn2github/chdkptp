--[[
lua helper functions for working with the chdk.* c api

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
local chdku={}
-- format a script message in a human readable way
function chdku.format_script_msg(msg)
	if msg.type == 'none' then
		return ''
	end
	local r=string.format("%d:%s:",msg.script_id,msg.type)
	-- for user messages, type is clear from value, strings quoted, others not
	if msg.type == 'user' or msg.type == 'return' then
		if msg.subtype == 'boolean' or msg.subtype == 'integer' or msg.subtype == 'nil' then
			r = r .. tostring(msg.value)
		elseif msg.subtype == 'string' then
			r = r .. string.format("'%s'",msg.value)
		else
			r = r .. msg.subtype .. ':' .. tostring(msg.value)
		end
	elseif msg.type == 'error' then
		r = r .. msg.subtype .. ':' .. tostring(msg.value)
	end
	return r
end

--[[
chunks of source code to be used remotely
can be used with chdku.exec
TODO some of these are duplicated with local code, but we don't yet have an easy way of sharing them
TODO would be good to minify
TODO handle order and dependencies
]]
chdku.rlib={
	-- mostly duplicated from util.serialize_r
	serialize=[[
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
]],
-- override default table serialization for messages
	serialize_msgs=[[
	usb_msg_table_to_string=serialize_r
]],
-- return file listing as {'filename'='f|d'}
-- note that non-file, non-directory will be ignored
-- may run out of memory on very large directories
	ls=[[
function ls(path)
	local t,msg=os.listdir(path)
	local r={}
	if not t then
		return msg
	end
	for k,v in pairs(t) do
		local s,msg=os.stat(path..'/'..v)
		if not s then
			return msg
		end
		if s.is_dir then
			r[v]='d'
		elseif s.is_file then
			r[v]='f'
		end
	end
	return r
end
]],
-- list directory as {'filename'={stat(filename)}}
-- more likely to run out of memory, should use putm messages
-- TODO checks stat status
	lsstat=[[
function lsstat(path)
	local t,msg=os.listdir(path)
	if not t then
		return msg
	end
	local r={}
	for k,v in pairs(t) do
		local s,msg = os.stat(path..'/'..v)
		if s then
			r[v]=s
		end
	end
	return r
end
]],
}

--[[
return a list of remote directory contents
return
table|false,msg
note may return an empty table if target is not a directory
]]
function chdku.listdir(path,mode) 
	if mode then
		chdku.exec("return lsstat('"..path.."')",{'serialize','serialize_msgs','lsstat'})
	else
		chdku.exec("return ls('"..path.."')",{'serialize','serialize_msgs','ls'})
	end
	local status,err=chdku.wait_status{ msg=true,run=false }
	if not status then
		return false,tostring(err)
	end
		
	if status.msg then
		msg,err=chdk.read_msg()
		if msg.type == 'return' and msg.subtype == 'string' and string.sub(msg.value,1,1) == '{' then
			-- TODO error checking
			return loadstring('return ' .. msg.value)()
		else
			return false, msg.value
		end
	end
end
--[[ 
status[,err]=chdku.exec("code",{"rlib name1","rlib name2"...})
wrapper for chdk.exec_lua, using optional code from rlibs
]]
function chdku.exec(code,libs)
	local libcode=''
	for k,v in ipairs(libs) do
		if chdku.rlib[v] then
			libcode = libcode .. chdku.rlib[v];
		else
			return false,'unknown rlib'..v
		end
	end
	return chdk.execlua(libcode .. code)
end

--[[
sleep until specified status is met
status,errmsg=chdku.wait_status(opts)
opts:
{
	-- bool values cause the function to return when the status matches the given value
	-- if not set, status of that item is ignored
	msg=bool
	run=bool
	timeout=<number> -- timeout in ms
	poll=<number> -- polling interval in ms
}
status: table with msg and run set to last status, and timeout set if timeout expired, or false,errormessage on error
TODO for gui, this should yield in lua, resume from timer or something
]]
function chdku.wait_status(opts)
	local timeleft = opts.timeout
	local sleeptime = opts.poll
	if not timeleft then
		timeleft=86400000 -- 1 day 
	end
	if not sleeptime or sleeptime < 50 then
		sleeptime=250
	end
	while true do
		local status,msg = chdk.script_status()
		if not status then
			return false,msg
		end
		if status.run == opts.run or status.msg == opts.msg then
			return status
		end
		if timeleft > 0 then
			if timeleft < sleeptime then
				sleeptime = timeleft
			end
			sys.sleep(sleeptime)
			timeleft =  timeleft - sleeptime
		else
			status.timeout=true
			return status
		end
	end
end
return chdku
