--[[
 Copyright (C) 2016-2017 <reyalp (at) gmail dot com>

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
use help for information about individual commands
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
			clevel=0x20,
			a=false,
		},
		help_detail=[[
 [file] name for log file, default A/dbg.log
 options
  -csize=<n> camera log buffer size, default 0x6000
  -clevel=<n> camera log level, messages with matching bits set are logged. default 0x20
  -a  append to existing log
 requires native calls enabled, camera with uart log support (all DryOS)
]],
		func=function(self,args)
			local logname=args[1]
			if not logname then
				logname='dbg.log'
			end
			opts = {
				logname=fsutil.make_camera_path(logname),
				overwrite=(args.a==false),
				logsize=tonumber(args.csize)+512,
				clevel=tonumber(args.clevel),
				csize=tonumber(args.csize),
			}
			con:execwait('opts='..serialize(opts)..[[

call_event_proc('StopCameraLog')
sleep(200)
call_event_proc('StartCameraLog',opts.clevel,opts.csize)
sleep(100)
require'uartr'.start(opts.logname,opts.overwrite,opts.logsize)
sleep(100)
call_event_proc('Printf',
	'%s dlstart CameraLog 0x%x,0x%x Uart "%s",%s,0x%x\n',
	os.date('%Y%m%d %H:%M:%S'),
	opts.clevel,opts.csize,
	opts.logname,tostring(opts.overwrite),opts.logsize
	)
]])
			m.logname=logname
			m.logsize=args.csize
			return true,'log started: '..m.logname
		end
	},
	{
		names={'dlgetcam'},
		help='print camera log on uart, download uart log',
		arghelp="[local]",
		args=cli.argparser.create{},
		help_detail=[[
 [local] name to download log to, default same as uart log
 log must have been started with dlstart
]],
		func=function(self,args)
			if not m.logname then
				return false,'log not started'
			end
			con:execwait([[
call_event_proc('Printf','%s dlgetcam\n',os.date('%Y%m%d %H:%M:%S'))
call_event_proc('ShowCameraLog')
call_event_proc('Printf','%s dlgetcam end\n',os.date('%Y%m%d %H:%M:%S'))
]])
			sys.sleep(1000) -- 500 was sometimes too short
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
  -s=<number> min prop id, default 0
  -e=<number> max prop id, default 999
  -c=<code> lua code to execute before getting props
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
  -c=<code> lua code to execute before getting props
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
		arghelp="[-l=<n>] [-c=<n>] [-cb=<n>] [-ca=<n>] <start> <end> <val>",
		args=cli.argparser.create{
			l=false,
			c=false,
			cb=false,
			ca=false,
		},
		help_detail=[[
 <start> start address
 <end>   end address
 <val>   value to find
 options
  -l=<n> stop after n matches 
  -c=<n> show N words before and after
  -cb=<n> show N words before match
  -ca=<n> show N words after match
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
			local do_ctx
			local ctx_before = 0
			local ctx_after = 0
			if args.c then
				do_ctx=true
				ctx_before = tonumber(args.c)
				ctx_after = tonumber(args.c)
			end
			if args.cb then
				do_ctx=true
				ctx_before = tonumber(args.cb)
			end
			if args.ca then
				do_ctx=true
				ctx_after = tonumber(args.ca)
			end

			printf("search 0x%08x-0x%08x 0x%08x\n",start,last,val)
			local t={}
			-- TODO should have ability to save results since it's slow
			con:execwait(string.format([[
mem_search_word{start=0x%x, last=0x%x, val=0x%x, limit=%s}
]],start,last,val,tostring(args.l)),{libs='mem_search_word',msgs=chdku.msg_unbatcher(t)})
			for i,v in ipairs(t) do
				local adr=bit32.band(v,0xFFFFFFFF)
				if do_ctx then
					if adr > ctx_before then
						adr = adr - 4*ctx_before
					else
						adr = 0
					end
					local count=ctx_before + ctx_after + 1
					cli:print_status(cli:execute(('rmem -i32 0x%08x %d'):format(adr,count)))
				else
					printf("0x%08x\n",adr) 
				end
			end
			return true
		end
	},
	{
		names={'dromlog'},
		help='get camera romlog',
		arghelp="[dest]",
		args=cli.argparser.create{ },
		help_detail=[[
 [dest] path/name for downloaded file, default ROMLOG.LOG
 GK.LOG / RomLogErr.txt will be prefixed with dst name if present

 requires native calls enabled
 existing ROMLOG.LOG, GK.LOG and RomLogErr.txt files will be removed
]],
		func=function(self,args)
			local dst=args[1]
			local gkdst
			local errdst
			if dst then
				-- make GK log name based on dest 
				local dstbase=fsutil.split_ext(dst)
				gkdst=dstbase..'-GK.LOG'
				errdst=dstbase..'-Err.LOG'
			else
				dst='ROMLOG.LOG'
				gkdst='GK.LOG'
				errdst='RomLogErr.txt'
			end
			local status, logname, gklogname = con:execwait([[
LOG_NAME="A/ROMLOG.LOG"
GKLOG_NAME="A/GK.LOG"
ERR_NAME="A/RomLogErr.txt"

if call_event_proc("SystemEventInit") == -1 then
    if call_event_proc("System.Create") == -1 then
        error("ERROR: SystemEventInit and System.Create failed")
    end
end
if os.stat(LOG_NAME) then
	os.remove(LOG_NAME)
end
if os.stat(GKLOG_NAME) then
	os.remove(GKLOG_NAME)
end
if os.stat(ERR_NAME) then
	os.remove(ERR_NAME)
end

-- first arg: filename, NULL for ROMLOG.TXT (dryos) or ROMLOG (vxworks)
-- second arg: if 0, shutdown camera after writing log
-- note, on vxworks the exception code, registers and stack trace are binary
call_event_proc("GetLogToFile",LOG_NAME,1)

if os.stat(ERR_NAME) then
	return false, ERR_NAME
end

if not os.stat(LOG_NAME) then
    error('logfile %s does not exist',LOG_NAME)
end
if os.stat(GKLOG_NAME) then
	return true, LOG_NAME, GKLOG_NAME
else
	return true, LOG_NAME
end
]])
			if not status then
				cli.infomsg("%s->%s\n",logname,errdst)
				con:download(logname,errdst)
				return false,string.format("ROMLOG failed, error %s\n",errdst)
			end
			cli.infomsg("%s->%s\n",logname,dst)
			con:download(logname,dst)
			if gklogname then
				cli.infomsg("%s->%s\n",gklogname,gkdst)
				con:download(gklogname,gkdst)
			end
			return true
		end
	},
}
end

return m
