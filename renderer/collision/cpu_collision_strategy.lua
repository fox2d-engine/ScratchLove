-- CPU Collision Detection Strategy
-- Optimized for small collision regions using direct pixel sampling

local CollisionStrategy = require("renderer.collision.collision_strategy")
local Global = require("global")
local ColorMatch = require("utils.color_match")
local FastPixelSampler = require("utils.fast_pixel")
local log = require("lib.log")
local bit = require("bit")

local bit_band = bit.band

---@class CPUCollisionStrategy: CollisionStrategy
local CPUCollisionStrategy = setmetatable({}, { __index = CollisionStrategy })
CPUCollisionStrategy.__index = CPUCollisionStrategy

---Create a new CPU collision strategy
---@return CPUCollisionStrategy
function CPUCollisionStrategy:new()
    local self = setmetatable(CollisionStrategy:new("CPU"), CPUCollisionStrategy)
    return self
end

---Check color collision using CPU-based pixel sampling
---@param sprite Sprite The sprite to check
---@param targetColor table RGB color to check for {r, g, b}
---@param spriteColor table|nil Optional sprite color mask {r, g, b}
---@param candidates table List of candidate sprites with intersection info
---@param bounds table Scratch coordinate bounds (required)
---@param runtime Runtime Runtime instance (required for background sampling)
---@return boolean collisionDetected Whether collision was detected
---@return number|nil collision_x X coordinate of collision point
---@return number|nil collision_y Y coordinate of collision point
function CPUCollisionStrategy:check(sprite, targetColor, spriteColor, candidates, bounds, runtime)
    if not bounds then
        log.warn("[CPU-Collision] No bounds provided")
        return false, nil, nil
    end

    if not runtime then
        log.warn("[CPU-Collision] No runtime provided")
        return false, nil, nil
    end

    -- Work directly in Scratch coordinates (no conversion needed!)
    local left = math.floor(bounds.left)
    local right = math.ceil(bounds.right)
    local bottom = math.floor(bounds.bottom) -- In Scratch: bottom < top
    local top = math.ceil(bounds.top)

    -- Clamp to Scratch stage bounds
    left = math.max(Global.SCRATCH_MIN_X, left)
    right = math.min(Global.SCRATCH_MAX_X, right)
    bottom = math.max(Global.SCRATCH_MIN_Y, bottom)
    top = math.min(Global.SCRATCH_MAX_Y, top)

    if left >= right or bottom >= top then
        return false, nil, nil
    end

    -- Convert target color to array format and 0-255 range
    local target_r, target_g, target_b = ColorMatch.normalizedToBytes(targetColor.r, targetColor.g, targetColor.b)

    -- Convert sprite color mask if provided
    local mask_r, mask_g, mask_b
    if spriteColor then
        mask_r, mask_g, mask_b = ColorMatch.normalizedToBytes(spriteColor.r, spriteColor.g, spriteColor.b)
    end

    -- Get configurable sampling step and alpha threshold
    local step = Global.COLLISION_SAMPLING_STEP
    local alphaThreshold = Global.COLLISION_ALPHA_THRESHOLD

    -- Pre-calculate target color mask for hot-path optimization
    -- This avoids repeating bitwise operations thousands of times in the inner loop
    local target_r_masked = bit_band(target_r, 0xF8)
    local target_g_masked = bit_band(target_g, 0xF8)
    local target_b_masked = bit_band(target_b, 0xF0)

    -- Pre-calculate sprite's inverse transform and sampler (matching native updateCPURenderAttributes)
    local spriteTransform = nil
    local spriteSampler = nil
    local spriteCostume = sprite:getCurrentCostume()
    if spriteCostume and spriteCostume.imageData then
        -- Get cached sampler
        if not spriteCostume._fastPixelSampler then
            spriteCostume._fastPixelSampler = FastPixelSampler:new(spriteCostume.imageData)
        end
        spriteSampler = spriteCostume._fastPixelSampler

        -- Get cached transform
        local transformCache = sprite:getTransformCache()
        if transformCache then
            spriteTransform = transformCache:getInverseTransform()
        end
    end

    -- Pre-fetch candidate transforms and samplers (matching native pattern)
    local candidateData = {}
    for _, candidateInfo in ipairs(candidates) do
        local candidate = candidateInfo.sprite -- Extract sprite from the structure
        local costume = candidate:getCurrentCostume()
        if costume and costume.imageData then
            -- Get cached sampler
            if not costume._fastPixelSampler then
                costume._fastPixelSampler = FastPixelSampler:new(costume.imageData)
            end

            -- Get cached transform
            local transformCache = candidate:getTransformCache()
            local transform = nil
            if transformCache then
                transform = transformCache:getInverseTransform()
            end

            if transform then
                table.insert(candidateData, {
                    sprite = candidate,
                    sampler = costume._fastPixelSampler,
                    transform = transform
                })
            end
        end
    end

    -- Iterate through pixels in the detection region (Scratch coordinates) with step
    for y = bottom, top, step do -- In Scratch: iterate from bottom to top
        for x = left, right, step do
            -- Already in Scratch coordinates - no conversion needed!
            local scratch_x = x
            local scratch_y = y

            -- Check if current sprite touches this point (matching native logic)
            local spriteHit = false
            if spriteColor then
                -- With color mask: use pre-fetched transform for fast sampling
                if spriteSampler and spriteTransform then
                    local r, g, b, a = spriteSampler:sampleWithTransform(spriteTransform, scratch_x, scratch_y)
                    if a > alphaThreshold then
                        -- Use native Scratch bitwise color matching
                        spriteHit = ColorMatch.colorMatches(r, g, b, mask_r, mask_g, mask_b)
                    end
                end
            else
                -- Without mask: use fast path with cached transform
                if spriteSampler and spriteTransform then
                    spriteHit = spriteSampler:touchesPointWithTransform(spriteTransform, scratch_x, scratch_y,
                        alphaThreshold)
                end
            end

            if spriteHit then
                -- Sample and blend colors from background/candidates
                local finalR, finalG, finalB = self:_sampleColorWithBlending(
                    candidateData, runtime, scratch_x, scratch_y)

                -- Optimized color match using pre-calculated masks (hot path optimization)
                -- This avoids 3 bitwise operations per pixel by using pre-computed target masks
                if bit_band(finalR, 0xF8) == target_r_masked and
                    bit_band(finalG, 0xF8) == target_g_masked and
                    bit_band(finalB, 0xF0) == target_b_masked then
                    return true, scratch_x, scratch_y
                end
            end
        end
    end

    return false, nil, nil
end

---Sample and blend colors from multiple sprites using alpha blending (matching native Scratch behavior)
---Uses OpenGL-style blending: gl.blendFunc(ONE, ONE_MINUS_SRC_ALPHA)
---@private
---@param candidateData table List of pre-processed candidate data {sprite, sampler, transform}
---@param runtime Runtime Runtime instance for pen/stage background
---@param scratch_x number X coordinate in Scratch space
---@param scratch_y number Y coordinate in Scratch space
---@return number r Red component (0-255)
---@return number g Green component (0-255)
---@return number b Blue component (0-255)
function CPUCollisionStrategy:_sampleColorWithBlending(candidateData, runtime, scratch_x, scratch_y)
    local finalR, finalG, finalB = 0, 0, 0
    local blendAlpha = 1.0

    local alphaThreshold = Global.COLLISION_ALPHA_THRESHOLD

    -- Blend all candidate sprites in reverse draw order (top to bottom)
    for i = #candidateData, 1, -1 do
        -- Early termination if completely opaque
        if blendAlpha == 0 then
            break
        end

        local data = candidateData[i]
        local r, g, b, a = data.sampler:sampleWithTransform(data.transform, scratch_x, scratch_y)

        -- Only blend if pixel is not fully transparent
        if a > alphaThreshold then
            -- Normalize alpha to 0-1 range
            local normalizedAlpha = a / 255

            -- Native Scratch: dst[0] = data[offset] * alpha
            local premultR = r * normalizedAlpha
            local premultG = g * normalizedAlpha
            local premultB = b * normalizedAlpha

            -- OpenGL-style blending: gl.blendFunc(ONE, ONE_MINUS_SRC_ALPHA)
            -- dst.rgb += (src.rgb * src.alpha) * blendAlpha
            -- blendAlpha *= (1 - src.alpha)
            finalR = finalR + premultR * blendAlpha
            finalG = finalG + premultG * blendAlpha
            finalB = finalB + premultB * blendAlpha
            blendAlpha = blendAlpha * (1 - normalizedAlpha)
        end
    end

    -- Native Scratch: backdrop → pen → sprites (bottom to top)
    -- Sampling order: sprites → pen → backdrop (top to bottom)
    if blendAlpha > 0 and runtime.penRenderer then
        local pen_r, pen_g, pen_b, pen_a = runtime.penRenderer:sampleColor(scratch_x, scratch_y)

        -- Only blend if pixel is not fully transparent
        if pen_a > alphaThreshold then
            -- Normalize alpha to 0-1 range
            local normalizedAlpha = pen_a / 255

            -- (shader sends premultiplied colors: u_penColor = {r*a, g*a, b*a, a})
            -- So we blend directly without additional premultiplication
            finalR = finalR + pen_r * blendAlpha
            finalG = finalG + pen_g * blendAlpha
            finalB = finalB + pen_b * blendAlpha
            blendAlpha = blendAlpha * (1 - normalizedAlpha)
        end
    end

    -- Add stage background color with remaining alpha
    -- Native Scratch: dst[0] += 255 * this._backgroundColor4f[0] * blendAlpha
    local bg = runtime.stage.backgroundColor
    if bg and blendAlpha > 0 then
        finalR = finalR + bg[1] * blendAlpha
        finalG = finalG + bg[2] * blendAlpha
        finalB = finalB + bg[3] * blendAlpha
    end

    -- Clamp to 0-255 range and return
    return math.min(255, math.max(0, finalR)),
        math.min(255, math.max(0, finalG)),
        math.min(255, math.max(0, finalB))
end

return CPUCollisionStrategy
