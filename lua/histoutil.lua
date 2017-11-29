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
  along with this program; if not, write to the Free Software
  Foundation, Inc., 59 Temple Place, Suite 330, Boston, MA  02111-1307  USA
--]]
--[[
histogram utilities
]]

local m={ }

--[[
assumes histo is a 0 based array of values, with a field total optionaly giving the total number of values
opts {
	fmt=string|function -- 'count' = raw count, '%' = % as float, '%.' = % as line of '.'
						-- or function(count), default 'count'
	outfn=function -- function(count, bin_start, bin_end)
	bin=number -- bin size, default 1
	min=number -- minimum value, default 0
	max=number -- maxium value, default #histo (in 0 based, 0th entry not counted)
	rfmt=string -- format for range vlaues
	total=number -- default histo.total
}

]]
function m.print(histo,opts)
	opts=util.extend_table({
		fmt='count',
		bin=1,
		min=0,
		total=histo.total,
	},opts)
	-- only use #histo if max not specified, in case histo is userdate without length operator
	if not opts.max then
		opts.max = #histo
	end
	-- dng histo makes total a member of histo
	local total=opts.total
	if not total then
		errlib.throw{etype='bad_arg',msg='histoutil.print: missing total'}
	end

	if not opts.max then
		errlib.throw{etype='bad_arg',msg='histoutil.print: missing max'}
	end
	if not opts.rfmt then
		local l=string.len(string.format('%d',opts.max))
		opts.rfmt='%'..l..'d'
	end

	local fmt_range
	local fmt_count
	if type(opts.fmt) == 'function' then
		fmt_count = opts.fmt
	elseif opts.fmt == '%' then
		fmt_count = function(count)
			return string.format('%6.2f',(count / total) * 100)
		end
	elseif opts.fmt == '%.' then
		fmt_count = function(count)
			return string.format('%s',string.rep('.',(count / total) * 100))
		end
	elseif opts.fmt=='count' then
		fmt_count = function(count)
			return tostring(count)
		end
	else
		errlib.throw{etype='bad_arg',msg='histoutil.print: bad fmt '..tostring(opts.fmt)}
	end

	if opts.bin == 1 then
		local fstr=opts.rfmt
		fmt_range = function(v1)
			return string.format(opts.rfmt,v1)
		end
	else
		local fstr=opts.rfmt..'-'..opts.rfmt
		fmt_range = function(v1,v2)
			return string.format(fstr,v1,v2)
		end
	end

	local outfn
	if opts.outfn then
		outfn=opts.outfn
	else
		outfn=function(count,v1,v2)
			printf("%s %s\n",fmt_range(v1,v2),fmt_count(count))
		end
	end

	local bin = opts.bin
	local v = opts.min

	while v <= opts.max do
		local count = 0
		for i=0,bin - 1 do
			-- bin size may not evenly divide range
			if v+i <= opts.max then
				count = count + histo[v+i]
			end
		end
		outfn(count,v,v+bin-1)
		v = v + bin
	end
	return true
end
function m.range_count(histo,vmin,vmax)
	local total=0
	for i=vmin,vmax do
		total = total + histo[i]
	end
	return total
end
return m
