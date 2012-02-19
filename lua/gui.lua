--[[ 
gui scratchpad
based on the button example from the IUP distribution
this file is licensed under the same terms as the IUP examples
]]
local gui = {}
local live = require('gui_live')
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

gui.has_cd = (cd and type(cd.CreateCanvas) == 'function')

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

function update_connection_status()
	local host_major, host_minor = chdk.host_api_version()
	if con:is_connected() then
		connect_icon.active = "YES"
		btn_connect.title = "Disconnect"
		local cam_major, cam_minor = con:camera_api_version()
		connect_label.title = string.format("host:%d.%d cam:%d.%d",host_major,host_minor,cam_major,cam_minor)
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
	update_connection_status()
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

camfiletree=iup.tree{}
camfiletree.name="Camera"
camfiletree.state="collapsed"
camfiletree.addexpanded="NO"
-- camfiletree.addroot="YES"

function camfiletree:get_data(id)
	return iup.TreeGetUserId(self,id)
end

-- TODO we could keep a map somewhere
function camfiletree:get_id_from_path(fullpath)
	local id = 0
	while true do
		local data = self:get_data(id)
		if data then
			if not data.dummy then
				if data:fullpath() == fullpath then
					return id
				end
			end
		else
			return
		end
		id = id + 1
	end
end

-- TODO
filetreedata_getfullpath = function(self)
	-- root is special special, we don't want to add slashes
	if self.name == 'A/' then
		return 'A/'
	end
	if self.path == 'A/' then
		return self.path .. self.name
	end
	return self.path .. '/' .. self.name
end

function camfiletree:set_data(id,data)
	data.fullpath = filetreedata_getfullpath
	iup.TreeSetUserId(self,id,data)
end

function do_download_dialog(data)
	local remotepath = data:fullpath()
	local filedlg = iup.filedlg{
		dialogtype = "SAVE",
		title = "Download "..remotepath, 
		filter = "*.*", 
		filterinfo = "all files",
		file = fsutil.basename(remotepath)
	} 

-- Shows file dialog in the center of the screen
	statusprint('download dialog ' .. remotepath)
	filedlg:popup (iup.ANYWHERE, iup.ANYWHERE)

-- Gets file dialog status
	local status = filedlg.status

-- new or overwrite (windows native dialog already prompts for overwrite)
	if status == "1" or status == "0" then 
		statusprint("d "..remotepath.."->"..filedlg.value)
		-- can't use mdownload here because local name might be different than remote basename
		add_status(con:download(remotepath,filedlg.value))
		add_status(lfs.touch(filedlg.value,chdku.ts_cam2pc(data.stat.mtime)))
-- canceled
--	elseif status == "-1" then 
	end
end

function do_dir_download_dialog(data)
	local remotepath = data:fullpath()
	local filedlg = iup.filedlg{
		dialogtype = "DIR",
		title = "Download contents of "..remotepath, 
	} 

-- Shows dialog in the center of the screen
	statusprint('dir download dialog ' .. remotepath)
	filedlg:popup (iup.ANYWHERE, iup.ANYWHERE)

-- Gets dialog status
	local status = filedlg.status

	if status == "0" then 
		statusprint("d "..remotepath.."->"..filedlg.value)
		add_status(con:mdownload({remotepath},filedlg.value))
	end
end

function do_dir_upload_dialog(data)
	local remotepath = data:fullpath()
	local filedlg = iup.filedlg{
		dialogtype = "DIR",
		title = "Upload contents to "..remotepath, 
	} 
-- Shows dialog in the center of the screen
	statusprint('dir upload dialog ' .. remotepath)
	filedlg:popup (iup.ANYWHERE, iup.ANYWHERE)

-- Gets dialog status
	local status = filedlg.status

	if status == "0" then 
		statusprint("d "..remotepath.."->"..filedlg.value)
		add_status(con:mupload({filedlg.value},remotepath))
		camfiletree:refresh_tree_by_path(remotepath)
	end
end


function do_upload_dialog(remotepath)
	local filedlg = iup.filedlg{
		dialogtype = "OPEN",
		title = "Upload to: "..remotepath, 
		filter = "*.*", 
		filterinfo = "all files",
		multiplefiles = "yes",
	} 
	statusprint('upload dialog ' .. remotepath)
	filedlg:popup (iup.ANYWHERE, iup.ANYWHERE)

-- Gets file dialog status
	local status = filedlg.status
	local value = filedlg.value
-- new or overwrite (windows native dialog already prompts for overwrite
	if status ~= "0" then
		statusprint('upload canceled status ' .. status)
		return
	end
	statusprint('upload value ' .. tostring(value))
	local paths = {}
	local e=1
	local dir
	while true do
		local s,sub
		s,e,sub=string.find(value,'([^|]+)|',e)
		if s then
			if not dir then
				dir = sub
			else
				table.insert(paths,fsutil.joinpath(dir,sub))
			end
		else
			break
		end
	end
	-- single select
	if #paths == 0 then
		table.insert(paths,value)
	end
	-- note native windows dialog does not allow multi-select to include directories.
	-- If it did, each to-level directory contents would get dumped into the target dir
	-- should add an option to mupload to include create top level dirs
	-- TODO test gtk/linux
	add_status(con:mupload(paths,remotepath))
	camfiletree:refresh_tree_by_path(remotepath)
end

function do_mkdir_dialog(data)
	local remotepath = data:fullpath()
	local dirname = iup.Scanf("Create directory\n"..remotepath.."%64.11%s\n",'');
	if dirname then
		printf('mkdir: %s',dirname)
		add_status(con:mkdir_m(fsutil.joinpath_cam(remotepath,dirname)))
		camfiletree:refresh_tree_by_path(remotepath)
	else
		printf('mkdir canceled')
	end
end

function do_delete_dialog(data)
	local msg
	local fullpath = data:fullpath()
	if data.stat.is_dir then
		msg = 'delete directory ' .. fullpath .. ' and all contents ?'
	else
		msg = 'delete ' .. fullpath .. ' ?'
	end
	if iup.Alarm('Confirm delete',msg,'OK','Cancel') == 1 then
		add_status(con:mdelete({fullpath}))
		camfiletree:refresh_tree_by_path(fsutil.dirname_cam(fullpath))
	end
end

function camfiletree:refresh_tree_by_id(id)
	if not id then
		printf('refresh_tree_by_id: nil id')
		return
	end
	local oldstate=self['state'..id]
	local data=self:get_data(id)
	statusprint('old state', oldstate)
	self:populate_branch(id,data:fullpath())
	if oldstate and oldstate ~= self['state'..id] then
		self['state'..id]=oldstate
	end
end

function camfiletree:refresh_tree_by_path(path)
	printf('refresh_tree_by_path: %s',tostring(path))
	local id = self:get_id_from_path(path)
	if id then
		printf('refresh_tree_by_path: found %s',tostring(id))
		self:refresh_tree_by_id(id)
	else
		printf('refresh_tree_by_path: failed to find %s',tostring(path))
	end
end
--[[
function camfiletree:dropfiles_cb(filename,num,x,y)
	-- note id -1 > not on any specific item
	local id = iup.ConvertXYToPos(self,x,y)
	printf('dropfiles_cb: %s %d %d %d %d\n',filename,num,x,y,id)
end
]]

function camfiletree:rightclick_cb(id)
	local data=self:get_data(id)
	if not data then
		return
	end
	if data.fullpath then
		statusprint('tree right click: fullpath ' .. data:fullpath())
	end
	if data.stat.is_dir then
		iup.menu{
			iup.item{
				title='Refresh',
				action=function()
					self:refresh_tree_by_id(id)
				end,
			},
			-- the default file selector doesn't let you multi-select with directories
			iup.item{
				title='Upload files...',
				action=function()
					do_upload_dialog(data:fullpath())
				end,
			},
			iup.item{
				title='Upload directory contents...',
				action=function()
					do_dir_upload_dialog(data)
				end,
			},
			iup.item{
				title='Download contents...',
				action=function()
					do_dir_download_dialog(data)
				end,
			},
			iup.item{
				title='Create directory...',
				action=function()
					do_mkdir_dialog(data)
				end,
			},
			iup.item{
				title='Delete...',
				action=function()
					do_delete_dialog(data)
				end,
			},
		}:popup(iup.MOUSEPOS,iup.MOUSEPOS)
	else
		iup.menu{
			iup.item{
				title='Download...',
				action=function()
					do_download_dialog(data)
				end,
			},
			iup.item{
				title='Delete...',
				action=function()
					do_delete_dialog(data)
				end,
			},
		}:popup(iup.MOUSEPOS,iup.MOUSEPOS)
	end
end

function camfiletree:populate_branch(id,path)
	self['delnode'..id] = "CHILDREN"
	statusprint('populate branch '..id..' '..path)
	if id == 0 then
		camfiletree.state="collapsed"
	end		
	local list,msg = con:listdir(path,{stat='*'})
	if type(list) == 'table' then
		chdku.sortdir_stat(list)
		for i=#list, 1, -1 do
			st = list[i]
			if st.is_dir then
				self['addbranch'..id]=st.name
				self:set_data(self.lastaddnode,{name=st.name,stat=st,path=path})
				-- dummy, otherwise tree nodes not expandable
				-- TODO would be better to only add if dir is not empty
				self['addleaf'..self.lastaddnode] = 'dummy'
				self:set_data(self.lastaddnode,{dummy=true})
			else
				self['addleaf'..id]=st.name
				self:set_data(self.lastaddnode,{name=st.name,stat=st,path=path})
			end
		end
	end
end

function camfiletree:branchopen_cb(id)
	statusprint('branchopen_cb ' .. id)
	if not con:is_connected() then
		statusprint('branchopen_cb not connected')
		return iup.IGNORE
	end
	local path
	if id == 0 then
		path = 'A/'
		-- chdku.exec('return os.stat("A/")',{libs={'serialize','serialize_msgs'}})
		-- TODO
		-- self:set_data(0,{name='A/',stat={is_dir=true},path=''})
		camfiletree:set_data(0,{name='A/',stat={is_dir=true},path=''})
	end
	local data = self:get_data(id)
	self:populate_branch(id,data:fullpath())
end

-- empty the tree, and add dummy we always re-populate on expand anyway
-- this crashes in gtk
--[[
function camfiletree:branchclose_cb(id)
	self['delnode'..id] = "CHILDREN"
	self['addleaf'..id] = 'dummy'
end
]]

live.init()

contab = iup.vbox{
	statustext,
}
maintabs = iup.tabs{
	contab,
	camfiletree,
	live.get_container(),
	tabtitle0='Console',
	tabtitle1='Files',
	tabtitle2=live.get_container_title(),
}

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
	live.update_run_state()
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
function dlg:resize_cb(w,h)
	--print("dlg Resize: Width="..w.."   Height="..h)
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
--	cam_buttons_normalize.normalize="BOTH"
--[[
	device_list = chdk.list_devices()
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
	camfiletree.addbranch0="dummy"
	camfiletree:set_data(0,{name='A/',stat={is_dir=true},path=''})

	util.util_stdout = status_out
	util.util_stderr = status_out
	do_connect_option()
	update_connection_status()
	do_execute_option()
	live.update_run_state()

	if (iup.MainLoopLevel()==0) then
	  iup.MainLoop()
	end
end

return gui;
