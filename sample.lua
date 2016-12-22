local Sm = {}

function Sm.lulu()
	for i = 1, 1000 do
		for j = 1, 1000 do
		end
	end
end

function Sm.motivating_example_1()
	local x, z = 0, nil
	for i=1,100 do
		local t = {i}
		if i == 90 then
			z = t
		end
		x = x + t[1]
	end
	print(x, z[1])
end

function Sm.resinking()
	local z = nil
	for i=1,200 do
		local t = {i}
		if i > 100 then
			if i == 190 then z = t end
		end
	end
	print(z[1])
end

function Sm.pointadds()
	local point
	point = {
		new = function(self, x, y)
			return setmetatable({x=x, y=y}, self)
		end,
		__add = function(a, b)
			return point:new(a.x + b.x, a.y + b.y)
		end,
	}
	point.__index = point
	local a, b = point:new(1.5, 2.5), point:new(3.25, 4.75)
	for i=1,100000000 do a = (a + b) + b end
	print(a.x, a.y)
end

function Sm.tdup(x)
	return { foo=1, bar=2, 1,2,x,4 }
end

function Sm.miltdup(x)
	for i=1,1000 do Sm.tdup(i) end
end

function Sm.call_some()
	print ("one")
	Sm.motivating_example_1()
	print ("end")
end


return Sm
