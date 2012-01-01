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
]]
util=require('util')
util:import()
chdku=require('chdku')
cli=require('cli')
--[[
Command line arguments
--]]
function bool_opt(rest)
	if rest == '-' then
		return true,false
	elseif rest ~= '' then
		return false
	end
	return true,true
end

cmd_opts = {
	{
		opt="g",
		help="start gui",
		process=bool_opt,
	},
	{
		opt="i",
		help="start interactive cli",
		process=bool_opt,
	},
	{
		opt="c",
		help="connect at startup",
		process=function(rest)
			if rest then
				options.c = rest
			else
				options.c = true
			end
			return true,options.c
		end,
	},
	{
		opt="n",
		help="non-interactive - quit after processing command line options",
		process=bool_opt,
	},
	{
		opt="e",
		help="execute cli command, multiple allowed",
		process=function(rest)
			if type(options.e) == 'table' then
				table.insert(options.e,rest)
			else 
				options.e = {rest}
			end
			return true,options.e
		end,
	},
	{
		opt="h",
		help="help",
		process=bool_opt,
	},
}

function print_help()
	printf(
[[
CHDK PTP control utility
Usage: chdkptp [options]
Options:
]])
	for i=1,#cmd_opts do
		printf("  -%-4s %s\n",cmd_opts[i].opt,cmd_opts[i].help)
	end
end

-- option values
options = {}
cmd_opts_map = {}
start_commands = {}
-- defaults TODO from prefs
function process_options()
	local i
	for i=1,#cmd_opts do
		options[cmd_opts[i].opt] = false
		cmd_opts_map[cmd_opts[i].opt] = cmd_opts[i]
	end

	while #args > 0 do
		local arg = table.remove(args,1)
		local s,e,cmd,rest = string.find(arg,'^-([a-zA-Z0-9])=?(.*)')
--		printf("opt %s rest (%s)[%s]\n",tostring(cmd),type(rest),tostring(rest))
		if s and options[cmd] ~= nil then
			local r,val=cmd_opts_map[cmd].process(rest,args)
			if r then
				options[cmd] = val
			else
				errf("malformed option %s\n",arg)
			end
		else
			errf("unrecognized argument %s\n",arg)
			invalid = true
		end
	end

	if options.h or invalid then
		print_help()
		return true
	end
end

process_options()

con=chdku.connection()

if options.g then
	if init_iup() then
		gui=require('gui')
		return gui:run()
	else
		error('gui not supported')
	end
else
	if options.c then
		local cmd="connect"
		if type(options.c) == 'string' then
			cmd = cmd .. ' ' .. options.c
		end
		cli:print_status(cli:execute(cmd));
	end
	-- for the gui, e commands will be run after the gui is started
	if options.e then
		for i=1,#options.e do
--			printf("e:%s\n",options.e[i])
			local status,msg=cli:execute(options.e[i])
			if not status then
				errf("%s\n",msg)
			elseif msg then
				fprintf(io.stderr,"%s\n",msg)
			end
		end
	end
	if options.i then
		return cli:run()
	end
end
