-- Fast Pixel Access Utility
-- Provides optimized pixel sampling using FFI for color collision detection

local ffi = require("ffi")
local math_floor = math.floor

-- Define pixel structure for FFI access
ffi.cdef [[
    typedef struct { uint8_t r, g, b, a; } FastPixel;
]]

---@class FastPixelSampler
---@field imageData love.ImageData Source image data
---@field pixels ffi.cdata* pointer to pixel data
---@field width number Image width
---@field height number Image height
local FastPixelSampler = {}
FastPixelSampler.__index = FastPixelSampler

---Create a new fast pixel sampler for an ImageData
---@param imageData love.ImageData The image data to sample from
---@return FastPixelSampler sampler New fast pixel sampler
function FastPixelSampler:new(imageData)
    local self = setmetatable({}, FastPixelSampler)

    self.imageData = imageData
    self.width = imageData:getWidth()
    self.height = imageData:getHeight()

    -- Get FFI pointer to pixel data
    self.pixels = ffi.cast("FastPixel*", imageData:getFFIPointer())

    return self
end

---Sample pixel color at given coordinates (with bounds checking)
---@param x number X coordinate (0-based)
---@param y number Y coordinate (0-based)
---@return number r Red component (0-255)
---@return number g Green component (0-255)
---@return number b Blue component (0-255)
---@return number a Alpha component (0-255)
function FastPixelSampler:getPixel(x, y)
    -- Bounds check
    if x < 0 or x >= self.width or y < 0 or y >= self.height then
        return 0, 0, 0, 0
    end

    -- Direct memory access
    local index = y * self.width + x
    local pixel = self.pixels[index]

    return pixel.r, pixel.g, pixel.b, pixel.a
end

---Sample pixel alpha at given coordinates (optimized for collision detection)
---@param x number X coordinate (0-based)
---@param y number Y coordinate (0-based)
---@return number alpha Alpha component (0-255)
function FastPixelSampler:getAlpha(x, y)
    -- Bounds check
    if x < 0 or x >= self.width or y < 0 or y >= self.height then
        return 0
    end

    -- Direct memory access - only read alpha
    local index = y * self.width + x
    return self.pixels[index].a
end

---Check if pixel is opaque at given coordinates
---@param x number X coordinate (0-based)
---@param y number Y coordinate (0-based)
---@param threshold? number Alpha threshold (default: 25, ~0.1 * 255)
---@return boolean opaque Whether pixel is opaque enough
function FastPixelSampler:isOpaque(x, y, threshold)
    threshold = threshold or 25 -- Default threshold matching renderer logic

    -- Bounds check
    if x < 0 or x >= self.width or y < 0 or y >= self.height then
        return false
    end

    -- Direct memory access - only check alpha
    local index = y * self.width + x
    return self.pixels[index].a > threshold
end

---Sample pixel color with floating point coordinates (using Transform)
---@param transform love.Transform Inverse transform for coordinate conversion
---@param scratchX number World X coordinate (Scratch space)
---@param scratchY number World Y coordinate (Scratch space)
---@return number r Red component (0-255)
---@return number g Green component (0-255)
---@return number b Blue component (0-255)
---@return number a Alpha component (0-255)
function FastPixelSampler:sampleWithTransform(transform, scratchX, scratchY)
    -- Apply inverse transform to get texture coordinates
    local texX, texY = transform:transformPoint(scratchX, scratchY)

    -- Convert to pixel coordinates using direct floor
    local pixelX = math_floor(texX)
    local pixelY = math_floor(texY)

    return self:getPixel(pixelX, pixelY)
end

---Check if sprite touches point using Transform (optimized)
---@param transform love.Transform Inverse transform for coordinate conversion
---@param scratchX number World X coordinate (Scratch space)
---@param scratchY number World Y coordinate (Scratch space)
---@param threshold? number Alpha threshold (default: 25)
---@return boolean touches Whether sprite touches the point
function FastPixelSampler:touchesPointWithTransform(transform, scratchX, scratchY, threshold)
    threshold = threshold or 25

    -- Apply inverse transform to get texture coordinates
    local texX, texY = transform:transformPoint(scratchX, scratchY)

    -- Convert to pixel coordinates using direct floor
    local pixelX = math_floor(texX)
    local pixelY = math_floor(texY)

    return self:isOpaque(pixelX, pixelY, threshold)
end

return FastPixelSampler
