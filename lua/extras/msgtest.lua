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
!m.testlen(<start length>,<optional max length>,<optional increment>)

set m.checkmem to report memory usage
use m.gc(<collect garbage arg>) to perform garbage collection on each iteration, either 'step', 'collect' or nil
]]
local m={}

function m.load()
	local status,err=con:exec('msg_shell:run()',{libs='msg_shell'})
	if not status then
		return false,err
	end
	return con:write_msg([[exec
msg_shell.msg_wait = nil
msg_shell.default_cmd=function(msg)
	if msgtest_gc then
		collectgarbage(msgtest_gc)
	end
	write_usb_msg(msg)
end
msg_shell.cmds.memstats=function()
	write_usb_msg(string.format('mem:%8d lmem:%8d',get_meminfo().free_size,collectgarbage('count')))
end
]])
end

function m.test_msg(len)
	local s=string.rep('x',len)
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
	if m.checkmem then
		local status,err=con:write_msg('memstats')
		if not status then
			printf('send failed\n')
			return
		end
		status,r = con:wait_msg({mtype='user'})
		if not status then
			printf('read failed %s\n',r) 
		else
			printf(r.value..'\n')
		end
	end
end
--[[
test messages of increasing length, from s to n
]]
function m.testlen(s,n,inc)
	if not n then 
		n=s
	end
	if not inc then
		inc=1
	end
	for i=s,n,inc do 
		printf("sending %d (0x%x)...",i,i)
		m.test_msg(i)
	end
end
--[[
test messages size s, n times
]]
function m.test(s,n)
	for i=1,n do 
		printf("send %d...",i)
		m.test_msg(s)
	end
end

function m.gc(mode)
	if not mode then
		mode='nil'
	else
		mode = '"'..mode..'"'
	end
	local status,err=con:write_msg('exec msgtest_gc='..mode)
	if not status then
		printf('send failed\n')
		return
	end
end
return m
