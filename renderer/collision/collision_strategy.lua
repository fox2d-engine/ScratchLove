-- Collision Strategy Base Class
-- Defines the interface for collision detection strategies (CPU and GPU)

---@class CollisionStrategy
---@field name string Strategy name for debugging
local CollisionStrategy = {}
CollisionStrategy.__index = CollisionStrategy

---Create a new collision strategy
---@param name string Strategy name
---@return CollisionStrategy
function CollisionStrategy:new(name)
    local self = setmetatable({}, CollisionStrategy)
    self.name = name or "Unknown"
    return self
end

---Check color collision between sprite and target color
---This method must be implemented by subclasses
---@param sprite Sprite The sprite to check
---@param targetColor table RGB color to check for {r, g, b}
---@param spriteColor table|nil Optional sprite color mask {r, g, b}
---@param candidates table List of candidate sprites with intersection info
---@param bounds table|nil Scratch coordinate bounds (required for CPU strategy)
---@param runtime Runtime Runtime instance (required for GPU strategy)
---@return boolean collisionDetected Whether collision was detected
---@return number|nil collision_x X coordinate of collision point
---@return number|nil collision_y Y coordinate of collision point
function CollisionStrategy:check(sprite, targetColor, spriteColor, candidates, bounds, runtime)
    error(string.format("CollisionStrategy:check() must be implemented in %s", self.name))
end

return CollisionStrategy
