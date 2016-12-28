
local bit = require 'bit'
local jutil = require 'jit.util'
local vmdef = require 'jit.vmdef'
local bc = require 'jit.bc'
local disass = require('jit.dis_'..jit.arch)

local band, shr = bit.band, bit.rshift
local inf = tonumber('inf')


local function pushf(t, f, ...)
	if select('#', ...) > 0 then
		f = f:format(...)
	end
	t[#t+1] = f
	return f
end

local function allipairs(t)
	local maxn = table.maxn(t)
	return function (t, k)
		repeat
			k = k + 1
		until t[k] ~= nil or k > maxn
		return k <= maxn and k or nil, t[k]
	end, t, 0
end

local function sortedpairs(t, emptyelem)
	if emptyelem ~= nil and next(t) == nil then
		local done = false
		return function ()
			if not done then
				done = true
				return emptyelem
			end
		end
	end

	local t2, map = {}, {}
	for k in pairs(t) do
		local sk = type(k) == 'number' and ('%20.6f'):format(k) or tostring(k)
		t2[#t2+1] = sk
		map[sk] = k
	end
	table.sort(t2)
	local i = 1
	return function ()
		local k = map[t2[i]]
		i = i+1
		return k, t[k]
	end
end

-- copied from jit.dump

local function fmtfunc(func, pc)
	local fi = jutil.funcinfo(func, pc)
	if fi.loc then
		return fi.loc
	elseif fi.ffid then
		return vmdef.ffnames[fi.ffid]
	elseif fi.addr then
		return ("C:%x"):format(fi.addr)
	else
		return "(?)"
	end
end

-----------

local function bcline(func, pc, prefix)
	local l
	if pc >= 0 then
		l = bc.line(func, pc, prefix)
		if not l then return l end
	else
		l = "0000 "..prefix.." FUNCC      \n"
	end

	l = l:gsub('%s+$', '')
	return l
end


local function func_bc(func, o)
	o = o or {}
	o[func] = jutil.funcinfo(func)
	if o[func].children then
		for n = -1, -inf, -1 do
			local k = jutil.funck(func, n)
			if not k then break end
			if type(k) == 'proto' then func_bc(k, o) end
		end
	end
	o[func].func = func
	o[func].bytecode = {}
	if not o[func].addr then
		local target = bc.targets(func)
		for pc = 1, inf do
			local s = bcline (func, pc, target[pc] and "=>")
			if not s then break end
			local fi_sub = jutil.funcinfo(func, pc)
			o[func].bytecode[pc] = {fi_sub.currentline, s}
		end
	end
	return o
end

--------------------------------------
-- tracing

-- copied from jit/dump.lua

local symtabmt = { __index = false }
local symtab = {}
local nexitsym = 0

-- Fill nested symbol table with per-trace exit stub addresses.
local function fillsymtab_tr(tr, nexit)
	local t = {}
	symtabmt.__index = t
	if jit.arch == "mips" or jit.arch == "mipsel" then
		t[jutil.traceexitstub(tr, 0)] = "exit"
		return
	end
	for i=0,nexit-1 do
		local addr = jutil.traceexitstub(tr, i)
		if addr < 0 then addr = addr + 2^32 end
		t[addr] = tostring(i)
	end
	local addr = jutil.traceexitstub(tr, nexit)
	if addr then t[addr] = "stack_check" end
end

-- Fill symbol table with trace exit stub addresses.
local function fillsymtab(tr, nexit)
	local t = symtab
	if nexitsym == 0 then
		local ircall = vmdef.ircall
		for i=0,#ircall do
			local addr = jutil.ircalladdr(i)
			if addr ~= 0 then
				if addr < 0 then addr = addr + 2^32 end
				t[addr] = ircall[i]
			end
		end
	end
	if nexitsym == 1000000 then -- Per-trace exit stubs.
		fillsymtab_tr(tr, nexit)
	elseif nexit > nexitsym then -- Shared exit stubs.
		for i=nexitsym,nexit-1 do
			local addr = jutil.traceexitstub(i)
			if addr == nil then -- Fall back to per-trace exit stubs.
				fillsymtab_tr(tr, nexit)
				setmetatable(symtab, symtabmt)
				nexit = 1000000
				break
			end
			if addr < 0 then addr = addr + 2^32 end
			t[addr] = tostring(i)
		end
		nexitsym = nexit
	end
	return t
end

-- Disassemble machine code.
local function dump_mcode(tr)
	local o = {}
	local info = jutil.traceinfo(tr)
	if not info then return end
	local mcode, addr, loop = jutil.tracemc(tr)
	if not mcode then return end
	if addr < 0 then addr = addr + 2^32 end
	local ctx = disass.create(mcode, addr, function (s) pushf(o, s) end)
	ctx.hexdump = 0
	ctx.symtab = fillsymtab(tr, info.nexit)
	if loop ~= 0 then
		symtab[addr+loop] = "LOOP"
		ctx:disass(0, loop)
		pushf (o, "->LOOP:\n")
		ctx:disass(loop, #mcode-loop)
		symtab[addr+loop] = nil
	else
		ctx:disass(0, #mcode)
	end
	return table.concat(o)
end




local irtype = {
  [0] = "nil",
  "fal",
  "tru",
  "lud",
  "str",
  "p32",
  "thr",
  "pro",
  "fun",
  "p64",
  "cdt",
  "tab",
  "udt",
  "flt",
  "num",
  "i8 ",
  "u8 ",
  "i16",
  "u16",
  "int",
  "u32",
  "i64",
  "u64",
  "sfp",
}

-- Lookup tables to convert some literals into names.
local litname = {
	["SLOAD "] = setmetatable({}, { __index = function(t, mode)
		local s = ""
		if band(mode, 1) ~= 0 then s = s.."P" end
		if band(mode, 2) ~= 0 then s = s.."F" end
		if band(mode, 4) ~= 0 then s = s.."T" end
		if band(mode, 8) ~= 0 then s = s.."C" end
		if band(mode, 16) ~= 0 then s = s.."R" end
		if band(mode, 32) ~= 0 then s = s.."I" end
		t[mode] = s
		return s
	end}),
	["XLOAD "] = { [0] = "", "R", "V", "RV", "U", "RU", "VU", "RVU", },
	["CONV  "] = setmetatable({}, { __index = function(t, mode)
		local s = irtype[band(mode, 31)]
		s = irtype[band(shr(mode, 5), 31)].."."..s
		if band(mode, 0x800) ~= 0 then s = s.." sext" end
		local c = shr(mode, 14)
		if c == 2 then s = s.." index" elseif c == 3 then s = s.." check" end
		t[mode] = s
		return s
	end}),
	["FLOAD "] = vmdef.irfield,
	["FREF  "] = vmdef.irfield,
	["FPMATH"] = vmdef.irfpm,
	["BUFHDR"] = { [0] = "RESET", "APPEND" },
	["TOSTR "] = { [0] = "INT", "NUM", "CHAR" },
}


local function ctlsub(c)
	if c == "\n" then return "\\n"
	elseif c == "\r" then return "\\r"
	elseif c == "\t" then return "\\t"
	else return ("\\%03d"):format(c:byte())
	end
end

local function formatk(tr, idx)
  local k, t, slot = jutil.tracek(tr, idx)
  local tn = type(k)
  local s
  if tn == "number" then
    if k == 2^52+2^51 then
      s = "bias"
    else
      s = ("%+.14g"):format(k)
    end
  elseif tn == "string" then
    s = (#k > 20 and '"%.20s"~' or '"%s"'):format(k:gsub("%c", ctlsub))
  elseif tn == "function" then
    s = fmtfunc(k)
  elseif tn == "table" then
    s = ("{%p}"):format(k)
  elseif tn == "userdata" then
    if t == 12 then
      s = ("userdata:%p"):format(k)
    else
      s = ("[%p]"):format(k)
      if s == "[0x00000000]" then s = "NULL" end
    end
  elseif t == 21 then -- int64_t
    s = tostring(k):sub(1, -3)
    if (s):sub(1, 1) ~= "-" then s = "+"..s end
  else
    s = tostring(k) -- For primitives.
  end
  s = ("%-4s"):format(s)
  if slot then
    s = ("%s @%d"):format(s, slot)
  end
  return s
end

local function printsnap(tr, snap)
	local o = {}
	local n = 2
	for s=0,snap[1]-1 do
		local sn = snap[n]
		if shr(sn, 24) == s then
			n = n + 1
			local ref = band(sn, 0xffff) - 0x8000 -- REF_BIAS
			if ref < 0 then
				pushf(o, formatk(tr, ref))
			elseif band(sn, 0x80000) ~= 0 then -- SNAP_SOFTFPNUM
				pushf(o, "%04d/%04d", ref, ref+1)
			else
				pushf(o, "%04d", ref)
			end
			pushf(o, band(sn, 0x10000) == 0 and " " or "|") -- SNAP_FRAME
		else
			pushf(o, "---- ")
		end
	end
	pushf(o, "]\n")
	return table.concat(o)
end

-- Dump snapshots (not interleaved with IR).
local function dump_snap(tr)
	local o = {"---- TRACE "..tr.." snapshots\n"}
	for i=0,1000000000 do
		local snap = jutil.tracesnap(tr, i)
		if not snap then break end
		pushf(o, "#%-3d %04d [ ", i, snap[0])
		pushf(o, printsnap(tr, snap))
	end
	return table.concat(o)
end

-- Return a register name or stack slot for a rid/sp location.
local function ridsp_name(ridsp, ins)
	local rid, slot = band(ridsp, 0xff), shr(ridsp, 8)
	if rid == 253 or rid == 254 then
		return (slot == 0 or slot == 255) and " {sink" or (" {%04d"):format(ins-slot)
	end
	if ridsp > 255 then return ("[%x]"):format(slot*4) end
	if rid < 128 then return disass.regname(rid) end
	return ""
end

-- Dump CALL* function ref and return optional ctype.
local function dumpcallfunc(o, tr, ins)
	local ctype
	if ins > 0 then
		local m, ot, op1, op2 = jutil.traceir(tr, ins)		-- luacheck: ignore m
		if band(ot, 31) == 0 then -- nil type means CARG(func, ctype).
			ins = op1
			ctype = formatk(tr, op2)
		end
	end
	if ins < 0 then
		pushf(o, "[0x%x](", tonumber((jutil.tracek(tr, ins))))
	else
		pushf(o, "%04d (", ins)
	end
	return ctype
end

-- Recursively gather CALL* args and dump them.
local function dumpcallargs(o, tr, ins)
	if ins < 0 then
		pushf(o, formatk(tr, ins))
	else
		local m, ot, op1, op2 = jutil.traceir(tr, ins)		-- luacheck: ignore m
		local oidx = 6*shr(ot, 8)
		local op = vmdef.irnames:sub(oidx+1, oidx+6)
		if op == "CARG  " then
			dumpcallargs(o, tr, op1)
			if op2 < 0 then
				pushf(o, " "..formatk(tr, op2))
			else
				pushf(o, " %04d", op2)
			end
		else
			pushf(o, "%04d", ins)
		end
	end
end

-- Dump IR and interleaved snapshots.
local function dump_ir(tr)
	local dumpsnap, dumpreg = false, true
	local info = jutil.traceinfo(tr)
	if not info then return end
	local nins = info.nins
	local o = {}
	local irnames = vmdef.irnames
	local snapref = 65536
	local snap, snapno
	if dumpsnap then
		snap = jutil.tracesnap(tr, 0)
		snapref = snap[0]
		snapno = 0
	end
	for ins=1,nins do
		if ins >= snapref then
			if dumpreg then
				pushf (o, "....              SNAP   #%-3d [ ", snapno)
			else
				pushf (o, "....        SNAP   #%-3d [ ", snapno)
			end
			pushf (o, printsnap(tr, snap))
			snapno = snapno + 1
			snap = jutil.tracesnap(tr, snapno)
			snapref = snap and snap[0] or 65536
		end
		local m, ot, op1, op2, ridsp = jutil.traceir(tr, ins)
		local oidx, t = 6*shr(ot, 8), band(ot, 31)
		local op = irnames:sub(oidx+1, oidx+6)
		if op == "LOOP  " then
			if dumpreg then
				pushf (o, "%04d ------------ LOOP ------------\n", ins)
			else
				pushf (o, "%04d ------ LOOP ------------\n", ins)
			end
		elseif op ~= "NOP   " and op ~= "CARG  " and
			(dumpreg or op ~= "RENAME")
		then
			local rid = band(ridsp, 255)
			if dumpreg then
				pushf (o, "%04d %-6s", ins, ridsp_name(ridsp, ins))
			else
				pushf (o, "%04d ", ins)
			end
			pushf (o, "%s%s %s %s ",
					(rid == 254 or rid == 253) and "}" or
					(band(ot, 128) == 0 and " " or ">"),
					band(ot, 64) == 0 and " " or "+",
					irtype[t], op)
			local m1, m2 = band(m, 3), band(m, 3*4)
			if op:sub(1, 4) == "CALL" then
				local ctype
				if m2 == 1*4 then -- op2 == IRMlit
					pushf (o, "%-10s  (", vmdef.ircall[op2])
				else
					ctype = dumpcallfunc(o, tr, op2)
				end
				if op1 ~= -1 then dumpcallargs(o, tr, op1) end
				pushf(o, ")")
				if ctype then pushf(o, " ctype "..ctype) end
			elseif op == "CNEW  " and op2 == -1 then
				pushf(o, formatk(tr, op1))
			elseif m1 ~= 3 then -- op1 != IRMnone
				if op1 < 0 then
					pushf(o, formatk(tr, op1))
				else
					pushf(o, m1 == 0 and "%04d" or "#%-3d", op1)
				end
				if m2 ~= 3*4 then -- op2 != IRMnone
					if m2 == 1*4 then -- op2 == IRMlit
						local litn = litname[op]
						if litn and litn[op2] then
							pushf(o, "  "..litn[op2])
						elseif op == "UREFO " or op == "UREFC " then
							pushf (o, "  #%-3d", shr(op2, 8))
						else
							pushf (o, "  #%-3d", op2)
						end
					elseif op2 < 0 then
						pushf (o, "  "..formatk(tr, op2))
					else
						pushf (o, "  %04d", op2)
					end
				end
			end
			pushf (o, "\n")
		end
	end
	if snap then
		if dumpreg then
			pushf (o, "....              SNAP   #%-3d [ ", snapno)
		else
			pushf (o, "....        SNAP   #%-3d [ ", snapno)
		end
		printsnap(tr, snap)
	end
	return table.concat(o)
end


-- Format trace error message.
local function fmterr(err, info)
  if type(err) == "number" then
    if type(info) == "function" then info = fmtfunc(info) end
    err = vmdef.traceerr[err]:format(info)
  end
  return err
end


local function tracelabel(tr, func, pc, otr, oex)
	local startex = otr and "("..otr.."/"..oex..") " or ""
	local info = jutil.traceinfo(tr)
	if not info then return '-- uncompiled --' end

	local link, ltype = info.link, info.linktype
	if ltype == "interpreter" then
		return ("%s -- fallback to interpreter\n")
			:format(startex)
	elseif ltype == "stitch" then
		return ("%s %s [%s]\n")
			:format(startex, ltype, fmtfunc(func, pc))
	elseif link == tr or link == 0 then
		return ("%s %s\n")
			:format(startex, ltype)
	elseif ltype == "root" then
		return ("%s -> %d\n")
			:format(startex, link)
	else
		return ("%s -> %d %s\n")
			:format(startex, link, ltype)
	end
end

----

local loomstart, loomstop
do
	local collecting = {[0]=0}
	local function append(v)
		local c = collecting
		c[0] = c[0] + 1
		c[c[0]] = v
		return c[0]
	end

	local function collect_trace(what, tr, func, pc, otr, oex)
		append({'trace', what, tr, func, pc, otr, oex, ''})
	end

	local function collect_record(tr, func, pc, depth)
		append({'record', tr, func, pc, depth, ''})
	end

	local function collect_texit(tr, ex, ngpr, nfpr, ...)
		append({'texit', tr, ex, ngpr, nfpr, ...})
	end

	local function do_attachs()
		jit.attach(collect_trace, 'trace')
		jit.attach(collect_record, 'record')
		jit.attach(collect_texit, 'texit')
	end

	local function do_detachs()
		jit.attach(collect_texit)
		jit.attach(collect_record)
		jit.attach(collect_trace)
	end

	local traces_data, seen_funcs = {}, {}
	local prevexp_t = {
		trace = function (what, tr, func, pc, otr, oex)		-- luacheck: ignore func pc
			if what == 'start' then
				local mcode, addr, loop = jutil.tracemc(tr)	-- luacheck: ignore mcode loop
				if addr ~= nil then
					if otr and oex then
						symtab[addr] = ("Trace #%d (exit %d/%d)"):format(tr, otr, oex)
					else
						symtab[addr] = ("Trace #%d"):format(tr)
					end
				end
			end
		end,
		record = function() end,
		texit = function () end,
	}
	local function gettrace(tr)
		traces_data[tr] = traces_data[tr] or {
			evt = {},
			rec = {},
			n = {
				trace = 0,
				start = 0,
				stop = 0,
				abort = 0,
				flush = 0,
				record = 0,
				texit = 0,
			},
			exits = {},
		}
		return traces_data[tr]
	end

	local exp_trace_t = {
		start = function (tr, func, pc, otr, oex)	-- luacheck: ignore func pc
			local t = gettrace(tr)
			t.parent = t.parent or otr
			t.p_exit = t.p_exit or oex
		end,

		stop = function (tr, func, pc, otr, oex)	-- luacheck: ignore tr func pc otr oex
		end,

		abort = function (tr, func, pc, otr, oex)	-- luacheck: ignore func pc
			local t = gettrace(tr)
			t.err = t.err or fmterr(otr, oex)
		end,

		flush = function (tr, func, pc, otr, oex)	-- luacheck: ignore tr func pc otr oex
			symtab, nexitsym = {}, 0
		end,
	}
	local expand_t = {
		trace = function (what, tr, func, pc, otr, oex)
			seen_funcs[func] = true
			local t = gettrace(tr)
			t.n.trace = t.n.trace + 1
			t.n[what] = (t.n[what] or 0) + 1

			t.ir = t.ir or dump_ir(tr)
			t.snap = t.snap or dump_snap(tr)
			t.mcode = t.mcode or dump_mcode(tr)
			t.info = t.info or jutil.traceinfo(tr)
			t.tracelabel = t.tracelabel or tracelabel(tr, func, pc, otr, oex)

			t.evt[#t.evt +1] = {
				what, func, pc,
				what=='abort' and fmterr(otr, oex) or nil,
			}

			local expf = exp_trace_t[what]
			return expf and expf(tr, func, pc, otr, oex)
		end,

		record = function (tr, func, pc, depth)
			local t = gettrace(tr)
			t.n.record = t.n.record + 1
			seen_funcs[func] = true
			t.rec[#t.rec+1] = {func, pc, bcline(func, pc, (' .'):rep(depth))}
			if pc >= 0 and band(jutil.funcbc(func, pc), 0xff) < 16 then
				t.rec[#t.rec+1] = {func, pc+1, bcline(func, pc+1, (' .'):rep(depth))}
			end
		end,

		texit = function (tr, ex, ngpr, nfpr, ...)
			local t = gettrace(tr)
			t.n.texit = t.n.texit + 1
			t.exits[ex] = (t.exits[ex] or 0) + 1
			t.evt[#t.evt+1] = {'exit', ex, ngpr, nfpr, ...}
		end,
	}

	function loomstart(clear)
		if clear then
			traces_data, seen_funcs = {}, {}
			collecting = {[0]=0}
		end
		do_attachs()
	end

	function loomstop(f, ...)
		do_detachs()
		for _, v in ipairs(collecting) do
			prevexp_t[v[1]](unpack(v, 2, table.maxn(v)))
		end
		for _, v in ipairs(collecting) do
			expand_t[v[1]](unpack(v, 2, table.maxn(v)))
		end
		local funcslist = {}
		for fun in pairs(seen_funcs) do
			funcslist[#funcslist+1] = fun
		end
		if f then
			return f(traces_data, funcslist, ...)
		end
		return traces_data, funcslist
	end
end
--------------------------------------
local function srclines(fn)
	local t, f = {}, io.open(fn)
	if f then
		for l in f:lines() do
			t[#t+1] = l
		end
		f:close()
	end
	return t
end

local function annotated(funcs, traces)
	local starts = {}
	for _, f in ipairs(funcs) do
		for _, fi in pairs(func_bc(f)) do
			starts[#starts+1] = {fi.currentline or 0, fi}
		end
	end
	table.sort(starts, function(a, b) return a[1]<b[1] end)
	for i, v in ipairs(starts) do
		starts[i] = v[2]
	end

	local srcs = {}
	local o, lastline = {}, 0
	for _, fi in ipairs(starts) do
		if fi.source and type(fi.func)=='function' then
			local srcname = fi.source:gsub('^@', '')
			srcs[srcname] = srcs[srcname] or srclines(srcname)
			o[srcname] = o[srcname] or {}
			local src, of = srcs[srcname], o[srcname]

			for pc, l in sortedpairs(fi.bytecode) do
				local lnum, bc = unpack(l)			-- luacheck: ignore bc
				for i = lastline+1, lnum-1 do
					of[#of+1] = {
						i = i,
						src = src[i],
						func = fi.func,
						pc = pc,
						bc = '',
						back = i<lastline,
						tr = {},
						evt = {},
					}
				end
				of[#of+1] = {
					i = lnum,
					src = src[lnum],
					func = fi.func,
					pc = pc,
					bc = bc,
					back = lnum<lastline,
					tr = {},
					evt = {},
				}
				lastline = math.max(lastline, lnum)
			end
		end
	end

	for i, tr in allipairs(traces) do
		for j, rec in ipairs(tr.rec) do
			local f, pc, bcl = unpack (rec)			-- luacheck: ignore bcl
			for srcname, osrc in pairs(o) do		-- luacheck: ignore srcname
				for _, ol in ipairs(osrc) do
					if ol.func == f and ol.pc == pc and #ol.bc>0 then
						ol.tr[#ol.tr+1] = {i, j}
						break
					end
				end
			end
		end
		for _, evt in ipairs(tr.evt) do
			local what, func, pc, msg = unpack(evt)
			for srcname, osrc in pairs(o) do		-- luacheck: ignore srcname
				for _, ol in ipairs(osrc) do
					if ol.func == func and ol.pc == pc and #ol.bc>0 then
						local k = msg or what
						ol.evt[k] = (ol.evt[k] or 0) + 1
					end
				end
			end
		end
	end
	return o
end

--------------------------------------

local template = require 'template'
local defer

return {
	on = loomstart,
	off = loomstop,

	start = function (opt, out)
		local tmpl = template(opt or 'loom.html')
		defer = newproxy(true)
		getmetatable(defer).__gc = xpcall(function ()
			local o = loomstop(tmpl)
			out = type(out)=='string' and assert(io.open(out, 'w'))
					or out or io.stdout
			out:write(o)
		end, function(err) print(debug.traceback(err)) end)

		loomstart()
	end,

	template = template,
	annotated = annotated,
	allipairs = allipairs,
	sortedpairs = sortedpairs,
}
