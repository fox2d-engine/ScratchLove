-- Rectangle class for AABB (Axis-Aligned Bounding Box) representation

---@class Rectangle
---@field left number Left boundary (minimum X)
---@field right number Right boundary (maximum X)
---@field bottom number Bottom boundary (minimum Y in Scratch coordinates)
---@field top number Top boundary (maximum Y in Scratch coordinates)
local Rectangle = {}
Rectangle.__index = Rectangle

---Create a new Rectangle with infinite bounds
---@return Rectangle
function Rectangle:new()
    local self = setmetatable({}, Rectangle)
    self.left = -math.huge
    self.right = math.huge
    self.bottom = -math.huge
    self.top = math.huge
    return self
end

---Create a Rectangle from bounds
---@param left number Left boundary
---@param right number Right boundary
---@param bottom number Bottom boundary
---@param top number Top boundary
---@return Rectangle
function Rectangle:fromBounds(left, right, bottom, top)
    local self = setmetatable({}, Rectangle)
    self.left = left
    self.right = right
    self.bottom = bottom
    self.top = top
    return self
end

---Copy a rectangle
---@param src Rectangle Source rectangle
---@return Rectangle
function Rectangle:copy(src)
    local self = setmetatable({}, Rectangle)
    self.left = src.left
    self.right = src.right
    self.bottom = src.bottom
    self.top = src.top
    return self
end

---Copy rectangle data into this rectangle (for reuse without allocation)
---@param src Rectangle Source rectangle to copy from
---@return Rectangle self
function Rectangle:copyFrom(src)
    self.left = src.left
    self.right = src.right
    self.bottom = src.bottom
    self.top = src.top
    return self
end

---Update this rectangle's bounds
---@param left number Left boundary
---@param right number Right boundary
---@param bottom number Bottom boundary
---@param top number Top boundary
---@return Rectangle self
function Rectangle:setBounds(left, right, bottom, top)
    self.left = left
    self.right = right
    self.bottom = bottom
    self.top = top
    return self
end

---Push this rectangle out to integer bounds (conservative expansion)
---@return Rectangle self
function Rectangle:snapToInt()
    self.left = math.floor(self.left)
    self.right = math.ceil(self.right)
    self.bottom = math.floor(self.bottom)
    self.top = math.ceil(self.top)
    return self
end

---Check whether this rectangle intersects another rectangle
---@param rect Rectangle Another rectangle
---@return boolean intersects
function Rectangle:intersects(rect)
    return not (self.right < rect.left or rect.right < self.left or
                self.top < rect.bottom or rect.top < self.bottom)
end

---Check whether a point is inside this rectangle
---@param x number X coordinate
---@param y number Y coordinate
---@return boolean contains
function Rectangle:containsPoint(x, y)
    return x >= self.left and x <= self.right and
           y >= self.bottom and y <= self.top
end

---Clamp this rectangle within bounds
---@param left number Minimum left boundary
---@param right number Maximum right boundary
---@param bottom number Minimum bottom boundary
---@param top number Maximum top boundary
---@return Rectangle self
function Rectangle:clamp(left, right, bottom, top)
    self.left = math.min(math.max(self.left, left), right)
    self.right = math.max(math.min(self.right, right), left)
    self.bottom = math.min(math.max(self.bottom, bottom), top)
    self.top = math.max(math.min(self.top, top), bottom)
    return self
end

---Compute the union of this rectangle with another
---@param rect Rectangle Another rectangle
---@return Rectangle result New rectangle containing the union
function Rectangle:union(rect)
    local result = Rectangle:new()
    result.left = math.min(self.left, rect.left)
    result.right = math.max(self.right, rect.right)
    result.bottom = math.min(self.bottom, rect.bottom)
    result.top = math.max(self.top, rect.top)
    return result
end

---Static method: Compute the union of two rectangles with result reuse
---@param a Rectangle First rectangle
---@param b Rectangle Second rectangle
---@param result Rectangle|nil Optional result rectangle to reuse (avoids allocation)
---@return Rectangle result Rectangle containing the union
function Rectangle.unionInto(a, b, result)
    result = result or Rectangle:new()
    result.left = math.min(a.left, b.left)
    result.right = math.max(a.right, b.right)
    result.bottom = math.min(a.bottom, b.bottom)
    result.top = math.max(a.top, b.top)
    return result
end

---Compute the intersection of this rectangle with another
---@param rect Rectangle Another rectangle
---@return Rectangle result New rectangle containing the intersection
function Rectangle:intersection(rect)
    local result = Rectangle:new()
    result.left = math.max(self.left, rect.left)
    result.right = math.min(self.right, rect.right)
    result.bottom = math.max(self.bottom, rect.bottom)
    result.top = math.min(self.top, rect.top)
    return result
end

---Static method: Compute the intersection of two rectangles with result reuse
---@param a Rectangle First rectangle
---@param b Rectangle Second rectangle
---@param result Rectangle|nil Optional result rectangle to reuse (avoids allocation)
---@return Rectangle result Rectangle containing the intersection
function Rectangle.intersectionInto(a, b, result)
    result = result or Rectangle:new()
    result.left = math.max(a.left, b.left)
    result.right = math.min(a.right, b.right)
    result.bottom = math.max(a.bottom, b.bottom)
    result.top = math.min(a.top, b.top)
    return result
end

---Expand this rectangle to include a point
---@param x number X coordinate
---@param y number Y coordinate
---@return Rectangle self
function Rectangle:expandToIncludePoint(x, y)
    self.left = math.min(self.left, x)
    self.right = math.max(self.right, x)
    self.bottom = math.min(self.bottom, y)
    self.top = math.max(self.top, y)
    return self
end

---Check if this rectangle is valid (has positive area)
---@return boolean valid
function Rectangle:isValid()
    return self.right >= self.left and self.top >= self.bottom
end

---Get the width of the rectangle
---@return number width
function Rectangle:getWidth()
    return self.right - self.left
end

---Get the height of the rectangle
---@return number height
function Rectangle:getHeight()
    return self.top - self.bottom
end

---Get the center X coordinate
---@return number centerX
function Rectangle:getCenterX()
    return (self.left + self.right) / 2
end

---Get the center Y coordinate
---@return number centerY
function Rectangle:getCenterY()
    return (self.bottom + self.top) / 2
end

---Get the area of the rectangle
---@return number area
function Rectangle:getArea()
    if not self:isValid() then
        return 0
    end
    return self:getWidth() * self:getHeight()
end

---Convert to screen coordinates (for Love2D rendering)
---@param scratchToScreenX function Function to convert X coordinate
---@param scratchToScreenY function Function to convert Y coordinate
---@return Rectangle screenRect Rectangle in screen coordinates
function Rectangle:toScreenCoords(scratchToScreenX, scratchToScreenY)
    local screenRect = Rectangle:new()
    -- Convert X coordinates (no flipping)
    screenRect.left = scratchToScreenX(self.left)
    screenRect.right = scratchToScreenX(self.right)
    -- Convert Y coordinates (Y axis is flipped: Scratch top becomes screen bottom)
    screenRect.bottom = scratchToScreenY(self.top)    -- Scratch top (high Y) -> screen bottom (high Y)
    screenRect.top = scratchToScreenY(self.bottom)    -- Scratch bottom (low Y) -> screen top (low Y)
    return screenRect
end

---Debug string representation
---@return string
function Rectangle:toString()
    return string.format("Rectangle(left=%.2f, right=%.2f, bottom=%.2f, top=%.2f)",
                        self.left, self.right, self.bottom, self.top)
end

-- Metamethod for tostring()
Rectangle.__tostring = Rectangle.toString

return Rectangle