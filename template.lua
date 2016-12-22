--[[
    derived from:
		https://github.com/dannote/lua-template/blob/master/template.lua
	by Danila Poyarkov
--]]

local _esc = {
	['&'] = '&amp;',
	['<'] = '&lt;',
	['>'] = '&gt;',
	['"'] = '&quot;',
	["'"] = '&#39;',
	['/'] = '&#47;'
}
local function escape(s)
  return tostring(s or ''):gsub("[\">/<'&]", _esc)
end

return function (tpl, ...)
	local src = (
		'local __e__, %s = ... ' ..
		'local __o__ = {} ' ..
		'local function __p__(x) __o__[#__o__+1] = tostring(x or "") end ' ..
		'local function __fp__(f, ...) __p__(f:format(...)) end '..
		'local function __ep__(x) __p__(__e__(x)) end ' ..
		'__p__[=[%s]=] ' ..
		'return table.concat(__o__)')
	:format(
		table.concat({...}, ', '),
		tpl
			:gsub('[][]=[][]', ']=] __p__"%1" __p__[=[')
			:gsub('{{=', ']=] __p__(')
			:gsub('{{:', ']=] __fp__(')
			:gsub('{{', ']=] __ep__(')
			:gsub('}}', ') __p__[=[')
			:gsub('{%%', ']=] ')
			:gsub('%%}', ' __p__[=[')
	)
-- 	io.stderr:write (src, '\n')
	local f = assert(loadstring(src))
	return function (...)
		return f(escape, ...)
	end
end
