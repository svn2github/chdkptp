--[[ 
gui scratchpad
based on the button example from the IUP distribution
this file is licensed under the same terms as the IUP examples
]]

local gui = {}

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

function btn_connect:action()
	local host_major, host_minor = chdk.host_api_version()
	if chdk.is_connected() then
		chdk.disconnect()
		connect_icon.active = "NO"
		btn_connect.title = "Connect"
		connect_label.title = string.format("host:%d.%d cam:-.-",host_major,host_minor)
	else
		if chdk.connect() then
			connect_icon.active = "YES"
			btn_connect.title = "Disconnect"
			local cam_major, cam_minor = chdk.camera_api_version()
			connect_label.title = string.format("host:%d.%d cam:%d.%d",host_major,host_minor,cam_major,cam_minor)
		end
	end
end

-- creates a text box
text = iup.text{ 
--	size = "700x",
	expand = "HORIZONTAL",
}

statustext = iup.text{ 
--	size = "700x256",
	multiline = "YES",
	readonly = "YES",
	expand = "YES",
}
--[[
device_menu = iup.menu
{
  {"Refresh devices"},
  {"Disconnect"},
  {},
} 
menu = iup.menu
{
  {
    "Device",
	device_menu
  },
}
--]]


--[[
status_timer = iup.timer{ 
	time = "500",
}
function status_timer:action_cb()
	if chdk.is_connected() then
		connect_icon.active = "YES"
		btn_connect.title = "Disconnect"
		connect_label.title = "connected"
	else
		connect_icon.active = "NO"
		btn_connect.title = "Connect"
		connect_label.title = "not connected"
	end
end
--]]
-- creates a button
btn_exec = iup.button{ 
	title = "Execute",
--	size = "EIGHTHxEIGHTH"
}

-- creates a button entitled Exit
btn_exit = iup.button{ title = "Exit" }

cam_btns={}
function cam_btn(name,title)
	if not title then
		title = name
	end
	cam_btns[name] = iup.button{
		title=title,
		size='31x15', -- couldn't get normalizer to work for some reason
		action=function(self)
			add_status(chdk.execlua('click("' .. name .. '")'))
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

cam_btn_frame = iup.frame{
	iup.vbox{
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
		iup.hbox{ 
			iup.button{
				title='zoom+',
				size='45x15',
				action=function(self)
					add_status(chdk.execlua('click("zoom_in")'))
				end,
			},
			iup.fill{
			},
			iup.button{
				title='zoom-',
				size='45x15',
				action=function(self)
					add_status(chdk.execlua('click("zoom_out")'))
				end,
			},
		},
		iup.button{
			title='shoot',
			size='94x15',
			action=function(self)
				add_status(chdk.execlua('shoot()'))
			end,
		}
	} ;
	title = "Camera Controls",
}
-- creates a dialog
dlg = iup.dialog{
	iup.vbox{ 
		iup.hbox{ 
			connect_icon,
			connect_label,
			iup.fill{},
			btn_connect;
		},
		iup.hbox{
			iup.vbox{
				statustext,
				text, 
			},
			iup.vbox{
				cam_btn_frame,
				iup.fill{},
				iup.hbox{
					iup.button{
						title='shutdown',
						size='45x15',
						action=function(self)
							add_status(chdk.execlua('shut_down()'))
						end,
					},
					iup.fill{},
					iup.button{
						title='reboot',
						size='45x15',
						action=function(self)
							add_status(chdk.execlua('reboot()'))
						end,
					},
				},
				iup.fill{ size="0x30"},
			}
		},
		iup.hbox{
			btn_exec,
			iup.fill{},
			btn_exit;
		};
		padding = '2x2'
	};
	title = "CHDK PTP", 
	resize = "YES", 
	menubox = "YES", 
	maxbox = "YES",
	minbox = "YES",
	menu = menu,
	size = "700x300",
	padding = '2x2'
}
--n1.normalize="BOTH"
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

function text:k_any(k)
	if k == iup.K_CR then
		btn_exec:action()
	elseif k == iup.K_UP then
		local hval = cmd_history:prev()
		if hval then
			text.value = hval
		end
	elseif k == iup.K_DOWN then
		text.value = cmd_history:next()
	end
end

function add_status(status,msg)
	if status then
		if msg then
			statustext.append = msg
		end
	else 
		statustext.append = "error: " .. msg
	end
end

function btn_exec:action()
	statustext.append = '> ' .. text.value
	cmd_history:add(text.value)
--	local status,err = chdk.execlua(text.value)
	add_status(cli:execute(text.value))
	text.value=''
end

-- callback called when the exit button is activated
function btn_exit:action()
  dlg:hide()
end

function gui:run()
--	cam_buttons_normalize.normalize="BOTH"
	device_list = chdk.list_devices()

--[[
	local devtext = ""
	for num,d in ipairs(device_list) do
		iup.Append(device_menu, iup.item{ title=num .. ": " .. d.model })
		devtext = devtext .. string.format("%d: %s %s/%s vendor %x product %x",num,d.model,d.bus,d.dev,d.vendor_id,d.product_id)
	end
	statustext.value = devtext
--]]

	-- shows dialog
	dlg:showxy( iup.CENTER, iup.CENTER)
	--status_timer.run = "YES"

	if (iup.MainLoopLevel()==0) then
	  iup.MainLoop()
	end
end

return gui;
