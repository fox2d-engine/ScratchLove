--[[
Copyright (c) 2012 Matthias Richter

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

---@type fun(x: number): number
---@type fun(x: number): number
---@type fun(x: number): number
local sqrt, cos, sin = math.sqrt, math.cos, math.sin

---Convert vector coordinates to string representation
---@param x number X coordinate
---@param y number Y coordinate
---@return string formatted String representation of vector
local function str(x,y)
	return "("..tonumber(x)..","..tonumber(y)..")"
end

---Multiply vector by scalar
---@param s number Scalar multiplier
---@param x number X component
---@param y number Y component
---@return number x_result X component multiplied by scalar
---@return number y_result Y component multiplied by scalar
local function mul(s, x,y)
	return s*x, s*y
end

---Divide vector by scalar
---@param s number Scalar divisor
---@param x number X component
---@param y number Y component
---@return number x_result X component divided by scalar
---@return number y_result Y component divided by scalar
local function div(s, x,y)
	return x/s, y/s
end

---Add two vectors
---@param x1 number First vector X component
---@param y1 number First vector Y component
---@param x2 number Second vector X component
---@param y2 number Second vector Y component
---@return number x_result Sum X component
---@return number y_result Sum Y component
local function add(x1,y1, x2,y2)
	return x1+x2, y1+y2
end

---Subtract second vector from first vector
---@param x1 number First vector X component
---@param y1 number First vector Y component
---@param x2 number Second vector X component
---@param y2 number Second vector Y component
---@return number x_result Difference X component
---@return number y_result Difference Y component
local function sub(x1,y1, x2,y2)
	return x1-x2, y1-y2
end

---Component-wise multiplication of two vectors
---@param x1 number First vector X component
---@param y1 number First vector Y component
---@param x2 number Second vector X component
---@param y2 number Second vector Y component
---@return number x_result Product X component
---@return number y_result Product Y component
local function permul(x1,y1, x2,y2)
	return x1*x2, y1*y2
end

---Dot product of two vectors
---@param x1 number First vector X component
---@param y1 number First vector Y component
---@param x2 number Second vector X component
---@param y2 number Second vector Y component
---@return number dot_product Dot product result
local function dot(x1,y1, x2,y2)
	return x1*x2 + y1*y2
end

---Cross product/determinant of two 2D vectors
---@param x1 number First vector X component
---@param y1 number First vector Y component
---@param x2 number Second vector X component
---@param y2 number Second vector Y component
---@return number determinant Cross product result
local function det(x1,y1, x2,y2)
	return x1*y2 - y1*x2
end

---Check if two vectors are equal
---@param x1 number First vector X component
---@param y1 number First vector Y component
---@param x2 number Second vector X component
---@param y2 number Second vector Y component
---@return boolean equal True if vectors are equal
local function eq(x1,y1, x2,y2)
	return x1 == x2 and y1 == y2
end

---Lexicographic less-than comparison
---@param x1 number First vector X component
---@param y1 number First vector Y component
---@param x2 number Second vector X component
---@param y2 number Second vector Y component
---@return boolean less_than True if first vector is lexicographically less than second
local function lt(x1,y1, x2,y2)
	return x1 < x2 or (x1 == x2 and y1 < y2)
end

---Component-wise less-than-or-equal comparison
---@param x1 number First vector X component
---@param y1 number First vector Y component
---@param x2 number Second vector X component
---@param y2 number Second vector Y component
---@return boolean less_equal True if first vector components are all <= second vector components
local function le(x1,y1, x2,y2)
	return x1 <= x2 and y1 <= y2
end

---Squared length of vector
---@param x number X component
---@param y number Y component
---@return number length_squared Squared length of vector
local function len2(x,y)
	return x*x + y*y
end

---Length of vector
---@param x number X component
---@param y number Y component
---@return number length Length of vector
local function len(x,y)
	return sqrt(x*x + y*y)
end

---Distance between two points
---@param x1 number First point X coordinate
---@param y1 number First point Y coordinate
---@param x2 number Second point X coordinate
---@param y2 number Second point Y coordinate
---@return number distance Distance between points
local function dist(x1,y1, x2,y2)
	return len(x1-x2, y1-y2)
end

---Normalize vector to unit length
---@param x number X component
---@param y number Y component
---@return number x_norm Normalized X component
---@return number y_norm Normalized Y component
local function normalize(x,y)
	local l = len(x,y)
	return x/l, y/l
end

---Rotate vector by angle
---@param phi number Rotation angle in radians
---@param x number X component
---@param y number Y component
---@return number x_rotated Rotated X component
---@return number y_rotated Rotated Y component
local function rotate(phi, x,y)
	local c, s = cos(phi), sin(phi)
	return c*x - s*y, s*x + c*y
end

---Get perpendicular vector (90 degree counter-clockwise rotation)
---@param x number X component
---@param y number Y component
---@return number x_perp Perpendicular X component
---@return number y_perp Perpendicular Y component
local function perpendicular(x,y)
	return -y, x
end

---Project vector onto another vector
---@param x number Vector to project X component
---@param y number Vector to project Y component
---@param u number Target vector X component
---@param v number Target vector Y component
---@return number x_proj Projected X component
---@return number y_proj Projected Y component
local function project(x,y, u,v)
	local s = (x*u + y*v) / (u*u + v*v)
	return s*u, s*v
end

---Mirror vector across another vector
---@param x number Vector to mirror X component
---@param y number Vector to mirror Y component
---@param u number Mirror axis X component
---@param v number Mirror axis Y component
---@return number x_mirror Mirrored X component
---@return number y_mirror Mirrored Y component
local function mirror(x,y, u,v)
	local s = 2 * (x*u + y*v) / (u*u + v*v)
	return s*u - x, s*v - y
end


-- the module
return {
	str = str,

	-- arithmetic
	mul    = mul,
	div    = div,
	add    = add,
	sub    = sub,
	permul = permul,
	dot    = dot,
	det    = det,
	cross  = det,

	-- relation
	eq = eq,
	lt = lt,
	le = le,

	-- misc operations
	len2          = len2,
	len           = len,
	dist          = dist,
	normalize     = normalize,
	rotate        = rotate,
	perpendicular = perpendicular,
	project       = project,
	mirror        = mirror,
}
