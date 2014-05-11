--[[
 Copyright (C) 2014 <reyalp (at) gmail dot com>

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
error handling utilities
]]

local m={
	last_traceback='',
 	-- when to include a traceback 'always', 'never', 'critical'
	-- crit means string errors (thrown with error(...) rather than throw)
	-- or error objects with crit set
	do_traceback='critical',
}
--[[
handler for xpcall
formats the error message with or without a traceback depending on settings
if thrown error object includes traceback, uses it, otherwise attempts to get a new one
--]]
function m.format(err)
	return m.format_f(err,m.do_traceback)
end
function m.format_traceback(err)
	return m.format_f(err,'always')
end
function m.format_f(err,do_traceback)
	-- not an error object, try to backtrace
	if do_traceback == 'never' then
		return tostring(err)
	end
	if type(err) == 'string' then
		m.last_traceback = debug.traceback('',3)
		return err ..  m.last_traceback
	end
	if type(err) ~= 'table' then
		err = string.format('unexpected error type %s [%s]',type(err),tostring(err))
		m.last_traceback = debug.traceback('',3)
		return err .. m.last_traceback
	end
	if not err.traceback or type(err.traceback) ~= 'string' then
		err.traceback = debug.traceback('',3)
	end
	m.last_traceback = err.traceback
	if do_traceback == 'always' or err.critical then
		return tostring(err) .. err.traceback
	end
	return tostring(err)
end
return m
