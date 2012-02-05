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
Camera timestamps are in seconds since Jan 1, 1970 in current camera time
PC timestamps (linux, windows) are since Jan 1, 1970 UTC
return offset of current PC time from UTC time, in seconds
]]
function chdku.ts_get_offset()
	-- local timestamp, assumed to be seconds since unix epoch
	local tslocal=os.time()
	-- !*t returns a table of hours, minutes etc in UTC (without a timezone spec)
	-- os.time turns this into a timestamp, treating as local time
	return tslocal - os.time(os.date('!*t',tslocal))
end

--[[
covert a timestamp from the camera to the equivalent local time on the pc
]]
function chdku.ts_cam2pc(tscam)
	local tspc = tscam - chdku.ts_get_offset()
	-- TODO
	-- on windows, a time < 0 causes os.date to return nil 
	-- these can appear from the cam if you set 0 with utime and have a negative utc offset
	-- since this is a bogus date anyway, just force it to zero to avoid runtime errors
	if tspc > 0 then
		return tspc
	end
	return 0
end

--[[
covert a timestamp from the pc to the equivalent on the camera
default to current time if none given
]]
function chdku.ts_pc2cam(tspc)
	if not tspc then
		tspc = os.time()
	end
	local tscam = tspc + chdku.ts_get_offset()
	-- TODO
	-- cameras handle < 0 times inconsistently (vxworks > 2100, dryos < 1970)
	if tscam > 0 then
		return tscam
	end
	return 0
end

--[[ 
connection methods, added to the connection object
]]
local con_methods = {}
--[[
check whether this cameras model and serial number match those given
assumes self.ptpdev is up to date
TODO - ugly
]]
function con_methods:match_ptp_info(match) 
	match = util.extend_table({model='.*',serial_number='.*'},match)
	-- older cams don't have serial
	local serial = ''
	if self.ptpdev.serial_number then
		serial = self.ptpdev.serial_number
	end
--	printf('model %s (%s) serial_number %s (%s)\n',ptp_info.model,match.model,ptp_info.serial_number, match.serial_number)
	return (string.find(self.ptpdev.model,match.model) and string.find(serial,match.serial_number))
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
opts:
	mtime=bool -- keep (default) or discard remote mtime NOTE files only for now
other opts are passed to find_files
]]
function con_methods:mdownload(srcpaths,dstpath,opts)
	if not dstpath then
		dstpath = '.'
	end
	local lopts=extend_table({mtime=true},opts)
	local ropts=extend_table({},opts)
	ropts.dirsfirst=true
	ropts.mtime=nil
	local dstmode = lfs.attributes(dstpath,'mode')
	if dstmode and dstmode ~= 'directory' then
		return false,'mdownload: dest must be a directory'
	end
	local files={}
	local status,rstatus,rerr = self:execwait('return ff_mdownload('..serialize(srcpaths)..','..serialize(ropts)..')',
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
			if lopts.mtime then
				status,err = lfs.touch(dst,chdku.ts_cam2pc(finfo.st.mtime));
				if not status then
					return status,err
				end
			end
		end
	end
	return true
end

--[[
upload files and directories
status[,err]=con:mupload(srcpaths,dstpath,opts)
opts are as for find_files, plus
	pretend: just print what would be done
	mtime: preserve mtime of local files
]]
local function mupload_fn(self,opts)
	local con=opts.con
	if #self.rpath == 0 and self.cur.st.mode == 'directory' then
		return true
	end
	if self.cur.name == '.' or self.cur.name == '..' then
		return true
	end
	local relpath
	local src=self.cur.full
	if #self.cur.path == 1 then
		relpath = self.cur.name
	else
		if #self.cur.path == 2 then
			relpath = self.cur.path[2]
		else
			relpath = fsutil.joinpath(unpack(self.cur.path,2))
		end
	end
	local dst=fsutil.joinpath_cam(opts.mu_dst,relpath)
	if self.cur.st.mode == 'directory' then
		if opts.pretend then
			printf('remote mkdir_m(%s)\n',dst)
		else
			local status,err=con:mkdir_m(dst)
			if not status then
				return false,err
			end
		end
		opts.lastdir = dst
	else
		local dst_dir=fsutil.dirname_cam(dst)
		-- cache target directory so we don't have an extra stat call for every file in that dir
		if opts.lastdir ~= dst_dir then
			local st,err=con:stat(dst_dir)
			if st then
				if not st.is_dir then
					return false, 'not a directory: '..dst_dir
				end
			else
				if opts.pretend then
					printf('remote mkdir_m(%s)\n',dst_dir)
				else
					local status,err=con:mkdir_m(dst_dir)
					if not status then
						return false,err
					end
				end
			end
			opts.lastdir = dst_dir
		end
		-- TODO stat'ing in batches would be faster
		st,err=con:stat(dst)
		if st and not st.is_file then
			return false, 'not a file: '..dst
		end
		-- TODO timestamp comparison
		printf('%s->%s\n',src,dst)
		if not opts.pretend then
			local status,err = con:upload(src,dst)
			if not status then
				return false,err
			end
			if opts.mtime then
				-- TODO updating times in batches would be faster
				local status,err = con:utime(dst,chdku.ts_pc2cam(self.cur.st.modification))
				if not status then
					return false,err
				end
			end
		end
	end
	return true
end

function con_methods:mupload(srcpaths,dstpath,opts)
	opts = util.extend_table({mtime=true},opts)
	opts.dirsfirst=true
	opts.mu_dst=dstpath
	opts.con=self
	return fsutil.find_files(srcpaths,opts,mupload_fn)
end

--[[
delete files and directories
opts are as for find_files, plus
	pretend:only return file name and action, don't delete
	skip_topdirs: top level directories passed in paths will not be removed 
		e.g. mdelete({'A/FOO'},{skip_topdirs=true}) will delete everything in FOO, but not foo itself
	ignore_errors: ignore failed deletes
]]
function con_methods:mdelete(paths,opts)
	opts=extend_table({},opts)
	opts.dirsfirst=false -- delete directories only after recursing into
	local results
	local msg_handler
	if opts.msg_handler then
		msg_handler = opts.msg_handler
		opts.msg_handler = nil -- don't serialize
	else
		results={}
		msg_handler = chdku.msg_unbatcher(results)
	end
	local status,err = self:call_remote('ff_mdelete',{libs={'ff_mdelete'},msgs=msg_handler},paths,opts)

	if not status then
		return false,err
	end
	if results then
		return results
	end
	return true
end

--[[
wrapper for remote functions, serialize args, combine remote and local error status 
func must be a string that evaluates to a function on the camera
returns remote function return values on success, false + message on failure
]]
function con_methods:call_remote(func,opts,...)
	local args = {...}
	local argstrs = {}
	-- preserve nils between values (not trailing ones but shouldn't matter in most cases)
	for i = 1,table.maxn(args) do
		argstrs[i] = serialize(args[i])
	end

	local code = "return "..func.."("..table.concat(argstrs,',')..")"
--	printf("%s\n",code)
	local results = {self:execwait(code,opts)}
	-- if local status is good, return remote
	if results[1] then
		-- start at 2 to discard local status
		return unpack(results,2,table.maxn(results)) -- maxn expression preserves nils
	end
	-- else return local error
	return false,results[2]
end

function con_methods:stat(path)
	return self:call_remote('os.stat',nil,path)
end

function con_methods:utime(path,mtime,atime)
	return self:call_remote('os.utime',nil,path,mtime,atime)
end

function con_methods:mdkir(path)
	return self:call_remote('os.mkdir',nil,path)
end

function con_methods:remove(path)
	return self:call_remote('os.remove',nil,path)
end

function con_methods:mkdir_m(path)
	return self:call_remote('mkdir_m',{libs='mkdir_m'},path)
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
	initwait={ms|false} -- passed to wait_status, wait before first poll
	poll={ms} -- passed to wait_status, poll interval after ramp up
	pollstart={ms|false} -- passed to wait_status, initial poll interval, ramps up to poll
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
	return self:exec(code,extend_table({wait=true,initwait=5},opts_in))
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
		-- TODO this causes a round trip.
		-- Could track locally if a script has been started since last script_status call showed complete/no messages
		-- wouldn't be safe vs scripts started in cam ui
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
		status,err=self:wait_status{
			msg=true,
			run=false,
			initwait=opts.initwait,
			poll=opts.poll,
			pollstart=opts.pollstart
		}
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
convenience method, get a message of a specific type
mtype=<string> - expected message type
msubtype=<string|nil> - expected subtype, or nil for any
munserialize=<bool> - unserialize and return the message value, only valid for user/return

returns
status,message|msg value
status first since message value could decode to false/nil
]]
function con_methods:read_msg_strict(opts)
	opts=extend_table({},opts)
	local msg,err=self:read_msg()
	if not msg or msg.type == 'none' then
		return false, err
	end
	if msg.script_id ~= self:get_script_id() then
		return false,'msg from unexpected script id'
	end
	if msg.type ~= opts.mtype then
		return false,'unexpected msg type'
	end
	if opts.msubtype and msg.subtype ~= opts.msubtype then
		return false,'wrong message subtype'
	end
	if opts.munserialize then
		local v = util.unserialize(msg.value)
		if opts.msubtype and type(v) ~= opts.msubtype then
			return false,'unserialize failed'
		end
		return true,v
	end
	return true,msg
end
--[[
convenience method, wait for a single message and return it
opts passed wait_status, and read_msg_strict
]]
function con_methods:wait_msg(opts)
	opts=extend_table({},opts)
	opts.msg=true
	opts.run=nil
	local status,err=self:wait_status(opts)
	if not status then
		return false,err
	end
	if status.timeout then
		return false,'timeout'
	end
	if not status.msg then
		return false,'no msg'
	end
	return self:read_msg_strict(opts)
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
	pollstart=<number> -- if not false, start polling at pollstart, double interval each iteration until poll is reached
	initwait=<number> -- wait N ms before first poll. If this is long enough for call to finish, saves round trip
}
status: table with msg and run set to last status, and timeout set if timeout expired, or false,errormessage on error
TODO for gui, this should yield in lua, resume from timer or something
]]
function con_methods:wait_status(opts)
	opts = util.extend_table({
		poll=250,
		pollstart=4,
		timeout=86400000 -- 1 day
	},opts)
	local timeleft = opts.timeout
	local sleeptime
	if opts.poll < 50 then
		opts.poll = 50
	end
	if opts.pollstart then
		sleeptime = opts.pollstart
	else
		sleeptime = opts.poll
	end
	if opts.initwait then
		sys.sleep(opts.initwait)
		timeleft = timeleft - opts.initwait
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
			if opts.pollstart and sleeptime < opts.poll then
				sleeptime = sleeptime * 2
				if sleeptime > opts.poll then
					sleeptime = opts.poll
				end
			end
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
set usbdev, ptpdev apiver for current connection
TODO handle not connected/errors
]]
function con_methods:update_connection_info()
	self.usbdev=self:get_usb_devinfo()
	self.ptpdev=self:get_ptp_devinfo()	
	local major,minor=self:camera_api_version()
	self.apiver={major=major,minor=minor}
end
--[[
override low level connect to gather some useful information that shouldn't change over life of connection
opts{
	raw:bool -- just call the low level connect (saves ~40ms)
}
]]
function con_methods:connect(opts)
	opts = util.extend_table({},opts)
	local status,err=chdk_connection.connect(self._con)
	if not status then
		return false,err
	end
	if opts.raw then
		return true
	end
	self:update_connection_info()
	return true
end

--[[
attempt to reconnect to the device
opts{
	wait=<ms> -- amount of time to wait, default 2 sec to avoid probs with dev numbers changing
	strict=bool -- fail if model, pid or serial number changes
}
if strict is not set, reconnect to different device returns true, <message>
]]
function con_methods:reconnect(opts)
	opts=util.extend_table({
		wait=2000,
		strict=true,
	},opts)
	if self:is_connected() then
		self:disconnect()
	end
	local ptpdev = self.ptpdev
	local usbdev = self.usbdev
	-- appears to be needed to avoid device numbers changing (reset too soon ?)
	sys.sleep(opts.wait)
	local status,err = self:connect()
	if not status then
		return status,err
	end
	if ptpdev.model ~= self.ptpdev.model
			or ptpdev.serial_number ~= self.ptpdev.serial_number
			or usbdev.product_id ~= self.usbdev.product_id then
		if opts.strict then
			self:disconnect()
			return false,'reconnected to a different device'
		else
			return true,'reconnected to a different device'
		end
	end
	return true
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

TODO this returns a *new* wrapper object, even
if one already exist for the underlying object
not clear if this is desirable, could cache a table of them
]]
function chdku.connection(devspec)
	local con = {}
	setmetatable(con,con_meta)
	con._con = chdk.connection(devspec)
	return con
end

return chdku
