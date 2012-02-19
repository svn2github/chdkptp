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
	return (cd 
			and type(cd.CreateCanvas) == 'function'
			and type(chdk.put_live_image_to_canvas ) == 'function')
end
-- TODO
local stats={
}
local container -- outermost widget
local livedata -- latest data fetched from cam
local icnv -- iup canvas
local vp_active -- viewport streaming selected
local bm_active -- bitmap streaming selected
local timer -- timer for fetching updates
local function toggle_vp(ih,state)
	vp_active = (state == 1)
end

local function toggle_bm(ih,state)
	bm_active = (state == 1)
end

function m.init()
	if not m.live_support() then
		return false
	end
	icnv = iup.canvas{rastersize="362x242",expand="NO"}
	container = iup.hbox{
		icnv,
		iup.frame{
			iup.vbox{
				iup.toggle{title="Viewfinder",action=toggle_vp},
				iup.toggle{title="UI Overlay",action=toggle_bm},
			},
			title="Stream"
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
		--stats.draw_start = ustime.new()
		ccnv:Activate()
		if livedata then
			if not chdk.put_live_image_to_canvas(ccnv,livedata) then
				print('put fail')
			end
		else
			ccnv:Clear()
		end
		--stats.draw_end = ustime.new()
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
		if con:is_connected() and maintabs.value == container then
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
--			stats.fetch_start = ustime.new()
			livedata = con:call_handler(con.live_handler,what)
--[[
			stats.fetch_end = ustime.new()
			stats.count = stats.count+1
			stats.bytes = livedata:len()
			stats.bytes_total = stats.bytes_total + data:len()
]]
			icnv:action()
		end
	end
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
		else
			timer.run = "NO"
		end
	end
end

return m
