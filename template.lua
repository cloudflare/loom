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
}
local function escape(s)
  return tostring(s or ''):gsub('[><&"]', _esc)
end

return function (tpl)
	local tplname = 'tmpl'
	if not tpl:find('\n', 1, true) then
		tplname = tpl
		local f = assert(io.open(tpl))
		tpl = assert(f:read('*a'))
		f:close()
	end

	local args = {'_e'}
	tpl = tpl:gsub('{{@(.-)}}', function (argl)
		argl:gsub('([_%a][_%w]*)', function (a) args[#args+1] = a return '' end)
		return ''
	end)

	local src = (
		'local %s = ... ' ..
		'local _o = {} ' ..
		'local function _p(x) _o[#_o+1] = tostring(x or "") end ' ..
		'local function _fp(f, ...) _p(f:format(...)) end '..
		'local function _ep(x) _p(_e(x)) end ' ..
		'_p[=[%s]=] ' ..
		'return table.concat(_o)')
	:format(
		table.concat(args, ', '),
		tpl
			:gsub('[][]=[][]', ']=] _p"%1" _p[=[')
			:gsub('{{=', ']=] _p(')
			:gsub('{{:', ']=] _fp(')
			:gsub('{{', ']=] _ep(')
			:gsub('}}', ') _p[=[')
			:gsub('{%%', ']=] ')
			:gsub('%%}', ' _p[=[')
	)
	local f = assert(loadstring(src, tplname))
	return function (...)
		return f(escape, ...)
	end
end
