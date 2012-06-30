--[[
 Copyright (C) 2010-2012 <reyalp (at) gmail dot com>
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
a script for stressing the usb layer and message system

usage:
!m=require'msgtest'
!m.load()
!m.test(<start lenght>,<optional max length>,<optional increment>)
]]
local m={}

function m.load()
	local status,err=con:exec('msg_shell:run()',{libs='msg_shell'})
	if not status then
		return false,err
	end
	return con:write_msg([[exec
msg_shell.default_cmd=function(msg)
	collectgarbage('step')
	write_usb_msg(msg,1000)
	sleep(10)
end
]])
end

function m.test(m,n,inc)
	if not n then 
		n=m
	end
	if not inc then
		inc=1
	end
	for i=m,n,inc do 
		local s=string.rep('x',i)
		printf("sending %d (0x%x)...",i,i)
		local status,err=con:write_msg(s)
		if not status then
			printf('send failed\n')
			return
		end
		local r
		status,r = con:wait_msg({mtype='user'})
		if not status then
			printf('read failed %s\n',r) 
		elseif s == r.value then 
			printf('ok\n')
		else
			printf('not equal\n')
		end
	 end
end
return m
