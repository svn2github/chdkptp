--[[
 Copyright (C) 2010-2012 <reyalp (at) gmail dot com>
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

]]
--[[
lua helper functions for working with the chdk.* c api
]]

local chdku={}
chdku.rlibs = require('rlibs')

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
connection methods, added to the connection object
]]
local con_methods = {}
--[[
check whether this cameras model and serial number match those given
TODO - ugly
]]
function con_methods:match_ptp_info(match) 
	match = util.extend_table({model='.*',serial_number='.*'},match)
	local ptp_info = self:get_ptp_devinfo()
	if not ptp_info then
		return false
	end
	-- older cams don't have serial
	if not ptp_info.serial_number then
		ptp_info.serial_number = ''
	end
--	printf('model %s (%s) serial_number %s (%s)\n',ptp_info.model,match.model,ptp_info.serial_number, match.serial_number)
	return (string.find(ptp_info.model,match.model) and string.find(ptp_info.serial_number,match.serial_number))
end

--[[
return a list of remote directory contents
dirlist[,err]=con:listdir(path,opts)
path should be directory, without a trailing slash (except in the case of A/...)
opts may be a table, or a string containing lua code for a table
returns directory listing as table, or false,error
note may return an empty table if target is not a directory
]]
function con_methods:listdir(path,opts) 
	if type(opts) == 'table' then
		opts = serialize(opts)
	elseif type(opts) ~= 'string' and type(opts) ~= 'nil' then
		return false, "invalid options"
	end
	if opts then
		opts = ','..opts
	else
		opts = ''
	end
	local results={}
	local i=1
	local status,err=self:execwait("return ls('"..path.."'"..opts..")",{
		libs='ls',
		msgs=chdku.msg_unbatcher(results),
	})
	if not status then
		return false,err
	end

	return results
end

--[[
download files and directories
status[,err]=con:mdownload(srcpaths,dstpath,opts)
opts are passed to find_files
]]
function con_methods:mdownload(srcpaths,dstpath,opts)
	if not dstpath then
		dstpath = '.'
	end
	opts=extend_table({},opts)
	opts.dirsfirst=true
	local dstmode = lfs.attributes(dstpath,'mode')
	if dstmode and dstmode ~= 'directory' then
		return false,'mdownload: dest must be a directory'
	end
	local files={}
	local status,rstatus,rerr = self:execwait('return ff_mdownload('..serialize(srcpaths)..','..serialize(opts)..')',
										{libs={'ff_mdownload'},msgs=chdku.msg_unbatcher(files)})

	if not status then
		return false,rstatus
	end
	if not rstatus then
		return false,rerr
	end

	if #files == 0 then
		warnf("no matching files\n");
		return true
	end

	if not dstmode then
		local status,err=fsutil.mkdir_m(dstpath)
		if not status then
			return false,err
		end
	end

	for i,finfo in ipairs(files) do
		local relpath
		local src,dst
		src = finfo.full
		if #finfo.path == 1 then
			relpath = finfo.name
		else
			if #finfo.path == 2 then
				relpath = finfo.path[2]
			else
				relpath = fsutil.joinpath(unpack(finfo.path,2))
			end
		end
		dst=fsutil.joinpath(dstpath,relpath)
		if finfo.st.is_dir then
--			printf('fsutil.mkdir_m(%s)\n',dst)
			local status,err = fsutil.mkdir_m(dst)
			if not status then
				return false,err
			end
		else
			local dst_dir = fsutil.dirname(dst)
			if dst_dir ~= '.' then
--				printf('fsutil.mkdir_m(%s)\n',dst_dir)
				local status,err = fsutil.mkdir_m(dst_dir)
				if not status then
					return false,err
				end
			end
			printf("%s->%s\n",src,dst);
			-- ptp download fails on zero byte files (zero size data phase, possibly other problems)
			if finfo.st.size > 0 then
				-- TODO check newer/older etc
				local status,err = self:download(src,dst)
				if not status then
					return status,err
				end
			else
				local f,err=io.open(dst,"wb")
				f:close()
			end
			-- TODO optionally set timestamps (need to translate)
		end
	end
	return true
end

local function mupload_r(src,dst,opts)
	
end
--[[
upload files and directories
status[,err]=con:mupload(srcpaths,dstpath,opts)
]]
function con_methods:mupload(srcpaths,dstpath,opts)
end

--[[
quick and dirty bulk delete, this may change or go away

delete files from directory, optionally matching pattern
note directory should not end in a /, unless it is A/
only *files* will be deleted, directories will not be touched
]]
function con_methods:deletefiles(dir,pattern)
	local files,err=self:listdir(dir,{stat="*",match=pattern})
	if not files then
		return false, err
	end
	for i,st in ipairs(files) do
		if st.is_file then
			local status,err=self:remove(fsutil.joinpath(dir,st.name))
			if not status then
				return false,err
			end
--			print('del '..st.name)
		end
	end
	return true
end

--[[
wrapper for remote functions, serialize args, combine remote and local error status 
func must be a string that evaluates to a function on the camera
returns remote function return values on success, false + message on failure
]]
function con_methods:call_remote(func,...)
	local args = {...}
	local argstrs = {}
	-- preserve nils between values (not trailing ones but shouldn't matter in most cases)
	for i = 1,table.maxn(args) do
		argstrs[i] = serialize(args[i])
	end

	local code = "return "..func.."("..table.concat(argstrs,',')..")"
--	printf("%s\n",code)
	local results = {self:execwait(code)}
	-- if local status is good, return remote
	if results[1] then
		-- start at 2 to discard local status
		return unpack(results,2,table.maxn(results)) -- maxn expression preserves nils
	end
	-- else return local error
	return false,results[2]
end

function con_methods:stat(path)
	return self:call_remote('os.stat',path)
end

function con_methods:mdkir(path)
	return self:call_remote('os.mkdir',path)
end

function con_methods:remove(path)
	return self:call_remote('os.remove',path)
end


--[[
sort an array of stat+name by directory status, name
]]
function chdku.sortdir_stat(list)
	table.sort(list,function(a,b) 
			if a.is_dir and not b.is_dir then
				return true
			end
			if not a.is_dir and b.is_dir then
				return false
			end
			return a.name < b.name
		end)
end

--[[
read pending messages and return error from current script, if available
]]
function con_methods:get_error_msg()
	while true do
		local msg,err = self:read_msg()
		if not msg then
			return false
		end
		if msg.type == 'none' then
			return false
		end
		if msg.type == 'error' and msg.script_id == self:get_script_id() then
			return msg.value
		end
		warnf("chdku.get_error_msg: ignoring message %s\n",chdku.format_script_msg(msg))
	end
end

--[[
format a remote lua error from chdku.exec using line number information
]]
local function format_exec_error(libs,code,errmsg)
	local lnum=tonumber(string.match(errmsg,'^%s*:(%d+):'))
	if not lnum then
		print('no match '..errmsg)
		return errmsg
	end
	local l = 0
	local lprev, errlib, errlnum
	for i,lib in ipairs(libs.list) do
		lprev = l
		l = l + lib.lines + 1 -- TODO we add \n after each lib when building code
		if l >= lnum then
			errlib = lib
			errlnum = lnum - lprev
			break
		end
	end
	if errlib then
		return string.format("%s\nrlib %s:%d\n",errmsg,errlib.name,errlnum)
	else
		return string.format("%s\nuser code: %d\n",errmsg,lnum - l)
	end
end

--[[
read and discard all pending messages. Returns false,error if message functions fails, otherwise true
]]
function con_methods:flushmsgs()
	repeat
		local msg,err=self:read_msg()
		if not msg then
			return false, err
		end
	until msg.type == 'none' 
	return true
end

--[[
return a closure to be used with as a chdku.exec msgs function, which unbatches messages msg_batcher into t
]]
function chdku.msg_unbatcher(t)
	local i=1
	return function(msg)
		if msg.subtype ~= 'table' then
			return false, 'unexpected message value'
		end
		local chunk,err=unserialize(msg.value)
		if err then
			return false, err
		end
		for j,v in ipairs(chunk) do
			t[i]=v
			i=i+1
		end
		return true
	end
end
--[[ 
wrapper for chdk.execlua, using optional code from rlibs
status[,err]=con:exec("code",opts)
opts {
	libs={"rlib name1","rlib name2"...} -- rlib code to be prepended to "code"
	wait=bool -- wait for script to complete, return values will be returned after status if true
	nodefaultlib=bool -- don't automatically include default rlibs
	clobber=bool -- if false, will check script-status and refuse to execute if script is already running
				-- clobbering is likely to result in crashes / memory leaks in current versions of CHDK!
	flushmsgs=bool -- if true (default) read and silently discard any pending messages before running script
					-- not applicable if clobber is true, since the running script could just spew messages indefinitely
	-- below only apply if with wait
	msgs={table|callback} -- table or function to receive user script messages
	rets={table|callback} -- table or function to receive script return values, instead of returning them
	fdata={any lua value} -- data to be passed as second argument to callbacks
}
callbacks
	status[,err] = f(message,fdata)
	processing continues if status is true, otherwise aborts and returns err
]]
-- use serialize by default
chdku.default_libs={
	'serialize_msgs',
}

--[[
convenience, defaults wait=true
]]
function con_methods:execwait(code,opts_in)
	return self:exec(code,extend_table({wait=true},opts_in))
end

function con_methods:exec(code,opts_in)
	-- setup the options
	local opts = extend_table({flushmsgs=true},opts_in)
	local liblist={}
	-- add default libs, unless disabled
	-- TODO default libs should be per connection
	if not opts.nodefaultlib then
		extend_table(liblist,chdku.default_libs)
	end
	-- allow a single lib to be given as by name
	if type(opts.libs) == 'string' then
		liblist={opts.libs}
	else
		extend_table(liblist,opts.libs)
	end

	-- check for already running script and flush messages
	if not opts.clobber then
		local status,err = self:script_status()
		if not status then
			return false,err
		end
		if status.run then
			return false,"a script is already running"
		end
		if opts.flushmsgs and status.msg then
			status,err=self:flushmsgs()
			if not status then
				return false,err
			end
		end
	end

	-- build the complete script from user code and rlibs
	local libs = chdku.rlibs:build(liblist)
	code = libs:code() .. code

	-- try to start the script
	local status,err=self:execlua(code)
	if not status then
		-- syntax error, try to fetch the error message
		if err == 'syntax' then
			local msg = self:get_error_msg()
			if msg then
				return false,format_exec_error(libs,code,msg)
			end
		end
		--  other unspecified error, or fetching syntax/compile error message failed
		return false,err
	end

	-- if not waiting, we're done
	if not opts.wait then
		return true
	end

	-- to collect return values
	-- first result is our status
	local results={true}
	local i=2

	-- process messages and wait for script to end
	while true do
		status,err=self:wait_status{ msg=true, run=false }
		if not status then
			return false,tostring(err)
		end
		if status.msg then
			local msg,err=self:read_msg()
			if not msg then
				return false, err
			end
			if msg.script_id ~= self:get_script_id() then
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
					if msg.subtype == 'table' and libs.map['serialize_msgs'] then
						results[i] = unserialize(msg.value)
					else
						results[i] = msg.value
					end
					i=i+1
				end
			elseif msg.type == 'error' then
				return false, format_exec_error(libs,code,msg.value)
			else
				return false, 'unexpected message type'
			end
		-- script is completed and all messages have been processed
		elseif status.run == false then
			-- returns were handled by callback or table
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
status,errmsg=con:wait_status(opts)
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
function con_methods:wait_status(opts)
	local timeleft = opts.timeout
	local sleeptime = opts.poll
	if not timeleft then
		timeleft=86400000 -- 1 day 
	end
	if not sleeptime or sleeptime < 50 then
		sleeptime=250
	end
	while true do
		local status,msg = self:script_status()
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
			timeleft = timeleft - sleeptime
		else
			status.timeout=true
			return status
		end
	end
end

--[[
meta table for wrapped connection object
]]
local con_meta = {
	__index = function(t,key)
		return con_methods[key]
	end
}

--[[
proxy connection methods from low level object to chdku
]]
local function init_connection_methods()
	for name,func in pairs(chdk_connection) do
		if con_methods[name] == nil and type(func) == 'function' then
			con_methods[name] = function(self,...)
				return chdk_connection[name](self._con,...)
			end
		end
	end
end

init_connection_methods()

--[[
bool = chdku.match_device(devinfo,match)
attempt to find a device specified by the match table 
{
	bus='bus pattern'
	dev='device pattern'
	product_id = number
}
]]
function chdku.match_device(devinfo,match) 
	--[[
	printf('try bus:%s (%s) dev:%s (%s) pid:%s (%s)\n',
		devinfo.bus, match.bus,
		devinfo.dev, match.dev,
		devinfo.product_id, tostring(match.product_id))
	--]]
	if string.find(devinfo.bus,match.bus) and string.find(devinfo.dev,match.dev) then
		return (match.product_id == nil or tonumber(match.product_id)==devinfo.product_id)
	end
	return false
end
--[[
return a connection object wrapped with chdku methods
devspec is a table specifying the bus and device name to connect to
no checking is done on the existence of the device
if devspec is null, a dummy connection is returned
]]
function chdku.connection(devspec)
	local con = {}
	setmetatable(con,con_meta)
	con._con = chdk.connection(devspec)
	return con
end

return chdku
