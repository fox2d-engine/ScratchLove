-- Frame Interpolation System
-- interpolation for smooth motion between logic frames

local log = require("lib.log")

local Interpolate = {}

-- Interpolation constants 
local CONSTANTS = {
    -- Position
    MIN_MOVEMENT = 0.1,        -- pixels (skip if smaller)
    TOLERANCE_MIN = 50,        -- pixels
    TOLERANCE_MAX = 240,       -- pixels
    TOLERANCE_SCALE = 1.5,     -- sprite size multiplier

    -- Ghost effect
    GHOST_MAX_CHANGE = 25,     -- units (0-100)

    -- Scale
    SCALE_MAX_CHANGE = 100,    -- percentage points

    -- Direction
    ANGLE_SNAP = 90            -- degrees (snap to 0°, 90°, 180°, 270°)
}

---Capture sprite state at frame start
---@param runtime Runtime The runtime instance
function Interpolate.setupInitialState(runtime)
    local renderer = runtime.renderer

    for _, target in ipairs(runtime.targets) do
        -- Reset renderer to actual end state (before interpolation)
        if renderer and target.interpolationData then
            -- Update renderer to show actual current state
            if not target.isStage then
                renderer:updateSpritePosition(target, target.x, target.y)
                renderer:updateSpriteRotation(target, target.direction)
                -- Scale: Sprite size is a single value, not scaleX/scaleY
                renderer:updateSpriteSize(target, target.size)
                renderer:updateSpriteEffect(target, "ghost", target.effects.ghost)
            end
        end

        -- Capture state for interpolation (visible, non-stage sprites only)
        if target.visible and not target.isStage then
            target.interpolationData = {
                x = target.x,
                y = target.y,
                direction = target.direction,
                scaleX = target.size,  -- In Scratch, size is a single value (not separate X/Y)
                scaleY = target.size,
                costumeIndex = target.currentCostume,
                ghost = target.effects.ghost or 0
            }
        else
            -- This prevents renderer from using stale interpolated values on visibility changes
            target.interpolationData = nil

            -- Clear all interpolated properties to ensure renderer falls back to actual values
            -- This is essential because setupInitialState runs in the logic thread BEFORE interpolation
            target._interpolatedX = nil
            target._interpolatedY = nil
            target._interpolatedDirection = nil
            target._interpolatedSize = nil
            target._interpolatedEffects = nil
        end
    end
end

---Interpolate sprite properties based on progress through frame
---@param runtime Runtime The runtime instance
---@param progress number Progress in frame (0.0 to 1.0)
function Interpolate.interpolate(runtime, progress)
    local renderer = runtime.renderer
    if not renderer then
        return
    end

    for _, target in ipairs(runtime.targets) do
        local interpData = target.interpolationData

        -- This prevents rendering stale interpolated state
        if not target.visible then
            target._interpolatedX = nil
            target._interpolatedY = nil
            target._interpolatedDirection = nil
            target._interpolatedSize = nil
            target._interpolatedEffects = nil
            goto continue
        end

        -- Skip if no interpolation data
        if not interpData then
            goto continue
        end

        -- POSITION INTERPOLATION
        local xDist = target.x - interpData.x
        local yDist = target.y - interpData.y
        local absXDist = math.abs(xDist)
        local absYDist = math.abs(yDist)

        if absXDist > CONSTANTS.MIN_MOVEMENT or absYDist > CONSTANTS.MIN_MOVEMENT then
            -- Get sprite bounds for tolerance calculation
            local bounds = target:getFastBounds()
            local spriteSize = (bounds.right - bounds.left) + (bounds.top - bounds.bottom)

            -- Tolerance: 50-240px based on sprite size
            local tolerance = math.min(
                CONSTANTS.TOLERANCE_MAX,
                math.max(CONSTANTS.TOLERANCE_MIN, CONSTANTS.TOLERANCE_SCALE * spriteSize)
            )

            local distance = math.sqrt(xDist * xDist + yDist * yDist)

            -- Only interpolate if movement is smooth (< tolerance)
            if distance < tolerance then
                local newX = interpData.x + (xDist * progress)
                local newY = interpData.y + (yDist * progress)
                renderer:updateSpritePosition(target, newX, newY)
            end
            -- Else: Large jump, render instantaneously (no update needed)
        end

        -- GHOST EFFECT INTERPOLATION
        local ghostChange = (target.effects.ghost or 0) - interpData.ghost
        local absGhostChange = math.abs(ghostChange)

        -- Only interpolate small changes (< 25 units)
        if absGhostChange > 0 and absGhostChange < CONSTANTS.GHOST_MAX_CHANGE then
            local newGhost = interpData.ghost + (ghostChange * progress)
            renderer:updateSpriteEffect(target, "ghost", newGhost)
        end

        -- DIRECTION AND SCALE INTERPOLATION
        -- Only if costume hasn't changed (costume change affects rendering)
        local costumeUnchanged = interpData.costumeIndex == target.currentCostume

        if costumeUnchanged and target.direction ~= interpData.direction then
            -- DIRECTION INTERPOLATION (SLERP)
            -- Skip 90-degree angles (0, 90, 180, 270) - tile-based games expect snapping
            if target.direction % CONSTANTS.ANGLE_SNAP ~= 0 or
               interpData.direction % CONSTANTS.ANGLE_SNAP ~= 0 then
                -- Spherical linear interpolation (slerp) for smooth rotation
                local currentRad = math.rad(target.direction)
                local startRad = math.rad(interpData.direction)

                local newDir = math.atan2(
                    math.sin(currentRad) * progress + math.sin(startRad) * (1 - progress),
                    math.cos(currentRad) * progress + math.cos(startRad) * (1 - progress)
                ) * 180 / math.pi

                renderer:updateSpriteRotation(target, newDir)
            end
            -- Else: 90° angle, snap without interpolation
        end

        if costumeUnchanged then
            -- SCALE INTERPOLATION
            local newScaleX = target.size
            local newScaleY = target.size
            local oldScaleX = interpData.scaleX
            local oldScaleY = interpData.scaleY

            if newScaleX ~= oldScaleX or newScaleY ~= oldScaleY then
                -- Skip if scale flips sign (e.g., -50 to +50 is a flip, not scaling)
                local sameSignX = (newScaleX >= 0) == (oldScaleX >= 0)
                local sameSignY = (newScaleY >= 0) == (oldScaleY >= 0)

                if sameSignX and sameSignY then
                    local changeX = newScaleX - oldScaleX
                    local changeY = newScaleY - oldScaleY

                    -- Skip large changes (>= 100%)
                    if math.abs(changeX) < CONSTANTS.SCALE_MAX_CHANGE and
                       math.abs(changeY) < CONSTANTS.SCALE_MAX_CHANGE then
                        local interpScaleX = oldScaleX + (changeX * progress)
                        local interpScaleY = oldScaleY + (changeY * progress)
                        -- In Scratch, size is a single value, so we use scaleX (they're the same)
                        renderer:updateSpriteSize(target, interpScaleX)
                    end
                end
            end
        end

        ::continue::
    end
end

return Interpolate
