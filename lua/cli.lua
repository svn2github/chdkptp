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
--]]

local cli = {
	cmds={},
	names={},
	finished = false,
}

cli.cmd_proto = {
	get_help = function(self)
		local namestr = self.names[1]
		if #self.names > 1 then
			namestr = namestr .. " (" .. self.names[2]
			for i=3,#self.names do
				namestr = namestr .. "," .. self.names[i]
			end
			namestr = namestr .. ")"
		end
		return string.format("%-12s %-12s: - %s\n",namestr,self.arghelp,self.help)
	end,
}

cli.cmd_meta = {
	__index = function(cmd, key)
		return cli.cmd_proto[key]
	end,
	__call = function(cmd,...)
		return cmd:func(...)
	end,
}

function cli:add_commands(cmds)
	for i = 1, #cmds do
		cmd = cmds[i]
		table.insert(self.cmds,cmd)
		if not cmd.arghelp then
			cmd.arghelp = ''
		end
		for _,name in ipairs(cmd.names) do
			if self.names[name] then
				warnf("duplicate command name %s\n",name)
			else
				self.names[name] = cmd
			end
		end
		setmetatable(cmd,cli.cmd_meta)
	end
end

function cli:prompt()
	if con:is_connected() then
		local script_id = con:get_script_id()
		if script_id then
			printf("con %d> ",script_id)
		else
			printf("con> ")
		end
	else
		printf("___> ")
	end
end

-- execute command given by a single line
-- returns status,message
-- message is an error message or printable value
function cli:execute(line)
	-- single char shortcuts
	local s,e,cmd = string.find(line,'^[%c%s]*([!?.#=])[%c%s]*')
	if not cmd then
		s,e,cmd = string.find(line,'^[%c%s]*([%w_]+)[%c%s]*')
	end
	if s then
		local args = string.sub(line,e+1)
		if self.names[cmd] then
			local status,msg = self.names[cmd](args)
			if not status and not msg then
				msg=cmd .. " failed"
			end
			return status,msg
		else 
			return false,string.format("unknown command '%s'\n",cmd)
		end
	elseif string.find(line,'[^%c%s]') then
		return false, string.format("bad input '%s'\n",line)
	end
	-- blank input is OK
	return true,""
end

function cli:print_status(status,msg) 
	if not status then
		errf("%s\n",tostring(msg))
	elseif msg and string.len(msg) ~= 0 then
		printf("%s",msg)
		if string.sub(msg,-1,-1) ~= '\n' then
			printf("\n")
		end
	end
end

function cli:run()
	self:prompt()
	for line in io.lines() do
		self:print_status(self:execute(line))
		if self.finished then
			break
		end
		self:prompt()
	end
end

-- add/correct A/ as needed, replace \ with /
function cli:make_camera_path(path)
	if not path then
		return 'A/'
	end
	-- fix slashes
	path = string.gsub(path,'\\','/')
	local pfx = string.sub(path,1,2)
	if pfx == 'A/' then
		return path
	end
	if pfx == 'a/' then
		return 'A' .. string.sub(path,2,-1)
	end
	return 'A/' .. path
end

-- returns <str>, <remaining arg string>
-- accepts quoted strings or space delimited
function cli:get_string_arg(arg)
	if type(arg) ~= 'string' then
		return
	end
	local path
	-- trim leading spaces
	local s, e = string.find(arg,'^[%c%s]*')
	arg = string.sub(arg,e+1)
	-- check for quotes
	s, e, str = string.find(arg,'^["]([^"]+)["]')
	if s then
		return str, string.sub(arg,e+1)
	end
	-- try without quotes
	s, e, str = string.find(arg,'^([^%c%s]+)')
	if s then
		return str, string.sub(arg,e+1)
	end
	return nil
end

--[[
t,args=cli:get_opts(args,optspec)
optspec is an array of option letters 
returns table of option values
plus arg string with recognized opts removed
TODO should unify command line processing with main.lua args
]]
function cli:get_opts(arg,optspec)
	local r={}
	for i,v in ipairs(optspec) do
		arg = string.gsub(arg,'-'..v,function() 
			r[v]=true
			return ''
		end)
	end
	return r,arg
end

-- returns num, <remaining arg string>
-- num can be signed hex or decimal
function cli:get_num_arg(arg)
	if type(arg) ~= 'string' then
		return
	end
	local hex,num
	local s, e, neg=string.find(arg,'^[%c%s]*(-?)')
	if not s then
		neg = ''
	end
	arg = string.sub(arg,e+1)
	s, e, hex=string.find(arg,'^(0[Xx])')
	if s then
		arg = string.sub(arg,e+1)
		s, e, num=string.find(arg,'^([%x]+)')
	else
		hex = ''
		s, e, num=string.find(arg,'^([%d]+)')
	end
	if s then
		return tonumber(neg..hex..num), string.sub(arg,e+1)
	end
end

cli:add_commands{
	{
		names={'help','h','?'},
		arghelp = '[command]';
		help='help on [command] or all commands',
		func=function(self,args) 
			if cli.names[args] then
				return true, cli.names[args]:get_help()
			end
			if args and args ~= "" then
				return false, string.format("unknown command '%s'\n",args)
			end
			msg = ""
			for i,c in ipairs(cli.cmds) do
				msg = msg .. c:get_help()
			end
			return true, msg
		end,
	},
	{
		names={'#'},
		help='comment',
		func=function(self,args) 
			return true
		end,
	},
	{
		names={'exec','!'},
		help='execute local lua',
		arghelp='<lua code>',
		func=function(self,args) 
			local f,r = loadstring(args)
			if f then
				r={pcall(f)};
				if not r[1] then 
					return false, string.format("call failed:%s\n",r[2])
				end
				local s
				if #r > 1 then
					s='=' .. serialize(r[2],{pretty=true,err_type=false,err_cycle=false})
					for i = 3, #r do
						s = s .. ',' .. serialize(r[i],{pretty=true,err_type=false,err_cycle=false})
					end
				end
				return true, s
			else
				return false, string.format("compile failed:%s\n",r)
			end
		end,
	},
	{
		names={'quit','q'},
		help='quit program',
		func=function() 
			cli.finished = true
			return true,"bye"
		end,
	},
	{
		names={'lua','l','.'},
		help='execute remote lua',
		arghelp='<lua code>',
		func=function(self,args) 
			return con:exec(args)
		end,
	},
	{
		names={'getm'},
		help='get messages',
		func=function(self,args) 
			local msgs=''
			local msg,err
			while true do
				msg,err=con:read_msg()
				if type(msg) ~= 'table' then 
					return false,msgs..err
				end
				if msg.type == 'none' then
					return true,msgs
				end
				msgs = msgs .. chdku.format_script_msg(msg) .. "\n"
			end
		end,
	},
	{
		names={'putm'},
		help='send message',
		arghelp='<msg string>',
		func=function(self,args) 
			return con:write_msg(args)
		end,
	},
	{
		names={'luar','='},
		help='execute remote lua, wait for result',
		arghelp='<lua code>',
		func=function(self,args) 
			local rets={}
			local msgs={}
			local status,err = con:execwait(args,{rets=rets,msgs=msgs})
			if not status then
				return false,err
			end
			local r=''
			for i=1,#msgs do
				r=r .. chdku.format_script_msg(msgs[i]) .. '\n'
			end
			for i=1,table.maxn(rets) do
				r=r .. chdku.format_script_msg(rets[i]) .. '\n'
			end
			return true,r
		end,
	},
	{
		-- TODO support display as words
		names={'rmem'},
		help=' read memory',
		arghelp='<address> [count]',
		func=function(self,args) 
			local addr
			addr,args = cli:get_num_arg(args)
			local count = cli:get_num_arg(args)
			if not addr then
				return false, "bad args"
			end
			if not count then
				count = 1
			end
			printf("0x%x %u\n",addr,count)
			r,msg = con:getmem(addr,count)
			if not r then
				return false,msg
			end
			return true,hexdump(r,addr)
		end,
	},
	{
		names={'list'},
		help='list devices',
		func=function() 
			local msg = ''
			local devs = chdk.list_usb_devices()
			for i,desc in ipairs(devs) do
				local lcon = chdku.connection(desc)
				local usb_info = lcon:get_usb_devinfo()
				local tempcon = false
				local status = "*"
				if not lcon:is_connected() then
					tempcon = true
					status = " "
					lcon:connect()
				end
				local ptp_info = lcon:get_ptp_devinfo()
				if not ptp_info then
					ptp_info = { model = "<unknown>" }
				end
				if not ptp_info.serial_number then
					ptp_info.serial_number ='(none)'
				end

				if lcon == con then
					status = status..", CLI"
				end

				msg = msg .. string.format("%s%d:%s b=%s d=%s v=0x%x p=0x%x s=%s\n",
											status, i,
											ptp_info.model,
											usb_info.bus, usb_info.dev,
											usb_info.vendor_id, usb_info.product_id,
											ptp_info.serial_number)
				if tempcon then
					lcon:disconnect()
				end
			end
			return true,msg
		end,
	},
	{
		names={'upload','u'},
		help='upload a file to the camera',
		arghelp="<local> [remote]",
		func=function(self,args) 
			local src,args = cli:get_string_arg(args)
			if not src then
				return false, "missing source"
			end
			local dst = cli:get_string_arg(args)
			-- no dst, use filename of source
			if not dst then
				dst = util.basename(src)
			-- trailing slash, append filename of source
			elseif string.find(dst,'[\\/]$') then
				dst = dst .. util.basename(src)
			end
			if not (src and dst) then
				return false, "bad/missing args ?"
			end
			dst = cli:make_camera_path(dst)
			local msg=string.format("%s->%s\n",src,dst)
			local r, msg2 = con:upload(src,dst)
			if msg2 then
				msg = msg .. msg2
			end
			return r, msg
		end,
	},
	{
		names={'download','d'},
		help='download a file from the camera',
		arghelp="<remote> [local]",
		func=function(self,args) 
			local src,args = cli:get_string_arg(args)
			if not src then
				return false, "missing source"
			end
			local dst = cli:get_string_arg(args)
			-- use final component
			if not dst then
				dst = util.basename(src)
			-- trailing slash, append filename of source
			-- TODO should use stat to figure out if target is a directory
			elseif string.find(dst,'[\\/]$') then
				dst = dst .. util.basename(src)
			end
			if not dst then
				return false, "bad/missing args ?"
			end
			src = cli:make_camera_path(src)
			local msg=string.format("%s->%s\n",src,dst)
			local r, msg2 = con:download(src,dst)
			if msg2 then
				msg = msg .. msg2
			end
			return r, msg
		end,
	},
	{
		names={'version','ver'},
		help='print API versions',
		func=function(self,args) 
			local host_ver = string.format("host:%d.%d cam:",chdk.host_api_version())
			if con:is_connected() then
				local cam_major, cam_minor = con:camera_api_version()
				if not cam_major then
					return false, host_ver .. string.format("error %s",cam_minor)
				end
				return true, host_ver .. string.format("%d.%d",cam_major,cam_minor)
			else
				return true, host_ver .. "not connected"
			end
		end,
	},
	{
		names={'connect','c'},
		help='connect to device',
		arghelp="[-b<bus>] [-d<dev>] [-p<pid>] [-s<serial>] [model] ",
		func=function(self,args) 
			local opt_map = {
				b='bus',
				d='dev',
				p='product_id',
				s='serial_number',
			}
			local match = {bus='.*',dev='.*'}
			local arg
			if con:is_connected() then
				con:disconnect()
			end
			arg,args = cli:get_string_arg(args)
--			printf("arg %s\n",tostring(arg))
			while arg do
				-- no -, assume model name
				if string.sub(arg,1,1) ~= '-' then
					match.model = arg
				else
					local s,e,opt,val = string.find(arg,'^-([bdps])[:=]?(.*)')
					if s then
--						printf("opt %s=%s\n",opt,val)
						match[opt_map[opt]] = val
					else
						return false,"invalid option "..arg
					end
				end
				arg,args = cli:get_string_arg(args)
--				printf("arg %s\n",tostring(arg))
			end
			local devices = chdk.list_usb_devices()
			local lcon
			for i, devinfo in ipairs(devices) do
				lcon = nil
				if chdku.match_device(devinfo,match) then
					lcon = chdku.connection(devinfo)
					-- if we are looking for model or serial, need to connect to the dev to check
					if match.model or match.serial_number then
						local tempcon = false
--						printf('model check %s %s\n',tostring(match.model),tostring(match.serial_number))
						if not lcon:is_connected() then
							lcon:connect()
							tempcon = true
						end
						if not lcon:match_ptp_info(match) then
							if tempcon then
								lcon:disconnect()
							end
							lcon = nil
						end
					end
					if lcon then
						break
					end
				end
			end
			if lcon then
				con = lcon
				if con:is_connected() then
					return true
				end
				return con:connect()
			end
			return false,"no matching devices found"
		end,
	},
	--[[
	-- TODO this isn't useful - on win device name can change on reset ?
	{
		names={'reconnect','r'},
		help='reconnect to current device',
		func=function(self,args) 
			if con:is_connected() then
				con:disconnect()
			end
			return con:connect()
		end,
	},
	]]
	{
		names={'disconnect','dis'},
		help='disconnect from device',
		func=function(self,args) 
			return con:disconnect()
		end,
	},
	{
		names={'ls'},
		help='list files/directories on camera',
		arghelp="[-l] [path]",
		func=function(self,args) 
			local opts,listops
			opts,args=cli:get_opts(args,{'l'})
			local path=cli:get_string_arg(args)
			path = cli:make_camera_path(path)
			if opts.l then
				listopts = { stat='*' }
			else
				listopts = { stat='/' }
			end
			local list,msg = con:listdir(path,listopts)
			if type(list) == 'table' then
				local r = ''
				if opts.l then
					-- alphabetic sort TODO sorting/grouping options
					chdku.sortdir_stat(list)
					for i,st in ipairs(list) do
						if st.is_dir then
							r = r .. string.format("%s/\n",st.name)
						else
							r = r .. string.format("%-13s %10d\n",st.name,st.size)
						end
					end
				else
					table.sort(list)
					for i,name in ipairs(list) do
						r = r .. name .. '\n'
					end
				end

				return true,r
			end
			return false,msg
		end,
	},
	{
		names={'reboot'},
		help='reboot the camera',
		arghelp="[file]",
		func=function(self,args) 
			local bootfile=cli:get_string_arg(args)
			if bootfile then
				bootfile = cli:make_camera_path(bootfile)
				bootfile = string.format("'%s'",bootfile)
			else
				bootfile = ''
			end
			-- sleep and disconnect to avoid later connection problems on some cameras
			-- clobber because we don't care about memory leaks
			local status,err=con:exec('sleep(1000);reboot('..bootfile..')',{clobber=true})
			if not status then
				return false,err
			end
			con:disconnect()
			-- sleep locally to avoid clobbering the reboot, and allow time for the camera to come up before trying to connect
			sys.sleep(3000)

			return con:connect()
		end,
	},
};

return cli;
