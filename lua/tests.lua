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
very quick and dirty test framework for some lua functions
]]
-- module
local m={}
-- tests
local t={}
-- assert with optional level for line numbers
local function tas(cond,msg,level)
	if not level then 
		level = 3
	end
	if cond then
		return
	end
	error(msg,level)
end
t.argparser = function()
	local function get_word(val,eword,epos) 
		local word,pos = cli.argparser:get_word(val)
		tas(word == eword,tostring(word) .. ' ~= '..tostring(eword))
		tas(pos == epos,tostring(pos) .. "~= "..tostring(epos))
	end
	get_word('','',1)
	get_word('whee','whee',5)
	get_word([["whee"]],'whee',7)
	get_word([['whee']],'whee',7)
	get_word([[\whee\]],[[\whee\]],7)
	get_word("whee foo",'whee',5)
	get_word([["whee\""]],[[whee"]],9)
	get_word([['whee\']],[[whee\]],8)
	get_word("'whee ",false,[[unclosed ']])
	get_word([["whee \]],false,[[unexpected \]])
	get_word('wh"e"e','whee',7)
	get_word('wh""ee','whee',7)
	get_word([[wh"\""ee]],[[wh"ee]],9)
end

t.dirname = function()
	assert(dirname('/')=='/')
	assert(dirname('//')=='/')
	assert(dirname('/a/b/')=='/a')
	assert(dirname('//a//b//')=='//a')
	assert(dirname()==nil)
	assert(dirname('a')=='.')
	assert(dirname('')=='.')
	assert(dirname('/a')=='/')
	assert(dirname('a/b')=='a')
	-- TODO should spoof ostype, so test runs on all platforms
	if sys.ostype() == 'Windows' then
		assert(dirname('c:\\')=='c:/')
		assert(dirname('c:')=='c:')
	end
end

t.basename = function()
	assert(basename('foo/bar')=='bar')
	assert(basename('foo/bar.txt','.txt')=='bar')
	assert(basename('bar')=='bar')
	assert(basename('bar/')=='bar')
	if sys.ostype() == 'Windows' then
		assert(basename('c:/')==nil)
		assert(basename('c:/bar')=='bar')
	end
end

t.basename_cam = function()
	assert(basename_cam('A/')==nil)
	assert(basename_cam('A/DISKBOOT.BIN')=='DISKBOOT.BIN')
	assert(basename_cam('bar/')=='bar')
end

t.dirname_cam = function()
	assert(dirname_cam('A/')=='A/')
	assert(dirname_cam('A/DISKBOOT.BIN')=='A/')
	assert(dirname_cam('bar/')==nil)
	assert(dirname_cam('A/CHDK/SCRIPTS')=='A/CHDK')
end

t.splitjoin_cam = function()
	assert(joinpath(unpack(splitpath_cam('A/FOO'))) == 'A/FOO')
	assert(joinpath(unpack(splitpath_cam('foo/bar/mod'))) == 'foo/bar/mod')
end

t.joinpath = function()
	assert(joinpath('/foo','bar')=='/foo/bar')
	assert(joinpath('/foo/','bar')=='/foo/bar')
	assert(joinpath('/foo/','/bar')=='/foo/bar')
	assert(joinpath('/foo/','bar','/mod')=='/foo/bar/mod')
	if sys.ostype() == 'Windows' then
		assert(joinpath('/foo\\','/bar')=='/foo\\bar')
	end
end

t.fsmisc = function()
	if sys.ostype() == 'Windows' then
		assert(joinpath(unpack(splitpath('d:/foo/bar/mod'))) == 'd:/foo/bar/mod')
		-- assert(joinpath(unpack(splitpath('d:foo/bar/mod'))) == 'd:foo/bar/mod')
	end
	assert(joinpath(unpack(splitpath('/foo/bar/mod'))) == '/foo/bar/mod')
	assert(joinpath(unpack(splitpath('foo/bar/mod'))) == './foo/bar/mod')
end

function m:run(name)
	-- TODO side affects galore
	printf('%s:start\n',name)
	status,msg = pcall(t[name])
	printf('%s:',name)
	if status then
		printf('ok\n')
	else
		printf('failed %s\n',msg)
	end
end

function m:runall()
	for k,v in pairs(t) do
		self:run(k)
	end
end

return m
