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
]]
--[[
module for live view gui
]]
local m={}
function m.live_support()
	return (cd ~= nil
			and type(cd.CreateCanvas) == 'function'
			and type(chdk.put_live_image_to_canvas ) == 'function')
end

local stats={ }
function stats:init_counters()
	self.count_xfer = 0
	self.count_frame = 0
	self.xfer_last = 0
	self.xfer_total = 0
end

stats:init_counters()

function stats:start()
	if self.run then
		return
	end
	self:init_counters()
	self.t_start_xfer = nil
	self.t_end_xfer = nil
	self.t_start_draw = nil
	self.t_end_draw = nil
	self.t_start = ustime.new()
	self.t_stop = nil
	self.run = true
end
function stats:stop()
	if not self.run then
		return
	end
	self.run = false
	self.t_stop = ustime.new()
end

function stats:start_frame()
	self.t_start_frame = ustime.new()
	self.count_frame = self.count_frame + 1
end

function stats:end_frame()
	self.t_end_frame = ustime.new()
end
function stats:start_xfer()
	self.t_start_xfer = ustime.new()
	self.count_xfer = self.count_xfer + 1
end
function stats:end_xfer(bytes)
	self.t_end_xfer = ustime.new()
	self.xfer_last = bytes
	self.xfer_total = self.xfer_total + bytes
end
function stats:get()
	local run
	local t_end
	local fps_avg = 0
	local frame_time =0
	local bps_avg = 0
	local xfer_time = 0
	local bps_last = 0

	if self.run then
		run = "yes"
		t_end = self.t_end_frame
	else
		run = "no"
		t_end = self.t_stop
	end
	local tsec = 1 -- dummy to prevent div0
	if t_end and self.t_start then
		tsec = (t_end:diffms(self.t_start)/1000)
	else
		tsec = 1 
	end
	if self.count_frame > 0 then
		fps_avg = self.count_frame/tsec
		frame_time = self.t_end_frame:diffms(self.t_start_frame)
	end
	if self.count_xfer > 0 then
		-- note this includes sleep
		bps_avg = self.xfer_total/tsec
		xfer_time = self.t_end_xfer:diffms(self.t_start_xfer)
		-- instananeous
		bps_last = self.xfer_last/xfer_time*1000
	end
	return string.format(
[[Running: %s
FPS avg: %0.2f
Frame last ms: %d
T/P avg kb/s: %d
Xfer last ms: %d
Xfer kb: %d
Xfer last kb/s: %d]],
		run,
		fps_avg,
		frame_time,
		bps_avg/1024,
		xfer_time,
		self.xfer_last/1024,
		bps_last/1024)
end

local container -- outermost widget
local livedata -- latest data fetched from cam
local icnv -- iup canvas
local vp_active -- viewport streaming selected
local bm_active -- bitmap streaming selected
local timer -- timer for fetching updates
local statslabel -- text for stats
local function toggle_vp(ih,state)
	vp_active = (state == 1)
end

local function toggle_bm(ih,state)
	bm_active = (state == 1)
end

local function update_should_run()
	-- TODO global maintabs
	if not con:is_connected() or maintabs.value ~= container then
		return false
	end
	return (vp_active or bm_active)
end

function m.init()
	if not m.live_support() then
		return false
	end
	icnv = iup.canvas{rastersize="362x242",expand="NO"}
	statslabel = iup.label{size="90x80",alignment="ALEFT:ATOP"}
	container = iup.hbox{
		icnv,
		iup.vbox{
			iup.frame{
				iup.vbox{
					iup.toggle{title="Viewfinder",action=toggle_vp},
					iup.toggle{title="UI Overlay",action=toggle_bm},
				},
				title="Stream"
			},
			iup.frame{
				statslabel,
				title="Statistics",
			},
		},
		margin="4x4",
		ngap="4"
	}

	function icnv:map_cb()
		self.ccnv = cd.CreateCanvas(cd.IUP,self)
	end

	function icnv:action()
		-- TODO global from gui
		if maintabs.value ~= container then
			return;
		end
		local ccnv = self.ccnv     -- retrieve the CD canvas from the IUP attribute
		stats:start_frame()
		ccnv:Activate()
		if livedata then
			if not chdk.put_live_image_to_canvas(ccnv,livedata) then
				print('put fail')
			end
		else
			ccnv:Clear()
		end
		stats:end_frame()
	end

	--[[
	function livecnv:resize_cb(w,h)
		print("Resize: Width="..w.."   Height="..h)
	end
	]]

	container_title='Live'
	timer = iup.timer{ 
		time = "100",
	}
	function timer:action_cb()
		if update_should_run() then
			stats:start()
			local what=0
			if vp_active then
				what = 1
			end
			if bm_active then
				what = what + 4
			end
			if what == 0 then
				return
			end
			-- TODO this needs to get reset on disconnect
			if not con.live_handler then
				--print('getting handler')
				con.live_handler = con:get_handler(1)
			end
			stats:start_xfer()
			livedata = con:call_handler(con.live_handler,what)
			if livedata then
				stats:end_xfer(livedata:len())
			else
				stats:stop()
			end
			icnv:action()
		else
			stats:stop()
		end
		statslabel.title = stats:get()
	end
	m.timer = timer -- test 
end
function m.get_container()
	return container
end
function m.get_container_title()
	return container_title
end
function m.on_connect_change(lcon)
	-- reset on connect or disconnect, will get updated in timer
	lcon.live_handler = nil
end
-- check whether we should be running, update timer
function m.update_run_state()
	if timer then
		-- TODO check this is updated in the callback for gtk
		-- better to just check if control is visible
		if maintabs.value == container then
			timer.run = "YES"
			stats:start()
		else
			timer.run = "NO"
			stats:stop()
		end
	end
end

return m
