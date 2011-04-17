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
TODO passing compiled chunks might be better but our lua configurations are different
]]
chdku.rlib={
--[[
mostly duplicated from util.serialize
global defaults can be changed from code
]]
	serialize=[[
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

serialize_defaults = {
	maxdepth=10,
	err_type=true,
	err_cycle=true,
	pretty=true,
}

function serialize(v,opts)
	if opts then
		for k,v in pairs(serialize_defaults) do
			if not opts[k] then
				opts[k]=v
			end
		end
	else
		opts=serialize_defaults
	end
	return serialize_r(v,opts)
end

]],
-- override default table serialization for messages
	serialize_msgs=[[
	usb_msg_table_to_string=serialize
]],
--[[
TODO rework this to a general iterate over directory function
sends file listing as serialized tables with write_usb_msg
returns true, or false,error message
opts={
	stat=bool|{table},
	listall=bool, 
	msglimit=number,
	match="pattern",
	pretty=bool,
}
stat
	false/nil, return an array of names without stating at all
	'/' return array of names, with / appended to dirs
	'*" return all stat fields
	{table} return stat fields named in table (TODO not implemented)
msglimit
	maximum number of items to return in a message
	each message will contain a table with partial results
	default 50
match
	pattern, file names matching with string.match will be returned
listall 
	passed as second arg to os.listdir
pretty
	should serialized results be pretty ?

may run out of memory on very large directories,
msglimit can help but os.listdir itself could use all memory
TODO message timeout is not checked
TODO handle case if 'path' is a file
]]
	ls=[[
function ls(path,opts_in)
	local opts={
		msglimit=50,
		msgtimeout=100000,
		pretty=false,
	}
	if opts_in then
		for k,v in pairs(opts_in) do
			opts[k]=v
		end
	end
	local t,msg=os.listdir(path,opts.listall)
	if not t then
		return false,msg
	end
	local r={}
	local count=1
	for i,v in ipairs(t) do
		if not opts.match or string.match(v,opts.match) then
			if opts.stat then
				local st,msg=os.stat(path..'/'..v)
				if not st then
					return false,msg
				end
				if opts.stat == '/' then
					if st.is_dir then
						r[count]=v .. '/'
					else 
						r[count]=v
					end
				elseif opts.stat == '*' then
					r[v]=st
				end
			else
				r[count]=t[i];
			end
			if count < opts.msglimit then
				count=count+1
			else
				write_usb_msg(serialize(r,{pretty=opts.pretty}),opts.msgtimeout)
				r={}
				count=1
			end
		end
	end
	if count > 1 then
		write_usb_msg(serialize(r,{pretty=opts.pretty}),opts.msgtimeout)
	end
	return true
end
]],
}

--[[
opts may be a table, or a string containing lua code for a table
return a list of remote directory contents
return
table|false,msg
note may return an empty table if target is not a directory
]]
function chdku.listdir(path,opts) 
	if type(opts) == 'table' then
		opts = serialize(opts)
	end
	local status,err=chdku.exec("return ls('"..path.."',"..opts..")",{'serialize','serialize_msgs','ls'})
	if not status then
		return false,err
	end
	local results={}

	while true do
		status,err=chdku.wait_status{ msg=true, run=false }
		if not status then
			return false,tostring(err)
		end
		
		if status.msg then
			local msg,err=chdk.read_msg()
			if not msg then
				return false, err
			end
			if msg.type == 'user' then
				if msg.subtype ~= 'string' or string.sub(msg.value,1,1) ~= '{' then
					return false, 'unexpected message value'
				end
				local chunk,err=unserialize(msg.value)
				if err then
					return false, err
				end
				for k,v in pairs(chunk) do
					results[k] = v
				end
			elseif msg.type ~= 'return' or msg.value ~= true then
				return false, msg.value
			end
		elseif status.run == false then
			return results
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
