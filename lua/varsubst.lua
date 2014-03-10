--[[
 Copyright (C) 2010-2014 <reyalp (at) gmail dot com>

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
utility for substitution strings
]]
local m={}

--[[
funcs={
	name=f(argstr),
}
where f returns the substitution value
--]]
m.run=function(str,funcs)
	-- TODO this won't catch many error cases, since they won't match
	-- TODO doesn't handle nesting
	-- TODO doesn't allow escaping
	-- TODO error isn't friendly
	local r=str:gsub('$(%b{})',
		function(str)
			-- try with just name
			local argstr
			local s,e,func=str:find('{([%w]+)}$')
			-- no match, try args (format is arbitrary)
			if not s then
				s,e,func,argstr=str:find('{([%w]+),%s*([^}]*)}$')
			end
			if not s then
				error('parse failed '..tostring(str))
			end
			-- could run recursively on argstr to support nesting
			if funcs[func] then
				return funcs[func](argstr)
			end
			error('unknown substitution function '..tostring(func))
		end)
	return r
end
return m
