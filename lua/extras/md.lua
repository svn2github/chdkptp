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
a script for testing motion detection
basic usage
!m=require'extras/md'
!m.start()
!r=m.do_md({threshold=10,grid=3,timeout=10000,wait=true,cell_diffs=true,cell_vals=true})
!m.print_result(r)
putm quit
]]

local m={}
--[[
default md parameters
see http://chdk.wikia.com/wiki/Motion_Detection#Function_:_md_detect_motion
--]]
m.md_defaults={
		cols=5, -- a: columns
		rows=5, -- b: rows
		mode=1, -- c: measure mode Y  - 0 for U, 1 for Y, 2 for V; RGB model: 3 for R, 4 for G, 5 for B
		timeout=10000, -- d: time to wait for moation, 10 sec
		interval=30, -- e: minimum interval between MD comparisons
		threshold=10, -- f: trigger threshold
		grid=0, -- g: grid 0=no, 1=grid, 2=sensitivity readout, 3=sensitivity readout & grid
		-- h is return value
		exclude_type=0, -- i: masking type  0=no regions, 1=include, 2=exclude
		exclude_c1=0, -- j: mask first column
		exclude_r1=0, -- k: mask first row 
		exclude_c2=0, -- l: mask last column (in this module, negative values count from the left, so -1 = cols - 1)
		exclude_r2=0, -- m: mask last row 
		fl=0, -- n: flags bit 1 = immediate shoot, bit 2 = debug log, bit 4 = dump liveview, bit 8 = don't release shoot_full
		step=6, -- o: pixel step
		start_delay=10, -- p: start delay. Zero delay seems to cause false trigger the first time md_detect_motion runs
}

function m.start()
	con:exec([[
msg_shell.cmds.md = function(msg)
	local opts=unserialize(string.sub(msg,3))
	local r={}
	local t0=get_tick_count()
	r.cell_count=md_detect_motion(
		opts.cols,
		opts.rows,
		opts.mode,
		opts.timeout,
		opts.interval,
		opts.threshold,
		opts.grid,
		0,
		opts.exclude_type,
		opts.exclude_c1,
		opts.exclude_r1,
		opts.exclude_c2,
		opts.exclude_r2,
		opts.fl,
		opts.step,
		opts.start_delay
	)
	r.time=get_tick_count() - t0
	if opts.cell_diffs then
		r.cell_diffs={}
		for y=1,opts.rows do
			r.cell_diffs[y]={}
			for x=1,opts.cols do
				table.insert(r.cell_diffs[y],md_get_cell_diff(x,y))
			end
		end
	end
	if opts.cell_vals then
		r.cell_vals={}
		for y=1,opts.rows do
			r.cell_vals[y]={}
			for x=1,opts.cols do
				table.insert(r.cell_vals[y],md_get_cell_val(x,y))
			end
		end
	end
	write_usb_msg(r)
end
msg_shell:run()
]],{libs={'msg_shell','unserialize','serialize_msgs'}})
end

function m.build_md_opts(opts)
	opts=util.extend_table_multi({},{m.md_defaults,opts})
	if opts.exclude_c2 < 0 then
		opts.exclude_c2	= opts.cols - opts.exclude_c2
	end
	if opts.exclude_r2 < 0 then
		opts.exclude_r2	= opts.cols - opts.exclude_r2
	end
	return opts
end

function m.do_md(opts)
	opts=m.build_md_opts(opts)
	con:write_msg(string.format('md %s',util.serialize(opts)))
	if not opts.wait then
		return
	end
	return con:wait_msg({mtype='user',munserialize=true})
end
function m.print_cell_result(cells)
	for y,row in ipairs(cells) do
		for x,val in ipairs(row) do
			printf("%4d",val)
		end
		printf("\n")
	end
end
function m.print_result(r)
	printf("cells: %d time: %.3f\n",r.cell_count,r.time/1000)
	if r.cell_vals then
		printf("values:\n");
		m.print_cell_result(r.cell_vals)
	end
	if r.cell_diffs then
		printf("diffs:\n");
		m.print_cell_result(r.cell_diffs)
	end
end

return m
