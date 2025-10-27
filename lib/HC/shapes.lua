---HC collision shapes module
---Provides various geometric shapes for collision detection
---Including convex/concave polygons, circles, and points

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

---@type fun(a: number, b: number): number
---@type fun(x: number): number
---@type number
local math_min, math_sqrt, math_huge = math.min, math.sqrt, math.huge

local _PACKAGE, common_local = (...):match("^(.+)%.[^%.]+"), common
if not (type(common) == 'table' and common.class and common.instance) then
	assert(common_class ~= false, 'No class commons specification available.')
	require(_PACKAGE .. '.class')
end
local vector  = require(_PACKAGE .. '.vector-light')
local Polygon = require(_PACKAGE .. '.polygon')
local GJK     = require(_PACKAGE .. '.gjk') -- actual collision detection

---@class HC_Vector
---@field x number X coordinate
---@field y number Y coordinate

---@class HC_BoundingBox
---@field [1] number Minimum X coordinate
---@field [2] number Minimum Y coordinate
---@field [3] number Maximum X coordinate
---@field [4] number Maximum Y coordinate

---@class HC_CollisionResult
---@field [1] number Separation vector X component
---@field [2] number Separation vector Y component
---@field x number Separation vector X component (alias)
---@field y number Separation vector Y component (alias)

---@class HC_IntersectionPoint
---@field x number Intersection X coordinate
---@field y number Intersection Y coordinate

-- reset global table `common' (required by class commons)
if common_local ~= common then
	common_local, common = common, common_local
end

---@class HC_Shape
---@field _type string Shape type identifier
---@field _rotation number Current rotation angle in radians
---@field init function Constructor
---@field moveTo function Move shape to absolute position
---@field rotation function Get current rotation
---@field rotate function Rotate by angle
---@field setRotation function Set absolute rotation
---@field center function Get shape center coordinates
---@field bbox function Get bounding box
---@field move function Move by offset
---@field scale function Scale shape
---@field contains function Check if point is inside shape
---@field collidesWith function Check collision with another shape
---@field support function Get support point in direction (GJK)
---@field intersectsRay function Check ray intersection
---@field intersectionsWithRay function Get all ray intersections
---@field outcircle function Get bounding circle
---@field draw function Draw shape (Love2D)

---Base class for all collision shapes
local Shape = {}

---Initialize base shape properties
---@param t string Shape type identifier
function Shape:init(t)
	self._type = t
	self._rotation = 0
end

---Move shape to absolute position
---@param x number Target X coordinate
---@param y number Target Y coordinate
function Shape:moveTo(x,y)
	local cx,cy = self:center()
	self:move(x - cx, y - cy)
end

---Get current rotation angle
---@return number rotation Current rotation in radians
function Shape:rotation()
	return self._rotation
end

---Rotate shape by additional angle
---@param angle number Rotation angle in radians
function Shape:rotate(angle)
	self._rotation = self._rotation + angle
end

---Set absolute rotation angle
---@param angle number Target rotation in radians
---@param x? number Optional rotation center X
---@param y? number Optional rotation center Y
---@return any result Result of rotation operation
function Shape:setRotation(angle, x,y)
	return self:rotate(angle - self._rotation, x,y)
end

---@class HC_Polygon
---@field vertices HC_Vector[]
---@field isConvex function
---@field splitConvex function
---@field contains function
---@field intersectsRay function
---@field intersectionsWithRay function
---@field bbox function
---@field move function
---@field rotate function
---@field scale function
---@field centroid HC_Vector

---@class HC_ConvexPolygonShape : HC_Shape
---@field _polygon HC_Polygon The underlying polygon
local ConvexPolygonShape = {}

---Initialize convex polygon shape
---@param polygon HC_Polygon Must be a convex polygon
function ConvexPolygonShape:init(polygon)
	Shape.init(self, 'polygon')
	assert(polygon:isConvex(), "Polygon is not convex.")
	self._polygon = polygon
end

---@class HC_ConcavePolygonShape : HC_Shape
---@field _polygon HC_Polygon The underlying polygon
---@field _shapes HC_ConvexPolygonShape[] Convex decomposition of the polygon
local ConcavePolygonShape = {}

---Initialize concave polygon shape
---@param poly HC_Polygon Can be any polygon (convex or concave)
function ConcavePolygonShape:init(poly)
	Shape.init(self, 'compound')
	self._polygon = poly
	self._shapes = poly:splitConvex()
	for i,s in ipairs(self._shapes) do
		self._shapes[i] = common_local.instance(ConvexPolygonShape, s)
	end
end

---@class HC_CircleShape : HC_Shape
---@field _center HC_Vector Circle center coordinates
---@field _radius number Circle radius
local CircleShape = {}

---Initialize circle shape
---@param cx number Center X coordinate
---@param cy number Center Y coordinate
---@param radius number Circle radius
function CircleShape:init(cx,cy, radius)
	Shape.init(self, 'circle')
	self._center = {x = cx, y = cy}
	self._radius = radius
end

---@class HC_PointShape : HC_Shape
---@field _pos HC_Vector Point coordinates
local PointShape = {}

---Initialize point shape
---@param x number Point X coordinate
---@param y number Point Y coordinate
function PointShape:init(x,y)
	Shape.init(self, 'point')
	self._pos = {x = x, y = y}
end

---Get support point in given direction (for GJK algorithm)
---@param dx number Direction X component
---@param dy number Direction Y component
---@return number x Support point X coordinate
---@return number y Support point Y coordinate
function ConvexPolygonShape:support(dx,dy)
	local v = self._polygon.vertices
	local max, vmax = -math_huge
	for i = 1,#v do
		local d = vector.dot(v[i].x,v[i].y, dx,dy)
		if d > max then
			max, vmax = d, v[i]
		end
	end
	return vmax.x, vmax.y
end

---Get support point in given direction (for GJK algorithm)
---@param dx number Direction X component
---@param dy number Direction Y component
---@return number x Support point X coordinate
---@return number y Support point Y coordinate
function CircleShape:support(dx,dy)
	return vector.add(self._center.x, self._center.y,
		vector.mul(self._radius, vector.normalize(dx,dy)))
end

---Check collision with another shape
---@param other HC_Shape Other shape to test collision with
---@return boolean collides True if shapes are colliding
---@return number? separation_x X component of separation vector (if colliding)
---@return number? separation_y Y component of separation vector (if colliding)
function ConvexPolygonShape:collidesWith(other)
	if self == other then return false end
	if other._type ~= 'polygon' then
		local collide, sx,sy = other:collidesWith(self)
		return collide, sx and -sx, sy and -sy
	end

	-- else: type is POLYGON
	return GJK(self, other)
end

---Check collision with another shape using convex decomposition
---@param other HC_Shape Other shape to test collision with
---@return boolean collides True if shapes are colliding
---@return number? separation_x X component of separation vector (if colliding)
---@return number? separation_y Y component of separation vector (if colliding)
function ConcavePolygonShape:collidesWith(other)
	if self == other then return false end
	if other._type == 'point' then
		return other:collidesWith(self)
	end

	-- TODO: better way of doing this. report all the separations?
	local collide,dx,dy = false,0,0
	for _,s in ipairs(self._shapes) do
		local status, sx,sy = s:collidesWith(other)
		collide = collide or status
		if status then
			if math.abs(dx) < math.abs(sx) then
				dx = sx
			end
			if math.abs(dy) < math.abs(sy) then
				dy = sy
			end
		end
	end
	return collide, dx, dy
end

---Check collision with another shape
---@param other HC_Shape Other shape to test collision with
---@return boolean collides True if shapes are colliding
---@return number? separation_x X component of separation vector (if colliding)
---@return number? separation_y Y component of separation vector (if colliding)
function CircleShape:collidesWith(other)
	if self == other then return false end
	if other._type == 'circle' then
		local px,py = self._center.x-other._center.x, self._center.y-other._center.y
		local d = vector.len2(px,py)
		local radii = self._radius + other._radius
		if d < radii*radii then
			-- if circles overlap, push it out upwards
			if d == 0 then return true, 0,radii end
			-- otherwise push out in best direction
			return true, vector.mul(radii - math_sqrt(d), vector.normalize(px,py))
		end
		return false
	elseif other._type == 'polygon' then
		return GJK(self, other)
	end

	-- else: let the other shape decide
	local collide, sx,sy = other:collidesWith(self)
	return collide, sx and -sx, sy and -sy
end

---Check collision with another shape
---@param other HC_Shape Other shape to test collision with
---@return boolean collides True if shapes are colliding
---@return number separation_x Always 0 for point collisions
---@return number separation_y Always 0 for point collisions
function PointShape:collidesWith(other)
	if self == other then return false end
	if other._type == 'point' then
		return (self._pos == other._pos), 0,0
	end
	return other:contains(self._pos.x, self._pos.y), 0,0
end

---Check if point is inside shape
---@param x number Point X coordinate
---@param y number Point Y coordinate
---@return boolean inside True if point is inside the shape
function ConvexPolygonShape:contains(x,y)
	return self._polygon:contains(x,y)
end

---Check if point is inside shape
---@param x number Point X coordinate
---@param y number Point Y coordinate
---@return boolean inside True if point is inside the shape
function ConcavePolygonShape:contains(x,y)
	return self._polygon:contains(x,y)
end

---Check if point is inside circle
---@param x number Point X coordinate
---@param y number Point Y coordinate
---@return boolean inside True if point is inside the circle
function CircleShape:contains(x,y)
	return vector.len2(x-self._center.x, y-self._center.y) < self._radius * self._radius
end

---Check if point is at exact same position
---@param x number Point X coordinate
---@param y number Point Y coordinate
---@return boolean same True if point is at the same position
function PointShape:contains(x,y)
	return x == self._pos.x and y == self._pos.y
end


---Check if ray intersects with shape
---@param x number Ray origin X coordinate
---@param y number Ray origin Y coordinate
---@param dx number Ray direction X component
---@param dy number Ray direction Y component
---@return boolean intersects True if ray intersects the shape
---@return number? t Parameter t where intersection occurs
function ConcavePolygonShape:intersectsRay(x,y, dx,dy)
	return self._polygon:intersectsRay(x,y, dx,dy)
end

---Check if ray intersects with shape
---@param x number Ray origin X coordinate
---@param y number Ray origin Y coordinate
---@param dx number Ray direction X component
---@param dy number Ray direction Y component
---@return boolean intersects True if ray intersects the shape
---@return number? t Parameter t where intersection occurs
function ConvexPolygonShape:intersectsRay(x,y, dx,dy)
	return self._polygon:intersectsRay(x,y, dx,dy)
end

---Get all intersection points with ray
---@param x number Ray origin X coordinate
---@param y number Ray origin Y coordinate
---@param dx number Ray direction X component
---@param dy number Ray direction Y component
---@return number[] t_values Array of t parameters where intersections occur
function ConcavePolygonShape:intersectionsWithRay(x,y, dx,dy)
	return self._polygon:intersectionsWithRay(x,y, dx,dy)
end

---Get all intersection points with ray
---@param x number Ray origin X coordinate
---@param y number Ray origin Y coordinate
---@param dx number Ray direction X component
---@param dy number Ray direction Y component
---@return number[] t_values Array of t parameters where intersections occur
function ConvexPolygonShape:intersectionsWithRay(x,y, dx,dy)
	return self._polygon:intersectionsWithRay(x,y, dx,dy)
end

---Get all intersection points with ray using quadratic formula
---Circle intersection if distance of ray/center is smaller than radius.
---With r(s) = p + d*s = (x,y) + (dx,dy) * s defining the ray and
---(x - cx)^2 + (y - cy)^2 = r^2, this problem is equivalent to solving:
---d*d s^2 + 2 d*(p-c) s + (p-c)*(p-c)-r^2 = 0
---@param x number Ray origin X coordinate
---@param y number Ray origin Y coordinate
---@param dx number Ray direction X component
---@param dy number Ray direction Y component
---@return number[] t_values Array of t parameters where intersections occur
function CircleShape:intersectionsWithRay(x,y, dx,dy)
	local pcx,pcy = x-self._center.x, y-self._center.y

	local a = vector.len2(dx,dy)
	local b = 2 * vector.dot(dx,dy, pcx,pcy)
	local c = vector.len2(pcx,pcy) - self._radius * self._radius
	local discr = b*b - 4*a*c

	if discr < 0 then return {} end

	discr = math_sqrt(discr)
	local ts, t1, t2 = {}, discr-b, -discr-b
	if t1 >= 0 then ts[#ts+1] = t1/(2*a) end
	if t2 >= 0 then ts[#ts+1] = t2/(2*a) end
	return ts
end

---Check if ray intersects with circle
---@param x number Ray origin X coordinate
---@param y number Ray origin Y coordinate
---@param dx number Ray direction X component
---@param dy number Ray direction Y component
---@return boolean intersects True if ray intersects the circle
---@return number t Minimum t parameter where intersection occurs
function CircleShape:intersectsRay(x,y, dx,dy)
	local tmin = math_huge
	for _, t in ipairs(self:intersectionsWithRay(x,y,dx,dy)) do
		tmin = math_min(t, tmin)
	end
	return tmin ~= math_huge, tmin
end

---Check if point lies on the ray
---@param x number Ray origin X coordinate
---@param y number Ray origin Y coordinate
---@param dx number Ray direction X component
---@param dy number Ray direction Y component
---@return boolean intersects True if point lies on the ray
---@return number t Parameter t where point lies on ray
function PointShape:intersectsRay(x,y, dx,dy)
	local px,py = self._pos.x-x, self._pos.y-y
	local t = px/dx
	-- see (px,py) and (dx,dy) point in same direction
	return (t == py/dy), t
end

---Get intersection with ray (single point if on ray)
---@param x number Ray origin X coordinate
---@param y number Ray origin Y coordinate
---@param dx number Ray direction X component
---@param dy number Ray direction Y component
---@return number[] t_values Array with single t value if point is on ray, empty otherwise
function PointShape:intersectionsWithRay(x,y, dx,dy)
	local intersects, t = self:intersectsRay(x,y, dx,dy)
	return intersects and {t} or {}
end

---Get shape center coordinates
---@return number x Center X coordinate
---@return number y Center Y coordinate
function ConvexPolygonShape:center()
	return self._polygon.centroid.x, self._polygon.centroid.y
end

---Get shape center coordinates
---@return number x Center X coordinate
---@return number y Center Y coordinate
function ConcavePolygonShape:center()
	return self._polygon.centroid.x, self._polygon.centroid.y
end

---Get circle center coordinates
---@return number x Center X coordinate
---@return number y Center Y coordinate
function CircleShape:center()
	return self._center.x, self._center.y
end

---Get point coordinates
---@return number x Point X coordinate
---@return number y Point Y coordinate
function PointShape:center()
	return self._pos.x, self._pos.y
end

---Get bounding circle (center and radius)
---@return number x Center X coordinate
---@return number y Center Y coordinate
---@return number radius Bounding circle radius
function ConvexPolygonShape:outcircle()
	local cx,cy = self:center()
	return cx,cy, self._polygon._radius
end

---Get bounding circle (center and radius)
---@return number x Center X coordinate
---@return number y Center Y coordinate
---@return number radius Bounding circle radius
function ConcavePolygonShape:outcircle()
	local cx,cy = self:center()
	return cx,cy, self._polygon._radius
end

---Get circle parameters (same as the circle itself)
---@return number x Center X coordinate
---@return number y Center Y coordinate
---@return number radius Circle radius
function CircleShape:outcircle()
	local cx,cy = self:center()
	return cx,cy, self._radius
end

---Get point bounding circle (radius 0)
---@return number x Point X coordinate
---@return number y Point Y coordinate
---@return number radius Always 0 for points
function PointShape:outcircle()
	return self._pos.x, self._pos.y, 0
end

---Get axis-aligned bounding box
---@return number min_x Minimum X coordinate
---@return number min_y Minimum Y coordinate
---@return number max_x Maximum X coordinate
---@return number max_y Maximum Y coordinate
function ConvexPolygonShape:bbox()
	return self._polygon:bbox()
end

---Get axis-aligned bounding box
---@return number min_x Minimum X coordinate
---@return number min_y Minimum Y coordinate
---@return number max_x Maximum X coordinate
---@return number max_y Maximum Y coordinate
function ConcavePolygonShape:bbox()
	return self._polygon:bbox()
end

---Get axis-aligned bounding box
---@return number min_x Minimum X coordinate
---@return number min_y Minimum Y coordinate
---@return number max_x Maximum X coordinate
---@return number max_y Maximum Y coordinate
function CircleShape:bbox()
	local cx,cy = self:center()
	local r = self._radius
	return cx-r,cy-r, cx+r,cy+r
end

---Get axis-aligned bounding box (same point for min and max)
---@return number min_x Point X coordinate
---@return number min_y Point Y coordinate
---@return number max_x Point X coordinate (same as min)
---@return number max_y Point Y coordinate (same as min)
function PointShape:bbox()
	local x,y = self:center()
	return x,y,x,y
end


---Move shape by offset
---@param x number X offset
---@param y number Y offset
function ConvexPolygonShape:move(x,y)
	self._polygon:move(x,y)
end

---Move shape by offset (includes all convex parts)
---@param x number X offset
---@param y number Y offset
function ConcavePolygonShape:move(x,y)
	self._polygon:move(x,y)
	for _,p in ipairs(self._shapes) do
		p:move(x,y)
	end
end

---Move circle by offset
---@param x number X offset
---@param y number Y offset
function CircleShape:move(x,y)
	self._center.x = self._center.x + x
	self._center.y = self._center.y + y
end

---Move point by offset
---@param x number X offset
---@param y number Y offset
function PointShape:move(x,y)
	self._pos.x = self._pos.x + x
	self._pos.y = self._pos.y + y
end


---Rotate shape around center point
---@param angle number Rotation angle in radians
---@param cx? number Rotation center X (defaults to shape center)
---@param cy? number Rotation center Y (defaults to shape center)
function ConcavePolygonShape:rotate(angle,cx,cy)
	Shape.rotate(self, angle)
	if not (cx and cy) then
		cx,cy = self:center()
	end
	self._polygon:rotate(angle,cx,cy)
	for _,p in ipairs(self._shapes) do
		p:rotate(angle, cx,cy)
	end
end

---Rotate polygon around center point
---@param angle number Rotation angle in radians
---@param cx? number Rotation center X
---@param cy? number Rotation center Y
function ConvexPolygonShape:rotate(angle, cx,cy)
	Shape.rotate(self, angle)
	self._polygon:rotate(angle, cx, cy)
end

---Rotate circle around center point (only affects position, not shape)
---@param angle number Rotation angle in radians
---@param cx? number Rotation center X
---@param cy? number Rotation center Y
function CircleShape:rotate(angle, cx,cy)
	Shape.rotate(self, angle)
	if not (cx and cy) then return end
	self._center.x,self._center.y = vector.add(cx,cy, vector.rotate(angle, self._center.x-cx, self._center.y-cy))
end

---Rotate point around center point
---@param angle number Rotation angle in radians
---@param cx? number Rotation center X
---@param cy? number Rotation center Y
function PointShape:rotate(angle, cx,cy)
	Shape.rotate(self, angle)
	if not (cx and cy) then return end
	self._pos.x,self._pos.y = vector.add(cx,cy, vector.rotate(angle, self._pos.x-cx, self._pos.y-cy))
end


---Scale shape by factor around center
---@param s number Scale factor (must be > 0)
function ConcavePolygonShape:scale(s)
	assert(type(s) == "number" and s > 0, "Invalid argument. Scale must be greater than 0")
	local cx,cy = self:center()
	self._polygon:scale(s, cx,cy)
	for _, p in ipairs(self._shapes) do
		local dx,dy = vector.sub(cx,cy, p:center())
		p:scale(s)
		p:moveTo(cx-dx*s, cy-dy*s)
	end
end

---Scale polygon by factor around center
---@param s number Scale factor (must be > 0)
function ConvexPolygonShape:scale(s)
	assert(type(s) == "number" and s > 0, "Invalid argument. Scale must be greater than 0")
	self._polygon:scale(s, self:center())
end

---Scale circle radius by factor
---@param s number Scale factor (must be > 0)
function CircleShape:scale(s)
	assert(type(s) == "number" and s > 0, "Invalid argument. Scale must be greater than 0")
	self._radius = self._radius * s
end

---Point scaling has no effect
---@param s? number Scale factor (ignored)
function PointShape:scale()
	-- nothing
end


---Draw polygon using Love2D graphics
---@param mode? string Draw mode ('line' or 'fill', defaults to 'line')
function ConvexPolygonShape:draw(mode)
	mode = mode or 'line'
	love.graphics.polygon(mode, self._polygon:unpack())
end

---Draw concave polygon using Love2D graphics
---@param mode? string Draw mode ('line' or 'fill', defaults to 'line')
---@param wireframe? boolean Show wireframe of convex decomposition
function ConcavePolygonShape:draw(mode, wireframe)
	local mode = mode or 'line'
	if mode == 'line' then
		love.graphics.polygon('line', self._polygon:unpack())
		if not wireframe then return end
	end
	for _,p in ipairs(self._shapes) do
		love.graphics.polygon(mode, p._polygon:unpack())
	end
end

---Draw circle using Love2D graphics
---@param mode? string Draw mode ('line' or 'fill', defaults to 'line')
---@param segments? number Number of segments for circle approximation
function CircleShape:draw(mode, segments)
	local x, y, r = self:outcircle()
	love.graphics.circle(mode or 'line', x, y, r, segments)
end

---Draw point using Love2D graphics
function PointShape:draw()
	(love.graphics.points or love.graphics.point)(self:center())
end


Shape = common_local.class('Shape', Shape)
ConvexPolygonShape  = common_local.class('ConvexPolygonShape',  ConvexPolygonShape,  Shape)
ConcavePolygonShape = common_local.class('ConcavePolygonShape', ConcavePolygonShape, Shape)
CircleShape         = common_local.class('CircleShape',         CircleShape,         Shape)
PointShape          = common_local.class('PointShape',          PointShape,          Shape)

---Create polygon shape (convex or concave based on input)
---@param polygon number|HC_Polygon First coordinate or polygon object
---@param ... number Additional coordinates if first parameter is number
---@return HC_ConvexPolygonShape|HC_ConcavePolygonShape polygon_shape New polygon shape
local function newPolygonShape(polygon, ...)
	-- create from coordinates if needed
	if type(polygon) == "number" then
		polygon = common_local.instance(Polygon, polygon, ...)
	else
		polygon = polygon:clone()
	end

	if polygon:isConvex() then
		return common_local.instance(ConvexPolygonShape, polygon)
	end

	return common_local.instance(ConcavePolygonShape, polygon)
end

---Create circle shape
---@param ... any Circle constructor arguments (x, y, radius)
---@return HC_CircleShape circle_shape New circle shape
local function newCircleShape(...)
	return common_local.instance(CircleShape, ...)
end

---Create point shape
---@param ... any Point constructor arguments (x, y)
---@return HC_PointShape point_shape New point shape
local function newPointShape(...)
	return common_local.instance(PointShape, ...)
end

---HC shapes module exports
---@class HC_ShapesModule
---@field ConcavePolygonShape HC_ConcavePolygonShape
---@field ConvexPolygonShape HC_ConvexPolygonShape
---@field CircleShape HC_CircleShape
---@field PointShape HC_PointShape
---@field newPolygonShape function
---@field newCircleShape function
---@field newPointShape function
return {
	ConcavePolygonShape = ConcavePolygonShape,
	ConvexPolygonShape  = ConvexPolygonShape,
	CircleShape         = CircleShape,
	PointShape          = PointShape,
	newPolygonShape     = newPolygonShape,
	newCircleShape      = newCircleShape,
	newPointShape       = newPointShape,
}

