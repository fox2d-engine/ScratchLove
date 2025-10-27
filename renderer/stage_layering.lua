-- Stage Layering System
-- Manages Scratch-style layer ordering for rendering

---@class StageLayering
local StageLayering = {}

-- Layer constants (from back to front)
StageLayering.BACKGROUND_LAYER = 0
StageLayering.VIDEO_LAYER = 1
StageLayering.PEN_LAYER = 2
StageLayering.SPRITE_LAYER = 3

-- Default layer order ranges
StageLayering.BACKGROUND_MIN = -1000000
StageLayering.VIDEO_MIN = -999999
StageLayering.PEN_MIN = -999998
StageLayering.SPRITE_MIN = -999997
StageLayering.SPRITE_MAX = 1000000

-- Layer names for debugging
StageLayering.LAYER_NAMES = {
    [StageLayering.BACKGROUND_LAYER] = "BACKGROUND",
    [StageLayering.VIDEO_LAYER] = "VIDEO",
    [StageLayering.PEN_LAYER] = "PEN", 
    [StageLayering.SPRITE_LAYER] = "SPRITE"
}

---Get the layer for a given target
---@param target Sprite|Stage The target to get layer for
---@return number layer The layer number
function StageLayering:getTargetLayer(target)
    if target.isStage then
        return self.BACKGROUND_LAYER
    else
        return self.SPRITE_LAYER
    end
end

---Get display name for a layer
---@param layer number Layer number
---@return string name Layer display name
function StageLayering:getLayerName(layer)
    return self.LAYER_NAMES[layer] or ("LAYER_" .. tostring(layer))
end

---Check if a layer order value is valid for sprites
---@param layerOrder number Layer order value to check
---@return boolean valid Whether the value is valid for sprites
function StageLayering:isValidSpriteLayerOrder(layerOrder)
    return layerOrder >= self.SPRITE_MIN and layerOrder <= self.SPRITE_MAX
end

---Clamp layer order to valid sprite range
---@param layerOrder number Layer order value to clamp
---@return number clampedValue Clamped layer order value
function StageLayering:clampSpriteLayerOrder(layerOrder)
    return math.max(self.SPRITE_MIN, math.min(self.SPRITE_MAX, layerOrder))
end

return StageLayering