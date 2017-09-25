--[[
  Copyright (C) 2017 <reyalp (at) gmail dot com>
  This program is free software; you can redistribute it and/or modify
  it under the terms of the GNU General Public License version 2 as
  published by the Free Software Foundation.

  This program is distributed in the hope that it will be useful,
  but WITHOUT ANY WARRANTY; without even the implied warranty of
  MERCHANTABILITY or FITNESS FOR A PARTICULAR PURPOSE.  See the
  GNU General Public License for more details.

  You should have received a copy of the GNU General Public License
  along with this program.  If not, see <http://www.gnu.org/licenses/>.
]]
--[[
chdkptp code to support https://chdk.setepontos.com/index.php?topic=11029.0
requires patched CHDK
!require'extras/camcon'.init_cli()
mcamcon drysh
]]
m={}
m.init_cli = function()
	cli:add_commands{
	{
		names={'mcamcon'},
		help='interact with camera console',
		arghelp="[eventproc [-n]] [-r]",
		args=cli.argparser.create{
			n=false,
			r=false
		},
		help_detail=[[
REQUIRES special build http://chdk.setepontos.com/index.php?topic=11029.msg108239#msg108239
 enter interactive mode that sends typed text to camera console and returns output
 text prefixed with % is sent as message shell commands, %quit to end
 eventproc
	eventproc to run in task, e.g. drysh or other interactive function
 options:
   -n don't end camcon when task completes
   -r assume camera script is already running
]],

		func=function(self,args) 
			local opts={
				task = args[1],
				autoexit = not args.n,
			}
			local code=[[
opts=
]]..serialize(opts)..
[[
msg_shell.read_msg_timeout=20
function send_output()
	local r={}
	while true do
		local s=cam_con_gets()
		if not s then
			sleep(50)
			s=cam_con_gets()
			if not s then
				break
			end
		end
		table.insert(r,s)
	end
	if #r > 0 then
		write_usb_msg(table.concat(r))
	end
end
msg_shell.cmds.quit=function(msg)
	write_usb_msg('ending msg_shell')
	msg_shell.done=true
end

msg_shell.cmds.cget=function(msg)
	send_output()
end
msg_shell.cmds.cput=function(msg)
	local s=string.sub(msg,5)
	local n=cam_con_puts(s)
	if n ~= s:len() then
		write_usb_msg(string.format("puts failed: %s ~= %s",n,s:len()))
		return
	end
	send_output()
end
msg_shell.idle=function()
	if opts.task then
		if get_task_result() then
			send_output()
			write_usb_msg(string.format("task completed: %d",get_task_result()))
			if opts.autoexit then
				msg_shell.done = true
			end
		end
	end
end
if opts.task then
	call_event_proc_task(opts.task)
	write_usb_msg('started '..opts.task)
	send_output()
else
	write_usb_msg('started msg_shell')
	send_output()
end
msg_shell:run()
]]
			if not args.r then
				local err=con:exec(code,{libs='msg_shell'})
				--if not status then
					--return false,err
				--end
			end
			local done
			while true do
				local status
				local msgwait = 500
				while true do
					-- wait (briefly) for messages or script exit
					-- most commands should produce a message
					status = con:wait_status{
						run=false,
						msg=true,
						timeout=msgwait,
						poll=50,
					}
					-- wait less for additional messages
					msgwait = 100
					if not status.msg then
						break
					end
					local output
					local msg=con:read_msg()
					if msg.script_id ~= con:get_script_id() then
						output = string.format("WARNING message from unexpected script %d %s\n",msg.script_id,chdku.format_script_msg(msg))
					elseif msg.type == 'user' then
						output = tostring(msg.value)
					elseif msg.type == 'return' then
						output = 'RETURN: '..tostring(msg.value)
					elseif msg.type == 'error' then
						output = 'ERROR: '..tostring(msg.value)
					else
						output = string.format("WARNING: unexpected message type %s %s\n",tostring(msg.type),chdku.format_script_msg(msg))
					end
					if output then
						printf("%s",output)
						if string.sub(output,-1,-1) ~= '\n' then
							printf("\n")
						end
					end
				end
				if done then
					break
				end
				-- this can happen on autoexit
				if not status.run then
					return true, 'msg_shell ended'
				end
				local line = cli.readline('camcon> ')
				if line then
					-- TODO add exit that drops out of camcon without quitting?
					-- would need to not error out if msg shell is already running
					local s,e = string.find(line,'^[%c%s]*%%')
					local msg
					if s then
						msg = string.sub(line,e+1)
						-- ensure we break out if quit requested
						if string.sub(msg,1,4) == 'quit' then
							done = true
						-- allow a bare % to just check for output
						elseif msg == '' then
							msg = 'cget'
						end
					else
						-- TODO lua itself can't accept non-line oriented input,
						-- so we force a return
						msg = 'cput '..line ..'\n'
					end
					con:write_msg(msg)
				else
					printf('io.read failed\n')
					done=true
				end
			end
			return true
		end,
	},
	}
end
return m
