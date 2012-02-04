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

local mc={}
--[[
connect to all available cams
TODO add matching support, store camera name, serial etc with con
]]
function mc:connect()
	local devices = chdk.list_usb_devices()
	self.cams={}
	for i, devinfo in ipairs(devices) do
		local lcon,msg = chdku.connection(devinfo)
		-- if not already connected, try to connect
		if not lcon:is_connected() then
			local status,err = lcon:connect()
			if not status then
				warnf('%d: connect failed bus:%s dev:%s err:%s\n',i,devinfo.dev,devinfo.bus,tostring(err))
			end
		end
		-- if connection didn't fail
		if lcon:is_connected() then
			local ptpinfo = lcon:get_ptp_devinfo()
			printf('%d: %s bus:%s dev:%s sn:%s\n',i,ptpinfo.model,devinfo.dev,devinfo.bus,tostring(ptpinfo.serial_number))
			table.insert(self.cams,lcon)
		end
	end
end

--[[
start the script on all cameras
]]
function mc:start(opts)
	for i,lcon in ipairs(self.cams) do
		local status,err = lcon:exec('mc.run('..util.serialize(opts)..')',{libs='multicam'})
		if not status then
			warnf('%d: load script failed: %s\n',i,tostring(err))
		end
	end
end

function mc:check_errors()
	for i,lcon in ipairs(self.cams) do
		local msg,err=lcon:read_msg()
		if msg then
			if msg.type ~= 'none' then
				if msg.script_id ~= lcon:get_script_id() then
					warnf("%d: message from unexpected script %d %s\n",i,msg.script_id,chdku.format_script_msg(msg))
				elseif msg.type == 'user' then
					warnf("%d: unexpected user message %s\n",i,chdku.format_script_msg(msg))
				elseif msg.type == 'return' then
					warnf("%d: unexpected return message %s\n",i,chdku.format_script_msg(msg))
				elseif msg.type == 'error' then
					warnf('%d:%s\n',i,msg.value)
				else
					warnf("%d: unknown message type %s\n",i,tostring(msg.type))
				end
			end
		else
			warnf('%d:read_msg error %s\n',i,tostring(err))
		end
	end
end

function mc:get_single_status(lcon,cmd,r)
	local status,err = lcon:script_status()
	if not status then
		r.failed = true
		r.err = err
		return
	end
	if status.msg then
		local msg,err=lcon:read_msg()
		if not msg then
			r.failed = true
			r.err = 'msg status with no message ?!?'
			return 
		end
		if msg.script_id ~= lcon:get_script_id() then
			-- TODO warn - not sure what to do with soft fails, keep trying ?
			warnf('msg from unexpected script_id %d\n',msg.script_id)
			return
		elseif msg.type == 'user' then
			if msg.subtype ~= 'table' then
				warnf('unexpected message type %s\n',msg.type)
				return
			end
			local v = util.unserialize(msg.value)
			if type(v) ~= 'table' then
				warnf('failed to unserialize msg\n')
				return
			end
			if v.cmd ~= cmd then
				warnf('message from unexpected cmd %s',tostring(msg.cmd))
				return
			end
			r.done = true
			r.status = v.status
			return
		elseif msg.type == 'return' then
			r.failed = true
			r.err = 'unexpected return'
			return
		elseif msg.type == 'error' then
			r.failed = true
			r.err = msg.value
			return
		else
			r.failed = true
			r.err = 'unkown message type ?!?'
			return
		end
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
	for i,lcon in ipairs(self.cams) do
		results[i] = {
			failed=false,
			done=false,
		}
	end
	local tstart=ustime.new()
	local tpoll=ustime.new()
	while true do
		local complete = 0
		tpoll:get()
		for i,lcon in ipairs(self.cams) do
			local r = results[i]
			if r.failed or r.done then
				complete = complete + 1
			else
				self:get_single_status(lcon,cmd,r)
			end
		end
		if complete == #self.cams then
			return true, results
		end
		if ustime.diffms(tstart) > opts.timeout then
			return false, results, 'timeout'
		end
		local poll = opts.poll - ustime.diffms(tpoll)
		if poll > 0 then
			sys.sleep(opts.poll)
		end
	end
end
--[[
send command
opts {
	wait=bool - expect / wait for status message
	arg=string
	--
}
]]
function mc:cmd(cmd,opts)
	opts=util.extend_table({},opts)
	for i,lcon in ipairs(self.cams) do
		local status,err = lcon:write_msg(cmd)
		if not status then
			warnf('%d: send %s cmd failed: %s\n',i,tostring(cmd),tostring(err))
		end
	end
	if not opts.wait then
		return true
	end
	return self:wait_status_msg(cmd,opts)
end

function mc:cmdwait(cmd,opts)
	opts = util.extend_table({wait=true},opts)
	return self:cmd(cmd,opts)
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
	tick: return the value of get_tick_count
	exit: end script
]]
local function init()
	chdku.rlibs:register({
		name='multicam',
		depend={'extend_table','serialize_msgs'},
		code=[[
mc={
	mode_sw_timeout=1000,
	preshoot_timeout=5000,
	shoot_complete_timeout=5000,
	msg_timeout=100000,
	shoot_hold=10,
}

cmds={}

-- wait, sleeping <wait> ms until <func> returns <value> or timeout hit
function wait_timeout(func,value,wait,timeout,msg)
	if not msg then
		msg = 'timeout'
	end
	while func() ~= value do
		sleep(wait)
		timeout = timeout - wait
		if wait <= 0 then
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

function cmds.rec()
	switch_mode_usb(1)
	return wait_timeout(get_mode,true,100,mc.mode_sw_timeout)
end
function cmds.play()
	switch_mode_usb(0)
	return wait_timeout(get_mode,false,100,mc.mode_sw_timeout)
end
function cmds.preshoot()
	press('shoot_half')
	local status=wait_timeout(get_shooting,true,10,mc.preshoot_timeout)
	if not status then
		release('shoot_half')
	end
	return status,msg
end

function cmds.shoot()
	local ms=tonumber(mc.args)
	if ms then
		sleep(ms)
	end
	press('shoot_full')
	sleep(mc.shoot_hold)
	release('shoot_full')
	return wait_timeout(get_shooting,false,100,mc.shoot_complete_timeout,'get_shooting timeout')
end

function cmds.tick()
	write_status(get_tick_count())
end

function cmds.exit()
	mc.done = true
end

function mc.run(opts)
	extend_table(mc,opts)
	repeat 
		local msg=read_usb_msg(mc.msg_timeout)
		if msg then
			mc.cmd,mc.args=string.match(msg,'^(%w+)%s*(.*)')
			if type(cmds[mc.cmd]) == 'function' then
				cmds[mc.cmd]()
			else
				write_status(false,'unknown')
			end
		end
	until mc.done
end
]]})
end
init()

return mc
