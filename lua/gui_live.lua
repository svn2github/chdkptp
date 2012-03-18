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
local stats=require('gui_live_stats')

local m={
	vp_par = 2, -- pixel aspect ratio for viewport 1:n, n=1,2
	bm_par = 1, -- pixel aspect ratio for bitmap 1:n, n=1,2
	vp_aspect_factor = 1, -- correction factor for height values when scaling for aspect
--[[
note - these are 'private' but exposed in the module for easier debugging
container -- outermost widget
icnv -- iup canvas
vp_active -- viewport streaming selected
bm_active -- bitmap streaming selected
timer -- timer for fetching updates
statslabel -- text for stats
]]
}

local screen_aspects = {
	[0]=4/3,
	16/9,
}

function m.live_support()
	local caps = guisys.caps()
	return (caps.CD and caps.LIVEVIEW)
end

function m.get_current_frame_data()
	if m.dump_replay then
		return m.dump_replay_frame
	end
	if con.live then
		return con.live.frame
	end
end

function m.get_current_base_data()
	if m.dump_replay then
		return m.dump_replay_base
	end
	if con.live then
		return con.live.base
	end
end

local vp_toggle=iup.toggle{
	title="Viewfinder",
	action=function(self,state)
		m.vp_active = (state == 1)
	end,
}

local bm_toggle = iup.toggle{
	title="UI Overlay",
	action=function(self,state)
		m.bm_active = (state == 1)
	end,
}

local aspect_toggle = iup.toggle{
	title="Scale for A/R",
	value="ON",
}
					
local function get_fb_selection()
	local what=0
	if m.vp_active then
		what = 1
	end
	if m.bm_active then
		what = what + 4
		what = what + 8 -- palette TODO shouldn't request if we don't understand type, but palette type is in dynamic data
	end
	return what
end

--[[
update canvas size from base and frame
]]
local function update_canvas_size()
	local vp_w = m.li.vp_max_width/m.vp_par
	local vp_h
	if aspect_toggle.value == 'ON' then
		vp_h = vp_w/screen_aspects[m.li.lcd_aspect_ratio]
		m.vp_aspect_factor = vp_h/m.li.vp_max_height
	else
		m.vp_aspect_factor = 1
		vp_h = m.li.vp_max_height
	end

	local w,h = gui.parsesize(m.icnv.rastersize)
	
	local update
	if w ~= vp_w then
		update = true
	end
	if h ~= vp_h then
		update = true
	end
	if update then
		m.icnv.rastersize = vp_w.."x"..vp_h
		iup.Refresh(m.container)
		gui.resize_for_content()
	end
end

local vp_par_toggle = iup.toggle{
	title="Viewfinder 1:1",
	action=function(self,state)
		if state == 1 then
			m.vp_par = 1
		else
			m.vp_par = 2
		end
	end,
}

local bm_par_toggle = iup.toggle{
	title="Overlay 1:1",
	value="1",
	action=function(self,state)
		if state == 1 then
			m.bm_par = 1
		else
			m.bm_par = 2
		end
	end,
}
local bm_fit_toggle = iup.toggle{
	title="Overlay fit",
	value="ON",
}

local function update_should_run()
	if not m.live_con_valid then
		return false
	end
	if not con:is_connected() or m.tabs.value ~= m.container then
		return false
	end
	return (m.vp_active or m.bm_active)
end

local function update_base_data(base)
	printf('update base data:\n')
	for i,f in ipairs(chdku.live_base_fields) do
		printf("%s:%s\n",f,tostring(chdku.live_get_base_field(base,f)))
	end
end

local last_frame_fields = {}
local function update_frame_data(frame)
	local dirty
	for i,f in ipairs(chdku.live_frame_fields) do
		local v = chdku.live_get_frame_field(frame,f)
		if v ~= last_frame_fields[f] then
			dirty = true
		end
	end
	if dirty then
		printf('update_frame_data: changed\n')
		for i,f in ipairs(chdku.live_frame_fields) do
			local v = chdku.live_get_frame_field(frame,f)
			printf("%s:%s->%s\n",f,tostring(last_frame_fields[f]),v)
			last_frame_fields[f]=v
		end
		if last_frame_fields.palette_buffer_start > 0 and last_frame_fields.palette_buffer_size > 0 then
			printf('palette:\n')
			local c=0
			---[[
			local bytes = {frame:byte(last_frame_fields.palette_buffer_start+1,
										last_frame_fields.palette_buffer_start+last_frame_fields.palette_buffer_size)}
			for i,v in ipairs(bytes) do
				printf("0x%02x,",v)
				c = c + 1
				if c == 16 then
					printf('\n')
					c=0
				else
					printf(' ')
				end
			end
			--]]
			--[[
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
			--]]
		end
	end
end

-- TODO this is just to allow us to read/write a binary integer record size
local dump_recsize = lbuf.new(4)

--[[
lbuf - optional lbuf to re-use, if possible
fh - file handle
returns (possibly new) lbuf or nil on eof
]]
local function read_dump_rec(lb,fh)
	if not dump_recsize:fread(fh) then
		return
	end
	local len = dump_recsize:get_u32()
	if not lb or lb:len() ~= len then
		lb = lbuf.new(len)
	end
	if lb:fread(fh) then -- on EOF, return nil
		return lb
	end
end

local function init_dump_replay()
	m.dump_replay_file = io.open(m.dump_replay_filename,"rb")
	if not m.dump_replay_file then
		printf("failed to open dumpfile\n")
		m.dump_replay = false
		return
	end
	m.dump_replay_base = read_dump_rec(m.dump_replay_frame,m.dump_replay_file)
	update_base_data(m.dump_replay_base)
end

local function end_dump_replay()
	m.dump_replay_file:close()
	m.dump_replay_file=nil
	m.dump_replay_base=nil
	m.dump_replay_frame=nil
	stats:stop()
end

local function read_dump_frame()
	stats:start()
	stats:start_xfer()

	local data = read_dump_rec(m.dump_replay_frame,m.dump_replay_file)
	-- EOF, loop
	if not data then
		end_dump_replay()
		init_dump_replay()
		data = read_dump_rec(m.dump_replay_frame,m.dump_replay_file)
	end
	m.dump_replay_frame = data
	update_frame_data(m.dump_replay_frame)
	stats:end_xfer(m.dump_replay_frame:len())
	-- TODO
	update_canvas_size()
end

local function end_dump()
	if con.live and con.live.dump_fh then
		printf('%d bytes recorded to %s\n',tonumber(con.live.dump_size),tostring(con.live.dump_fn))
		con:live_dump_end()
	end
end

local function record_dump()
	if not m.dump_active then
		return
	end
	if not con.live.dump_fh then
		local status,err = con:live_dump_start()
		if not status then
			printf('error starting dump:%s\n',tostring(err))
			m.dump_active = false
			-- TODO update checkbox
			return
		end
		printf('recording to %s\n',con.live.dump_fn)
	end
	local status,err = con:live_dump_frame()
	if not status then
		printf('error dumping frame:%s\n',tostring(err))
		end_dump()
		m.dump_active = false
	end
end

local function toggle_dump(ih,state)
	m.dump_active = (state == 1)
	-- TODO this should be called on disconnect etc
	if not m.dumpactive then
		end_dump()
	end
end

local function toggle_play_dump(self,state)
	if state == 1 then
		local filedlg = iup.filedlg{
			dialogtype = "OPEN",
			title = "File to play", 
			filter = "*.lvdump", 
		} 
		filedlg:popup (iup.ANYWHERE, iup.ANYWHERE)

		local status = filedlg.status
		local value = filedlg.value
		if status ~= "0" then
			printf('play dump canceled\n')
			self.value = "OFF"
			return
		end
		printf('playing %s\n',tostring(value))
		m.dump_replay_filename = value
		init_dump_replay()
		m.dump_replay = true
	else
		end_dump_replay()
		m.dump_replay = false
	end
end


local function timer_action(self)
	if update_should_run() then
		stats:start()
		local what=get_fb_selection()
		if what == 0 then
			return
		end
		stats:start_xfer()
		local status,err = con:live_get_frame(what)
		if not status then
			end_dump()
			printf('error getting frame: %s\n',tostring(err))
			gui.update_connection_status() -- update connection status on error, to prevent spamming
			stats:stop()
		else
			stats:end_xfer(con.live.frame:len())
			update_frame_data(con.live.frame)
			record_dump()
			update_canvas_size()
		end
		m.icnv:action()
	elseif m.dump_replay then
		read_dump_frame()
		m.icnv:action()
	else
		stats:stop()
	end
	m.statslabel.title = stats:get()
end

local function init_timer(time)
	if not time then
		time = "100"
	end 
	if m.timer then
		iup.Destroy(m.timer)
	end
	m.timer = iup.timer{ 
		time = time,
		action_cb = function()
			-- use xpcall so we don't get a popup every frame
			local cstatus,msg = xpcall(timer_action,util.err_traceback)
			if not cstatus then
				printf('live timer update error\n%s',tostring(msg))
				-- TODO could stop live updates here, for now just spam the console
			end
		end,
	}
	m.update_run_state()
end

local function update_fps(val)
	val = tonumber(val)
	if val == 0 then
		return
	end
	val = math.floor(1000/val)
	if val ~= tonumber(m.timer.time) then
		-- reset stats
		stats:stop()
		init_timer(val)
	end
end

local function redraw_canvas(self)
	if m.tabs.value ~= m.container then
		return;
	end
	local ccnv = self.dccnv
	stats:start_frame()
	ccnv:Activate()
	ccnv:Clear()
	if m.get_current_frame_data() then
		if m.vp_active then
			m.vp_img = liveimg.get_viewport_pimg(m.vp_img,m.get_current_base_data(),m.get_current_frame_data(),m.vp_par == 2)
			if m.vp_img then
				if aspect_toggle.value == "ON" then
					m.vp_img:put_to_cd_canvas(ccnv,
						m.li.vp_xoffset/m.vp_par,
						(m.li.vp_max_height - m.li.vp_height - m.li.vp_yoffset)*m.vp_aspect_factor,
						m.vp_img:width(),
						m.vp_img:height()*m.vp_aspect_factor)
				else
					m.vp_img:put_to_cd_canvas(ccnv,
						m.li.vp_xoffset/m.vp_par,
						m.li.vp_max_height - m.li.vp_height - m.li.vp_yoffset)
				end
			end
		end
		if m.bm_active then
			m.bm_img = liveimg.get_bitmap_pimg(m.bm_img,m.get_current_base_data(),m.get_current_frame_data(),m.bm_par == 2)
			if m.bm_img then
				if bm_fit_toggle.value == "ON" then
					m.bm_img:blend_to_cd_canvas(ccnv, 0, 0, m.li.vp_max_width/m.vp_par, m.li.vp_max_height*m.vp_aspect_factor)
				else
					m.bm_img:blend_to_cd_canvas(ccnv, 0, m.li.vp_max_height - m.li.bm_max_height)
				end
			else
				print('no bm')
			end
		end
	end
	ccnv:Flush()
	stats:end_frame()
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
					vp_toggle,
					bm_toggle,
					vp_par_toggle,
					bm_par_toggle,
					bm_fit_toggle,
					aspect_toggle,
					iup.hbox{
						iup.label{title="Target FPS"},
						iup.text{
							spin="YES",
							spinmax="30",
							spinmin="1",
							spininc="1",
							value="10",
							action=function(self,c,newval)
								local v = tonumber(newval)
								local min = tonumber(self.spinmin)
								local max = tonumber(self.spinmax)
								if v and v >= min and v <= max then
									self.value = tostring(v)
									self.caretpos = string.len(tostring(v))
									update_fps(self.value)
								end
								return iup.IGNORE
							end,
							spin_cb=function(self,newval)
								update_fps(newval)
							end
						},
					},
				},
				title="Stream"
			},
			iup.tabs{
				iup.vbox{
					m.statslabel,
					tabtitle="Statistics",
				},
				iup.vbox{
					tabtitle="Debug",
					iup.toggle{title="Dump to file",action=toggle_dump},
					iup.toggle{title="Play from file",action=toggle_play_dump},
					iup.button{
						title="Quick dump",
						action=function()
							add_status(cli:execute('dumpframes'))
						end,
					},
				},
			},
		},
		margin="4x4",
		ngap="4"
	}

	function icnv:map_cb()
		-- TODO UseContextPlus seems harmless if not built with plus support
		if guisys.caps().CDPLUS then
			cd.UseContextPlus(true)
			printf("ContexIsPlus iup:%s cd:%s\n",tostring(cd.ContextIsPlus(cd.IUP)),tostring(cd.ContextIsPlus(cd.DBUFFER)))
		end
		self.ccnv = cd.CreateCanvas(cd.IUP,self)
		self.dccnv = cd.CreateCanvas(cd.DBUFFER,self.ccnv)
		if guisys.caps().CDPLUS then
			cd.UseContextPlus(false)
		end
		self.dccnv:SetBackground(cd.EncodeColor(32,32,32))
	end

	icnv.action=redraw_canvas

	function icnv:unmap_cb()
		self.dccnv:Kill()
		self.ccnv:Kill()
	end

	--[[
	function icnv:resize_cb(w,h)
		print("Resize: Width="..w.."   Height="..h)
	end
	--]]
	-- TODO - convenience meta table to access base and frame info. This should be bound to the lbuf somehow

	local live_info_meta = {
		__index=function(t,key)
			local base = m.get_current_base_data()
			local frame = m.get_current_frame_data()

			if base and chdku.live_base_map[key] then
				return chdku.live_get_base_field(base,key)
			end
			if frame and chdku.live_frame_map[key] then
				return chdku.live_get_frame_field(frame,key)
			end
		end
	}
	m.li = {}
	setmetatable(m.li,live_info_meta)

	m.container_title='Live'
end

function m.set_tabs(tabs)
	m.tabs = tabs
end
function m.get_container()
	return m.container
end
function m.get_container_title()
	return m.container_title
end
function m.on_connect_change(lcon)
	m.live_con_valid = false
	if con:is_connected() then
		local status, err = con:live_init_streaming()
		if not status then
			printf('error initializing live streaming: %s\n',tostring(err))
			return
		end
		
		if con.live.version_major ~= 1 then
			printf('incompatible live view version %d %d\n',tonumber(con.live.version_major),tonumber(con.live.version_minor))
			return
		end
		update_base_data(con.live.base)
		m.live_con_valid = true
	end
end
-- check whether we should be running, update timer
function m.update_run_state(state)
	if state == nil then
		state = (m.tabs.value == m.container)
	end
	if state then
		m.timer.run = "YES"
		stats:start()
	else
		m.timer.run = "NO"
		stats:stop()
	end
end
function m.on_tab_change(new,old)
	if not m.live_support() then
		return
	end
	if new == m.container then
		m.update_run_state(true)
	else
		m.update_run_state(false)
	end
end

-- for anything that needs to be intialized when everything is started
function m.on_dlg_run()
	init_timer()
end

return m
