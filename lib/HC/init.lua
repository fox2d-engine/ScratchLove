---HardonCollider (HC) main module
---2D collision detection library for Lua/Love2D
---Provides shapes, spatial hashing, and collision detection

--[[
Copyright (c) 2011 Matthias Richter

Permission is hereby granted, free of charge, to any person obtaining a copy
of this software and associated documentation files (the "Software"), to deal
in the Software without restriction, including without limitation the rights
to use, copy, modify, merge, publish, distribute, sublicense, and/or sell
copies of the Software, and to permit persons to whom the Software is
furnished to do so, subject to the following conditions:

The above copyright notice and this permission notice shall be included in
all copies or substantial portions of the Software.

Except as contained in this notice, the name(s) of the above copyright holders
shall not be used in advertising or otherwise to promote the sale, use or
other dealings in this Software without prior written authorization.

THE SOFTWARE IS PROVIDED "AS IS", WITHOUT WARRANTY OF ANY KIND, EXPRESS OR
IMPLIED, INCLUDING BUT NOT LIMITED TO THE WARRANTIES OF MERCHANTABILITY,
FITNESS FOR A PARTICULAR PURPOSE AND NONINFRINGEMENT. IN NO EVENT SHALL THE
AUTHORS OR COPYRIGHT HOLDERS BE LIABLE FOR ANY CLAIM, DAMAGES OR OTHER
LIABILITY, WHETHER IN AN ACTION OF CONTRACT, TORT OR OTHERWISE, ARISING FROM,
OUT OF OR IN CONNECTION WITH THE SOFTWARE OR THE USE OR OTHER DEALINGS IN
THE SOFTWARE.
]]--

---@type string
---@type table
local _NAME, common_local = ..., common
if not (type(common) == 'table' and common.class and common.instance) then
	assert(common_class ~= false, 'No class commons specification available.')
	require(_NAME .. '.class')
end
local Shapes      = require(_NAME .. '.shapes')
local Spatialhash = require(_NAME .. '.spatialhash')

-- reset global table `common' (required by class commons)
if common_local ~= common then
	common_local, common = common, common_local
end

local newPolygonShape = Shapes.newPolygonShape
local newCircleShape  = Shapes.newCircleShape
local newPointShape   = Shapes.newPointShape

---@class HC_Collider
---@field _hash HC_Spatialhash Spatial hash for collision detection
---@field init function Constructor
---@field hash function Get spatial hash instance
---@field resetHash function Reset spatial hash with new cell size
---@field register function Register shape in collision system
---@field remove function Remove shape from collision system
---@field polygon function Create polygon shape
---@field rectangle function Create rectangle shape
---@field circle function Create circle shape
---@field point function Create point shape
---@field neighbors function Get neighboring shapes
---@field collisions function Get colliding shapes
---@field raycast function Cast ray and find intersections
---@field shapesAt function Find shapes at given point

---Main HardonCollider class
local HC = {}

---Initialize collision system with spatial hash
---@param cell_size? number Spatial hash cell size (defaults to 100)
function HC:init(cell_size)
  self:resetHash(cell_size)
end

---Get spatial hash instance
---@return HC_Spatialhash hash The spatial hash
function HC:hash() return self._hash end -- consistent interface with global HC instance

---Reset spatial hash with new cell size
---@param cell_size? number New cell size (defaults to 100)
---@return HC_Collider self For method chaining
function HC:resetHash(cell_size)
	self._hash = common_local.instance(Spatialhash, cell_size or 100)
	return self
end

---Register shape in collision system and set up automatic spatial hash updates
---@param shape HC_Shape Shape to register
---@return HC_Shape shape The registered shape (for chaining)
function HC:register(shape)
	self._hash:register(shape, shape:bbox())

	-- keep track of where/how big the shape is
	for _, f in ipairs({'move', 'rotate', 'scale'}) do
		local old_function = shape[f]
		shape[f] = function(this, ...)
			local x1,y1,x2,y2 = this:bbox()
			old_function(this, ...)
			self._hash:update(this, x1,y1,x2,y2, this:bbox())
			return this
		end
	end

	return shape
end

---Remove shape from collision system
---@param shape HC_Shape Shape to remove
---@return HC_Collider self For method chaining
function HC:remove(shape)
	self._hash:remove(shape, shape:bbox())
	for _, f in ipairs({'move', 'rotate', 'scale'}) do
		shape[f] = function()
			error(f.."() called on a removed shape")
		end
	end
	return self
end

---Create and register polygon shape
---@param ... number Coordinate pairs (x1, y1, x2, y2, ...)
---@return HC_ConvexPolygonShape|HC_ConcavePolygonShape polygon New polygon shape
function HC:polygon(...)
	return self:register(newPolygonShape(...))
end

---Create and register rectangle shape
---@param x number Left edge X coordinate
---@param y number Top edge Y coordinate
---@param w number Width
---@param h number Height
---@return HC_ConvexPolygonShape rectangle New rectangle shape
function HC:rectangle(x,y,w,h)
	return self:polygon(x,y, x+w,y, x+w,y+h, x,y+h)
end

---Create and register circle shape
---@param x number Center X coordinate
---@param y number Center Y coordinate
---@param r number Radius
---@return HC_CircleShape circle New circle shape
function HC:circle(x,y,r)
	return self:register(newCircleShape(x,y,r))
end

---Create and register point shape
---@param x number Point X coordinate
---@param y number Point Y coordinate
---@return HC_PointShape point New point shape
function HC:point(x,y)
	return self:register(newPointShape(x,y))
end

---Get all shapes that could potentially collide with given shape
---@param shape HC_Shape Shape to find neighbors for
---@return table<HC_Shape, HC_Shape> neighbors Set of neighboring shapes
function HC:neighbors(shape)
	local neighbors = self._hash:inSameCells(shape:bbox())
	rawset(neighbors, shape, nil)
	return neighbors
end

---Get all shapes colliding with given shape and their separation vectors
---@param shape HC_Shape Shape to test collisions for
---@return table<HC_Shape, HC_CollisionResult> collisions Map of colliding shapes to separation vectors
function HC:collisions(shape)
	local candidates = self:neighbors(shape)
	for other in pairs(candidates) do
		local collides, dx, dy = shape:collidesWith(other)
		if collides then
			rawset(candidates, other, {dx,dy, x=dx, y=dy})
		else
			rawset(candidates, other, nil)
		end
	end
	return candidates
end

---Cast a ray and find all intersecting shapes within range
---@param x number Ray origin X coordinate
---@param y number Ray origin Y coordinate
---@param dx number Ray direction X component (normalized)
---@param dy number Ray direction Y component (normalized)
---@param range number Maximum ray distance
---@return table<HC_Shape, HC_IntersectionPoint[]> intersections Map of shapes to intersection points
function HC:raycast(x, y, dx, dy, range)
	local dxr, dyr = dx * range, dy * range
	local bbox = { x + dxr , y + dyr, x, y }
	local candidates = self._hash:inSameCells(unpack(bbox))

	for col in pairs(candidates) do
		local rparams = col:intersectionsWithRay(x, y, dx, dy)
		if #rparams > 0 then
			for i, rparam in pairs(rparams) do
				if rparam < 0 or rparam > range then
					rawset(rparams, i, nil)
				else
					local hitx, hity = x + (rparam * dx), y + (rparam * dy)
					rawset(rparams, i, { x = hitx, y = hity })
				end
			end
			rawset(candidates, col, rparams)
		else
			rawset(candidates, col, nil)
		end
	end
	return candidates
end

---Find all shapes that contain the given point
---@param x number Point X coordinate
---@param y number Point Y coordinate
---@return table<HC_Shape, HC_Shape> shapes Set of shapes containing the point
function HC:shapesAt(x, y)
	local candidates = {}
	for c in pairs(self._hash:cellAt(x, y)) do
		if c:contains(x, y) then
			rawset(candidates, c, c)
		end
	end
	return candidates
end

-- Create the class and default instance
HC = common_local.class('HardonCollider', HC)
---@type HC_Collider
local instance = common_local.instance(HC)

---HardonCollider module with both class and instance methods
---@class HC_Module
---@field new function Create new HC instance
---@field resetHash function Reset spatial hash (instance method)
---@field register function Register shape (instance method)
---@field remove function Remove shape (instance method)
---@field polygon function Create polygon (instance method)
---@field rectangle function Create rectangle (instance method)
---@field circle function Create circle (instance method)
---@field point function Create point (instance method)
---@field neighbors function Get neighbors (instance method)
---@field collisions function Get collisions (instance method)
---@field shapesAt function Get shapes at point (instance method)
---@field hash function Get spatial hash (instance method)
---@overload fun(...): HC_Collider
return setmetatable({
	---Create new HC collider instance
	---@param ... any Constructor arguments
	---@return HC_Collider collider New collider instance
	new       = function(...) return common_local.instance(HC, ...) end,
	resetHash = function(...) return instance:resetHash(...) end,
	register  = function(...) return instance:register(...) end,
	remove    = function(...) return instance:remove(...) end,

	polygon   = function(...) return instance:polygon(...) end,
	rectangle = function(...) return instance:rectangle(...) end,
	circle    = function(...) return instance:circle(...) end,
	point     = function(...) return instance:point(...) end,

	neighbors  = function(...) return instance:neighbors(...) end,
	collisions = function(...) return instance:collisions(...) end,
	shapesAt   = function(...) return instance:shapesAt(...) end,
	hash       = function() return instance.hash() end,
}, {__call = function(_, ...) return common_local.instance(HC, ...) end})
