--[[
 Copyright (C) 2014-2016 <reyalp (at) gmail dot com>

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

substitution strings are of the form
${name} or ${name,args}
]]
local m={}

local methods={}

--[[
expand a single ${} expression
]]
function methods.process_var(self,str,validate_only)
	-- discard {}
	str=str:sub(2,-2)
	-- extract func name
	local s,e,func=str:find('^([%w_]+)')
	-- no match, try args (format is arbitrary)
	local argstr
	if e ~= str:len() then
		s,e,argstr=str:find(',%s*(.*)$')
	end
	if not s then
		errlib.throw{etype='varsubst',msg='parse failed '..tostring(str)}
	end
	-- recursively expand args, so ${foo, ${bar}} gets expanded
	-- TODO there is no way to prevent any {} from being counted in the %b{}
	if argstr then
		argstr=self:run(argstr,validate_only)
	end
	if self.funcs[func] then
		if validate_only then
			return func -- replace substs with name, removing ${ for syntax check
		else
			return self.funcs[func](argstr,self)
		end
	end
	errlib.throw{etype='varsubst',msg='unknown substitution function '..tostring(func)}
end

--[[
process a string
]]
methods.run=function(obj,str,validate_only)
	local r=str:gsub('$(%b{})',
		function(s)
			return obj:process_var(s,validate_only)
		end)
	return r
end
--[[
syntax check
]]
methods.validate=function(obj,str)
	local r=obj:run(str,true)
	if string.match(r,'%${') then
		errlib.throw{etype='varsubst',msg='unclosed ${'}
	end
	return r
end

--[[
create a temporary varsubsts using 'funcs' and validate str with it
throws on error
]]
m.validate_funcs=function(funcs,str)
	return m.new(funcs):validate(str)
end
--[[
return a function that passes the named value from state through string.format, 
using the first arg as the format string, or default_fmt if not specified
]]
m.format_state_val=function(name,default_fmt)
	return function(argstr,obj)
		if not argstr then 
			argstr=default_fmt
		end
		return string.format(argstr,obj.state[name])
	end
end
--[[
return a function that passes the named value from state through os.date
using the first arg as the date format, or default_fmt if not specified
]]
m.format_state_date=function(name,default_fmt)
	return function(argstr,obj)
		if not argstr then 
			argstr=default_fmt
		end
		return os.date(argstr,obj.state[name])
	end
end

-- general purpose string functions
m.string_subst_funcs={
--[[
TODO doesn't have quoting or escaping, string args better not contain , or {} or leading spaces
TODO error checking isn't done at validation time. Non-nested could in principle
]]
	-- ${s_format,0x%x %s,101,good doggos} = "0x65 good doggos"
	s_format=function(argstr,obj)
		if not argstr then
			errlib.throw{etype='varsubst',msg='s_format missing arguments'}
		end
		local args=util.string_split(argstr,',%s*')
		return string.format(unpack(args))
	end,
	-- ${s_sub,hello world,-5} = "world"
	s_sub=function(argstr,obj)
		if not argstr then
			errlib.throw{etype='varsubst',msg='s_sub missing arguments'}
		end
		local args=util.string_split(argstr,',%s*')
		if #args < 2 or #args > 3 then
			errlib.throw{etype='varsubst',msg='s_sub expected 2 or 3 arguments, not '..tostring(argstr)}
		end
		args[2] = tonumber(args[2])
		if not args[2] then
			errlib.throw{etype='varsubst',msg='s_sub expected number, not '..tostring(args[2])}
		end
		if args[3] then
			args[3] = tonumber(args[3])
			if not args[3] then
				errlib.throw{etype='varsubst',msg='s_sub expected number, not '..tostring(args[3])}
			end
		end
		return string.sub(unpack(args))
	end,

	-- ${s_upper,hi} = "HI"
	s_upper=function(argstr,obj)
		if not argstr then
			errlib.throw{etype='varsubst',msg='s_upper missing arguments'}
		end
		return string.upper(argstr)
	end,
	-- ${s_lower,Bye} = "bye"
	s_lower=function(argstr,obj)
		if not argstr then
			errlib.throw{etype='varsubst',msg='s_lower missing arguments'}
		end
		return string.lower(argstr)
	end,
	-- ${s_reverse,he} = "eh"
	s_reverse=function(argstr,obj)
		if not argstr then
			errlib.throw{etype='varsubst',msg='s_reverse missing arguments'}
		end
		return string.reverse(argstr)
	end,
	-- ${s_rep,he,2} = "hehe"
	s_rep=function(argstr,obj)
		if not argstr then
			errlib.throw{etype='varsubst',msg='s_rep missing arguments'}
		end
		local args=util.string_split(argstr,',%s*')
		if #args ~= 2 then
			errlib.throw{etype='varsubst',msg='s_rep expected 2 arguments, not '..tostring(argstr)}
		end
		args[2]=tonumber(args[2])
		if not args[2] then
			errlib.throw{etype='varsubst',msg='s_rep expected number, not '..tostring(args[2])}
		end
		return string.rep(unpack(args))
	end,
	--[[
	${s_match,subject,pattern[,init]}
	returns first match of pattern in string, starting from init.
	If pattern contains captures, the match is each capture concatenated in order
	${s_match,hello world,.o%s.*} = "lo world"
	${s_match,hello world,(%a+)%s+(%a+)} = "helloworld"
	--]]
	s_match=function(argstr,obj)
		if not argstr then
			errlib.throw{etype='varsubst',msg='s_match missing arguments'}
		end
		local args=util.string_split(argstr,',%s*')
		if #args < 2 or #args > 3 then
			errlib.throw{etype='varsubst',msg='s_match expected 2 or 3 arguments, not '..tostring(argstr)}
		end
		if args[3] then
			args[3] = tonumber(args[3])
			if not args[3] then
				errlib.throw{etype='varsubst',msg='s_match expected number, not '..tostring(args[3])}
			end
		end
		local r={string.match(unpack(args))}
		return table.concat(r)
	end,
	--[[
	${s_gsub,subject,pattern,replacement[,limit]}
	
	returns string with limit matches of pattern replaced by replacement
	in replacement, %0 stands for the whole match, while %1-%9 corespond to captures
	${s_gsub,hello world,(%a+)%s+(%a+),%2 %1} = "world hello"
	--]]
	s_gsub=function(argstr,obj)
		if not argstr then
			errlib.throw{etype='varsubst',msg='s_gsub missing arguments'}
		end
		local args=util.string_split(argstr,',%s*')
		if #args < 3 or #args > 4 then
			errlib.throw{etype='varsubst',msg='s_gsub expected 3 or 4 arguments, not '..tostring(argstr)}
		end
		if args[4] then
			args[4] = tonumber(args[4])
			if not args[4] then
				errlib.throw{etype='varsubst',msg='s_gsub expected number, not '..tostring(args[4])}
			end
		end
		return string.gsub(unpack(args))
	end,
}
--[[
funcs={
	name,f(str,obj)
}
state=table containing any state to be used by funcs, keying by func name recommended
--]]
m.new=function(funcs,state)
	local t={
		funcs=funcs,
		state=state,
	}
	if not t.state then
		t.state={}
	end
	util.extend_table(t,methods)
	return t
end
return m
