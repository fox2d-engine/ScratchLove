---HC spatial hash for efficient collision detection
---Divides space into cells to reduce collision testing overhead
---Part of the HardonCollider (HC) physics library

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

---@type fun(x: number): number
local floor = math.floor
---@type fun(a: number, b: number): number
---@type fun(a: number, b: number): number
local min, max = math.min, math.max

local _PACKAGE = (...):match("^(.+)%.[^%.]+")
local common_local = common
if not (type(common) == 'table' and common.class and common.instance) then
	assert(common_class ~= false, 'No class commons specification available.')
	require(_PACKAGE .. '.class')
	common_local = common
end
local vector  = require(_PACKAGE .. '.vector-light')

---@class HC_Spatialhash
---@field cell_size number Size of each grid cell
---@field cells table<number, table<number, table<HC_Shape, HC_Shape>>> Grid cells indexed by coordinates
---@field init function Constructor
---@field cellCoords function Convert world coordinates to cell coordinates
---@field cell function Get or create cell at grid position
---@field cellAt function Get cell at world coordinates
---@field shapes function Get all shapes in hash
---@field inSameCells function Get all shapes in same cells as bounding box
---@field register function Add shape to spatial hash
---@field remove function Remove shape from spatial hash
---@field update function Update shape position in spatial hash
---@field intersectionsWithSegment function Get intersections with line segment
---@field draw function Draw spatial hash grid

---Spatial hash for efficient collision detection
local Spatialhash = {}

---Initialize spatial hash with given cell size
---@param cell_size? number Size of each grid cell (defaults to 100)
function Spatialhash:init(cell_size)
	self.cell_size = cell_size or 100
	self.cells = {}
end

---Convert world coordinates to cell coordinates
---@param x number World X coordinate
---@param y number World Y coordinate
---@return number cell_x Cell X coordinate
---@return number cell_y Cell Y coordinate
function Spatialhash:cellCoords(x,y)
	return floor(x / self.cell_size), floor(y / self.cell_size)
end

---Get or create cell at grid position
---@param i number Cell X coordinate
---@param k number Cell Y coordinate
---@return table<HC_Shape, HC_Shape> cell Cell containing shapes
function Spatialhash:cell(i,k)
	local row = rawget(self.cells, i)
	if not row then
		row = {}
		rawset(self.cells, i, row)
	end

	local cell = rawget(row, k)
	if not cell then
		cell = {}
		rawset(row, k, cell)
	end

	return cell
end

---Get cell at world coordinates
---@param x number World X coordinate
---@param y number World Y coordinate
---@return table<HC_Shape, HC_Shape> cell Cell containing shapes
function Spatialhash:cellAt(x,y)
	return self:cell(self:cellCoords(x,y))
end

---Get all shapes in the spatial hash
---@return table<HC_Shape, HC_Shape> shapes Set of all shapes
function Spatialhash:shapes()
	local set = {}
	for i,row in pairs(self.cells) do
		for k,cell in pairs(row) do
			for obj in pairs(cell) do
				rawset(set, obj, obj)
			end
		end
	end
	return set
end

---Get all shapes that are in the same cells as the bounding box
---@param x1 number Bounding box minimum X
---@param y1 number Bounding box minimum Y
---@param x2 number Bounding box maximum X
---@param y2 number Bounding box maximum Y
---@return table<HC_Shape, HC_Shape> shapes Set of shapes in overlapping cells
function Spatialhash:inSameCells(x1,y1, x2,y2)
	local set = {}
	x1, y1 = self:cellCoords(x1, y1)
	x2, y2 = self:cellCoords(x2, y2)
	for i = x1,x2 do
		for k = y1,y2 do
			for obj in pairs(self:cell(i,k)) do
				rawset(set, obj, obj)
			end
		end
	end
	return set
end

---Register shape in spatial hash with given bounding box
---@param obj HC_Shape Shape to register
---@param x1 number Bounding box minimum X
---@param y1 number Bounding box minimum Y
---@param x2 number Bounding box maximum X
---@param y2 number Bounding box maximum Y
function Spatialhash:register(obj, x1, y1, x2, y2)
	x1, y1 = self:cellCoords(x1, y1)
	x2, y2 = self:cellCoords(x2, y2)
	for i = x1,x2 do
		for k = y1,y2 do
			rawset(self:cell(i,k), obj, obj)
		end
	end
end

---Remove shape from spatial hash
---@param obj HC_Shape Shape to remove
---@param x1? number Bounding box minimum X (if nil, searches all cells)
---@param y1? number Bounding box minimum Y
---@param x2? number Bounding box maximum X
---@param y2? number Bounding box maximum Y
function Spatialhash:remove(obj, x1, y1, x2,y2)
	-- no bbox given. => must check all cells
	if not (x1 and y1 and x2 and y2) then
		for _,row in pairs(self.cells) do
			for _,cell in pairs(row) do
				rawset(cell, obj, nil)
			end
		end
		return
	end

	-- else: remove only from bbox
	x1,y1 = self:cellCoords(x1,y1)
	x2,y2 = self:cellCoords(x2,y2)
	for i = x1,x2 do
		for k = y1,y2 do
			rawset(self:cell(i,k), obj, nil)
		end
	end
end

---Update shape position in spatial hash
---@param obj HC_Shape Shape to update
---@param old_x1 number Old bounding box minimum X
---@param old_y1 number Old bounding box minimum Y
---@param old_x2 number Old bounding box maximum X
---@param old_y2 number Old bounding box maximum Y
---@param new_x1 number New bounding box minimum X
---@param new_y1 number New bounding box minimum Y
---@param new_x2 number New bounding box maximum X
---@param new_y2 number New bounding box maximum Y
function Spatialhash:update(obj, old_x1,old_y1, old_x2,old_y2, new_x1,new_y1, new_x2,new_y2)
	old_x1, old_y1 = self:cellCoords(old_x1, old_y1)
	old_x2, old_y2 = self:cellCoords(old_x2, old_y2)

	new_x1, new_y1 = self:cellCoords(new_x1, new_y1)
	new_x2, new_y2 = self:cellCoords(new_x2, new_y2)

	if old_x1 == new_x1 and old_y1 == new_y1 and
	   old_x2 == new_x2 and old_y2 == new_y2 then
		return
	end

	for i = old_x1,old_x2 do
		for k = old_y1,old_y2 do
			rawset(self:cell(i,k), obj, nil)
		end
	end
	for i = new_x1,new_x2 do
		for k = new_y1,new_y2 do
			rawset(self:cell(i,k), obj, obj)
		end
	end
end

---@class HC_IntersectionInfo
---@field [1] HC_Shape Shape that was intersected
---@field [2] number Parameter t along the segment (0 to segment length)
---@field [3] number Intersection point X coordinate
---@field [4] number Intersection point Y coordinate

---Get all intersections with a line segment
---@param x1 number Segment start X coordinate
---@param y1 number Segment start Y coordinate
---@param x2 number Segment end X coordinate
---@param y2 number Segment end Y coordinate
---@return HC_IntersectionInfo[] intersections Array of intersection info, sorted by distance
function Spatialhash:intersectionsWithSegment(x1, y1, x2, y2)
	local odx, ody = x2 - x1, y2 - y1
	local len, cur = vector.len(odx, ody), 0
	local dx, dy = vector.normalize(odx, ody)
	local step = self.cell_size / 2
	local visited = {}
	local points = {}
	local mt = math.huge

	while (cur + step < len) do
		local cx, cy = x1 + dx * cur,  y1 + dy * cur
		local shapes = self:cellAt(cx, cy)
		cur = cur + step

		for _, shape in pairs(shapes) do
			if (not visited[shape]) then
				local ints = shape:intersectionsWithRay(x1, y1, dx, dy)

				for _, t in ipairs(ints) do
					if (t >= 0 and t <= len) then
						local px, py = vector.add(x1, y1, vector.mul(t, dx, dy))
						table.insert(points, {shape, t, px, py})
					end
				end

				visited[shape] = true
			end
		end
	end

	table.sort(points, function(a, b)
		return a[2] < b[2]
	end)

	return points
end

---Draw spatial hash grid using Love2D graphics
---@param how? string Draw mode ('line' or 'fill', defaults to 'line')
---@param show_empty? boolean Whether to show empty cells (defaults to true)
---@param print_key? boolean Whether to print cell coordinates (defaults to false)
function Spatialhash:draw(how, show_empty, print_key)
	if show_empty == nil then show_empty = true end
	for k1,v in pairs(self.cells) do
		for k2,cell in pairs(v) do
			local is_empty = (next(cell) == nil)
			if show_empty or not is_empty then
				local x = k1 * self.cell_size
				local y = k2 * self.cell_size
				love.graphics.rectangle(how or 'line', x,y, self.cell_size, self.cell_size)

				if print_key then
					love.graphics.print(("%d:%d"):format(k1,k2), x+3,y+3)
				end
			end
		end
	end
end

return common_local.class('Spatialhash', Spatialhash)
