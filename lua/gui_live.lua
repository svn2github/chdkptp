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
local m={
--[[
note - these are 'private' but exposed in the module for easier debugging
container -- outermost widget
livedata -- latest data fetched from cam
icnv -- iup canvas
vp_active -- viewport streaming selected
bm_active -- bitmap streaming selected
timer -- timer for fetching updates
statslabel -- text for stats
livehandler -- "handler" to call for live data
livebasedata -- non-changing framebuffer data
]]
}
function m.live_support()
	return (cd ~= nil
			and type(cd.CreateCanvas) == 'function'
			and type(chdk.put_live_image_to_canvas ) == 'function')
end

local stats={
	t_start_frame = ustime.new(),
	t_end_frame = ustime.new(),
	t_start_xfer = ustime.new(),
	t_end_xfer = ustime.new(),
	t_start_draw = ustime.new(),
	t_end_draw = ustime.new(),
	t_start = ustime.new(),
	t_stop = ustime.new(),
}
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
	self.t_start:get()
	self.run = true
end
function stats:stop()
	if not self.run then
		return
	end
	self.run = false
	self.t_stop:get()
end

function stats:start_frame()
	self.t_start_frame:get()
	self.count_frame = self.count_frame + 1
end

function stats:end_frame()
	self.t_end_frame:get()
end
function stats:start_xfer()
	self.t_start_xfer:get()
	self.count_xfer = self.count_xfer + 1
end
function stats:end_xfer(bytes)
	self.t_end_xfer:get()
	self.xfer_last = bytes
	self.xfer_total = self.xfer_total + bytes
end
function stats:get()
	local run
	local t_end
	-- TODO a rolling average would be more useful
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
	local tsec = (t_end:diffms(self.t_start)/1000)
	if tsec == 0 then
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
	-- TODO this rapidly spams lua with lots of unique strings
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


local function toggle_vp(ih,state)
	m.vp_active = (state == 1)
end

local function toggle_bm(ih,state)
	m.bm_active = (state == 1)
end

local function update_should_run()
	-- TODO global maintabs
	if not con:is_connected() or maintabs.value ~= m.container then
		return false
	end
	return (m.vp_active or m.bm_active)
end

-- TODO temp test, should have a proper binding in C (?)
m.lbasedata={}
local base_fields={
	'version_major',
	'version_minor',
	'vp_max_width',
	'vp_max_height',
	'vp_buffer_width',
	'bm_max_width',
	'bm_max_height',
	'bm_buffer_width',
	'lcd_ascpect_ratio',
}
local function update_basedata(basedata)
	local t={basedata:get_i32(0,-1)}
	printf("update_basedata\n");
	if #t ~= #base_fields then
		printf("size mismatch!\n")
	end
	for i,f in ipairs(base_fields) do
		m.lbasedata[f]=t[i]
		printf("%s:%s\n",f,tostring(t[i]))
	end
end

m.lvidinfo={}
local vidinfo_fields={
	'vp_xoffset',             -- Viewport X offset in pixels (for cameras with variable image size)
	'vp_yoffset',             -- Viewport Y offset in pixels (for cameras with variable image size)
	'vp_width',               -- Actual viewport width in pixels (for cameras with variable image size)
	'vp_height',              -- Actual viewport height in pixels (for cameras with variable image size)
	'vp_buffer_start',        -- Offset in data transferred where the viewport data starts
	'vp_buffer_size',         -- Size of viewport data sent (in bytes)
	'bm_buffer_start',        -- Offset in data transferred where the bitmap data starts
	'bm_buffer_size',         -- Size of bitmap data sent (in bytes)
	'palette_type',           -- Camera palette type 
							  -- (0 = no palette', 1 = 16 x 4 byte AYUV values, 2 = 16 x 4 byte AYUV values with A = 0..3, 3 = 256 x 4 byte AYUV values with A = 0..3)
	'palette_buffer_start',   -- Offset in data transferred where the palette data starts
	'palette_buffer_size',    -- Size of palette data sent (in bytes)
}
local function update_vidinfo(livedata)
	local dirty
	for i,f in ipairs(vidinfo_fields) do
		local v = livedata:get_i32((i-1)*4)
		if v ~= m.lvidinfo[f] then
			dirty = true
		end
	end
	if dirty then
		printf('update_vidinfo: changed\n')
		for i,f in ipairs(vidinfo_fields) do
			local v = livedata:get_i32((i-1)*4)
			printf("%s:%s->%s\n",f,tostring(m.lvidinfo[f]),v)
			m.lvidinfo[f]=v
		end
		if m.lvidinfo.palette_buffer_start > 0 and m.lvidinfo.palette_buffer_size > 0 then
			printf('palette:\n')
			local c = 0
			for i=0, m.lvidinfo.palette_buffer_size-1, 4 do
				local v = livedata:get_i32(m.lvidinfo.palette_buffer_start+i)
				printf("%08x",v)
				c = c + 1
				if c == 4 then
					c=0
					printf('\n')
				else 
					printf(' ')
				end
			end
		end
	end
end


function m.init()
	if not m.live_support() then
		return false
	end
	local icnv = iup.canvas{rastersize="360x240",border="NO",expand="NO"}
	m.icnv = icnv
	m.statslabel = iup.label{size="90x80",alignment="ALEFT:ATOP"}
	m.container = iup.hbox{
		iup.frame{
			icnv,
		},
		iup.vbox{
			iup.frame{
				iup.vbox{
					iup.toggle{title="Viewfinder",action=toggle_vp},
					iup.toggle{title="UI Overlay",action=toggle_bm},
				},
				title="Stream"
			},
			iup.frame{
				m.statslabel,
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
		if maintabs.value ~= m.container then
			return;
		end
		local ccnv = self.ccnv     -- retrieve the CD canvas from the IUP attribute
		stats:start_frame()
		ccnv:Activate()
		if m.livedata then
			if not chdk.put_live_image_to_canvas(ccnv,m.livedata) then
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

	m.container_title='Live'
	m.timer = iup.timer{ 
		time = "100",
	}
	function m.timer:action_cb()
		if update_should_run() then
			stats:start()
			local what=0
			if m.vp_active then
				what = 1
			end
			if m.bm_active then
				what = what + 4
				what = what + 8 -- palette TODO shouldn't request if we don't understand type, but palette type is in dynamic data
			end
			if what == 0 then
				return
			end
			if not m.livehandler then
				m.livehandler = con:get_handler(1)
				m.livebasedata = con:call_handler(m.livebasedata,m.livehandler,0x80)
				update_basedata(m.livebasedata)
			end
			stats:start_xfer()
			m.livedata = con:call_handler(m.livedata,m.livehandler,what)
			if m.livedata then
				stats:end_xfer(m.livedata:len())
				update_vidinfo(m.livedata)
			else
				stats:stop()
			end
			icnv:action()
		else
			stats:stop()
		end
		m.statslabel.title = stats:get()
	end
end
function m.get_container()
	return m.container
end
function m.get_container_title()
	return m.container_title
end
function m.on_connect_change(lcon)
	-- reset on connect or disconnect, will get updated in timer
	m.livehandler = nil
	m.livebasedata = nil
end
-- check whether we should be running, update timer
function m.update_run_state()
	if m.timer then
		-- TODO check this is updated in the callback for gtk
		-- better to just check if control is visible
		if maintabs.value == m.container then
			m.timer.run = "YES"
			stats:start()
		else
			m.timer.run = "NO"
			stats:stop()
		end
	end
end

-- for anything that needs to be intialized when everything is started
function m.on_dlg_run()
	m.update_run_state()
end

return m
