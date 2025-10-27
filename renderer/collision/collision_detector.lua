-- Collision Detector
-- Manages collision detection using CPU or GPU strategies based on region size

local Global = require("global")
local log = require("lib.log")
local Rectangle = require("utils.rectangle")
local CPUCollisionStrategy = require("renderer.collision.cpu_collision_strategy")
local GPUCollisionStrategy = require("renderer.collision.gpu_collision_strategy")

-- Pre-allocated Rectangle objects for collision detection (matching TurboWarp pattern)
-- These are reused across all collision checks to avoid memory allocation
local _rect1 = Rectangle:new()
local _rect2 = Rectangle:new()
local _intersection = Rectangle:new()
local _candidatesBounds = Rectangle:new()

---@class CollisionDetector
---@field runtime Runtime Runtime instance
---@field cpuStrategy CPUCollisionStrategy CPU-based collision detection
---@field gpuStrategy GPUCollisionStrategy GPU-based collision detection
---@field _orderedSpritesGetter function Function to get ordered sprites
local CollisionDetector = {}
CollisionDetector.__index = CollisionDetector

---Create a new collision detector
---@param runtime Runtime Runtime instance
---@param orderedSpritesGetter function Function to get ordered sprites from renderer
---@return CollisionDetector
function CollisionDetector:new(runtime, orderedSpritesGetter)
    local self = setmetatable({}, CollisionDetector)
    self.runtime = runtime
    self.cpuStrategy = CPUCollisionStrategy:new()
    self.gpuStrategy = GPUCollisionStrategy:new()
    self._orderedSpritesGetter = orderedSpritesGetter
    return self
end

---Check color collision between sprite and target color
---Automatically selects CPU or GPU strategy based on region size
---@param sprite Sprite The sprite to check
---@param targetColor table RGB color to check for {r, g, b}
---@param spriteColor table|nil Optional sprite color mask {r, g, b}
---@return boolean collisionDetected Whether collision was detected
---@return number|nil collision_x X coordinate of collision point
---@return number|nil collision_y Y coordinate of collision point
function CollisionDetector:checkColorCollision(sprite, targetColor, spriteColor)
    local costume = sprite:getCurrentCostume()
    if not costume or not costume.image or not sprite.visible then
        return false, nil, nil
    end

    -- Get candidate sprites that might be touching
    local candidateSprites = self:_getCandidatesTouching(sprite)
    if #candidateSprites == 0 then
        return false, nil, nil
    end

    -- Calculate optimized detection region bounds (union of intersections, matching native Scratch)
    local bounds = self:_computeCandidatesBounds(candidateSprites)
    if not bounds then
        return false, nil, nil
    end

    -- Calculate pixel count for CPU/GPU decision
    local CPU_PIXEL_THRESHOLD = Global.COLLISION_CPU_THRESHOLD
    local boundsWidth = math.abs(bounds.right - bounds.left)
    local boundsHeight = math.abs(bounds.top - bounds.bottom)
    local totalPixels = boundsWidth * boundsHeight * (#candidateSprites + 1)

    -- Choose detection method based on pixel count
    local strategy
    if totalPixels >= CPU_PIXEL_THRESHOLD then
        log.debug("[CollisionDetector] Using GPU strategy: %d pixels, %d candidates",
            totalPixels, #candidateSprites)
        strategy = self.gpuStrategy
    else
        log.debug("[CollisionDetector] Using CPU strategy: %d pixels, %d candidates",
            totalPixels, #candidateSprites)
        strategy = self.cpuStrategy
    end

    -- Execute collision detection with selected strategy
    return strategy:check(sprite, targetColor, spriteColor, candidateSprites, bounds, self.runtime)
end

---Get candidate sprites that might be touching the given sprite
---@private
---@param sprite Sprite The sprite to check
---@return table candidateSprites List of candidate data with intersection info
function CollisionDetector:_getCandidatesTouching(sprite)
    local candidates = {}

    -- Reuse pre-allocated Rectangle (_rect1) to avoid memory allocation
    -- Use getSnappedBounds() which returns cached snapped bounds (huge optimization!)
    sprite:getSnappedBounds(_rect1)

    -- Check all visible sprites (work directly in Scratch coordinates)
    local orderedSprites = self._orderedSpritesGetter()

    for _, otherSprite in ipairs(orderedSprites) do
        if otherSprite ~= sprite and otherSprite.visible then
            -- Reuse pre-allocated Rectangle (_rect2) to avoid allocation
            -- Use getSnappedBounds() which caches snapped bounds per sprite
            otherSprite:getSnappedBounds(_rect2)

            -- AABB intersection test in Scratch coordinates
            Rectangle.intersectionInto(_rect1, _rect2, _intersection)
            if _intersection:isValid() then
                local intersectionCopy = Rectangle:copy(_intersection)
                table.insert(candidates, {
                    sprite = otherSprite,
                    intersection = intersectionCopy
                })
            end
        end
    end

    return candidates
end

---Compute the union bounds from candidate sprites intersections (matching native Scratch logic)
---@private
---@param candidates table List of candidate data with intersection info
---@return Rectangle|nil bounds Union of all intersection bounds, or nil if no candidates
function CollisionDetector:_computeCandidatesBounds(candidates)
    if #candidates == 0 then
        return nil
    end

    -- Reuse pre-allocated _candidatesBounds rectangle (matching TurboWarp pattern)
    _candidatesBounds:copyFrom(candidates[1].intersection)

    -- Union with all other intersections, reusing _candidatesBounds
    for i = 2, #candidates do
        Rectangle.unionInto(_candidatesBounds, candidates[i].intersection, _candidatesBounds)
    end

    return _candidatesBounds
end

return CollisionDetector
