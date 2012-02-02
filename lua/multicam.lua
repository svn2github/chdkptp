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
!mc:set_record()
!mc:shoot()
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

function mc:set_record()
	for i,lcon in ipairs(self.cams) do
		-- TODO satus/error checking
		lcon:exec('switch_mode_usb(1)')
	end
end

function mc:shoot()
	-- load script and start halfshoot
	for i,lcon in ipairs(self.cams) do
		local status,err = lcon:exec('return mc_shoot()',{libs='multicam'})
		if not status then
			warnf('%d: load shoot script failed: %s\n',i,tostring(err))
		end
	end
	-- give the cams time to ready
	-- TODO could wait for a message
	sys.sleep(2000)
	-- send a shoot message to each cam
	-- TODO could calibrate a delay and send
	for i,lcon in ipairs(self.cams) do
		local status,err = lcon:write_msg('shoot')
		if not status then
			warnf('%d: send shoot message failed: %s\n',i,tostring(err))
		end
	end
	sys.sleep(2000)
	-- read all messages for each camera
	-- TODO success/fail
	for i,lcon in ipairs(self.cams) do
		while true do
			local msg,err=lcon:read_msg()
			if type(msg) == 'table' then 
				if msg.type == 'none' then
					break
				end
				printf('%d:%s\n',i,chdku.format_script_msg(msg))
			else
				warnf('%d: read status failed: %s\n',i,tostring(err))
			end
		end
	end
end

function mc:init()
	chdku.rlibs:register({
		name='multicam',
		depend={'extend_table','serialize_msgs'},
		code=[[
function mc_shoot(opts)
	opts = extend_table({
		preshoot_timeout = 1000,
		msg_timeout = 5000
	},opts);
	
	local wait=0
	press('shoot_half')
	while get_shooting() ~= true do
		sleep(10)
		wait = wait + 10
		if wait >= opts.preshoot_timeout then
			return false, 'get_shooting timed out'
		end
	end
	-- TODO could send a status message here
	sleep(10)
	msg = read_usb_msg(opts.msg_timeout)
	if not msg then
		return false, 'shot msg wait timed out'
	end
	if msg == 'shoot' then
		press('shoot_full')
		sleep(10)
		release('shoot_full')
	end
	release('shoot_half')
	return true
end
]]})
end

mc:init()
return mc
