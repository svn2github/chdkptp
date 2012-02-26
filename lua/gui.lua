--[[ 
gui scratchpad
based on the button example from the IUP distribution
this file is licensed under the same terms as the IUP examples
]]
local gui = {}
local live = require('gui_live')
local tree = require('gui_tree')
-- make global for easier testing
gui.live = live
gui.tree = tree
-- defines released button image
img_release = iup.image {
      {1,1,1,1,1,1,1,1,1,1,1,1,1,1,1,1},
      {1,1,1,1,1,1,1,1,1,1,1,1,1,1,1,2},
      {1,1,3,3,3,3,3,3,3,3,3,3,3,3,2,2},
      {1,1,3,3,3,3,3,3,3,3,3,3,3,3,2,2},
      {1,1,3,3,3,3,3,3,3,3,3,3,3,3,2,2},
      {1,1,3,3,3,3,3,3,3,3,3,3,3,3,2,2},
      {1,1,3,3,3,3,3,3,3,3,3,3,3,3,2,2},
      {1,1,3,3,3,3,3,3,4,4,3,3,3,3,2,2},
      {1,1,3,3,3,3,3,4,4,4,4,3,3,3,2,2},
      {1,1,3,3,3,3,3,4,4,4,4,3,3,3,2,2},
      {1,1,3,3,3,3,3,3,4,4,3,3,3,3,2,2},
      {1,1,3,3,3,3,3,3,3,3,3,3,3,3,2,2},
      {1,1,3,3,3,3,3,3,3,3,3,3,3,3,2,2},
      {1,1,3,3,3,3,3,3,3,3,3,3,3,3,2,2},
      {1,1,3,3,3,3,3,3,3,3,3,3,3,3,2,2},
      {1,2,2,2,2,2,2,2,2,2,2,2,2,2,2,2},
      {2,2,2,2,2,2,2,2,2,2,2,2,2,2,2,2};
      colors = { "215 215 215", "40 40 40", "30 50 210", "240 0 0" }
}

-- defines pressed button image
img_press = iup.image {
      {1,1,1,1,1,1,1,1,1,1,1,1,1,1,1,1},
      {1,1,1,1,1,1,1,1,1,1,1,1,1,1,1,2},
      {1,1,3,3,3,3,3,3,3,3,3,3,3,3,2,2},
      {1,1,3,3,3,3,3,3,3,3,3,3,3,3,2,2},
      {1,1,3,3,3,3,3,3,3,3,3,3,3,3,2,2},
      {1,1,3,3,3,3,3,3,3,3,3,3,3,3,2,2},
      {1,1,3,3,3,3,3,4,4,3,3,3,3,3,2,2},
      {1,1,3,3,3,3,4,4,4,4,3,3,3,3,2,2},
      {1,1,3,3,3,3,4,4,4,4,3,3,3,3,2,2},
      {1,1,3,3,3,3,3,4,4,3,3,3,3,3,2,2},
      {1,1,3,3,3,3,3,3,3,3,3,3,3,3,2,2},
      {1,1,3,3,3,3,3,3,3,3,3,3,3,3,2,2},
      {1,1,3,3,3,3,3,3,3,3,3,3,3,3,2,2},
      {1,1,3,3,3,3,3,3,3,3,3,3,3,3,2,2},
      {1,1,3,3,3,3,3,3,3,3,3,3,3,3,2,2},
      {1,2,2,2,2,2,2,2,2,2,2,2,2,2,2,2},
      {2,2,2,2,2,2,2,2,2,2,2,2,2,2,2,2};
      colors = { "40 40 40", "215 215 215", "0 20 180", "210 0 0" }
}

-- defines deactivated button image
img_inactive = iup.image {
      {1,1,1,1,1,1,1,1,1,1,1,1,1,1,1,1},
      {1,1,1,1,1,1,1,1,1,1,1,1,1,1,1,2},
      {1,1,3,3,3,3,3,3,3,3,3,3,3,3,2,2},
      {1,1,3,3,3,3,3,3,3,3,3,3,3,3,2,2},
      {1,1,3,3,3,3,3,3,3,3,3,3,3,3,2,2},
      {1,1,3,3,3,3,3,3,3,3,3,3,3,3,2,2},
      {1,1,3,3,3,3,3,3,3,3,3,3,3,3,2,2},
      {1,1,3,3,3,3,3,3,4,4,3,3,3,3,2,2},
      {1,1,3,3,3,3,3,4,4,4,4,3,3,3,2,2},
      {1,1,3,3,3,3,3,4,4,4,4,3,3,3,2,2},
      {1,1,3,3,3,3,3,3,4,4,3,3,3,3,2,2},
      {1,1,3,3,3,3,3,3,3,3,3,3,3,3,2,2},
      {1,1,3,3,3,3,3,3,3,3,3,3,3,3,2,2},
      {1,1,3,3,3,3,3,3,3,3,3,3,3,3,2,2},
      {1,1,3,3,3,3,3,3,3,3,3,3,3,3,2,2},
      {1,2,2,2,2,2,2,2,2,2,2,2,2,2,2,2},
      {2,2,2,2,2,2,2,2,2,2,2,2,2,2,2,2};
      colors = { "215 215 215", "40 40 40", "100 100 100", "200 200 200" }
}

connect_icon = iup.label{
	image = img_release,
	iminactive = img_inactive,
	active = "NO",
}

connect_label = iup.label{
	title = string.format("host:%d.%d cam:-.- ",chdk.host_api_version()),
}

-- creates a button
btn_connect = iup.button{ 
	title = "Connect",
	size = "48x"
}

-- parse a NxM attribute and return as numbers
function gui.parsesize(size)
	local w,h=string.match(size,'(%d+)x(%d+)')
	return tonumber(w),tonumber(h)
end

function gui.update_connection_status()
	local host_major, host_minor = chdk.host_api_version()
	if con:is_connected() then
		connect_icon.active = "YES"
		btn_connect.title = "Disconnect"
		connect_label.title = string.format("host:%d.%d cam:%d.%d",host_major,host_minor,con.apiver.major,con.apiver.minor)
	else
		connect_icon.active = "NO"
		btn_connect.title = "Connect"
		connect_label.title = string.format("host:%d.%d cam:-.-",host_major,host_minor)
	end
	live.on_connect_change(con)
end

function btn_connect:action()
	if con:is_connected() then
		con:disconnect()
	else
		-- TODO temp, connect to the "first" device, need to add cam selection
		-- mostly copied from cli connect
		local devs = chdk.list_usb_devices()
		if #devs > 0 then
			con = chdku.connection(devs[1])
			add_status(con:connect())
		else
			add_status(false,"no devices available")
		end
	end
	gui.update_connection_status()
end

-- console input
inputtext = iup.text{ 
	expand = "HORIZONTAL",
}

-- console output
statustext = iup.text{ 
	multiline = "YES",
	readonly = "YES",
	expand = "YES",
	formatting = "YES",
	scrollbar = "VERTICAL",
	autohide = "YES",
	visiblelines="2",
	appendnewline="NO",
}


function statusprint(...)
	local args={...}
	local s = tostring(args[1])
	for i=2,#args do
		s=s .. ' ' .. tostring(args[i])
	end
	statustext.append = s
	statusupdatepos()
end

-- TODO it would be better to only auto update if not manually scrolled up
-- doesn't work all the time
function statusupdatepos()
	local pos = statustext.count -- iup 3.5 only
	if not pos then
		pos = string.len(statustext.value)
	end
	local l = iup.TextConvertPosToLinCol(statustext,pos)
	local h = math.floor(tonumber(string.match(statustext.size,'%d+x(%d+)'))/8)
	--print(l,h)
	if l > h then
		l=l-h + 1
		--print('scrollto',l)
		statustext.scrollto = string.format('%d:1',l)
	end
end

-- creates a button
btn_exec = iup.button{ 
	title = "Execute",
}

cam_btns={}
function cam_btn(name,title)
	if not title then
		title = name
	end
	cam_btns[name] = iup.button{
		title=title,
		size='31x15', -- couldn't get normalizer to work for some reason
		action=function(self)
			add_status(con:execlua('click("' .. name .. '")'))
		end,
	}
end
cam_btn("erase")
cam_btn("up")
cam_btn("print")
cam_btn("left")
cam_btn("set")
cam_btn("right")
cam_btn("display","disp")
cam_btn("down")
cam_btn("menu")

cam_btn_frame = iup.vbox{
	iup.hbox{ 
		cam_btns.erase,
		cam_btns.up,
		cam_btns.print,
	},
	iup.hbox{ 
		cam_btns.left,
		cam_btns.set,
		cam_btns.right,
	},
	iup.hbox{ 
		cam_btns.display,
		cam_btns.down,
		cam_btns.menu,
	},
	iup.label{separator="HORIZONTAL"},
	iup.hbox{ 
		iup.button{
			title='zoom+',
			size='45x15',
			action=function(self)
				add_status(con:execlua('click("zoom_in")'))
			end,
		},
		iup.fill{
		},
		iup.button{
			title='zoom-',
			size='45x15',
			action=function(self)
				add_status(con:execlua('click("zoom_out")'))
			end,
		},
		expand="HORIZONTAL",
	},
	iup.label{separator="HORIZONTAL"},
	iup.button{
		title='shoot',
		size='94x15',
		action=function(self)
			add_status(con:execlua('shoot()'))
		end,
	},
	iup.label{separator="HORIZONTAL"},
	iup.hbox{
		iup.button{
			title='rec',
			size='45x15',
			action=function(self)
				add_status(con:execlua('switch_mode_usb(1)'))
			end,
		},
		iup.fill{},
		iup.button{
			title='play',
			size='45x15',
			action=function(self)
				add_status(con:execlua('switch_mode_usb(0)'))
			end,
		},
		expand="HORIZONTAL",
	},
	iup.fill{},
	iup.hbox{
		iup.button{
			title='shutdown',
			size='45x15',
			action=function(self)
				add_status(con:execlua('shut_down()'))
			end,
		},
		iup.fill{},
		iup.button{
			title='reboot',
			size='45x15',
			action=function(self)
				add_status(con:execlua('reboot()'))
			end,
		},
		expand="HORIZONTAL",
	},
	expand="VERTICAL",
	nmargin="4x4",
	ngap="2"
}

tree.init()
live.init()

contab = iup.vbox{
	statustext,
}
maintabs = iup.tabs{
	contab,
	tree.get_container(),
	live.get_container(),
	tabtitle0='Console',
	tabtitle1=tree.get_container_title(),
	tabtitle2=live.get_container_title(),
}

live.set_tabs(maintabs)

inputbox = iup.hbox{
	inputtext, 
	btn_exec,
}
leftbox = iup.vbox{
	maintabs,
--				statustext,
	inputbox,
	nmargin="4x4",
	ngap="2"
}

--[[
TODO this is lame, move console output for min-console or full tab
]]
function maintabs:tabchange_cb(new,old)
	--print('tab change')
	if new == contab then
		iup.SaveClassAttributes(statustext)
		iup.Detach(statustext)
		iup.Insert(contab,nil,statustext)
		iup.Map(statustext)
		iup.Refresh(dlg)
		statusupdatepos()
	elseif old == contab then
		iup.SaveClassAttributes(statustext)
		iup.Detach(statustext)
		iup.Insert(leftbox,inputbox,statustext)
		iup.Map(statustext)
		iup.Refresh(dlg)
		statusupdatepos()
	end
	gui.resize_for_content() -- this may trigger a second refresh, but needed
	live.on_tab_change(new,old)
end
-- creates a dialog
dlg = iup.dialog{
	iup.vbox{ 
		iup.hbox{ 
			connect_icon,
			connect_label,
			iup.fill{},
			btn_connect;
			nmargin="4x2",
		},
		iup.label{separator="HORIZONTAL"},
		iup.hbox{
			leftbox,
			iup.vbox{
			},
			cam_btn_frame,
		},
	};
	title = "CHDK PTP", 
	resize = "YES", 
	menubox = "YES", 
	maxbox = "YES",
	minbox = "YES",
	menu = menu,
	rastersize = "700x460",
	padding = '2x2'
}
function gui.content_size()
	return gui.parsesize(dlg[1].rastersize)
end
--[[
size the dialog large enough for the content
]]
function gui.resize_for_content(refresh)
	local cw,ch= gui.content_size()
	local w,h=gui.parsesize(dlg.clientsize)
	--[[
	print("resize_for_content dlg:"..w.."x"..h)
	print("resize_for_content content:"..cw.."x"..ch)
	--]]
	if not (w and cw and h and ch) then
		return
	end
	local update
	if w < cw then
		w = cw
		update = true
	end
	if h < ch then
		h = ch
		update = true
	end
	if update then
		dlg.clientsize = w..'x'..h
		iup.Refresh(dlg)
	end
end

function dlg:resize_cb(w,h)
	--[[
	local cw,ch=gui.content_size()
	print("dlg Resize: Width="..w.."   Height="..h)
	print("dlg content: Width="..cw.."   Height="..ch)
	--]]
	self.clientsize=w.."x"..h
end

cmd_history = {
	pos = 1,
	prev = function(self) 
		if self[self.pos - 1]  then
			self.pos = self.pos - 1
			return self[self.pos]
--[[
		elseif #self > 1 then
			self.pos = #self
			return self[self.pos]
--]]
		end
	end,
	next = function(self) 
		if self[self.pos + 1]  then
			self.pos = self.pos + 1
			return self[self.pos]
		end
	end,
	add = function(self,value) 
		table.insert(self,value)
		self.pos = #self+1
	end
}

function inputtext:k_any(k)
	if k == iup.K_CR then
		btn_exec:action()
	elseif k == iup.K_UP then
		local hval = cmd_history:prev()
		if hval then
			inputtext.value = hval
		end
	elseif k == iup.K_DOWN then
		inputtext.value = cmd_history:next()
	end
end

--[[
mock file object that sends to gui console
]]
status_out = {
	write=function(self,...)
		statusprint(...)
	end
}

function add_status(status,msg)
	if status then
		if msg then
			printf(msg)
		end
	else 
		printf("error: %s",tostring(msg))
	end
end

function btn_exec:action()
	printf('> %s\n',inputtext.value)
	cmd_history:add(inputtext.value)
	add_status(cli:execute(inputtext.value))
	inputtext.value=''
	-- handle cli exit
	if cli.finished then
		dlg:hide()
	end
end

function gui:run()
	-- shows dialog
	dlg:showxy( iup.CENTER, iup.CENTER)

	tree.on_dlg_run()
	util.util_stdout = status_out
	util.util_stderr = status_out
	do_connect_option()
	gui.update_connection_status()
	do_execute_option()
	live.on_dlg_run()
	gui.resize_for_content()

	if (iup.MainLoopLevel()==0) then
	  iup.MainLoop()
	end
end

return gui
