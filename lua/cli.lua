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

--[[
get command args of the form -a[=value] -bar[=value] .. [wordarg1] [wordarg2] [wordarg...]
--]]
local argparser = { }
cli.argparser = argparser

-- trim leading spaces
function argparser:trimspace(str)
	local s, e = string.find(str,'^[%c%s]*')
	return string.sub(str,e+1)
end
--[[
get a 'word' argument, either a sequence of non-white space characters, or a quoted string
inside " \ is treated as an escape character
return word, end position on success or false, error message
]]
function argparser:get_word(str)
	local result = ''
	local esc = false
	local qchar = false
	local pos = 1
	while pos <= string.len(str) do
		local c = string.sub(str,pos,pos)
		-- in escape, append next character unconditionally
		if esc then
			result = result .. c
			esc = false
		-- inside double quote, start escape and discard backslash
		elseif qchar == '"' and c == '\\' then
			esc = true
		-- character is the current quote char, close quote and discard
		elseif c == qchar then
			qchar = false
		-- not hit a space and not inside a quote, end
		elseif not qchar and string.match(c,"[%c%s]") then
			break
		-- hit a quote and not inside a quote, enter quote and discard
		elseif not qchar and c == '"' or c == "'" then
			qchar = c
		-- anything else, copy
		else
			result = result .. c
		end
		pos = pos + 1
	end
	if esc then
		return false,"unexpected \\"
	end
	if qchar then
		return false,"unclosed " .. qchar
	end
	return result,pos
end

function argparser:parse_words(str)
	local words={}
	str = self:trimspace(str)
	while string.len(str) > 0 do
		local w,pos = self:get_word(str)
		if not w then
			return false,pos -- pos is error string
		end
		table.insert(words,w)
		str = string.sub(str,pos)
		str = self:trimspace(str)
	end
	return words
end

--[[
parse a command string into switches and word arguments
switches are in the form -swname[=value]
word arguments are anything else
any portion of the string may be quoted with '' or ""
inside "", \ is treated as an escape
on success returns table with args as array elements and switches as named elements
on failure returns false, error
defs defines the valid switches and their default values. Can also define default values of numeric args
TODO enforce switch values, number of args, integrate with help
]]
function argparser:parse(str)
	-- default values
	local results=util.extend_table({},self.defs)
	local words,errmsg=self:parse_words(str)
	if not words then
		return false,errmsg
	end
	for i, w in ipairs(words) do
		-- look for -name
		local s,e,swname=string.find(w,'^-(%a[%w_-]*)')
		-- found a switch
		if s then		
			if type(self.defs[swname]) == 'nil' then
				return false,'unknown switch '..swname
			end
			local swval
			-- no value
			if e == string.len(w) then
				swval = true
			elseif string.sub(w,e+1,e+1) == '=' then
				-- note, may be empty string but that's ok
				swval = string.sub(w,e+2)
			else
				return false,"invalid switch value "..string.sub(w,e+1)
			end
			results[swname]=swval
		else
			table.insert(results,w)
		end
	end
	return results
end

-- a default for comands that want the raw string
argparser.nop = {
	parse =function(self,str)
		return str
	end
}

function argparser.create(defs)
	local r={ defs=defs }
	return util.mt_inherit(r,argparser)
end

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
	get_help_detail = function(self)
		local msg=self:get_help()
		if self.help_detail then
			msg = msg..self.help_detail..'\n'
		end
		return msg
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
		if not cmd.args then
			cmd.args = argparser.nop
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
	local s,e,cmd = string.find(line,'^[%c%s]*([!.#=])[%c%s]*')
	if not cmd then
		s,e,cmd = string.find(line,'^[%c%s]*([%w_]+)[%c%s]*')
	end
	if s then
		local args = string.sub(line,e+1)
		if self.names[cmd] then
			local status,msg
			args,msg = self.names[cmd].args:parse(args)
			if not args then
				return false,msg
			end
			local t0=ustime.new()
			status,msg = self.names[cmd](args)
			if cli.showtime then
				printf("time %.4f\n",ustime.diff(t0)/1000000)
			end
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

cli:add_commands{
	{
		names={'help','h'},
		arghelp='[cmd]|[-v]',
		args=argparser.create{v=false},
		help='help on [cmd] or all commands',
		help_detail=[[
 help -v gives full help on all commands, otherwise as summary is printed
]],
		func=function(self,args) 
			cmd = args[1]
			if cmd and cli.names[cmd] then
				return true, cli.names[cmd]:get_help_detail()
			end
			if cmd then
				return false, string.format("unknown command '%s'\n",cmd)
			end
			msg = ""
			for i,c in ipairs(cli.cmds) do
				if args.v then
					msg = msg .. c:get_help_detail()
				else
					msg = msg .. c:get_help()
				end
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
		help_detail=[[
 Execute lua in chdkptp. 
 The global variable con accesses the current CLI connection.
 Return values are printed in the console.
]],
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
		names={'lua','.'},
		help='execute remote lua',
		arghelp='<lua code>',
		help_detail=[[
 Execute Lua code on the camera.
 Returns immediately after the script is started.
 Return values or error messages can be retrieved with getm after the script is completed.
]],
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
		help_detail=[[
 Execute Lua code on the camera, waiting for the script to end.
 Return values or error messages are printed after the script completes.
]],
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
		help='read memory',
		args=argparser.create(), -- only word args
		arghelp='<address> [count]',
		func=function(self,args) 
			local addr = tonumber(args[1])
			local count = tonumber(args[2])
			if not addr then
				return false, "bad args"
			end
			if not count then
				count = 1
			end

			r,msg = con:getmem(addr,count)
			if not r then
				return false,msg
			end
			return true,string.format("0x%x %u\n",addr,count)..hexdump(r,addr)
		end,
	},
	{
		names={'list'},
		help='list devices',
		help_detail=[[
 Lists all recognized PTP devices in the following format
  <status><num><modelname> b=<bus> d=<device> v=<usb vendor> p=<usb pid> s=<serial number>
 status values
  * connected, current target for CLI commands (con global variable)
  + connected, not CLI target
  - not connected
 serial numbers are not available from all models
]],
		func=function() 
			local msg = ''
			local devs = chdk.list_usb_devices()
			for i,desc in ipairs(devs) do
				local lcon = chdku.connection(desc)
				local usb_info = lcon:get_usb_devinfo()
				local tempcon = false
				local status = "+"
				if not lcon:is_connected() then
					tempcon = true
					status = "-"
					lcon:connect()
				end
				local ptp_info = lcon:get_ptp_devinfo()
				if not ptp_info then
					ptp_info = { model = "<unknown>" }
				end
				if not ptp_info.serial_number then
					ptp_info.serial_number ='(none)'
				end

				if lcon._con == con._con then
					status = "*"
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
		arghelp="[-nolua] <local> [remote]",
		args=argparser.create{nolua=false},
		help_detail=[[
 <local>  file to upload
 [remote] destination
   If not specified, file is uploaded to A/
   If remote is a directory or ends in / uploaded to remote/<local file name>
 -nolua   skip lua based checks on remote
   Allows upload while running script
   Prevents detecting if remote is a directory
 Some cameras have problems with paths > 32 characters
 Dryos cameras do not handle non 8.3 filenames well
]],
		func=function(self,args) 
			local src = args[1]
			if not src then
				return false, "missing source"
			end
			if lfs.attributes(src,'mode') ~= 'file' then
				return false, 'src is not a file: '..src
			end

			local dst_dir
			local dst = args[2]
			-- no dst, use filename of source
			if dst then
				dst = fsutil.make_camera_path(dst)
				if string.find(dst,'[\\/]$') then
					-- trailing slash, append filename of source
					dst = string.sub(dst,1,-2)
					if not args.nolua then
						local st,err = con:stat(dst)
						if not st then
							return false, 'stat dest '..dst..' failed: ' .. err
						end
						if not st.is_dir then
							return false, 'not a directory: '..dst
						end
					end
					dst = fsutil.joinpath(dst,fsutil.basename(src))
				else
					if not args.nolua then
						local st = con:stat(dst)
						if st and st.is_dir then
							dst = fsutil.joinpath(dst,fsutil.basename(src))
						end
					end
				end
			else
				dst = fsutil.make_camera_path(fsutil.basename(src))
			end

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
		arghelp="[-nolua] <remote> [local]",
		args=argparser.create{nolua=false},
		help_detail=[[
 <remote> file to download
 	A/ is prepended if not present
 [local]  destination
   If not specified, the file will be downloaded to the current directory
   If a directory, the file will be downloaded into it
 -nolua   skip lua based checks on remote
   Allows download while running script
]],

		func=function(self,args) 
			local src = args[1]
			if not src then
				return false, "missing source"
			end
			local dst = args[2]
			if not dst then
				-- no dest, use final component of source path
				dst = fsutil.basename(src)
			elseif string.match(dst,'[\\/]+$') then
				-- explicit / treat it as a directory
				dst = fsutil.joinpath(dst,fsutil.basename(src))
				-- and check if it is
				local dst_dir = fsutil.dirname(dst)
				-- TODO should create it
				if lfs.attributes(dst_dir,'mode') ~= 'directory' then
					return false,'not a directory: '..dst_dir
				end
			elseif lfs.attributes(dst,'mode') == 'directory' then
				-- if target is a directory download into it
				dst = fsutil.joinpath(dst,fsutil.basename(src))
			end

			src = fsutil.make_camera_path(src)
			if not args.nolua then
				local src_st,err = con:stat(src)
				if not src_st then
					return false, 'stat source '..src..' failed: ' .. err
				end
				if not src_st.is_file then
					return false, src..' is not a file'
				end
			end
			local msg=string.format("%s->%s\n",src,dst)
			local r, msg2 = con:download(src,dst)
			if msg2 then
				msg = msg .. msg2
			end
			return r, msg
		end,
	},
	{
		names={'mdownload','mdl'},
		help='download file/directories from the camera',
		arghelp="[options] <remote, remote, ...> <target dir>",
		args=argparser.create{
			fmatch=false,
			dmatch=false,
			rmatch=false,
			nodirs=false,
			maxdepth=100,
			nomtime=false,
		},
		help_detail=[[
 <remote...> files/directories to download
 <target dir> directory to download into
 options:
   -fmatch=<pattern> download only file with path/name matching <pattern>
   -dmatch=<pattern> only create directories with path/name matching <pattern>
   -rmatch=<pattern> only recurse into directories with path/name matching <pattern>
   -nodirs           only create directories needed to download file  
   -maxdepth=n       only recurse into N levels of directory
   -nomtime			 don't preserve modification time of remote files
 note <pattern> is a lua pattern, not a filesystem glob like *.JPG
]],

		func=function(self,args) 
			if #args < 2 then
				return false,'expected source(s) and destination'
			end
			local dst=table.remove(args)
			local srcs={}
			for i,v in ipairs(args) do
				srcs[i]=fsutil.make_camera_path(v)
			end
			-- TODO some of these need translating, so can't pass direct
			local opts={
				fmatch=args.fmatch,
				dmatch=args.dmatch,
				rmatch=args.rmatch,
				dirs=not args.nodirs,
				maxdepth=tonumber(args.maxdepth),
				mtime=not args.nomtime
			}
			return con:mdownload(srcs,dst,opts)
		end,
	},
	{
		names={'mupload','mup'},
		help='upload file/directories to the camera',
		arghelp="[options] <local, local, ...> <target dir>",
		args=argparser.create{
			fmatch=false,
			dmatch=false,
			rmatch=false,
			nodirs=false,
			maxdepth=100,
			pretend=false,
			nomtime=false,
		},
		help_detail=[[
 <local...> files/directories to upload
 <target dir> directory to upload into
 options:
   -fmatch=<pattern> upload only file with path/name matching <pattern>
   -dmatch=<pattern> only create directories with path/name matching <pattern>
   -rmatch=<pattern> only recurse into directories with path/name matching <pattern>
   -nodirs           only create directories needed to upload file 
   -maxdepth=n       only recurse into N levels of directory
   -pretend          print actions instead of doing them
   -nomtime          don't preserve local modification time
 note <pattern> is a lua pattern, not a filesystem glob like *.JPG
]],

		func=function(self,args) 
			if #args < 2 then
				return false,'expected source(s) and destination'
			end
			local dst=fsutil.make_camera_path(table.remove(args))
			local srcs={}
			-- args has other stuff in it, copy array parts
			srcs={unpack(args)}
			-- TODO some of these need translating, so can't pass direct
			local opts={
				fmatch=args.fmatch,
				dmatch=args.dmatch,
				rmatch=args.rmatch,
				dirs=not args.nodirs,
				maxdepth=tonumber(args.maxdepth),
				pretend=args.pretend,
				mtime=not args.nomtime,
			}
			return con:mupload(srcs,dst,opts)
		end,
	},
	{
		names={'delete','rm'},
		help='delete file/directories from the camera',
		arghelp="[options] <target, target,...>",
		args=argparser.create{
			fmatch=false,
			dmatch=false,
			rmatch=false,
			nodirs=false,
			maxdepth=100,
			pretend=false,
			ignore_errors=false,
			skip_topdirs=false,
		},
		help_detail=[[
 <target...> files/directories to remote
 options:
   -fmatch=<pattern> upload only file with names matching <pattern>
   -dmatch=<pattern> only delete directories with names matching <pattern>
   -rmatch=<pattern> only recurse into directories with names matching <pattern>
   -nodirs           don't delete drictories recursed into, only files
   -maxdepth=n       only recurse into N levels of directory
   -pretend          print actions instead of doing them
   -ignore_errors    don't abort if delete fails, continue to next item
   -skip_topdirs     don't delete directories given in command line, only contents
 note <pattern> is a lua pattern, not a filesystem glob like *.JPG
]],

		func=function(self,args) 
			if #args < 1 then
				return false,'expected at least one target'
			end
			-- args has other stuff in it, copy array parts
			local tgts={}
			for i,v in ipairs(args) do
				tgts[i]=fsutil.make_camera_path(v)
			end
			-- TODO some of these need translating, so can't pass direct
			local opts={
				fmatch=args.fmatch,
				dmatch=args.dmatch,
				rmatch=args.rmatch,
				dirs=not args.nodirs,
				maxdepth=tonumber(args.maxdepth),
				pretend=args.pretend,
				ignore_errors=args.ignore_errors,
				skip_topdirs=args.skip_topdirs,
			}
			-- TODO use msg_handler to print as they are deleted instead of all at the end
			local results,err = con:mdelete(tgts,opts)
			if not results then
				return false,err
			end
			for i,v in ipairs(results) do
				printf("%s: ",v.file)
				if v.status then
					printf('OK')
				else
					printf('FAILED')
				end
				if v.msg then
					printf(": %s",v.msg)
				end
				printf('\n')
			end
			return true
		end,
	},
	{
		names={'mkdir'},
		help='create directories on camera',
		arghelp="<directory>",
		args=argparser.create{ },
		help_detail=[[
 <directory> directory to create. Intermediate directories will be created as needed
]],
		func=function(self,args)
			if #args ~= 1 then
				return false,'expected exactly one arg'
			end
			return con:mkdir_m(fsutil.make_camera_path(args[1]))
		end
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
		arghelp="[-b=<bus>] [-d=<dev>] [-p=<pid>] [-s=<serial>] [model] ",
		args=argparser.create{
			b='.*',
			d='.*',
			p=false,
			s=false,
		},
		
		help_detail=[[
 If no options are given, connects to the first available device.
 <pid> is the USB product ID, as a decimal or hexadecimal number.
 All other options are treated as a Lua pattern. For alphanumerics, this is a case sensitive substring match.
 If the serial or model are specified, a temporary connection will be made to each device
 If <model> includes spaces, it must be quoted.
 If multiple devices match, the first matching device will be connected.
]],
		func=function(self,args) 
			local match = {}
			local opt_map = {
				b='bus',
				d='dev',
				p='product_id',
				s='serial_number',
				[1]='model',
			}
			for k,v in pairs(opt_map) do
				-- TODO matches expect nil
				if type(args[k]) == 'string' then
					match[v] = args[k]
				end
--				printf('%s=%s\n',v,tostring(args[k]))
			end

			if con:is_connected() then
				con:disconnect()
			end

			if match.product_id and not tonumber(match.product_id) then
				return false,"expected number for product id"
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
	{
		names={'reconnect','r'},
		help='reconnect to current device',
		-- TODO depends on camera coming back on current dev/bus, not guaranteed
		-- caching model/serial could help
		func=function(self,args) 
			if con:is_connected() then
				con:disconnect()
			end
			-- appears to be needed to avoid device numbers changing (reset too soon ?)
			sys.sleep(2000)
			return con:connect()
		end,
	},
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
		args=argparser.create{l=false},
		arghelp="[-l] [path]",
		func=function(self,args) 
			local listops
			local path=args[1]
			path = fsutil.make_camera_path(path)
			if args.l then
				listopts = { stat='*' }
			else
				listopts = { stat='/' }
			end
			local list,msg = con:listdir(path,listopts)
			if type(list) == 'table' then
				local r = ''
				if args.l then
					-- alphabetic sort TODO sorting/grouping options
					chdku.sortdir_stat(list)
					for i,st in ipairs(list) do
						local name = st.name
						local size = st.size
						if st.is_dir then
							name = name..'/'
							size = '<dir>'
						else
						end
						-- print(i,name,chdku.ts_cam2pc(st.mtime))
						r = r .. string.format("%s %10s %s\n",os.date('%c',chdku.ts_cam2pc(st.mtime)),tostring(size),name)
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
		args=argparser.create(),
		help_detail=[[
 [file] is an optional file to boot.
  If not given, the normal boot process is used.
  The file may be an unencoded binary or on DryOS only, an encoded .FI2
 chdkptp attempts to reconnect to the camera after it boots.
]],
		-- TODO reconnect depends on camera coming back on current dev/bus, not guaranteed
		-- caching model/serial could help
		func=function(self,args) 
			local bootfile=args[1]
			if bootfile then
				bootfile = fsutil.make_camera_path(bootfile)
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
