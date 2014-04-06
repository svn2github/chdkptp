--[[
 Copyright (C) 2013 <reyalp (at) gmail dot com>
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
interactive remote shoot in continuous mode
--]]
local m={}

--[[
initializer remotecap handlers and path
]]
function init_handlers(args,opts)
	local dst = args[1]
	local dst_dir
	if dst then
		if string.match(dst,'[\\/]+$') then
			-- explicit / treat it as a directory
			-- and check if it is
			dst_dir = string.sub(dst,1,-2)
			if lfs.attributes(dst_dir,'mode') ~= 'directory' then
				cli.dbgmsg('mkdir %s\n',dst_dir)
				local status,err = fsutil.mkdir_m(dst_dir)
				if not status then
					return false,err
				end
			end
			dst = nil
		elseif lfs.attributes(dst,'mode') == 'directory' then
			dst_dir = dst
			dst = nil
		end
	end
	local rcopts={}
	if args.jpg then
		rcopts.jpg=chdku.rc_handler_file(dst_dir,dst)
	end
	if args.dng then
		local badpix = args.badpix
		if badpix == true then
			badpix = 0
		end
		local dng_info = {
			lstart=opts.lstart,
			lcount=opts.lcount,
			badpix=badpix,
		}
		rcopts.dng_hdr = chdku.rc_handler_store(function(chunk) dng_info.hdr=chunk.data end)
		rcopts.raw = chdku.rc_handler_raw_dng_file(dst_dir,dst,'dng',dng_info)
	else
		if args.raw then
			rcopts.raw=chdku.rc_handler_file(dst_dir,dst)
		end
		if args.dnghdr then
			rcopts.dng_hdr=chdku.rc_handler_file(dst_dir,dst)
		end
	end
	return rcopts
end
m.cli_cmd_func = function(self,args)
	local opts,err = cli:get_shoot_common_opts(args)
	if not opts then
		return false,err
	end

	util.extend_table(opts,{
		fformat=0,
		lstart=0,
		lcount=0,
	})
	-- fformat required for init
	if args.jpg then
		opts.fformat = opts.fformat + 1
	end
	if args.dng then
		opts.fformat = opts.fformat + 6
	else
		if args.raw then
			opts.fformat = opts.fformat + 2
		end
		if args.dnghdr then
			opts.fformat = opts.fformat + 4
		end
	end
	-- default to jpeg TODO won't be supported on cams without raw hook
	if opts.fformat == 0 then
		opts.fformat = 1
		args.jpg = true
	end

	if args.badpix and not args.dng then
		util.warnf('badpix without dng ignored\n')
	end

	if args.s or args.c then
		if args.dng or args.raw then
			if args.s then
				opts.lstart = tonumber(args.s)
			end
			if args.c then
				opts.lcount = tonumber(args.c)
			end
		else
			util.warnf('subimage without raw ignored\n')
		end
	end

	local rcopts
	rcopts,err = init_handlers(args,opts)
	if not rcopts then
		return false, err
	end

	-- wait time for remotecap
	opts.cap_timeout=30000
	-- wait time for shoot hook
	opts.shoot_hook_timeout=args.cmdwait * 1000

	local opts_s = serialize(opts)
	cli.dbgmsg('rs_init\n')
	local status,rstatus,rerr = con:execwait('return rsint_init('..opts_s..')',{libs={'rsint'}})
	if not status then
		return false,rstatus
	end
	if not rstatus then
		return false,rerr
	end

	local status,err = con:exec('return rsint_run('..opts_s..')',{libs={'rsint'}})
	-- rs_shoot should not initialize remotecap if there's an error, so no need to uninit
	if not status then
		return false,err
	end

	done = false
	local status,err
	repeat
--				local line = io.read()
		local line = cli.readline('rsint> ')
		if not line then
			warnf('cli.readline failed / eof\n')
			break
		end
		status, err = con:script_status()
		if not status then 
			warnf('script_status failed %s\n',tostring(err))
			break
		end
		if status.msg then
			local status, err = con:read_all_msgs({
				['return']=function(msg,opts)
					printf("script return %s\n",tostring(msg.value))
				end,
				user=function(msg,opts)
					printf("script msg %s\n",tostring(msg.value))
				end,
				error=function(msg,opts)
					return false,msg.value
				end,
			})
			if not status then
				return false, err
			end
		end
		if not status.run then 
			warnf('script not running\n')
			break
		end
		local s,e,cmd = string.find(line,'^[%c%s]*([%w_]+)[%c%s]*')
		local rest = string.sub(line,e+1)
		-- printf("cmd [%s] rest [%s]\n",cmd,rest);
		if cmd == 'path' then
			if rest == '' then
				rest = nil
			end
			args[1] = rest
			rcopts,err = init_handlers(args,opts)
			-- TODO handle error, should send l to script
		else
			-- remaining commands assumed to be cam side
			-- TODO could check if remotecap has timed out here
			status, err = con:write_msg(cmd..' '..rest)
			if not status then
				done=true
				warnf('write_msg failed %s\n',tostring(err))
				-- TODO might have remotecap data, but probably won't be able to read it if msg failed
				break
			end
			if cmd == 's' or cmd == 'l' then
				status,err = con:capture_get_data(rcopts)
				if not status then
					warnf('capture_get_data error %s\n',tostring(err))
				end
				if cmd == 'l' then
					done=true
				end
			end
		end
	until done

	local t0=ustime.new()
	-- wait for shot script to end or timeout
	local wstatus,werr=con:wait_status{
		run=false,
		timeout=30000,
	}
	if not wstatus then
		warnf('error waiting for shot script %s\n',tostring(werr))
	elseif wstatus.timeout then
		warnf('timed out waiting for shot script\n')
	end
	cli.dbgmsg("script wait time %.4f\n",ustime.diff(t0)/1000000)
	-- TODO check messages

	local ustatus, uerr = con:execwait('init_usb_capture(0)') -- try to uninit
	-- if uninit failed, combine with previous status
	if not ustatus then
		uerr = 'uninit '..tostring(uerr)
		status = false
		if err then
			err = err .. ' ' .. uerr
		else 
			err = uerr
		end
	end
	return status, err
end

function m.register_rlib() 
	chdku.rlibs:register{
		name='rsint',
		depend={'extend_table','serialize_msgs','rs_shoot_init'},
		code=[[
function wait_shooting(state, timeout)
	if not timeout then
		timeout = 2000
	end
	local timeout_tick = get_tick_count() + timeout
 	while get_shooting() ~= state do
		sleep(10)
		if get_tick_count() >= timeout_tick then
			return false, 'get_shooting timed out'
		end
	end
	return true
end

function rsint_init(opts)
	if type(hook_shoot) ~= 'table' then
		return false, 'build does not support shoot hook'
	end

	opts.cont=1
	return rs_init(opts)
end

-- from msg_shell
cmds={
	echo=function(msg)
		if write_usb_msg(msg) then
			print("ok")
		else 
			print("fail")
		end
	end,
	exec=function(msg)
		local f,err=loadstring(string.sub(msg,5));
		if f then 
			local r={f()} -- pcall would be safer but anything that yields will fail
			for i, v in ipairs(r) do
				write_usb_msg(v)
			end
		else
			write_usb_msg(err)
			print("loadstring:"..err)
		end
	end,
	pcall=function(msg)
		local f,err=loadstring(string.sub(msg,6));
		if f then 
			local r={pcall(f)}
			for i, v in ipairs(r) do
				write_usb_msg(v)
			end
		else
			write_usb_msg(err)
			print("loadstring:"..err)
		end
	end,
}

function rsint_run(opts)
	press('shoot_half')

	status, err = wait_shooting(true)
	if not status then
		return false, err
	end

	local errmsg

	hook_shoot.set(opts.shoot_hook_timeout)
	local shoot_count = hook_shoot.count()
	press('shoot_full')
	while true do
		local next_shot
		local msg=read_usb_msg(10)

		if type(get_usb_capture_target) == 'function' and get_usb_capture_target() == 0 then
			errmsg = 'remote capture cancelled'
			break
		end

		local cmd=nil
		if msg then
			cmd = string.match(msg,'^%w+')
		end
		if cmd == 's' or cmd == 'l' then
			next_shot = true
		elseif msg then
			if type(cmds[cmd]) == 'function' then
				cmds[cmd](msg)
			else
				write_usb_msg('unknown command '..tostring(cmd))
			end
		end
		if next_shot then
 			if hook_shoot.is_ready() then
				shoot_count = hook_shoot.count()
				hook_shoot.continue()
				next_shot = false
			end
		else
			if hook_shoot.count() > shoot_count and not hook_shoot.is_ready() then
				errmsg = 'timeout waiting for command'
				break
			end
		end
		if cmd == 'l' then
			break
		end
	end
	hook_shoot.set(0)
	release('shoot_full')
	if errmsg then
		return false, errmsg
	end
	return true
end
]]}
end
return m
