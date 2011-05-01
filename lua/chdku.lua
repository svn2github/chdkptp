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

-- TODO this should be split out into it's own module(s)
--[[
simple library system for building remote commands
chunks of source code to be used remotely
can be used with chdku.exec
TODO some of these are duplicated with local code, but we don't yet have an easy way of sharing them
TODO would be good to minify
TODO passing compiled chunks might be better but our lua configurations are different
]]
local rlibs = {
	libs={},
}
--[[
register{
	name='libname'
	depend='lib'|{'lib1','lib2'...}, -- already registered rlibs this one requires (cyclic deps not allowed)
	code='', -- main lib code.
}
]]
function rlibs:register(t)
	-- for convenience, single lib may be given as string
	if type(t.depend) == 'string' then
		t.depend = {t.depend}
	elseif type(t.depend) == 'nil' then
		t.depend = {}
	elseif type(t.depend) ~= 'table' then
		error('expected dependency table or string')
	end
	if type(t.code) ~= 'string' then
		error('expected code string')
	end
	if type(t.name) ~= 'string' then
		error('expected name string')
	end
	for i,v in ipairs(t.depend) do
		if not self.libs[v] then
			errf('%s missing dep %s\n',t.name,v)
		end
	end
	self.libs[t.name] = t
end

--[[
register an array of libs
]]
function rlibs:register_array(t)
	for i,v in ipairs(t) do
		self:register(v)
	end
end

--[[
add deps for a single lib
]]
function rlibs:build_single(build,name)
	local lib = self.libs[name]
	if not lib then
		errf('unknown lib %s\n',tostring(name))
	end
	-- already added
	if build.map[name] then
		return
	end
	for i,dname in ipairs(lib.depend) do
		self:build_single(build,dname)
	end
	build.map[name]=lib
	table.insert(build.list,lib)
end
--[[
return a list of rlibs in dependency order
t=rlibs:build_list('name'|{'name1','name2',...})
]]
function rlibs:build_list(libnames)
	-- single can be given as string
	if type(libnames) == 'string' then
		libnames={libnames}
	elseif type(libnames) ~= 'table' then
		error('rlibs:build_list expected string or table for libnames')
	end
	local build={
		list={},
		map={},
	}
	for i,name in ipairs(libnames) do
		self:build_single(build,name)
	end
	return build.list
end
--[[
return a string containing all the required rlib code
code=rlibs:build('name'|{'name1','name2',...})
]]
function rlibs:build(names)
	local liblist = self:build_list(names)
	-- TODO would be good to keep a map of line numbers here somehow
	-- or possibly exec should keep the code around ?
	local code=""
	for i,lib in ipairs(liblist) do
		code = code .. lib.code .. '\n'
	end
	return code
end

rlibs:register_array{
--[[
mostly duplicated from util.serialize
global defaults can be changed from code
]]
{
	name='serialize',
	code=[[
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
	pretty=false,
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
},
-- override default table serialization for messages
{
	name='serialize_msgs',
	depend='serialize',
	code=[[
	usb_msg_table_to_string=serialize
]],
},
--[[
	status[,err]=dir_iter(path,func,opts)
general purpose directory iterator
interates over directory 'path', calling
func(path,filename,opts.fdata) on each item
func is called with a nil filename after listing is complete
]]
{
	name='dir_iter',
	code=[[
function dir_iter(path,func,opts)
	if not opts then
		opts = {}
	end
		
	local t,err=os.listdir(path,opts.listall)
	if not t then
		return false,err
	end
	for i,v in ipairs(t) do
		local status,err=func(path,v,opts)
		if not status then
			return status,err
		end
	end
	return func(path,nil,opts)
end
]],
},
--[[
function to batch stuff in groups of messages
b=msg_batcher{
	batchsize=num, -- items per batch
	timeout=num, -- message timeout
}
call
b:write() adds items and sends when batch size is reached
b:flush() sends any remaining items
]]
{
	name='msg_batcher',
	depend='serialize_msgs',
	code=[[
function msg_batcher(opts_in)
	local t = {
		batchsize=50,
		timeout=100000
	}
	if opts_in then
		for k,v in pairs(opts_in) do
			t[k] = v
		end
	end
	t.data = {}
	t.n = 0
	t.write=function(self,val)
		self.n = self.n + 1
		self.data[self.n] = val
		if self.n >= self.batchsize then
			return self:flush()
		end
		return true
	end
	t.flush = function(self)
		if self.n > 0 then
			if not write_usb_msg(self.data,self.timeout) then
				return false
			end
			self.data = {}
			self.n = 0
		end
		return true
	end
	return t
end
]],
},
--[[
retrieve a directory listing of names, batched in messages
]]
{
	name='ls_simple',
	depend='msg_batcher',
	code=[[
function ls_simple(path)
	local b=msg_batcher()
	local t,err=os.listdir(path)
	if not t then
		return false,err
	end
	for i,v in ipairs(t) do
		if not b:write(v) then
			return false
		end
	end
	return b:flush()
end
]],
},
--[[
TODO rework this to a general iterate over directory function
sends file listing as serialized tables with write_usb_msg
returns true, or false,error message
opts={
	stat=bool|{table},
	listall=bool, 
	msglimit=number,
	match="pattern",
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

may run out of memory on very large directories,
msglimit can help but os.listdir itself could use all memory
TODO message timeout is not checked
TODO handle case if 'path' is a file
]]
{
	name='ls',
	depend='serialize_msgs',
	code=[[
function ls(path,opts_in)
	local opts={
		msglimit=50,
		msgtimeout=100000,
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
				write_usb_msg(r,opts.msgtimeout)
				r={}
				count=1
			end
		end
	end
	if count > 1 then
		write_usb_msg(r,opts.msgtimeout)
	end
	return true
end
]],
},
}

chdku.rlibs = rlibs
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
	local results={}
	local status,err=chdku.exec("return ls('"..path.."',"..opts..")",
		{
			wait=true,
			libs='ls',
			msgs=function(msg)
				if msg.subtype ~= 'table' then
					return false, 'unexpected message value'
				end
				local chunk,err=unserialize(msg.value)
				if err then
					return false, err
				end
				for k,v in pairs(chunk) do
					results[k] = v
				end
				return true
			end,
		})
	if not status then
		return false,err
	end

	return results
end

--[[
read pending messages and return error from current script, if available
]]
function chdku.get_error_msg()
	while true do
		local msg,err = chdk.read_msg()
		if not msg then
			return false
		end
		if msg.type == 'none' then
			return false
		end
		if msg.type == 'error' and msg.script_id == chdk.get_script_id() then
			return msg.value
		end
		warnf("chdku.get_error_msg: ignoring message %s\n",chdku.format_script_msg(msg))
	end
end
--[[ 
wrapper for chdk.execlua, using optional code from rlibs
status[,err]=chdku.exec("code",opts)
opts {
	libs={"rlib name1","rlib name2"...} -- rlib code to be prepended to "code"
	wait=bool -- wait for script to complete, return values will be returned after status if true
	-- below only apply if with wait
	msgs={table|callback} -- table or function to receive user script messages
	rets={table|callback} -- table or function to receive script return values, instead of returning them
	fdata={any lua value} -- data to be passed as second argument to callbacks
}
callbacks
	status[,err] = f(message,fdata)
	processing continues if status is true, otherwise aborts and returns err
]]
function chdku.exec(code,opts_in)
	local opts = extend_table({},opts_in)
	if opts.libs then
		code = chdku.rlibs:build(opts.libs) .. code
	end
	local status,err=chdk.execlua(code)
	if not status then
		-- syntax error, try to fetch the error message
		if err == 'syntax' then
			-- TODO extract error line and match with code
			local msg = chdku.get_error_msg()
			if msg then
				return false,msg
			end
		end
		return false,err
	end
	if not opts.wait then
		return true
	end

	-- to collect return values
	-- first result is our status
	local results = {true}
	local i=2

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
			if msg.script_id ~= chdk.get_script_id() then
				warnf("chdku.exec: message from unexpected script %s\n",msg.script_id,chdku.format_script_msg(msg))
			elseif msg.type == 'user' then
				if type(opts.msgs) == 'function' then
					local status,err = opts.msgs(msg,opts.fdata)
					if not status then
						return false,err
					end
				elseif type(opts.msgs) == 'table' then
					table.insert(opts.msgs,msg)
				else
					warnf("chdku.exec: unexpected user message %s\n",chdku.format_script_msg(msg))
				end
			elseif msg.type == 'return' then
				if type(opts.rets) == 'function' then
					local status,err = opts.rets(msg,opts.fdata)
					if not status then
						return false,err
					end
				elseif type(opts.rets) == 'table' then
					table.insert(opts.rets,msg)
				else
					-- if serialize_msgs is not selected, table return values will be strings
					-- TODO not updated for new rlib yet
					if msg.subtype == 'table' and in_table(opts.libs,'serialize_msgs') then
						results[i] = unserialize(msg.value)
					else
						results[i] = msg.value
					end
					i=i+1
				end
			elseif msg.type == 'error' then
				return false, msg.value
			else
				return false, 'unexpected message type'
			end
		elseif status.run == false then
			if opts.rets then
				return true
			else
				return unpack(results,1,table.maxn(results)) -- maxn expression preserves nils
			end
		end
	end

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
