--[[
 Copyright (C) 2016 <reyalp (at) gmail dot com>

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

various dev utils as cli commands
usage
!require'extras/devutil':init_cli()

--]]
local m={}
local proptools=require'extras/proptools'

m.stop_uart_log = function()
	if not m.logname then
		errlib.throw{etype='bad_arg',msg='log not started'}
	end
	con:execwait([[
require'uartr'.stop()
]])
end

m.resume_uart_log = function()
	if not m.logname then
		errlib.throw{etype='bad_arg',msg='log not started'}
	end
	con:execwait(string.format([[
require'uartr'.start('%s',false,0x%x)
]],m.logname,m.logsize+512))
end

m.init_cli = function()
	cli:add_commands{
	{
		names={'dlstart'},
		help='start uart log w/large log buffers',
		arghelp="[options] [file]",
		args=cli.argparser.create{
			csize=0x6000,
			a=false,
		},
		help_detail=[[
 [file] name for log file, default A/dbg.log
 options
  -csize=<n> camera log buffer size
  -a  append to existing log
 requires native calls enabled, camera with uart log support (all DryOS)
]],
		func=function(self,args)
			local logname=args[1]
			if not logname then
				logname='dbg.log'
			end
			logname = fsutil.make_camera_path(logname)
			con:execwait(string.format([[
call_event_proc('StopCameraLog')
sleep(200)
call_event_proc('StartCameraLog',0x20,0x%x)
sleep(100)
require'uartr'.start('%s',%s,0x%x)
]],args.csize,logname,tostring(args.a==false),args.csize+512))
			m.logname=logname
			m.logsize=args.csize
			return true,'log started: '..m.logname
		end
	},
	{
		names={'dlgetcam'},
		help='show camera log and download uart log',
		arghelp="[local]",
		args=cli.argparser.create{},
		help_detail=[[
 [local] name to download log to, default same as uart log
 log must have been started with startlog
]],
		func=function(self,args)
			if not m.logname then
				return false,'log not started'
			end
			con:execwait([[call_event_proc('ShowCameraLog')]])
			sys.sleep(500)
			local dlcmd='download '..m.logname
			if args[1] then
				dlcmd = dlcmd..' '..args[1]
			end
			return cli:execute(dlcmd)
		end
	},
	{
		names={'dlget'},
		help='download uart log',
		arghelp="[local]",
		args=cli.argparser.create{},
		help_detail=[[
 [local] name to download log to, default same as uart log
 log must have been started with startlog
]],

		func=function(self,args)
			if not m.logname then
				return false,'log not started'
			end
			local dlcmd='download '..m.logname
			if args[1] then
				dlcmd = dlcmd..' '..args[1]
			end
			return cli:execute(dlcmd)
		end
	},
	{
		names={'dlstop'},
		help='stop uart log',
		func=function(self,args)
			m.stop_uart_log()
			return true
		end
	},
	{
		names={'dlresume'},
		help='resume uart log',
		func=function(self,args)
			m.resume_uart_log()
			return true
		end
	},
	{
		names={'dpget'},
		help='get range of propcase values',
		arghelp="[options]",
		args=cli.argparser.create{
			s=0,
			e=999,
			c=false,
		},
		help_detail=[[
 options:
  -s min prop id, default 0
  -e max prop id, default 999
  -c=[code] lua code to execute before getting props
]],

		func=function(self,args)
			args.e=tonumber(args.e)
			args.s=tonumber(args.s)
			if args.e < args.s then
				return false,'invalid range'
			end
			m.psnap=proptools.get(args.s, args.e + 1 - args.s,args.c)
			return true
		end
	},
	{
		names={'dpsave'},
		help='save propcase values obtained with dpget',
		arghelp="[file]",
		args=cli.argparser.create{ },
		help_detail=[[
 [file] output file
]],

		func=function(self,args)
			if not m.psnap then
				return false,'no saved props'
			end
			if not args[1] then
				return false,'missing filename'
			end
			proptools.write(m.psnap,args[1])
			return true,'saved '..args[1]
		end
	},
	{
		names={'dpcmp'},
		help='compare current propcase values with last dpget',
		arghelp="[options]",
		args=cli.argparser.create{
			c=false,
		},
		help_detail=[[
 options:
  -c=[code] lua code to execute before getting props
]],
		func=function(self,args)
			if not m.psnap then
				return false,'no saved props'
			end
			proptools.comp(m.psnap,proptools.get(m.psnap._min, m.psnap._max - m.psnap._min,args.c))
			return true
		end
	},
	{
		names={'dsearch32'},
		help='search memory for specified 32 bit value',
		arghelp="<start> <end> <val>",
		args=cli.argparser.create{ },
		help_detail=[[
 <start> start address
 <end>   end address
 <val>   value to find
]],
		func=function(self,args)
			local start=tonumber(args[1])
			local last=tonumber(args[2])
			local val=tonumber(args[3])
			if not start then
				return false, 'missing start address'
			end
			if not last then
				return false, 'missing end address'
			end
			if not val then
				return false, 'missing value'
			end
			printf("search 0x%08x-0x%08x 0x%08x\n",start,last,val)
			local t={}
			-- TODO should have limits on number of matches, ability to save results since it's slow
			con:execwait(string.format([[
mem_search_word{start=0x%x, last=0x%x, val=0x%x}
]],start,last,val),{libs='mem_search_word',msgs=chdku.msg_unbatcher(t)})
			for i,v in ipairs(t) do
				printf("0x%08x\n",bit32.band(v,0xFFFFFFFF)) 
			end
			return true
		end
	},
}
end

return m
