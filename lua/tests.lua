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

local function spoof_fsutil_ostype(name)
	fsutil.ostype = function()
		return name
	end
end
local function unspoof_fsutil_ostype()
	fsutil.ostype = sys.ostype
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
	assert(fsutil.dirname('/')=='/')
	assert(fsutil.dirname('//')=='/')
	assert(fsutil.dirname('/a/b/')=='/a')
	assert(fsutil.dirname('//a//b//')=='//a')
	assert(fsutil.dirname()==nil)
	assert(fsutil.dirname('a')=='.')
	assert(fsutil.dirname('')=='.')
	assert(fsutil.dirname('/a')=='/')
	assert(fsutil.dirname('a/b')=='a')

	spoof_fsutil_ostype('Windows')
	assert(fsutil.dirname('c:\\')=='c:/')
	assert(fsutil.dirname('c:')=='c:')
	unspoof_fsutil_ostype()
end

t.basename = function()
	assert(fsutil.basename('foo/bar')=='bar')
	assert(fsutil.basename('foo/bar.txt','.txt')=='bar')
	assert(fsutil.basename('bar')=='bar')
	assert(fsutil.basename('bar/')=='bar')
	spoof_fsutil_ostype('Windows')
	assert(fsutil.basename('c:/')==nil)
	assert(fsutil.basename('c:/bar')=='bar')
	unspoof_fsutil_ostype()
end

t.basename_cam = function()
	assert(fsutil.basename_cam('A/')==nil)
	assert(fsutil.basename_cam('A/DISKBOOT.BIN')=='DISKBOOT.BIN')
	assert(fsutil.basename_cam('bar/')=='bar')
end

t.dirname_cam = function()
	assert(fsutil.dirname_cam('A/')=='A/')
	assert(fsutil.dirname_cam('A/DISKBOOT.BIN')=='A/')
	assert(fsutil.dirname_cam('bar/')==nil)
	assert(fsutil.dirname_cam('A/CHDK/SCRIPTS')=='A/CHDK')
end

t.splitjoin_cam = function()
	assert(fsutil.joinpath(unpack(fsutil.splitpath_cam('A/FOO'))) == 'A/FOO')
	assert(fsutil.joinpath(unpack(fsutil.splitpath_cam('foo/bar/mod'))) == 'foo/bar/mod')
end

t.joinpath = function()
	assert(fsutil.joinpath('/foo','bar')=='/foo/bar')
	assert(fsutil.joinpath('/foo/','bar')=='/foo/bar')
	assert(fsutil.joinpath('/foo/','/bar')=='/foo/bar')
	assert(fsutil.joinpath('/foo/','bar','/mod')=='/foo/bar/mod')
	spoof_fsutil_ostype('Windows')
	assert(fsutil.joinpath('/foo\\','/bar')=='/foo\\bar')
	unspoof_fsutil_ostype()
end

t.fsmisc = function()
	spoof_fsutil_ostype('Windows')
	assert(fsutil.joinpath(unpack(fsutil.splitpath('d:/foo/bar/mod'))) == 'd:/foo/bar/mod')
	-- assert(fsutil.joinpath(unpack(fsutil.splitpath('d:foo/bar/mod'))) == 'd:foo/bar/mod')
	unspoof_fsutil_ostype()
	assert(fsutil.joinpath(unpack(fsutil.splitpath('/foo/bar/mod'))) == '/foo/bar/mod')
	assert(fsutil.joinpath(unpack(fsutil.splitpath('foo/bar/mod'))) == './foo/bar/mod')
end

t.ustime = function()
	local t=os.time()
	local t0=ustime.new(t,600000)
	local t1=ustime.new(t+1,500000)
	assert(ustime.diff(t1,t0)==900000)
end

t.lbuf = function()
	local s="hello world"
	local l=lbuf.new(s)
	assert(s:len() == l:len())
	assert(s == l:string())
	assert(s:sub(0,100) == l:string(0,100))
	assert(l:string(-5)=='world')
	assert(l:string(1,5)=='hello')
	assert(l:string(nil,5)=='hello')
	assert(l:string(100,200)==s:sub(100,200))
	assert(l:byte(0)==s:byte(0))
	assert(l:byte(5)==s:byte(5))
	local t1 = {l:byte(-5,100)}
	local t2 = {s:byte(-5,100)}
	assert(#t1 == #t2)
	for i,v in ipairs(t2) do
		assert(t1[i]==t2[i])
	end
	l=lbuf.new(100)
	assert(l:len()==100)
	assert(l:byte()==0)
	s=""
	l=lbuf.new(s)
	assert(l:len()==0)
	assert(l:byte()==nil)
	assert(l:string()=="")
end

t.lbufi = function()
	-- TODO not endian aware
	local l=lbuf.new('\001\000\000\000\255\255\255\255')
	assert(l:int32()==1)
	assert(l:int32(10)==nil)
	assert(l:int32(5)==nil)
	assert(l:int32(4,10)==-1)
	assert(l:uint32()==1)
	assert(l:int32(4)==-1)
	assert(l:uint32(4)==0xFFFFFFFF)
	assert(l:uint32(1)==0xFF000000)
	local t={l:int32(0,100)}
	assert(#t == 2)
	assert(t[1] == 1)
	assert(t[2] == -1)
	local l=lbuf.new('\001\000\000\000\000\255\255\255\255')
	assert(l:int32(1)==0x000000)
	local t={l:uint32(0,3)}
	assert(#t == 2)
	assert(t[1] == 1)
	assert(t[2] == 0xFFFFFF00)
end

function m:run(name)
	-- TODO side affects galore
	printf('%s:start\n',name)
	status,msg = xpcall(t[name],util.err_traceback)
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
