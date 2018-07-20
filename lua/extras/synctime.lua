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
simple script to synchronize camera time with PC
requires native calls enabled
May be some confusions with DST on some cameras
restarting camera after use is recommended, because registering eventprocs may have side effects

usage
!require'extras/synctime'.sync()

]]
local m={}
function m.sync(opts)
	opts=util.extend_table({utc=false,subsec=true,subsec_margin=10},opts)
	con:execwait[[
if call_event_proc('FA.Create') == -1 then
	error('FA.Create failed')
end
if call_event_proc('InitializeAdjustmentFunction') == -1 then
	error('InitializeAdjustmentFunction failed')
end
]]

	local lfmt='*t'
	if opts.utc then
		lfmt='!*t'
	end
	-- send set command on next second change, less subsec_margin for USB overhead
	local sec,usec=sys.gettimeofday()
	if opts.subsec then
		local waitms = (1000 - usec/1000) - opts.subsec_margin
		if waitms < 0 then
			waitms = waitms + 1000
			sec = sec + 1
		end
		sec = sec+1 -- setting time on transition to next second
		sys.sleep(waitms)
	end
	local lt=os.date(lfmt,sec)
	local ot,nt=con:execwait(string.format([[
local ot=os.date('*t')
if call_event_proc('SetYear',%d) == -1
	or call_event_proc('SetMonth',%d) == -1
	or call_event_proc('SetDay',%d) == -1
	or call_event_proc('SetHour',%d) == -1
	or call_event_proc('SetMinute',%d) == -1
	or call_event_proc('SetSecond',%d) == -1 then
	error('set failed')
end
return ot,os.date('*t')
]],lt.year,lt.month,lt.day,lt.hour,lt.min,lt.sec),{libs='serialize_msgs'})
	printf('pc  %d/%02d/%02d %02d:%02d:%02d\n',lt.year,lt.month,lt.day,lt.hour,lt.min,lt.sec)
	printf('old %d/%02d/%02d %02d:%02d:%02d\n',ot.year,ot.month,ot.day,ot.hour,ot.min,ot.sec)
	printf('new %d/%02d/%02d %02d:%02d:%02d\n',nt.year,nt.month,nt.day,nt.hour,nt.min,nt.sec)
end
return m
