--[[
 Copyright (C) 2012-2018 <reyalp (at) gmail dot com>
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
experimental code for shooting with multiple cameras
not optimized for best sync, lots of loose ends
usage:
!mc=require('multicam')
!mc:connect()
!mc:start()
!return mc:cmdwait('rec')
!return mc:cmdwait('preshoot')
!return mc:cmdwait('shoot')
!return mc:cmdwait('play')
!mc:cmd('exit')
]]

local mc={
	cams={},     -- array of all connections
	selected={}, -- array of selected connects, ordered by ID
	max_id=0,    -- max used ID, since list may not be contiguous
	cmd_defaults={ -- defaults for mc:cmd
		flushmsgs=true,
		printcmd='once'
	},
	download_images_subst_funcs=util.extend_table({
		id=varsubst.format_state_val('id','%02d'),
	},chdku.imglist_subst_funcs)
}

--[[
return an iterator over selected cams
]]
function mc:icams()
	local i=0
	return function()
		i=i+1
		return self.selected[i]
	end
end
--[[
find specified device/bus in cams list, returns connection or nil
]]
function mc:find_dev(devspec)
	for i,lcon in ipairs(self.cams) do
		if devspec.dev == lcon.condev.dev and devspec.bus == lcon.condev.bus then
			return lcon
		end
	end
end

function mc:find_serial(serial)
	for i,lcon in ipairs(self.cams) do
		if lcon.ptpdev.serial_number == serial then
			return lcon
		end
	end
end

function mc:find_id(id)
	for i,lcon in ipairs(self.cams) do
		if lcon.mc_id == id then
			return lcon
		end
	end
end

--[[
connect to cameras, default all available
opts:{
	add=bool -- don't reset existing list, just add any matching camereas
	match={ -- match spec as used in CLI connect
		bus=string 
		dev=string
		product_id=number
		serial_number=string
		model=string
		plain=bool -- controls whether dev, bus, model, and serial are pattern or plain text match
	}
	list=bool or string -- list file defining serial numbers and order, exclusive with add and match
	selected=bool -- connect to connections already in selected list. Assumes disconnected with
	                 mc:disconnect, exclusive of other options
	close_tempcons -- disconnect non-selected cameras, otherwise left connected but not in the mc list
}
]]
function mc:connect(opts)
	opts=util.extend_table({
	},opts)
	if opts.list and (opts.match or opts.add) then
		errlib.throw{etype='bad_arg',msg='list may not be combined with match or add'}
	end
	if opts.selected then
		if opts.match or opts.add or opts.list then
			errlib.throw{etype='bad_arg',msg='selected may not be combined with list, match or add'}
		end
		for lcon in self:icams() do
			local con_status = lcon:is_connected()
			if not con_status then
				local err
				con_status,err = lcon:connect_pcall()
				if not con_status then
					warnf('%d: connect failed bus:%s dev:%s err:%s\n',lcon.mc_id,lcon.condev.bus,lcon.condev.dev,tostring(err))
				end
			end
			if con_status then
				printf('+ %d:%s b=%s d=%s s=%s\n',
					lcon.mc_id,
					lcon.ptpdev.model,
					lcon.condev.bus,
					lcon.condev.dev,
					tostring(lcon.ptpdev.serial_number))
			end
		end
		return
	end
	if not opts.match then
		opts.match = {}
	end

	if not opts.add then
		self.cams={}
		self.cams_by_serial={}
	end

	local ser_list
	if opts.list then
		if opts.list == true then
			ser_list = self:load_list()
		else
			ser_list = self:load_list(opts.list)
		end
	end


	local devices = chdk.list_usb_devices()

	for i, devinfo in ipairs(devices) do
		local lcon,msg = chdku.connection(devinfo)
		-- if already connected just update connection info on wrapper
		-- otherwise, try to connect
		if lcon:is_connected() then
			lcon:update_connection_info()
		else
			local status,err = lcon:connect_pcall()
			if not status then
				warnf('%d: connect failed bus:%s dev:%s err:%s\n',i,devinfo.bus,devinfo.dev,tostring(err))
			end
		end
		-- if connection didn't fail
		if lcon:is_connected() then
			-- TODO alt serial mechanism for cams that don't have
			local serial = lcon.ptpdev.serial_number
			local status = '-'
			if opts.list then
				if serial then
					if ser_list[serial] then
						status='+'
						lcon.mc_id = ser_list[serial].id
						table.insert(self.cams,lcon)
						-- TODO this should probably be an error
						-- also duplicate ID
						if self.cams_by_serial[serial] then
							warnf('%d: duplicate serial:%s\n',i,lcon.ptpdev.serial_number)
						end
						self.cams_by_serial[serial]=lcon
					else
						status='i'
					end
				else
					warnf('ignoring camera with no serial\n')
					status='i'
				end
			else
				if not self:find_dev(devinfo) then
					-- empty match matches everything
					if chdku.match_device(devinfo,opts.match) and lcon:match_ptp_info(opts.match) then
						status='+'
						table.insert(self.cams,lcon)
						-- ensure new cams have a unique id even, loaded list may not be contiguous
						self.max_id = self.max_id + 1
						lcon.mc_id = self.max_id
						if serial then
							self.cams_by_serial[serial]=lcon
						end
					else
						status='i'
					end
				end
			end
			printf('%s %d:%s b=%s d=%s s=%s\n',
				status,
				i,
				lcon.ptpdev.model,
				lcon.condev.bus,
				lcon.condev.dev,
				tostring(lcon.ptpdev.serial_number))
			-- disconnect temporary connections
			if status == 'i' and opts.close_tempcons then
				lcon:disconnect()
			end
		end
	end
	-- warn on missing cams, update max id
	if opts.list then
		for serial, cam_data in pairs(ser_list) do
			if not self.cams_by_serial[serial] then
				warnf('missing cam %s:%s\n',cam_data.id,serial)
			end
			if cam_data.id > self.max_id then
				self.max_id = cam_data.id
			end
		end
	end
	self:sel('all')
end

--[[
disconnect selected cameras
]]
function mc:disconnect()
	for lcon in self:icams() do
		lcon:disconnect()
	end
end

--[[
reconnect selected cameras
]]
function mc:reconnect()
	for lcon in self:icams() do
		lcon:disconnect()
	end
	sys.sleep(2000)
	self:connect({selected=true})
end

--[[
select cameras by ID
what is one of
array of ids
table specifying range with {min=min_id,max=max_id}
min,max default to 1, max_id respectively
single id
]]
function mc:sel(what)
	-- treat single id like array
	if type(what) == 'number' then
		what={what}
	end
	if what == 'all' then
		self.selected = util.extend_table({},self.cams)
	elseif type(what) == 'table' then
		local new_sel = {}
		-- range
		if what.min or what.max then
			if not what.min then
				what.min = 1
			end
			if not what.max then
				what.max = self.max_id
			end
			for i=what.min,what.max do
				local lcon = self:find_id(i)
				-- note ids may have gaps, so missing is not an error
				if lcon then
					table.insert(new_sel,lcon)
				end
			end
		else
		-- array of explicit IDs
			for i,v in ipairs(what) do
				local lcon = self:find_id(v)
				if lcon then
					table.insert(new_sel,lcon)
				else
					errlib.throw{etype='bad_arg',msg='attempted to select non-existent id '..tostring(v)}
				end
			end
		end
		self.selected = new_sel
	else
		errlib.throw{etype='bad_arg',msg='invalid selection'}
	end
	-- sort by ID so operations happen in a consistent order
	table.sort(self.selected, function(a,b) return a.mc_id < b.mc_id end)
end

function mc:describe(lcon)
	local status = '?'
	if util.in_table(self.selected,lcon) then
		status = '*'
	elseif util.in_table(self.cams,lcon) then
		status = ' '
	end
	printf('%s id=%s %s b=%s d=%s s=%s\n',
		status,
		lcon.mc_id,
		lcon.ptpdev.model,
		lcon.condev.bus,
		lcon.condev.dev,
		tostring(lcon.ptpdev.serial_number))
end

function mc:list_sel()
	for lcon in self:icams() do
		self:describe(lcon)
	end
end

--[[
check for disconnected cameras,
powercycle them with cam_powercycle_cmd if set, otherwise wait for manual power cycle
reconnect using connect_opts (default all cameras) and start multicam script
]]
function mc:check_connections(connect_opts)
	local dis_cams={}
	local con_cams={}
	-- build lists of connected and disconnected
	for lcon in self:icams() do
		if lcon:is_connected() then
			table.insert(con_cams,lcon.mc_id)
		else
			table.insert(dis_cams,lcon.mc_id)
		end
	end
	-- no disconnected cams, done
	if #dis_cams == 0 then
		printf("all %d cams ok\n",#con_cams)
		return
	end
	self:sel(con_cams)
	-- exit camera side script on still running cams
	self:cmd('exit')
	for i, mc_id in ipairs(dis_cams) do
		printf("restart %d\n",mc_id)
		-- some command that powercycles the crashed cameras based on camera id
		if self.cam_powercycle_cmd then
			os.execute(self.cam_powercycle_cmd .. ' ' .. mc_id)
		end
	end
	if self.cam_powercycle_cmd then
		-- give the cameras time to start
		sys.sleep(5000)
	else
		cli.readline("press return when cameras are restarted >")
	end
	-- (re)connect cameras
	self:connect(connect_opts)
	-- restart script
	self:start()
	return
end


function mc:list_all()
	for i,lcon in ipairs(self.cams) do
		self:describe(lcon)
	end
end

local function get_list_path(path)
	if not path then
		path=fsutil.joinpath(get_chdkptp_home('.'),'mccams.txt')
	end
	return path
end
--[[
write a list of camera serial numbers 
path=string --path to file default CHDKPTP_HOME/mccams.txt
opts:{
	overwrite=bool
}
]]
function mc:save_list(path,opts)
	opts=util.extend_table({},opts)
	if #mc.cams == 0 then
		warnf("no cameras\n")
		return
	end
	path=get_list_path(path)

	if not opts.overwrite and lfs.attributes(path,'mode') then
		warnf("%s exists, overwrite not enabled\n",path)
		return
	end

	local t={}
	for lcon in self:icams() do
		if lcon.ptpdev.serial_number then
			-- TODO might want to include additional data
			t[lcon.ptpdev.serial_number] = {id=lcon.mc_id}
		else
			warnf("%s: missing serial\n",lcon.mc_id)
		end
	end
	local s=util.serialize(t,{pretty=true,bracket_keys=true})

	fsutil.mkdir_parent(path)
	local fh=fsutil.open_e(path,'wb')
	fh:write(s)
	fh:close()
	printf("wrote: %s\n",path)
end
--[[
load and return saved camera list
]]
function mc:load_list(path)
	path=get_list_path(path)
	local list=fsutil.readfile_e(path)
	return util.unserialize(list)
end

function mc:start_single(lcon,opts)
	opts = util.extend_table({},opts)
	opts.id = lcon.mc_id
	local status = lcon:script_status()
	-- attempt to end a running mc (otherwise script id is wrong)
	-- TODO should use killscript if safe
	if status.run then
		warnf('%s: attempting to stop running script\n',lcon.mc_id)
		lcon:write_msg('exit')
		status = lcon:wait_status{
			run=false,
			timeout=250,
		}
		if status.timeout then
			errlib.throw{etype='timeout','timed out waiting for script'}
		end
	end

	lcon:exec('mc.run('..util.serialize(opts)..')',{libs='multicam'})
end

--[[
set id on connection and on cam if script is running.
If script not running, will be updated on next start
]]
function mc:set_id_cam(lcon,id)
	lcon.mc_id = id
	if lcon:script_status().run then
		-- copy table
		local saved_sel = util.extend_table({},self.selected)
		self.selected={lcon} -- allow using normal command functions on just this connection
		local status, rstatus, err = self:cmdwait(string.format('setid %d',lcon.mc_id))
		if not status then
			warnf("setid failed %s",tostring(err))
		end
		if rstatus.failed then
			warnf("setid failed %s",tostring(rstatus.err))
		end
		self.selected=saved_sel
	end
end
--[[
change the id of a camera
old_id = number -- existing id of camera to change
new_id = number -- new id value
conflicts = 'swap' | 'error' -- what to do if new exists, default 'swap'
selection is reset to all
]]
function mc:set_id(old_id,new_id,conflicts)
	if not conflicts then
		conflicts = 'swap'
	end
	local lcon=self:find_id(old_id)
	if not lcon then
		errlib.throw{etype='bad_arg',msg='no matching id: '..tostring(old_id)}
	end
	local conflict_con=self:find_id(new_id)
	if conflict_con then
		if conflicts == 'error' then
			errlib.throw{etype='bad_arg',msg='new id already exists: '..tostring(new_id)}
		elseif conflicts ~= 'swap' then
			errlib.throw{etype='bad_arg',msg='invalid conflict option: '..tostring(conflicts)}
		end
		-- otherwise, swap
		self:set_id_cam(conflict_con,old_id)
	end
	self:set_id_cam(lcon,new_id)

	-- update max_id if needed
	if new_id > self.max_id then
		self.max_id = new_id
	end

	-- reset selection, since it may no longer be valid
	self:sel('all')
end

--[[
start the script on all cameras
]]
function mc:start(opts)
	for lcon in self:icams() do
		local status, err=xpcall(function() return self:start_single(lcon,opts) end ,errutil.format)
		if not status then
			warnf('%s: failed %s\n',lcon.mc_id,err)
		end
	end
end

function mc:check_errors()
	for lcon in self:icams() do
		local status,msg=lcon:read_msg_pcall()
		if status then
			if msg.type ~= 'none' then
				if msg.script_id ~= lcon:get_script_id() then
					warnf("%s: message from unexpected script %d %s\n",lcon.mc_id,msg.script_id,chdku.format_script_msg(msg))
				elseif msg.type == 'user' then
					warnf("%s: unexpected user message %s\n",lcon.mc_id,chdku.format_script_msg(msg))
				elseif msg.type == 'return' then
					warnf("%s: unexpected return message %s\n",lcon.mc_id,chdku.format_script_msg(msg))
				elseif msg.type == 'error' then
					warnf('%s:%s\n',lcon.mc_id,msg.value)
				else
					warnf("%s: unknown message type %s\n",lcon.mc_id,tostring(msg.type))
				end
			end
		else
			warnf('%s:read_msg error %s\n',lcon.mc_id,tostring(err))
		end
	end
end

function mc:init_sync_single_send(i,lcon,lt0,rt0,ticks,sends)
	local tsend = ustime.new()
	local diff = ustime.diffms(lt0)
	lcon:write_msg('tick')
	sends[i] = ustime.diffms(tsend)

	local expect = rt0 + diff
	local msg=lcon:wait_msg({
			mtype='user',
			msubtype='table',
			munserialize=true,
	})
	printf('%s: send %d diff %d pred=%d r=%d delta=%d\n',
		lcon.mc_id,
		sends[i],
		diff,
		expect,
		msg.status,
		expect-msg.status)
	table.insert(ticks,expect-msg.status)
end

--[[
get tick count as a sync'd command
all variation should be due to the cameras 10 ms tick resolution
]]
function mc:check_sync_single(lcon,opts)
	opts=util.extend_table({
		count=10,
		verbose=true,
		syncat=100,
	},opts)
	local deltas = {}
	for i=1,opts.count do
		local expect = self:get_sync_tick(lcon,ustime.new(),opts.syncat)
		lcon:write_msg(string.format('synctick %d',expect))
		local msg=lcon:wait_msg({
				mtype='user',
				msubtype='table',
				munserialize=true,
		})
		deltas[i] = expect-msg.status
		if opts.verbose then
			printf('%s: expect=%d r=%d d=%d %s\n',
				lcon.mc_id,
				expect,
				msg.status,
				expect-msg.status,
				msg.msg)
		end
	end
	local stats=util.table_stats(deltas)
	printf('%s: n=%d min=%d max=%d mean=%f sd=%f\n',
			lcon.mc_id,
			#deltas,
			stats.min,
			stats.max,
			stats.mean,
			stats.sd)
end

function mc:init_sync_single(lcon,lt0,rt0,count)
	local ticks={}
	local sends={}
	--printf('lt0 %d rt0 %d\n',lt0,rt0)
	for i=1,count do
		local status,err=pcall(self.init_sync_single_send,self,i,lcon,lt0,rt0,ticks,sends)
		if not status then
			warnf('init_sync_single_send %s\n',tostring(err))
		end
	end
-- average difference between predicted and returned time in test
-- large |value| implies initial from init_sync was an exteme
	local tick_stats = util.table_stats(ticks)
-- msend average time to complete a send, accounts for a portion of latency
-- not clear what this includes, or how much is spent in each direction
	local send_stats = util.table_stats(sends)
	printf('%s: ticks=%d min=%d max=%d mean=%f sd=%f\n',
			lcon.mc_id,
			#ticks,
			tick_stats.min,
			tick_stats.max,
			tick_stats.mean,
			tick_stats.sd)
	printf('%s: sends=%d min=%d max=%d mean=%f sd=%f\n',
			lcon.mc_id,
			#sends,
			send_stats.min,
			send_stats.max,
			send_stats.mean,
			send_stats.sd)
	lcon.mc_sync = {
		lt0=lt0, -- base local time
		rt0=rt0, -- base remote time obtained at lt0 + latency
		tickoff=tick_stats.mean,
		msend=send_stats.mean,
		sdsend=send_stats.sd,
		-- adjusted base remote time 
		rtadj = rt0 - tick_stats.mean - send_stats.mean/2,
	}
end
function mc:init_sync_cam(lcon,count)
	local t0=ustime.new()
	lcon:write_msg('tick')
	local msg=lcon:wait_msg({
		mtype='user',
		msubtype='table',
		munserialize=true,
	})
	self:init_sync_single(lcon,t0,msg.status,count)
end
--[[
initialize values to allow all cameras to execute a given command as close as possible to the same real time
]]
function mc:init_sync(count)
	-- flush any old messages
	self:flushmsgs()
	self.min_sync_delay = 0 -- minimum time required to send to all cams
	if not count then
		count = 10
	end
	for lcon in self:icams() do
		local status,err=pcall(self.init_sync_cam,self,lcon,count)
		if status then
			-- TODO mean send time might not be enough, add one SD
			self.min_sync_delay = self.min_sync_delay + lcon.mc_sync.msend + lcon.mc_sync.sdsend
		else
			warnf('%s:init_sync_cam: %s\n',lcon.mc_id,tostring(err))
		end
	end
	printf('minimum sync delay %d\n',self.min_sync_delay)
end

--[[
fill in status table r for a single camera
cmd is the command for which status is expect, nil or false accepts any
status table is in the form
{
 done=bool -- state to track all cameras that have returned a status
 failed=bool -- true if there were local or communication arrors
 status={ -- camera side status table
  cmd=string -- command  name
  status=value -- camera side status value, may be any serializable type
  msg=string -- camera side message, usually an error 
 }
}
]]
function mc:get_single_status(lcon,cmd,r)
	local status,err = lcon:script_status_pcall()
	if not status then
		r.failed = true
		r.err = tostring(err)
		return
	else
		status=err
	end
	if status.msg then
		local status,msg=pcall(lcon.read_msg_strict,lcon,{
			mtype='user',
			msubtype='table',
			munserialize=true
		})
		if not status then
			r.failed = true
			r.err = tostring(msg)
			return 
		end
		-- TODO it would be good to skip over any stale status messages
		if cmd and msg.cmd ~= cmd then
			r.failed = true
			r.err = 'status from unexpected cmd:'..tostring(msg.cmd)
		end
		r.done = true
		r.status = msg
		return
	elseif status.run == false then
		-- not running, no messages waiting
		r.failed = true
		r.err = 'script not running'
		return
	end
end
--[[
wait until all cameras have returned a status message for 'cmd' or timed out
]]
function mc:wait_status_msg(cmd,opts)
	opts = util.extend_table({
		timeout=10000,
		initwait=10,
		poll=250,
	},opts)
	if opts.initwait then
		sys.sleep(opts.initwait)
	end
	local results={}
	for lcon in self:icams() do
		results[lcon.mc_id] = {
			failed=false,
			done=false,
		}
	end
	local tstart=ustime.new()
	local tpoll=ustime.new()
	while true do
		local complete = 0
		tpoll:get()
		for lcon in self:icams() do
			local r = results[lcon.mc_id]
			if r.failed or r.done then
				complete = complete + 1
			else
				self:get_single_status(lcon,cmd,r)
			end
		end
		if complete == #self.selected then
			return true, results
		end
		if ustime.diffms(tstart) > opts.timeout then
			for lcon in self:icams() do
				if not results[lcon.mc_id].done then
					results[lcon.mc_id].failed=true
					results[lcon.mc_id].err='timeout'
				end
			end
			return false, results
		end
		local poll = opts.poll - ustime.diffms(tpoll)
		if poll > 0 then
			sys.sleep(opts.poll)
		end
	end
end
--[[
get camera tick matching tstart + syncat
<camera base time> + <tstart - local base time> + syncat
]]
function mc:get_sync_tick(lcon,tstart,syncat)
	return lcon.mc_sync.rtadj + ustime.diffms(tstart,lcon.mc_sync.lt0) + syncat
end
function mc:flushmsgs()
	for lcon in self:icams() do
		lcon:flushmsgs()
	end
end
--[[
send command
opts {
	wait=bool - expect / wait for status message
	flushmsgs=bool - flush any pending messages
	syncat=<ms> -- number of ms after now command should execute (TODO accept a ustime)
	args=string -- additional arugments after synctime (if set)
	printcmd=bool|'once' -- print commands to each cam as sent, or once before sent to any
}
if syncat is set, sends a synchronized command
to execute at approximately local issue time + syncat
command must accept a camera tick time as it's argument (e.g. shoot)
]]
function mc:cmd(cmd,opts)
	local tstart = ustime.new()
	opts=util.extend_table_multi({},{mc.cmd_defaults,opts})
	if opts.flushmsgs then
		self:flushmsgs()
	end
	if opts.printcmd == 'once' then
		local s=cmd
		if opts.syncat then
			s=string.format('%s [sync +%d]',s,opts.syncat)
		end
		if opts.args then
			s=s..' '..opts.args
		end
		printf('%s\n',s)
	end
	for lcon in self:icams() do
		local sendcmd = cmd
		local status,err
		if opts.syncat then
			sendcmd = string.format('%s %d',sendcmd,self:get_sync_tick(lcon,tstart,opts.syncat))
		end
		if opts.args then
			sendcmd = sendcmd..' '..opts.args
		end
		local status,err = lcon:write_msg_pcall(sendcmd)
		if opts.printcmd == true then
			printf('%s:%s\n',lcon.mc_id,sendcmd)
		end
		if not status then
			warnf('%s: send %s cmd failed: %s\n',lcon.mc_id,tostring(sendcmd),tostring(err))
		end
	end
	if not opts.wait then
		return true
	end

	-- to match remote command name
	local cmdname=string.match(cmd,'^([%w_]+)')

	return self:wait_status_msg(cmdname,opts)
end

function mc:cmdwait(cmd,opts)
	opts = util.extend_table({wait=true},opts)
	return self:cmd(cmd,opts)
end

function mc:print_cmd_status(status,results)
	if status then
		printf("ok\n")
	else
		printf("errors\n")
	end
	if results then
		for lcon in mc:icams() do
			local v=results[lcon.mc_id]
			printf('%s: %s\n',lcon.mc_id,tostring(util.serialize(v,{pretty=true})))
		end
	end
end
function mc:print_cmd_status_short(status,results)
	if self.verbose then
		self:print_cmd_status(status,results)
		return
	end
	if status then
		printf("ok\n")
	else
		printf("errors\n")
	end
	if results then
		for lcon in mc:icams() do
			local v=results[lcon.mc_id]
			if v.failed or not v.status.status then
				printf('%s: %s\n',lcon.mc_id,tostring(util.serialize(v,{pretty=true})))
			end
		end
	end
end
--[[
take one ore more shots
opts:{
	tv=number -- APEX*96 shutter speed
	sv=number -- APEX*96 "real" ISO
	av=number -- APEX*96 aperture
	nd=number -- nd filter state 0=canon fw, 1=in 2=out
	synctime=number -- number of milliseconds in the future to shoot, must be >= min_sync_deley
	shots=number -- number of shots, default 1
	interval=number -- number of milliseconds between shots, default 2000
	cont=bool -- use continuous mode for shooting, if enabled in canon UI, default true
	usb_pwr_sync=bool -- hardware usb sync, shoots when +5v goes to 0.
						-- synctime and interval ignored, does not wait for status
--]]
function mc:shoot(opts) 
	opts = util.extend_table({
	},opts)
	if not opts.usb_pwr_sync then
		if not self.min_sync_delay then
			warnf('sync not initialized\n')
			return
		end
		if not opts.synctime then
			opts.synctime=self.min_sync_delay + 50
		elseif opts.synctime < self.min_sync_delay then
			warnf("synctime %d < min_sync_delay %d, adjusted\n",opts.synctime,self.min_sync_delay)
			opts.synctime = self.min_sync_delay + 50
		end
	end
	self:flushmsgs()
	local init_cmds = {}
	local init_cmd
	if opts.tv then
		table.insert(init_cmds,string.format('set_tv96_direct(%d)',opts.tv))
	end
	if opts.sv then
		table.insert(init_cmds,string.format('set_sv96(%d)',opts.sv))
	end
	if opts.av then
		table.insert(init_cmds,string.format('set_av96_direct(%d)',opts.av))
	end
	if opts.nd then
		table.insert(init_cmds,string.format('set_nd_filter(%d)',tostring(opts.nd)))
	end
	if #init_cmds > 0 then
		init_cmd = 'call '..table.concat(init_cmds,';')
	end
	if init_cmd then
		self:print_cmd_status_short(self:cmdwait(init_cmd))
	end
	self:print_cmd_status_short(self:cmdwait('preshoot'))
	if opts.usb_pwr_sync then
		-- no wait because polling while camera is in USB busy loop causes errors
		self:cmd('shoot_burst_usb_pwr',{
			args=util.serialize{shots=opts.shots,cont=opts.cont,release_half=true}
		})
	else
		self:print_cmd_status_short(self:cmdwait('shoot_burst',{
			syncat=opts.synctime,
			args=util.serialize{shots=opts.shots,interval=opts.interval,cont=opts.cont,release_half=true}
		}))
	end
end
--[[
take one ore more shots, printing timestamps on the screen to allow rough sync comparison
opts:{
	tv:number -- APEX*96 shutter speed
	sv:number -- APEX*96 "real" ISO
	shoot_cmd:string -- shoot type, either shoot or shoot_hook_sync
	synctime:number -- number of milliseconds in the future to shoot, must be >= min_sync_deley
	defexp:boolean -- use tv=1/256 sv=400
--]]
function mc:testshots(opts) 
	opts = util.extend_table({ 
		nshots=1,
		shoot_cmd='shoot',
	},opts)
	if not self.min_sync_delay then
		warnf('sync not initialized\n')
		return
	end
	self:flushmsgs()
	if not opts.synctime or opts.synctime < self.min_sync_delay then
		opts.synctime = self.min_sync_delay + 50
	end
	if opts.defexp then
		opts.tv = 768
		opts.sv = 672
	end
	local init_cmds = {}
	local init_cmd
	if opts.tv then
		table.insert(init_cmds,string.format('set_tv96_direct(%d)',opts.tv))
	end
	if opts.sv then
		table.insert(init_cmds,string.format('set_sv96(%d)',opts.sv))
	end
	if #init_cmds > 0 then
		init_cmd = 'call '..table.concat(init_cmds,';')
	end
	for i=1,opts.nshots do
		self:print_cmd_status(self:cmdwait('call return get_exp_count()'))
		if init_cmd then
			self:print_cmd_status(self:cmdwait(init_cmd))
		end
		self:print_cmd_status(self:cmdwait('preshoot'))
		local t=ustime.new()
		self:cmd(opts.shoot_cmd,{syncat=opts.synctime})
		if opts.synctime > 60 then
			sys.sleep(opts.synctime - 60)
		end
		for j=1,25 do
			printf('%d %d\n',i,ustime.diffms(t)-opts.synctime)
			sys.sleep(20)
		end
		self:print_cmd_status(self:wait_status_msg(opts.shoot_cmd))
		self:print_cmd_status(self:cmdwait('call return get_exp_count()'))
		sys.sleep(500)
	end
end

--[[
run a cmd that returns data via batched messages, for things like file lists
]]
function mc:cmd_msgbatch_cam(lcon,cmd)
	local status,err = lcon:write_msg_pcall(cmd)
	if not status then
		warnf('%s: send %s cmd failed: %s\n',lcon.mc_id,tostring(cmd),tostring(err))
		return
	end
	local r={}
	while true do
		local msg=lcon:wait_msg({
				mtype='user',
				msubtype='table',
				munserialize=true,
		})
		-- batcher message, should just have numeric indexes
		if msg.status == nil then
			for k,v in ipairs(msg) do
				table.insert(r,v)
			end
		-- error
		elseif not msg.status then 
			warnf('%s: failed %s\n',lcon.mc_id,tostring(msg.msg))
			return
		-- done
		else
			return r
		end
	end
end
function mc:cmd_msgbatch(cmd)
	local r={}
	for lcon in self:icams() do
		local l=self:cmd_msgbatch_cam(lcon,cmd)
		if l then
			r[lcon.mc_id] = l
		end
	end
	return r
end

--[[
list images for all cams, return in array indexed by mc_id
]]
function mc:imglist(opts)
	opts=util.extend_table({},opts)
	local ropts=util.extend_table({
		dirs=false,
		fmatch='%a%a%a_%d%d%d%d%.%w%w%w',
	},opts,{
		keys=chdku.imglist_remote_opts,
	})
	local cmd = string.format('imglist %s',util.serialize(ropts))

	local r=self:cmd_msgbatch(cmd)
	if opts.sort then
		for lcon in self:icams() do
			if r[lcon.mc_id] then
				chdku.imglist_sort(r[lcon.mc_id],opts)
			end
		end
	end
	return r
end

--[[
general file listing
]]
function mc:find_files(paths,opts)
	if type(paths) == 'string' then
		paths = {paths}
	end
	opts=util.extend_table({},opts)
	local ropts=util.extend_table({},opts)
	ropts.ff_func=nil
	local cmd = string.format('call return find_files(%s,%s,%s)',
		util.serialize(paths),
		util.serialize(ropts),
		opts.ff_func)
	return self:cmd_msgbatch(cmd)
end

function mc:delete_files_list_cam(lcon,imgs,opts)
	for i,f in ipairs(imgs) do
		if opts.verbose then
			printf('os.remove("%s")\n',f.full)
		end
		if not opts.pretend then
			lcon:flushmsgs() -- prevent status from being confused by stale messages
			-- TODO one at a time with status is slow, should batch in both directions
			local status,err = lcon:write_msg_pcall(string.format('pcall return os.remove("%s")',f.full))
			if not status then
				warnf("%s send failed %s\n",lcon.mc_id,tostring(err))
				return
			end
			local msg=lcon:wait_msg({
					mtype='user',
					msubtype='table',
					munserialize=true,
			})
			if msg.status == false then
				warnf("%s remove failed %s\n",lcon.mc_id,tostring(msg.err))
			end
		end
	end
end

--[[
delete files/directories listed in format return by find_files / imglist
to delete directories, you must ensure files are sorted with directories last (dirsfirst=false for find_files)
e.g.
l=mc:find_files('A/DCIM',{dmatch='%d%d%d___%d%d',fmatch='%d%d%d___%d%d/.*',dirsfirst=false,ff_func='find_files_all_fn'})
mc:delete_files_list(l)
]]
function mc:delete_files_list(list,opts)
	opts=util.extend_table({},opts)
	if opts.pretend then
		opts.verbose = true
	end

	for id,imgs in pairs(list) do
		local lcon = self:find_id(id)
		if lcon then
			self:delete_files_list_cam(lcon,imgs,opts)
		else
			warnf("missing connection %s\n",id)
		end
	end
end
-- backwards compat
mc.delete_images_list = mc.delete_files_list

--[[
opts={
	dst=string -- substitution pattern for downloaded files
	delete=bool -- delete after download - not directories will not be deleted
	overwrite=bool -- overwrite existing
	pretend=bool -- print actions without doing anything. Sets verbose unless verbose is explicitly false
	verbose=bool -- print actions
	-- everything else passed to imagelist, download_file_ff
}
multicam specific substitution variables
${id,strfmt} camera ID, default format %02d
see chdku imglist_subst_funcs for standard variables
returns list of images
]]
function mc:download_images(opts)
	opts=util.extend_table({
		dst='${id}/${subdir}/${name}',
		info_fn=util.printf,
		dlseq_start=1,
		shotseq_start=1,
		sort='date',
		sort_order='asc',
	},opts)
	if opts.pretend and opts.verbose ~= false then
		opts.verbose = true
	end
	local subst=varsubst.new(self.download_images_subst_funcs)
	subst:validate(opts.dst)
	chdku.set_subst_time_state(subst.state)

	-- list all images
	local list=self:imglist(opts)
	for id,imgs in pairs(list) do
		local lcon=self:find_id(id)
		if not lcon then
			warnf("missing connection %s\n",id)
			break
		end
		subst.state.id = id
		lcon:set_subst_con_state(subst.state)

		subst.state.dlseq = opts.dlseq_start
		subst.state.shotseq = opts.shotseq_start
		subst.state._seq_first_done = false -- state is re-used for multiple cams
		for i,f in ipairs(imgs) do
			chdku.imglist_set_subst_finfo_state(subst.state,f)
			chdku.imglist_set_subst_seq_state(subst.state)
			local dst = subst:run(opts.dst)
			lcon:download_file_ff(f,dst,opts)
		end
	end
	if opts.delete then
		self:delete_files_list(list,{pretend=opts.pretend,verbose=opts.verbose})
	end
	return list
end

--[[
remote script
waits in a loop for messages
most commands return status with messages of the form
{
	cmd=<command name>
	status=<status|return value>
	msg=<error message>
}
commands
	rec: switch to record
	play: switch to playback
	preshoot: press shoot half and wait for get_shooting
	shoot [ms]: wait [ms], press shoot full, wait for get_shooting
	shoot_hook_sync [ms]: as above, except using chdk >= 1.3 shoot hook
	shoot_burst <ms> <options>: shoot one or more shots using shoot hook
	shoot_burst_usb_pwr <options>: shoot one or more shots using usb vbus hardware control
	tick: return the value of get_tick_count
	synctick [ms]: wait [ms], return get_tick_count after wait
	exit: end script
	id: toggle id display
	lastimg: return full path of last shot image
	imglist: send a list of images using using find_files, terminated by a status message
			must NOT be used directly with cmdwait
			args should be a serialized lua table of options for find_files, optionally specifying
			initial paths with start_paths
	call <lua code>: run given lua code, return any results with write_status
	pcall <lua code>: run given lua code in pcall, return any results with write_status
]]
local function init()
	chdku.rlibs:register({
		name='multicam',
		depend={'extend_table','serialize_msgs','unserialize','ff_imglist'},
		code=[[
props=require'propcase'
if type(hook_shoot) == 'table' then
	require'hookutil'
end

mc={
	mode_sw_timeout=2500,
	preshoot_timeout=5000,
	shoot_complete_timeout=5000,
	msg_timeout=100,
	shoot_hold=10,
	shoot_hook_timeout=5000,
	raw_hook_timeout=5000,
	shoot_hook_ready_timeout=10000,
	raw_hook_ready_timeout=10000,
}

color={
	transparent=256,
	black=257,
	white=258,
	red=259,
	green=263,
	blue=266,
	yellow=271,
}

cmds={}

-- wait, sleeping <wait> ms until <func> returns <value> or timeout hit, write status message
function wait_timeout_write_status(func,value,wait,timeout,msg)
	if not msg then
		msg = 'timeout'
	end
	while func() ~= value do
		sleep(wait)
		timeout = timeout - wait
		if timeout <= 0 then
			write_status(false,msg)
			return false
		end
	end
	write_status(true)
	return true
end

function write_status(status,msg)
	write_usb_msg({
		status=status,
		msg=msg,
		cmd=mc.cmd,
	},mc.status_msg_timeout)
end

function wait_tick(synctick)
	if synctick then
		local s=synctick - get_tick_count()
		if s >= 10 then
			sleep(s)
		end
	end
end

function draw_id()
	if not mc.show_id then
		return
	end
	if mc.id then
		draw_string(5, 5, string.format('%02d',mc.id), color.white, color.blue, 4) 
	else
		draw_string(5, 5, "-", color.white, color.red, 4) 
	end
end

function cmds.id()
	mc.show_id=not mc.show_id
	draw_clear()
	draw_id()
	write_status(true,mc.show_id)
end

function cmds.setid()
	local old_id = mc.id
	local new_id = tonumber(mc.args)
	mc.id = new_id
	write_status(true, string.format('%d=>%d',old_id,new_id))
end

function cmds.rec()
	if not get_mode() then
		switch_mode_usb(1)
	end
	wait_timeout_write_status(get_mode,true,100,mc.mode_sw_timeout)
end
function cmds.play()
	if get_mode() then
		switch_mode_usb(0)
	end
	wait_timeout_write_status(get_mode,false,100,mc.mode_sw_timeout)
end
function cmds.preshoot()
	press('shoot_half')
	local status=wait_timeout_write_status(get_shooting,true,10,mc.preshoot_timeout)
	if not status then
		release('shoot_half')
	end
end

function cmds.shoot()
	wait_tick(tonumber(mc.args))
	press('shoot_full')
	sleep(mc.shoot_hold)
	release('shoot_full')
	wait_timeout_write_status(get_shooting,false,100,mc.shoot_complete_timeout,'get_shooting timeout')
end

function cmds.shoot_hook_sync()
	if type(hook_shoot) ~= 'table' then
		write_status(false, 'build does not support shoot hook')
		return
	end
	hook_shoot.set(mc.shoot_hook_timeout)
	press('shoot_full')
	local wait_time = 0
	while not hook_shoot.is_ready() do
		if wait_time > mc.shoot_hook_ready_timeout then
			hook_shoot.set(0)
			release('shoot_full')
			write_status(false, 'hook_shoot ready timeout')
			return
		end
		sleep(10)
		wait_time = wait_time + 10
	end
	wait_tick(tonumber(mc.args))
	hook_shoot.continue()
	sleep(mc.shoot_hold)
	release('shoot_full')
	hook_shoot.set(0)
	wait_timeout_write_status(get_shooting,false,100,mc.shoot_complete_timeout,'get_shooting timeout')
end

function cmds.shoot_burst()
	if type(hook_shoot) ~= 'table' then
		write_status(false, 'build does not support shoot hook')
		return
	end
	local synctick,rest=string.match(mc.args,'^([%w_]+)%s*(.*)')
	synctick=tonumber(synctick)
	local opts,err
	if string.len(rest) > 0 then
		opts,err=unserialize(rest)
		if not opts then
			write_status(false,'unserialize failed '..tostring(err))
			return
		end
	end
	opts=extend_table({
		shots=1,
		interval=2000,
		cont=true,
		shoot_hook_timeout=mc.shoot_hook_timeout,
		raw_hook_timeout=mc.raw_hook_timeout,
		shoot_hook_ready_timeout=mc.shoot_hook_ready_timeout,
		raw_hook_ready_timeout=mc.raw_hook_ready_timeout,
	},opts)
	local cont = opts.cont and get_prop(props.DRIVE_MODE) == 1

	local r={}
	hook_shoot.set(opts.shoot_hook_timeout)
	hook_raw.set(opts.raw_hook_timeout)
	local last_shot_tick
	if cont then
		press('shoot_full_only')
	end

	for i=1,opts.shots do
		if not cont then
			press('shoot_full_only')
		end
		if not hook_shoot.wait_ready({timeout=opts.shoot_hook_ready_timeout,timeout_error=false}) then
			release('shoot_full') -- both full and half
			hook_shoot.set(0)
			hook_raw.set(0)
			write_status(false, 'hook_shoot ready timeout')
			return
		end
		ready_tick=get_tick_count()
		wait_tick(synctick)
		hook_shoot.continue()
		local shot_tick=get_tick_count()
		local shot_int
		if last_shot_tick then
			shot_int=shot_tick - last_shot_tick
		else
			shot_int=0
		end
		last_shot_tick = shot_tick
		r[i]=string.format("%d w:%d i=%d",i,synctick-ready_tick,shot_int)
		synctick=synctick+opts.interval
		if not cont then
			release('shoot_full_only')
		end
		-- wait for raw hook before shooting again
		if not hook_raw.wait_ready({timeout=opts.raw_hook_ready_timeout,timeout_error=false}) then
			release('shoot_full') -- both full and half
			hook_shoot.set(0)
			hook_raw.set(0)
			write_status(false, 'hook_raw ready timeout')
			return
		end
		hook_raw.continue()
	end
	if cont then
		release('shoot_full_only')
	end
	if opts.release_half then
		release('shoot_half')
	end
	hook_shoot.set(0)
	hook_raw.set(0)
	write_status(true,table.concat(r,', '))
end

function cmds.shoot_burst_usb_pwr()
	if type(hook_shoot) ~= 'table' then
		write_status(false, 'build does not support shoot hook')
		return
	end
	local opts,err
	if string.len(mc.args) > 0 then
		opts,err=unserialize(mc.args)
		if not opts then
			write_status(false,'unserialize failed '..tostring(err))
			return
		end
	end
	opts=extend_table({
		shots=1,
		cont=true,
		shoot_hook_timeout=mc.shoot_hook_timeout,
		raw_hook_timeout=mc.raw_hook_timeout,
		shoot_hook_ready_timeout=mc.shoot_hook_ready_timeout,
		raw_hook_ready_timeout=mc.raw_hook_ready_timeout, -- TODO should account for expected USB interval, exposure time
	},opts)
	local cont = opts.cont and get_prop(props.DRIVE_MODE) == 1

	usb_force_active(true) -- users should probably set this on startup, but setting again doesn't hurt

	local r={}
	hook_shoot.set(opts.shoot_hook_timeout)
	hook_raw.set(opts.raw_hook_timeout)
	local last_shot_tick
	if cont then
		press('shoot_full_only')
	end

	for i=1,opts.shots do
		usb_sync_wait(true)
		if not cont then
			press('shoot_full_only')
		end
		-- used only for button control
		if not hook_shoot.wait_ready({timeout=opts.shoot_hook_ready_timeout,timeout_error=false}) then
			usb_sync_wait(false)
			release('shoot_full') -- both full and half
			hook_shoot.set(0)
			hook_raw.set(0)
			write_status(false, 'hook_shoot ready timeout')
			return
		end
		hook_shoot.continue()
		if not cont then
			release('shoot_full_only')
		end
		-- wait for raw hook before shooting again
		if not hook_raw.wait_ready({timeout=opts.raw_hook_ready_timeout,timeout_error=false}) then
			release('shoot_full') -- both full and half
			usb_sync_wait(false)
			hook_shoot.set(0)
			hook_raw.set(0)
			write_status(false, 'hook_raw ready timeout')
			return
		end
		r[i]=string.format("%d r:%d",i,get_tick_count())
		hook_raw.continue()
	end
	if cont then
		release('shoot_full_only')
	end
	if opts.release_half then
		release('shoot_half')
	end
	hook_shoot.set(0)
	hook_raw.set(0)
	write_status(true,table.concat(r,', '))
end

function cmds.tick()
	write_status(get_tick_count())
end

function cmds.synctick()
	t=get_tick_count()
	wait_tick(tonumber(mc.args))
	write_status(get_tick_count(),string.format('start %d',t))
end

function cmds.exit()
	mc.done = true
end

function cmds.call()
	local f,err=loadstring(mc.args)
	if f then 
		write_status({f()})
	else
		write_status(false,err)
	end
end

function cmds.pcall()
	local f,err=loadstring(mc.args)
	if f then 
		local r={pcall(f)}
		local status=table.remove(r,1)
		if not status then
			write_status(false,r)
		else
			write_status(true,r)
		end
	else
		write_status(false,err)
	end
end
function cmds.getlastimg()
	write_status(true,string.format('%s/IMG_%04d.JPG',get_image_dir(),get_exp_count()))
end

function cmds.imglist()
	local args,err=unserialize(mc.args)
	if not args then
		write_status(false,'unserialize failed '..tostring(err))
		return
	end
	local status,err = ff_imglist(args)
	if status then
		write_status(true,'done')
	else
		write_status(false,tostring(err))
	end
end

function mc.idle()
	draw_id()
end

function mc.run(opts)
	extend_table(mc,opts)
	set_yield(-1,-1)
	repeat 
		local msg=read_usb_msg(mc.msg_timeout)
		if msg then
			mc.cmd,mc.args=string.match(msg,'^([%w_]+)%s*(.*)')
			if type(cmds[mc.cmd]) == 'function' then
				cmds[mc.cmd]()
			else
				write_status(false,'unknown')
			end
		else
			mc.idle()
		end
	until mc.done
end
]]})
end
init()

return mc
