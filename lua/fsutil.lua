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
--]]
--[[
local path and filesystem related utilities
depends on sys.ostype and lfs
]]
local fsutil={}
--[[
valid separator characters
]]
-- default function for ostype, can override for testing
fsutil.ostype = sys.ostype

function fsutil.dir_sep_chars()
	if fsutil.ostype() == 'Windows' then
		return '\\/'
	end
	return '/'
end

--[[
similar to unix basename
]]
function fsutil.basename(path,sfx)
	if not path then
		return nil
	end
	local drive
	-- drive is discarded, like leading /
	drive,path = fsutil.splitdrive(path)
	local s,e,bn=string.find(path,'([^'..fsutil.dir_sep_chars()..']+)['..fsutil.dir_sep_chars()..']?$')
	if not s then
		return nil
	end
	if sfx and string.len(sfx) < string.len(bn) then
		if string.sub(bn,-string.len(sfx)) == sfx then
			bn=string.sub(bn,1,string.len(bn) - string.len(sfx))
		end
	end
	return bn
end

function fsutil.splitdrive(path)
	if fsutil.ostype() ~= 'Windows' then
		return '',path
	end
	local s,e,drive,rest=string.find(path,'^(%a:)(.*)')
	if not drive then
		drive = ''
		rest = path
	end
	if not rest then
		rest = ''
	end
	return drive,rest
end
--[[
note A/=>nil
]]
function fsutil.basename_cam(path,sfx)
	if not path then
		return nil
	end
	if path == 'A/' then
		return nil
	end
	local s,e,bn=string.find(path,'([^/]+)/?$')
	if not s then
		return nil
	end
	if sfx and string.len(sfx) < string.len(bn) then
		if string.sub(bn,-string.len(sfx)) == sfx then
			bn=string.sub(bn,1,string.len(bn) - string.len(sfx))
		end
	end
	return bn
end

--[[
similar to unix dirname, with some workarounds to make it more useful on windows
UNC paths are not supported
]]
function fsutil.dirname(path)
	if not path then
		return nil
	end
	local drive=''
	-- windows - save the drive, if present, and perform dirname on the rest of the path
	drive,path=fsutil.splitdrive(path)
	-- remove trailing blah/?
	local dn=string.gsub(path,'[^'..fsutil.dir_sep_chars()..']+['..fsutil.dir_sep_chars()..']*$','')
	if dn == '' then
		if drive == '' then
			return '.'
		else
			return drive
		end
	end
	-- remove any trailing /
	dn = string.gsub(dn,'['..fsutil.dir_sep_chars()..']*$','')
	-- all /
	if dn == '' then
		return drive..'/'
	end
	return drive..dn
end

--[[
dirname variant for camera paths
note, A/ is ambiguous if used on relative paths, treated specially
has trailing directory removed, except for A/ (camera functions trailing / on A/ and reject on subdirs) 
A/ must be uppercase (as required by dryos)
]]
function fsutil.dirname_cam(path)
	if not path then
		return nil
	end
	if path == 'A/' then
		return path
	end
	-- remove trailing blah/?
	dn=string.gsub(path,'[^/]+/*$','')
	-- invalid, 
	if dn == '' then
		return nil
	end
	-- remove any trailing /
	dn = string.gsub(dn,'/*$','')
	if dn == 'A' then
		return 'A/'
	end
	-- all /, invalid
	if dn == '' then
		return nil
	end
	return dn
end

--[[ 
add / between components, only if needed.
accepts / or \ as a separator on windows
TODO joinpath('c:','foo') becomes c:/foo
]]
function fsutil.joinpath(...)
	local parts={...}
	-- TODO might be more useful to handle empty/missing parts
	if #parts < 2 then
		error('joinpath requires at least 2 parts',2)
	end
	local r=parts[1]
	for i = 2, #parts do
		local v = string.gsub(parts[i],'^['..fsutil.dir_sep_chars()..']','')
		if not string.match(r,'['..fsutil.dir_sep_chars()..']$') then
			r=r..'/'
		end
		r=r..v
	end
	return r
end

function fsutil.joinpath_cam(...)
	local parts={...}
	-- TODO might be more useful to handle empty/missing parts
	if #parts < 2 then
		error('joinpath requires at least 2 parts',2)
	end
	local r=parts[1]
	for i = 2, #parts do
		local v = string.gsub(parts[i],'^/','')
		if not string.match(r,'/$') then
			r=r..'/'
		end
		r=r..v
	end
	return r
end

--[[
split a path into an array of components
the leading component will may have a /, drive or .
]]
function fsutil.splitpath(path)
	local parts={}
	while true do
		local part=fsutil.basename(path)
		path = fsutil.dirname(path)
		table.insert(parts,1,part)
		if path == '.' or path == '/' or (fsutil.ostype() == 'Windows' and string.match(path,'^%a:/?$')) then
			table.insert(parts,1,path)
			return parts
		end
	end
end

function fsutil.splitpath_cam(path)
	local parts={}
	while true do
		local part=fsutil.basename_cam(path)
		path = fsutil.dirname_cam(path)
		table.insert(parts,1,part)
		if path == 'A/' then
			table.insert(parts,1,path)
			return parts
		end
		if path == nil then
			return parts
		end
	end
end
--[[
make multiple subdirectories
]]
function fsutil.mkdir_m(path)
	local mode = lfs.attributes(path,'mode')
	if mode == 'directory' then
		return true
	end
	if mode then
		return false,'path exists, not directory'
	end
	local parts = fsutil.splitpath(path)
	-- never try to create the initial . or /
	local p=parts[1]
	for i=2, #parts do
		p = fsutil.joinpath(p,parts[i])
		local mode = lfs.attributes(p,'mode')
		if not mode then
			local status,err = lfs.mkdir(p)
			if not status then
				return false,err
			end
		elseif mode ~= 'directory' then
			return false,'path exists, not directory'
		end
	end
	return true
end

return fsutil
