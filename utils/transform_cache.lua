-- Transform Cache Manager
-- Manages lazy-loaded transformation-related caches for sprites
-- Provides unified dirty tracking and cache invalidation

local Rectangle = require("utils.rectangle")

---@class TransformCache
---@field sprite Sprite Owner sprite
---@field dirty boolean Whether transform is dirty
---@field lastTransform table Last transform parameters for dirty checking
---@field transformedAABB Rectangle|nil Cached transformed AABB
---@field snappedAABB Rectangle|nil Cached snapped (integer bounds) AABB
---@field inverseTransform love.Transform|nil Cached inverse transform for coordinate conversion
---@field _aabbTransform love.Transform|nil Reusable transform object for AABB calculation
local TransformCache = {}
TransformCache.__index = TransformCache

---Create a new transform cache for a sprite
---@param sprite Sprite Owner sprite
---@return TransformCache
function TransformCache:new(sprite)
    local self = setmetatable({}, TransformCache)

    self.sprite = sprite
    self.dirty = true

    -- Track last transform state for dirty checking
    self.lastTransform = {
        x = sprite.x or 0,
        y = sprite.y or 0,
        direction = sprite.direction or 90,
        size = sprite.size or 100,
        rotationStyle = sprite.rotationStyle or "all around",
        costume = sprite.currentCostume or 0
    }

    -- Cached values
    self.transformedAABB = nil
    self.snappedAABB = nil  -- Cached snapped bounds (for collision detection)
    self.inverseTransform = nil

    return self
end

---Check if transform has changed and mark dirty if needed
---@return boolean isDirty Whether transform is dirty
function TransformCache:checkDirty()
    local sprite = self.sprite

    -- Check if any transform property has changed
    if self.lastTransform.x ~= sprite.x or
        self.lastTransform.y ~= sprite.y or
        self.lastTransform.direction ~= sprite.direction or
        self.lastTransform.size ~= sprite.size or
        self.lastTransform.rotationStyle ~= sprite.rotationStyle or
        self.lastTransform.costume ~= sprite.currentCostume then
        self:markDirty()
        return true
    end

    return self.dirty
end

---Mark all caches as dirty
function TransformCache:markDirty()
    self.dirty = true
    -- Clear derived caches
    self.transformedAABB = nil
    self.snappedAABB = nil  -- Clear snapped bounds cache
    self.inverseTransform = nil
end

---Update tracking state after recalculation
function TransformCache:updateTracking()
    local sprite = self.sprite
    self.lastTransform.x = sprite.x
    self.lastTransform.y = sprite.y
    self.lastTransform.direction = sprite.direction
    self.lastTransform.size = sprite.size
    self.lastTransform.rotationStyle = sprite.rotationStyle
    self.lastTransform.costume = sprite.currentCostume
    self.dirty = false
end

---Get transformed AABB (lazy-loaded)
---@param result Rectangle|nil Optional result rectangle to reuse (avoids allocation)
---@return Rectangle rect Transformed AABB
function TransformCache:getTransformedAABB(result)
    -- Check if recalculation is needed
    if self:checkDirty() or not self.transformedAABB then
        self:recalculateTransformedAABB()
    end

    -- If result parameter provided, copy into it for reuse
    if result then
        result:copyFrom(self.transformedAABB)
        return result
    end

    return self.transformedAABB
end

---Get fast bounds (uses AABB)
---Mimics native Scratch getFastBounds behavior
---@param result Rectangle|nil Optional result rectangle to reuse (avoids allocation)
---@return Rectangle rect Transformed AABB bounds
function TransformCache:getFastBounds(result)
    -- Always use AABB
    return self:getTransformedAABB(result)
end

---Get snapped (integer bounds) AABB for collision detection
---This caches the snapped bounds to avoid repeated snapToInt calls
---@param result Rectangle|nil Optional result rectangle to reuse (avoids allocation)
---@return Rectangle rect Snapped AABB with integer bounds
function TransformCache:getSnappedBounds(result)
    -- Check if recalculation is needed
    if self:checkDirty() or not self.snappedAABB then
        -- Get base bounds
        local bounds = self:getFastBounds()

        -- Create snapped copy and cache it
        self.snappedAABB = Rectangle:copy(bounds)
        self.snappedAABB:snapToInt()
    end

    -- If result parameter provided, copy into it for reuse
    if result then
        result:copyFrom(self.snappedAABB)
        return result
    end

    return self.snappedAABB
end

---Recalculate transformed AABB using matrix transformation
---@private
---@return number minX, number maxX, number minY, number maxY
function TransformCache:_calculateAABBMatrix()
    local sprite = self.sprite
    local costume = sprite:getCurrentCostume()

    if not costume or not costume.image then
        return sprite.x, sprite.x, sprite.y, sprite.y
    end

    -- Get image dimensions and properties
    local iw = costume.image:getWidth()
    local ih = costume.image:getHeight()
    local bitmapResolution = costume.bitmapResolution or 1

    local originX = costume.rotationCenterX or (iw / 2)
    local originY = costume.rotationCenterY or (ih / 2)

    -- Calculate final scale and rotation based on rotation style
    local scale = sprite.size / 100
    local finalScale = scale / bitmapResolution
    local rotation = 0
    local scaleX = finalScale
    local scaleY = finalScale

    if sprite.rotationStyle == "all around" then
        rotation = math.rad(sprite.direction - 90)
    elseif sprite.rotationStyle == "left-right" and sprite.direction < 0 then
        scaleX = -finalScale
    end

    -- Build transform matrix matching Love2D draw semantics
    -- love.graphics.draw(image, x, y, r, sx, sy, ox, oy) applies:
    -- Translate(x, y) * Rotate(r) * Scale(sx, sy) * Translate(-ox, -oy)
    local screenX = sprite.runtime:scratchToScreenX(sprite.x)
    local screenY = sprite.runtime:scratchToScreenY(sprite.y)

    -- Reuse or create transform object
    local transform = self._aabbTransform
    if not transform then
        transform = love.math.newTransform()
        self._aabbTransform = transform
    else
        transform:reset()
    end

    -- Apply transform chain in same order as Love2D draw
    transform:translate(screenX, screenY)
    transform:rotate(rotation)
    transform:scale(scaleX, scaleY)
    transform:translate(-originX, -originY)

    -- Transform 4 corners
    local corners = {
        {x = 0, y = 0},  -- top-left
        {x = iw, y = 0}, -- top-right
        {x = iw, y = ih}, -- bottom-right
        {x = 0, y = ih},  -- bottom-left
    }

    local minX, maxX = math.huge, -math.huge
    local minY, maxY = math.huge, -math.huge

    for _, corner in ipairs(corners) do
        -- Transform corner using matrix
        local sx, sy = transform:transformPoint(corner.x, corner.y)

        -- Convert screen coordinates back to Scratch coordinates
        local scratchX = sprite.runtime:screenToScratchX(sx)
        local scratchY = sprite.runtime:screenToScratchY(sy)

        minX = math.min(minX, scratchX)
        maxX = math.max(maxX, scratchX)
        minY = math.min(minY, scratchY)
        maxY = math.max(maxY, scratchY)
    end

    return minX, maxX, minY, maxY
end

---Recalculate transformed AABB
function TransformCache:recalculateTransformedAABB()
    local sprite = self.sprite
    local rect = Rectangle:new()

    local costume = sprite:getCurrentCostume()
    if not costume or not costume.image then
        -- No costume, return point at sprite position
        self.transformedAABB = rect:setBounds(sprite.x, sprite.x, sprite.y, sprite.y)
        self:updateTracking()
        return
    end

    -- Calculate AABB using matrix transformation method
    local minX, maxX, minY, maxY = self:_calculateAABBMatrix()
    self.transformedAABB = rect:setBounds(minX, maxX, minY, maxY)

    self:updateTracking()
end

---Get Love2D Transform for inverse transformation (lazy-loaded)
---@return love.Transform|nil transform Inverse transform for world->local coordinate conversion
function TransformCache:getInverseTransform()
    -- Check if recalculation is needed
    if self:checkDirty() or not self.inverseTransform then
        self:recalculateInverseTransform()
    end

    return self.inverseTransform
end

---Recalculate Love2D inverse transform
function TransformCache:recalculateInverseTransform()
    local sprite = self.sprite
    local costume = sprite:getCurrentCostume()

    if not costume or not costume.image then
        self.inverseTransform = nil
        self:updateTracking()
        return
    end

    local iw = costume.image:getWidth()
    local ih = costume.image:getHeight()
    local bitmapResolution = costume.bitmapResolution or 1

    local originX = costume.rotationCenterX or (iw / 2)
    local originY = costume.rotationCenterY or (ih / 2)

    -- Calculate transformation parameters (matching AABB logic exactly)
    local scale = sprite.size / 100
    local finalScale = scale / bitmapResolution
    local rotation = 0
    local scaleX = finalScale
    local scaleY = finalScale

    if sprite.rotationStyle == "all around" then
        rotation = math.rad(sprite.direction - 90)
    elseif sprite.rotationStyle == "left-right" and sprite.direction < 0 then
        scaleX = -finalScale
    end

    -- Build inverse transform matrix to match AABB forward transform
    -- Forward transform (from recalculateTransformedAABB):
    --   dx = (tx - originX) * scaleX
    --   dy = (ty - originY) * scaleY
    --   rx = dx * cos_r - dy * sin_r
    --   ry = dx * sin_r + dy * cos_r
    --   sx = screenX + rx,  sy = screenY + ry
    --   scratchX = screenToScratchX(sx) = sx - STAGE_HALF_WIDTH
    --   scratchY = screenToScratchY(sy) = STAGE_HALF_HEIGHT - sy
    -- Since screenX = sprite.x + STAGE_HALF_WIDTH and screenY = STAGE_HALF_HEIGHT - sprite.y,
    -- this simplifies to:
    --   scratchX = sprite.x + rx
    --   scratchY = sprite.y - ry
    -- Inverse transform (Scratch world -> texture):
    --   dx = scratchX - sprite.x,  dy = scratchY - sprite.y
    --   sx = dx * cos_r - dy * sin_r
    --   sy = -dx * sin_r - dy * cos_r
    --   tx = sx / scaleX + originX
    --   ty = sy / scaleY + originY
    -- Matrix form:
    --   tx = (cos_r / scaleX) * scratchX + (-sin_r / scaleX) * scratchY + offset_x
    --   ty = (-sin_r / scaleY) * scratchX + (-cos_r / scaleY) * scratchY + offset_y

    local cos_r = math.cos(rotation)
    local sin_r = math.sin(rotation)

    local e11 = cos_r / scaleX
    local e12 = -sin_r / scaleX
    local e14 = -sprite.x * cos_r / scaleX + sprite.y * sin_r / scaleX + originX

    local e21 = -sin_r / scaleY
    local e22 = -cos_r / scaleY
    local e24 = sprite.x * sin_r / scaleY + sprite.y * cos_r / scaleY + originY

    -- Create or reuse transform object (reduce GC pressure)
    local transform = self.inverseTransform
    if not transform then
        transform = love.math.newTransform()
    end

    -- Set matrix elements directly to match the derived inverse transform
    transform:setMatrix(e11, e12, 0, e14,
                        e21, e22, 0, e24,
                        0, 0, 1, 0,
                        0, 0, 0, 1)

    self.inverseTransform = transform

    -- Update tracking state
    self:updateTracking()
end

---Clear all caches
function TransformCache:clear()
    self.transformedAABB = nil
    self.inverseTransform = nil
    self._aabbTransform = nil
    self.dirty = true
end

return TransformCache
