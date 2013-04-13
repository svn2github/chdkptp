--[[
usage
!m=require'extras/dbgdump'
!m.load('MY.DMP')
or
!loadfile('lua/extras/dbgdump.lua')().load('LUAERR.DMP')
]]
local m = {}
m.meminfo_fields = {
	'start_address',
	'end_address',
	'total_size',
	'allocated_size',
	'allocated_peak',
	'allocated_count',
	'free_size',
	'free_block_max_size',
	'free_block_count',
}
m.meminfo_map={}

m.header_fields = {
	'ver',
	'time',
	'product_id',
	'romstart',
	'text_start',
	'data_start',
	'bss_start',
	'bss_end',
	'sp',
	'stack_count',
	'user_val',
	'user_data_len',
	'flags',
}
m.header_map={}

m.meminfo_size = 4*#m.meminfo_fields
m.header_size = 4*#m.header_fields

local function init_maps()
	for i,name in ipairs(m.header_fields) do
		m.header_map[name] = (i-1)*4
	end
	for i,name in ipairs(m.meminfo_fields) do
		m.meminfo_map[name] = (i-1)*4
	end
end
init_maps()

local function bind_meminfo(lb,offset)
	local mt = {
		__index=function(t,k)
			if m.meminfo_map[k] then		
				return lb:get_i32(offset + m.meminfo_map[k])
			end
		end
	}
	local t={}
	t.print=function()
		for i,name in ipairs(m.meminfo_fields) do
			local v=t[name]
			printf("%19s %11d 0x%08x\n",name,v,v)
		end
	end
	setmetatable(t,mt)
	return t
end

local function bind_dump(lb)
	local mt = {
		__index=function(t,k)
			if m.header_map[k] then		
				return lb:get_u32(m.header_map[k])
			end
		end,
	}
	local t={_lb = lb}
	setmetatable(t,mt)
	t.mem = bind_meminfo(lb,m.header_size)
	t.exmem = bind_meminfo(lb,m.header_size+m.meminfo_size)
	t.stacki = function(i)
		return lb:get_i32(m.header_size + m.meminfo_size*2 + i*4)
	end
	t.stacku = function(i)
		return lb:get_u32(m.header_size + m.meminfo_size*2 + i*4)
	end
	t.user_data_str = function() 
		return lb:string(-t.user_data_len,-1)
	end
	return t
end

function m.load(name)
	local f,err=io.open(name,'rb')
	if not f then
		return false, err
	end
	local s=f:read('*a')
	f:close()
	if not s then
		return false, 'read failed'
	end
	local lb=lbuf.new(s)
	local d=bind_dump(lb)
	if d.ver ~= 1 then
		return false, 'unknown version '..tostring(d.ver)
	end
	printf("loaded version %d\n",d.ver)
	printf("time %s (%d)\n",os.date('!%Y:%m:%d %H:%M:%S',d.time),d.time)
	for i=3,#m.header_fields do
		local name = m.header_fields[i]
		printf("%19s %11u 0x%08x\n",name,d[name],d[name])
	end
	printf("meminfo:\n")
	d.mem.print();
	printf("exmeminfo:\n")
	d.exmem.print();

	local heap_start = d.mem.start_address
	local heap_end = d.mem.end_address
	local exheap_start = d.exmem.start_address
	local exheap_end = d.exmem.end_address
	printf('stack:\n')
	for i=0,d.stack_count-1 do
		local v=d.stacku(i)
		if not v then
			printf("truncated dump at %d ?\n",i*4)
			break
		end
		local desc = ''
		if v >= d.romstart then
			desc = 'ROM'
		end
		if exheap_start ~= 0 and v >= exheap_start and v <= exheap_end then
			desc = 'exmem heap'
		end
		if heap_start ~= 0xFFFFFFFF and v >= heap_start and v <= heap_end then
			desc = 'heap'
		end
		if v >= d.text_start and v < d.data_start then
			desc = 'CHDK text'
			if v%2 ~= 0 then
				desc = desc .. ' (thumb ?)'
			elseif v%4 == 0 then
				desc = desc .. ' (arm ?)'
			end
		elseif v >= d.data_start and v < d.bss_start then
			desc = 'CHDK data'
		elseif v >= d.bss_start and v <= d.bss_end then
			desc = 'CHDK bss'
		elseif v >= d.sp and v <= d.sp+d.stack_count*4 then
			 -- may not be accurate since we don't know full depth of stack
			desc = 'stack ?'
		end
		printf('%04d 0x%08x: 0x%08x %11d %s\n',i*4,d.sp + i*4,v,v,desc)
	end
	if d.user_data_len > 0 then
		printf('user data:\n%s\n',util.hexdump(d.user_data_str(),d.user_val))
	end
	return d
end

return m
