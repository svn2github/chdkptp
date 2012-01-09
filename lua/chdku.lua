--[[
lua helper functions for working with the chdk.* c api

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
local chdku={}
-- format a script message in a human readable way
function chdku.format_script_msg(msg)
	if msg.type == 'none' then
		return ''
	end
	local r=string.format("%d:%s:",msg.script_id,msg.type)
	-- for user messages, type is clear from value, strings quoted, others not
	if msg.type == 'user' or msg.type == 'return' then
		if msg.subtype == 'boolean' or msg.subtype == 'integer' or msg.subtype == 'nil' then
			r = r .. tostring(msg.value)
		elseif msg.subtype == 'string' then
			r = r .. string.format("'%s'",msg.value)
		else
			r = r .. msg.subtype .. ':' .. tostring(msg.value)
		end
	elseif msg.type == 'error' then
		r = r .. msg.subtype .. ':' .. tostring(msg.value)
	end
	return r
end

-- TODO this should be split out into it's own module(s)
--[[
simple library system for building remote commands
chunks of source code to be used remotely
can be used with chdku.exec
TODO some of these are duplicated with local code, but we don't yet have an easy way of sharing them
TODO would be good to minify
TODO passing compiled chunks might be better but our lua configurations are different
]]
local rlibs = {
	libs={},
}
--[[
register{
	name='libname'
	depend='lib'|{'lib1','lib2'...}, -- already registered rlibs this one requires (cyclic deps not allowed)
	code='', -- main lib code.
}
]]
function rlibs:register(t)
	-- for convenience, single lib may be given as string
	if type(t.depend) == 'string' then
		t.depend = {t.depend}
	elseif type(t.depend) == 'nil' then
		t.depend = {}
	elseif type(t.depend) ~= 'table' then
		error('expected dependency table or string')
	end
	if type(t.code) ~= 'string' then
		error('expected code string')
	end
	if type(t.name) ~= 'string' then
		error('expected name string')
	end
	t.lines = 0 
	for c in string.gmatch(t.code,'\n') do
		t.lines = t.lines + 1
	end

	for i,v in ipairs(t.depend) do
		if not self.libs[v] then
			errf('%s missing dep %s\n',t.name,v)
		end
	end
	self.libs[t.name] = t
end

--[[
register an array of libs
]]
function rlibs:register_array(t)
	for i,v in ipairs(t) do
		self:register(v)
	end
end

--[[
add deps for a single lib
]]
function rlibs:build_single(build,name)
	local lib = self.libs[name]
	if not lib then
		errf('unknown lib %s\n',tostring(name))
	end
	-- already added
	if build.map[name] then
		return
	end
	for i,dname in ipairs(lib.depend) do
		self:build_single(build,dname)
	end
	build.map[name]=lib
	table.insert(build.list,lib)
end
--[[
return an object containing the libs with deps resolved
obj=rlibs:build('name'|{'name1','name2',...})
]]
-- helper for returned object
local function rlib_get_code(build)
	local code=""
	for i,lib in ipairs(build.list) do
		code = code .. lib.code .. '\n'
	end
	return code
end
function rlibs:build(libnames)
	-- single can be given as string, 
	-- nil is allowed, returns empty object
	if type(libnames) == 'string' or type(libnames) == 'nil' then
		libnames={libnames}
	elseif type(libnames) ~= 'table' then
		error('rlibs:build_list expected string or table for libnames')
	end
	local build={
		list={},
		map={},
		code=rlib_get_code,
	}
	for i,name in ipairs(libnames) do
		self:build_single(build,name)
	end
	return build
end
--[[
return a string containing all the required rlib code
code=rlibs:build('name'|{'name1','name2',...})
]]
function rlibs:code(names)
	local build = self:build(names)
	return build:code();
end

rlibs:register_array{
--[[
mostly duplicated from util.serialize
global defaults can be changed from code
]]
{
	name='serialize',
	code=[[
serialize_r = function(v,opts,seen,depth)
	local vt = type(v)
	if vt == 'nil' or  vt == 'boolean' or vt == 'number' then
		return tostring(v)
	elseif vt == 'string' then
		return string.format('%q',v)
	elseif vt == 'table' then
		if not depth then
			depth = 1
		end
		if depth >= opts.maxdepth then
			error('serialize: max depth')
		end
		if not seen then
			seen={}
		elseif seen[v] then 
			if opts.err_cycle then
				error('serialize: cycle')
			else
				return '"cycle:'..tostring(v)..'"'
			end
		end
		seen[v] = true;
		local r='{'
		for k,v1 in pairs(v) do
			if opts.pretty then
				r = r .. '\n' ..  string.rep(' ',depth)
			end
			if type(k) == 'string' and string.match(k,'^[_%a][%a%d_]*$') then
				r = r .. tostring(k)
			else
				r = r .. '[' .. serialize_r(k,opts,seen,depth+1) .. ']'
			end
			r = r .. '=' .. serialize_r(v1,opts,seen,depth+1) .. ','
		end
		if opts.pretty then
			r = r .. '\n' .. string.rep(' ',depth-1)
		end
		r = r .. '}'
		return r
	elseif opts.err_type then
		error('serialize: unsupported type ' .. vt, 2)
	else
		return '"'..tostring(v)..'"'
	end
end
serialize_defaults = {
	maxdepth=10,
	err_type=true,
	err_cycle=true,
	pretty=false,
}
function serialize(v,opts)
	if opts then
		for k,v in pairs(serialize_defaults) do
			if not opts[k] then
				opts[k]=v
			end
		end
	else
		opts=serialize_defaults
	end
	return serialize_r(v,opts)
end
]],
},
--[[
mt_inherit from util
]]
{
	name='mt_inherit',
	code=[[
function mt_inherit(t,base)
	local mt={
		__index=function(table, key)
			return base[key]
		end
	}
	setmetatable(t,mt)
	return t
end
]],
},
--[[
extend_table from util
note deep will fail unless you include extend_table_r
]]
{
	name='extend_table',
	code=[[
function extend_table(target,source,deep)
	if type(target) ~= 'table' then
		error('extend_table: target not table')
	end
	if source == nil then
		return target
	end
	if type(source) ~= 'table' then 
		error('extend_table: source not table')
	end
	if source == target then
		error('extend_table: source == target')
	end
	if deep then
		return extend_table_r(target, source)
	else 
		for k,v in pairs(source) do
			target[k]=v
		end
		return target
	end
end
]],
},
--[[
recursive version of extend_table
not meant to be used on its own 
depends are intentially weird, requiring this will pull in extend_table
]]
{
	name='extend_table_r',
	depend='extend_table',
	code=[[
extend_table_max_depth = 10
function extend_table_r(target,source,seen,depth) 
	if not seen then
		seen = {}
	end
	if not depth then
		depth = 1
	end
	if depth > extend_table_max_depth then
		error('extend_table: max depth');
	end
	-- a source could have refernces to the target, don't want to do that
	seen[target]=true
	if seen[source] then
		error('extend_table: cycles');
	end
	seen[source]=true
	for k,v in pairs(source) do
		if type(v) == 'table' then
			if type(target[k]) ~= 'table' then
				target[k] = {}
			end
			extend_table_r(target[k],v,seen,depth+1)
		else
			target[k]=v
		end
	end
	return target
end
]],
},
-- override default table serialization for messages
{
	name='serialize_msgs',
	depend='serialize',
	code=[[
	usb_msg_table_to_string=serialize
]],
},
--[[
join a path with / as needed
]]
{
	name='joinpath',
	code=[[
function joinpath(...)
	local parts={...}
	if #parts < 2 then
		error('joinpath requires at least 2 parts')
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
]],
},
--[[
function to batch stuff in groups of messages
each batch is sent as a numeric array
b=msg_batcher{
	batchsize=num, -- items per batch
	timeout=num, -- message timeout
}
call
b:write(value) adds items and sends when batch size is reached
b:flush() sends any remaining items
]]
{
	name='msg_batcher',
	depend={'serialize_msgs','extend_table'},
	code=[[
function msg_batcher(opts)
	local t = extend_table({
		batchsize=50,
		timeout=100000
	},opts)
	t.data={}
	t.n=0
	t.write=function(self,val)
		self.n = self.n+1
		self.data[self.n]=val
		if self.n >= self.batchsize then
			return self:flush()
		end
		return true
	end
	t.flush = function(self)
		if self.n > 0 then
			if not write_usb_msg(self.data,self.timeout) then
				return false
			end
			self.data={}
			self.n=0
		end
		return true
	end
	return t
end
]],
},
--[[
retrieve a directory listing of names, batched in messages
]]
{
	name='ls_simple',
	depend='msg_batcher',
	code=[[
function ls_simple(path)
	local b=msg_batcher()
	local t,err=os.listdir(path)
	if not t then
		return false,err
	end
	for i,v in ipairs(t) do
		if not b:write(v) then
			return false
		end
	end
	return b:flush()
end
]],
},
--[[
object to aid interating over directories
di=dir_iter.new{
	callback=function(di)
	listall=bool -- pass to os.listdir; currently broken, stat on . or .. fails
	-- users may add their own methods or members
}
status,err=di:run(dir)

callback must return true to continue processing, or false optionally followed by an error message on error
the following are available to callback
di.cur={
	st=<stat information>
	full=<full path and filename>
	dir=<directory part>
	name=<basename>
}
di.path an array of path elements representing the directories recursed into
	di.path[1] is always the initial path passed to run(), no matter how many subdirectories deep it is
di:depth() depth of recursion, initial directory is 1
di:can_recurse() to check if the current items is valid to recurse into
di:recurse() to recurse into a directory
]]
{
	name='dir_iter',
	depend={'serialize_msgs','joinpath','mt_inherit','extend_table'},
	code=[[
dir_iter={}
function dir_iter.new(t)
	if not t then
		t={}
	end
	mt_inherit(t,dir_iter)
	return t
end

function dir_iter:depth()
	return #self.path
end

function dir_iter:can_recurse()
	if not self.cur.st.is_dir or self.cur.name == '.' or self.cur.name == '..' then
		return false
	end
	return true
end

function dir_iter:recurse()
	if not self:can_recurse() then
		return false
	end
	table.insert(self.path,self.cur.name)
	local save_cur = self.cur
	local save_curdir = self.cur_dir
	self.cur_dir = joinpath(self.cur_dir,self.cur.name)
	local status,err = self:singledir()
	self.cur_dir = save_curdir
	self.cur = save_cur
	table.remove(self.path)
	return status,err
end

function dir_iter:singledir()
	local t,err=os.listdir(self.cur_dir,self.listall)
	if not t then
		return false,err
	end
	for i,name in ipairs(t) do
		self.cur={name=name,dir=self.cur_dir,full=joinpath(self.cur_dir,name)}
		local st,err = os.stat(self.cur.full)
		if not st then
			return false,err
		end
		self.cur.st = st
		local status, err = self:callback()
		if not status then
			return false,err
		end
	end
	return true
end

function dir_iter:run(dir)
	self.path={dir}
	self.cur_dir=dir
	self.cur={}
	local st,err=os.stat(dir)
	if not st then
		return false,err
	end
	if not st.is_dir then
		return false,"not a directory"
	end
	return self:singledir()
end
]],
},
--[[
process directory tree with matching
status,err = find_files(dir,opts,func)
opts={
	fmatch='<pattern>', -- match on names of files, default any
	dmatch='<pattern>', -- match on names of directories, default any 
	rmatch='<pattern>', -- recurse into directories matching, default any 
	dirs=true, -- pass directories to func. otherwise only files sent to func, but dirs are still recursed
	dirsfirst=false, -- process directories before contained files
	maxdepth=100, -- maxium number of directories to recurse into. 1 = only initial dir
	martians=bool -- return non-file, not directory items (vol label,???) default false
}
func defaults to batching the file names
unless dirsfirst is set, directories will be recursed into before calling func on the containing directory
TODO
match on stat fields (newer, older etc)
match by path components e.g. /foo[ab]/bar/.*%.lua
]]
{
	depend={'dir_iter','msg_batcher','extend_table'},
	name='find_files',
	code=[[
function find_files_full_fn(di,opts,func)
	return di:ff_bwrite(di.cur.full)
end

function find_files_stat_fn(di,opts,func)
	return di:ff_bwrite(extend_table({path=di.cur.full},di.cur.st))
end

function find_files(path,opts,func)
	if not func then
		func=find_files_default_fn
	end
	opts=extend_table({
		dirs=true,
		dirsfirst=false,
		maxdepth=100,
	},opts)

	local d=dir_iter.new({
		ff_check_match=function(self,opts)
			if self.cur.st.is_file then
				return not opts.fmatch or string.match(self.cur.name,opts.fmatch)
			end
			if self.cur.st.is_dir then
				return not opts.dmatch or string.match(self.cur.name,opts.dmatch)
			end
			if opts.martians then
				return true
			end
			return false
		end,
		ff_bwrite=function(self,data)
			if not self.ff_batcher then
				self.ff_batcher = msg_batcher()
			end
			return self.ff_batcher:write(data)
		end,
		ff_func=func,
		ff_item=function(self,opts)
			if not self:ff_check_match(opts) then
				return true
			end
			return self:ff_func(opts)
		end,
		callback=function(self)
			if self.cur.st.is_dir then
				if opts.dirs and opts.dirsfirst then
					local status,err = self:ff_item(opts)
					if not status then
						return false,err
					end
				end
				if self:depth() < opts.maxdepth and self:can_recurse() then
					if not opts.rmatch or string.match(self.cur.name,opts.rmatch) then
						local status,err = self:recurse()
						if not status then
							return false,err
						end
					end
				end
				if opts.dirs and not opts.dirsfirst then
					local status,err = self:ff_item(opts)
					if not status then
						return false,err
					end
				end
			else
				local status,err = self:ff_item(opts)
				if not status then
					return false,err
				end
			end
			return true
		end
	})
	local status,err = d:run(path)
	if not status then
		return false,err
	end
	if d.ff_batcher then
		return d.ff_batcher:flush()
	end
	return true
end
]],
},
--[[
camera side support for mdownload
]]
{
	depend={'find_files'},
	name='ff_mdownload',
	code=[[
function ff_mdownload_fn(self,opts)
	local r={}
	r.st = self.cur.st
	if #self.path == 1 then
		r.relname = self.cur.name
	else
		if #self.path == 2 then
			r.relname =  self.path[2]
		elseif #self.path > 2 then
			r.relname = joinpath(unpack(self.path,2))
		end
		r.relname = joinpath(r.relname,self.cur.name)
	end
	return self:ff_bwrite(r)
end

function ff_mdownload(dir,opts)
	return find_files(dir,opts,ff_mdownload_fn)
end
]],
},
--[[
TODO rework this to a general iterate over directory function
sends file listing as serialized tables with write_usb_msg
returns true, or false,error message
opts={
	stat=bool|{table}|'/'|'*',
	listall=bool, 
	msglimit=number,
	match="pattern",
}
stat
	false/nil, return an array of names without stating at all
	'/' return array of names, with / appended to dirs
	'*" return array of stat results, plus name="name"
	{table} return stat fields named in table (TODO not implemented)
msglimit
	maximum number of items to return in a message
	each message will contain a table with partial results
	default 50
match
	pattern, file names matching with string.match will be returned
listall 
	passed as second arg to os.listdir

may run out of memory on very large directories,
msglimit can help but os.listdir itself could use all memory
TODO message timeout is not checked
TODO handle case if 'path' is a file
]]
{
	name='ls',
	depend={'msg_batcher','joinpath'},
	code=[[
function ls(path,opts_in)
	local opts={
		msglimit=50,
		msgtimeout=100000,
	}
	if opts_in then
		for k,v in pairs(opts_in) do
			opts[k]=v
		end
	end
	local t,msg=os.listdir(path,opts.listall)
	if not t then
		return false,msg
	end
	local b=msg_batcher{
		batchsize=opts.msglimit,
		timeoute=opts.msgtimeout
	}
	for i,v in ipairs(t) do
		if not opts.match or string.match(v,opts.match) then
			if opts.stat then
				local st,msg=os.stat(joinpath(path,v))
				if not st then
					return false,msg
				end
				if opts.stat == '/' then
					if st.is_dir then
						b:write(v .. '/')
					else 
						b:write(v)
					end
				elseif opts.stat == '*' then
					st.name=v
					b:write(st)
				end
			else
				b:write(t[i])
			end
		end
	end
	b:flush()
	return true
end
]],
},
--[[
a simple long lived script for interactive testing
example
!return con:exec('msg_shell:run()',{libs='msg_shell'})
putm exec message="hello world"
putm exec print(message)
]]
{
	name='msg_shell',
	code=[[
msg_shell={}
msg_shell.done=false
msg_shell.cmds={
	quit=function(msg)
		msg_shell.done=true
	end,
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
msg_shell.run=function(self)
	repeat 
		local msg=read_usb_msg()
		if msg then
			local cmd = string.match(msg,'^%w+')
			if type(self.cmds[cmd]) == 'function' then
				self.cmds[cmd](msg)
			elseif type(self.default_cmd) == 'function' then
				self.default_cmd(msg)
			else
				print('undefined command: '..cmd)
			end
		else
			sleep(100)
		end
	until self.done
end
]],
},
}

chdku.rlibs = rlibs
--[[ 
connection methods, added to the connection object
]]
local con_methods = {}
--[[
check whether this cameras model and serial number match those given
TODO - ugly
]]
function con_methods:match_ptp_info(match) 
	match = util.extend_table({model='.*',serial_number='.*'},match)
	local ptp_info = self:get_ptp_devinfo()
	if not ptp_info then
		return false
	end
	-- older cams don't have serial
	if not ptp_info.serial_number then
		ptp_info.serial_number = ''
	end
--	printf('model %s (%s) serial_number %s (%s)\n',ptp_info.model,match.model,ptp_info.serial_number, match.serial_number)
	return (string.find(ptp_info.model,match.model) and string.find(ptp_info.serial_number,match.serial_number))
end

--[[
return a list of remote directory contents
dirlist[,err]=con:listdir(path,opts)
path should be directory, without a trailing slash (except in the case of A/...)
opts may be a table, or a string containing lua code for a table
returns directory listing as table, or false,error
note may return an empty table if target is not a directory
]]
function con_methods:listdir(path,opts) 
	if type(opts) == 'table' then
		opts = serialize(opts)
	elseif type(opts) ~= 'string' and type(opts) ~= 'nil' then
		return false, "invalid options"
	end
	if opts then
		opts = ','..opts
	else
		opts = ''
	end
	local results={}
	local i=1
	local status,err=self:execwait("return ls('"..path.."'"..opts..")",{
		libs='ls',
		msgs=chdku.msg_unbatcher(results),
	})
	if not status then
		return false,err
	end

	return results
end

--[[
download files and directories
status[,err]=con:mdownload(srcpath,dstpath,opts)
opts are passed to find_files
]]
function con_methods:mdownload(srcpath,dstpath,opts)
	if not dstpath then
		dstpath = '.'
	end
	opts=extend_table({},opts)
	opts.dirsfirst=true
	if lfs.attributes(dstpath,'mode') ~= 'directory' then
		local status,err = util.mkdir_m(dstpath)
		if not status then
			return false,err
		end
	end
	local files={}
	local status,err = self:execwait('ff_mdownload("'..srcpath..'",'..serialize(opts)..')',
										{libs={'ff_mdownload'},msgs=chdku.msg_unbatcher(files)})

	if not status then
		return false,err
	end

	if #files == 0 then
		warnf("no matching files\n");
		return true
	end

	for i,finfo in ipairs(files) do
		if finfo.st.is_dir then
--			printf('util.mkdir_m(%s)\n',joinpath(dstpath,finfo.relname))
			local status,err = util.mkdir_m(joinpath(dstpath,finfo.relname))
			if not status then
				return false,err
			end
		else
			local dst_dir = util.dirname(finfo.relname)
			if dst_dir ~= '.' then
--				printf('util.mkdir_m(%s)\n',util.joinpath(dstpath,dst_dir))
				local status,err = util.mkdir_m(util.joinpath(dstpath,dst_dir))
				if not status then
					return false,err
				end
			end
			src = joinpath(srcpath,finfo.relname)
			dst = joinpath(dstpath,finfo.relname)
			printf("%s->%s\n",src,dst);
			local status,err = self:download(src,dst)
			if not status then
				return status,err
			end
		end
	end
	return true
end
--[[
quick and dirty bulk delete, this may change or go away

delete files from directory, optionally matching pattern
note directory should not end in a /, unless it is A/
only *files* will be deleted, directories will not be touched
]]
function con_methods:deletefiles(dir,pattern)
	local files,err=self:listdir(dir,{stat="*",match=pattern})
	if not files then
		return false, err
	end
	for i,st in ipairs(files) do
		if st.is_file then
			local status,err=self:remove(joinpath(dir,st.name))
			if not status then
				return false,err
			end
--			print('del '..st.name)
		end
	end
	return true
end

--[[
wrapper for remote functions, serialize args, combine remote and local error status 
func must be a string that evaluates to a function on the camera
returns remote function return values on success, false + message on failure
]]
function con_methods:call_remote(func,...)
	local args = {...}
	local argstrs = {}
	-- preserve nils between values (not trailing ones but shouldn't matter in most cases)
	for i = 1,table.maxn(args) do
		argstrs[i] = serialize(args[i])
	end

	local code = "return "..func.."("..table.concat(argstrs,',')..")"
--	printf("%s\n",code)
	local results = {self:execwait(code)}
	-- if local status is good, return remote
	if results[1] then
		-- start at 2 to discard local status
		return unpack(results,2,table.maxn(results)) -- maxn expression preserves nils
	end
	-- else return local error
	return false,results[2]
end

function con_methods:stat(path)
	return self:call_remote('os.stat',path)
end

function con_methods:mdkir(path)
	return self:call_remote('os.mkdir',path)
end

function con_methods:remove(path)
	return self:call_remote('os.remove',path)
end


--[[
sort an array of stat+name by directory status, name
]]
function chdku.sortdir_stat(list)
	table.sort(list,function(a,b) 
			if a.is_dir and not b.is_dir then
				return true
			end
			if not a.is_dir and b.is_dir then
				return false
			end
			return a.name < b.name
		end)
end

--[[
read pending messages and return error from current script, if available
]]
function con_methods:get_error_msg()
	while true do
		local msg,err = self:read_msg()
		if not msg then
			return false
		end
		if msg.type == 'none' then
			return false
		end
		if msg.type == 'error' and msg.script_id == self:get_script_id() then
			return msg.value
		end
		warnf("chdku.get_error_msg: ignoring message %s\n",chdku.format_script_msg(msg))
	end
end

--[[
format a remote lua error from chdku.exec using line number information
]]
local function format_exec_error(libs,code,errmsg)
	local lnum=tonumber(string.match(errmsg,'^%s*:(%d+):'))
	if not lnum then
		print('no match '..errmsg)
		return errmsg
	end
	local l = 0
	local lprev, errlib, errlnum
	for i,lib in ipairs(libs.list) do
		lprev = l
		l = l + lib.lines + 1 -- TODO we add \n after each lib when building code
		if l >= lnum then
			errlib = lib
			errlnum = lnum - lprev
			break
		end
	end
	if errlib then
		return string.format("%s\nrlib %s:%d\n",errmsg,errlib.name,errlnum)
	else
		return string.format("%s\nuser code: %d\n",errmsg,lnum - l)
	end
end

--[[
read and discard all pending messages. Returns false,error if message functions fails, otherwise true
]]
function con_methods:flushmsgs()
	repeat
		local msg,err=self:read_msg()
		if not msg then
			return false, err
		end
	until msg.type == 'none' 
	return true
end

--[[
return a closure to be used with as a chdku.exec msgs function, which unbatches messages msg_batcher into t
]]
function chdku.msg_unbatcher(t)
	local i=1
	return function(msg)
		if msg.subtype ~= 'table' then
			return false, 'unexpected message value'
		end
		local chunk,err=unserialize(msg.value)
		if err then
			return false, err
		end
		for j,v in ipairs(chunk) do
			t[i]=v
			i=i+1
		end
		return true
	end
end
--[[ 
wrapper for chdk.execlua, using optional code from rlibs
status[,err]=con:exec("code",opts)
opts {
	libs={"rlib name1","rlib name2"...} -- rlib code to be prepended to "code"
	wait=bool -- wait for script to complete, return values will be returned after status if true
	nodefaultlib=bool -- don't automatically include default rlibs
	clobber=bool -- if false, will check script-status and refuse to execute if script is already running
				-- clobbering is likely to result in crashes / memory leaks in current versions of CHDK!
	flushmsgs=bool -- if true (default) read and silently discard any pending messages before running script
					-- not applicable if clobber is true, since the running script could just spew messages indefinitely
	-- below only apply if with wait
	msgs={table|callback} -- table or function to receive user script messages
	rets={table|callback} -- table or function to receive script return values, instead of returning them
	fdata={any lua value} -- data to be passed as second argument to callbacks
}
callbacks
	status[,err] = f(message,fdata)
	processing continues if status is true, otherwise aborts and returns err
]]
-- use serialize by default
chdku.default_libs={
	'serialize_msgs',
}

--[[
convenience, defaults wait=true
]]
function con_methods:execwait(code,opts_in)
	return self:exec(code,extend_table({wait=true},opts_in))
end

function con_methods:exec(code,opts_in)
	-- setup the options
	local opts = extend_table({flushmsgs=true},opts_in)
	local liblist={}
	-- add default libs, unless disabled
	-- TODO default libs should be per connection
	if not opts.nodefaultlib then
		extend_table(liblist,chdku.default_libs)
	end
	-- allow a single lib to be given as by name
	if type(opts.libs) == 'string' then
		liblist={opts.libs}
	else
		extend_table(liblist,opts.libs)
	end

	-- check for already running script and flush messages
	if not opts.clobber then
		local status,err = self:script_status()
		if not status then
			return false,err
		end
		if status.run then
			return false,"a script is already running"
		end
		if opts.flushmsgs and status.msg then
			status,err=self:flushmsgs()
			if not status then
				return false,err
			end
		end
	end

	-- build the complete script from user code and rlibs
	local libs = chdku.rlibs:build(liblist)
	code = libs:code() .. code

	-- try to start the script
	local status,err=self:execlua(code)
	if not status then
		-- syntax error, try to fetch the error message
		if err == 'syntax' then
			local msg = self:get_error_msg()
			if msg then
				return false,format_exec_error(libs,code,msg)
			end
		end
		--  other unspecified error, or fetching syntax/compile error message failed
		return false,err
	end

	-- if not waiting, we're done
	if not opts.wait then
		return true
	end

	-- to collect return values
	-- first result is our status
	local results={true}
	local i=2

	-- process messages and wait for script to end
	while true do
		status,err=self:wait_status{ msg=true, run=false }
		if not status then
			return false,tostring(err)
		end
		if status.msg then
			local msg,err=self:read_msg()
			if not msg then
				return false, err
			end
			if msg.script_id ~= self:get_script_id() then
				warnf("chdku.exec: message from unexpected script %s\n",msg.script_id,chdku.format_script_msg(msg))
			elseif msg.type == 'user' then
				if type(opts.msgs) == 'function' then
					local status,err = opts.msgs(msg,opts.fdata)
					if not status then
						return false,err
					end
				elseif type(opts.msgs) == 'table' then
					table.insert(opts.msgs,msg)
				else
					warnf("chdku.exec: unexpected user message %s\n",chdku.format_script_msg(msg))
				end
			elseif msg.type == 'return' then
				if type(opts.rets) == 'function' then
					local status,err = opts.rets(msg,opts.fdata)
					if not status then
						return false,err
					end
				elseif type(opts.rets) == 'table' then
					table.insert(opts.rets,msg)
				else
					-- if serialize_msgs is not selected, table return values will be strings
					if msg.subtype == 'table' and libs.map['serialize_msgs'] then
						results[i] = unserialize(msg.value)
					else
						results[i] = msg.value
					end
					i=i+1
				end
			elseif msg.type == 'error' then
				return false, format_exec_error(libs,code,msg.value)
			else
				return false, 'unexpected message type'
			end
		-- script is completed and all messages have been processed
		elseif status.run == false then
			-- returns were handled by callback or table
			if opts.rets then
				return true
			else
				return unpack(results,1,table.maxn(results)) -- maxn expression preserves nils
			end
		end
	end
end

--[[
sleep until specified status is met
status,errmsg=con:wait_status(opts)
opts:
{
	-- bool values cause the function to return when the status matches the given value
	-- if not set, status of that item is ignored
	msg=bool
	run=bool
	timeout=<number> -- timeout in ms
	poll=<number> -- polling interval in ms
}
status: table with msg and run set to last status, and timeout set if timeout expired, or false,errormessage on error
TODO for gui, this should yield in lua, resume from timer or something
]]
function con_methods:wait_status(opts)
	local timeleft = opts.timeout
	local sleeptime = opts.poll
	if not timeleft then
		timeleft=86400000 -- 1 day 
	end
	if not sleeptime or sleeptime < 50 then
		sleeptime=250
	end
	while true do
		local status,msg = self:script_status()
		if not status then
			return false,msg
		end
		if status.run == opts.run or status.msg == opts.msg then
			return status
		end
		if timeleft > 0 then
			if timeleft < sleeptime then
				sleeptime = timeleft
			end
			sys.sleep(sleeptime)
			timeleft = timeleft - sleeptime
		else
			status.timeout=true
			return status
		end
	end
end

--[[
meta table for wrapped connection object
]]
local con_meta = {
	__index = function(t,key)
		return con_methods[key]
	end
}

--[[
proxy connection methods from low level object to chdku
]]
local function init_connection_methods()
	for name,func in pairs(chdk_connection) do
		if con_methods[name] == nil and type(func) == 'function' then
			con_methods[name] = function(self,...)
				return chdk_connection[name](self._con,...)
			end
		end
	end
end

init_connection_methods()

--[[
bool = chdku.match_device(devinfo,match)
attempt to find a device specified by the match table 
{
	bus='bus pattern'
	dev='device pattern'
	product_id = number
}
]]
function chdku.match_device(devinfo,match) 
	--[[
	printf('try bus:%s (%s) dev:%s (%s) pid:%s (%s)\n',
		devinfo.bus, match.bus,
		devinfo.dev, match.dev,
		devinfo.product_id, tostring(match.product_id))
	--]]
	if string.find(devinfo.bus,match.bus) and string.find(devinfo.dev,match.dev) then
		return (match.product_id == nil or tonumber(match.product_id)==devinfo.product_id)
	end
	return false
end
--[[
return a connection object wrapped with chdku methods
devspec is a table specifying the bus and device name to connect to
no checking is done on the existence of the device
if devspec is null, a dummy connection is returned
]]
function chdku.connection(devspec)
	local con = {}
	setmetatable(con,con_meta)
	con._con = chdk.connection(devspec)
	return con
end

return chdku
