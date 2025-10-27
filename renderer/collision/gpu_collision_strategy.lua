-- GPU Collision Detection Strategy
-- Optimized for large collision regions using GPU-accelerated rendering

local CollisionStrategy = require("renderer.collision.collision_strategy")
local Global = require("global")
local log = require("lib.log")
local ffi = require("ffi")
local math_floor = math.floor

ffi.cdef [[
    typedef struct { uint8_t r, g, b, a; } Pixel;
]]

---@class GPUCollisionStrategy: CollisionStrategy
---@field _collisionCanvas love.Canvas|nil Temporary canvas for collision detection
---@field _collisionShader love.Shader|nil Shader for collision detection with color mask
local GPUCollisionStrategy = setmetatable({}, { __index = CollisionStrategy })
GPUCollisionStrategy.__index = GPUCollisionStrategy

---Create a new GPU collision strategy
---@return GPUCollisionStrategy
function GPUCollisionStrategy:new()
    local self = setmetatable(CollisionStrategy:new("GPU"), GPUCollisionStrategy)
    self._collisionCanvas = nil
    self._collisionShader = nil
    return self
end

---Check color collision using GPU-accelerated rendering
---@param sprite Sprite The sprite to check
---@param targetColor table RGB color to check for {r, g, b}
---@param spriteColor table|nil Optional sprite color mask {r, g, b}
---@param candidates table List of candidate sprites with intersection info
---@param bounds table|nil Scratch coordinate bounds (not used in GPU strategy)
---@param runtime Runtime Runtime instance (required)
---@return boolean collisionDetected Whether collision was detected
---@return number|nil collision_x X coordinate of collision point
---@return number|nil collision_y Y coordinate of collision point
function GPUCollisionStrategy:check(sprite, targetColor, spriteColor, candidates, bounds, runtime)
    if not runtime then
        log.warn("[GPU-Collision] No runtime provided")
        return false, nil, nil
    end

    local costume = sprite:getCurrentCostume()
    if not costume or not costume.image then
        return false, nil, nil
    end

    -- Get sprite transform properties
    local sprite_image = costume.image
    local sprite_width = sprite_image:getWidth()
    local sprite_height = sprite_image:getHeight()
    local sprite_x = runtime:scratchToScreenX(sprite.x)
    local sprite_y = runtime:scratchToScreenY(sprite.y)

    local bitmapResolution = costume.bitmapResolution or 1
    local scale = sprite.size / 100
    local finalScale = scale / bitmapResolution

    local originX = costume.rotationCenterX or (sprite_width / 2)
    local originY = costume.rotationCenterY or (sprite_height / 2)

    local rotation = 0
    local scaleX = finalScale
    local scaleY = finalScale
    if sprite.rotationStyle == "all around" then
        rotation = math.rad(sprite.direction - 90)
    elseif sprite.rotationStyle == "left-right" and sprite.direction < 0 then
        scaleX = -finalScale
    end

    -- Create or reuse temporary canvas for collision detection
    if not self._collisionCanvas then
        self._collisionCanvas = love.graphics.newCanvas(Global.STAGE_WIDTH, Global.STAGE_HEIGHT)
    end
    if not self._collisionShader then
        -- Create shader for collision detection with optional color mask
        self._collisionShader = love.graphics.newShader [[
            uniform vec3 colorMask;
            uniform bool useColorMask;

            vec4 effect(vec4 color, Image texture, vec2 texture_coords, vec2 screen_coords) {
                vec4 pixel = Texel(texture, texture_coords);

                // Alpha threshold - discard transparent pixels
                if (pixel.a < 0.1) {
                    discard;
                }

                // Color mask - if enabled, only keep pixels matching the mask color
                if (useColorMask) {
                    vec3 diff = abs(colorMask - pixel.rgb);
                    // Tolerance of 3/255 to match Scratch native
                    if (any(greaterThan(diff, vec3(3.0/255.0)))) {
                        discard;
                    }
                }

                return pixel * color;
            }
        ]]
    end

    local temp_canvas = self._collisionCanvas

    -- Save graphics state
    local prev_canvas = love.graphics.getCanvas()
    local prev_blend_mode = love.graphics.getBlendMode()
    local prev_shader = love.graphics.getShader()

    -- Stencil function to define sprite shape with optional color mask
    local function sprite_stencil()
        love.graphics.push()
        love.graphics.translate(sprite_x, sprite_y)
        love.graphics.rotate(rotation)
        love.graphics.scale(scaleX, scaleY)
        love.graphics.setColor(1, 1, 1, 1)

        -- Configure shader with color mask if needed
        love.graphics.setShader(self._collisionShader)
        if spriteColor then
            -- Send color mask parameters to shader
            self._collisionShader:send("useColorMask", true)
            self._collisionShader:send("colorMask", { spriteColor.r, spriteColor.g, spriteColor.b })
        else
            -- Only use alpha threshold
            self._collisionShader:send("useColorMask", false)
        end

        love.graphics.draw(sprite_image, -originX, -originY)
        love.graphics.setShader()
        love.graphics.pop()
    end

    -- Set up canvas with stencil for background sampling
    love.graphics.setCanvas({ temp_canvas, stencil = true })
    love.graphics.clear(0, 0, 0, 0)

    -- Configure stencil - only non-transparent sprite pixels set stencil value to 1
    love.graphics.stencil(sprite_stencil, "replace", 1, false)

    -- Only draw in stencil area (where sprite is)
    love.graphics.setStencilTest("equal", 1)

    -- Draw the background layers in the stencil area
    love.graphics.setBlendMode("alpha", "premultiplied")
    love.graphics.setColor(1, 1, 1, 1)

    -- Draw stage backdrop
    if runtime.stage and runtime.stage.drawStage then
        -- Use runtime's renderer to draw stage
        if runtime.renderer then
            runtime.renderer:drawStage(runtime.stage)
        end
    end

    -- Draw pen layer
    if runtime.penRenderer then
        local penCanvas = runtime.penRenderer:getCanvas()
        local penRenderer = runtime.penRenderer
        -- Scale high-resolution pen canvas to fit stage size
        local scaleX = Global.STAGE_WIDTH / penRenderer.actualCanvasWidth
        local scaleY = Global.STAGE_HEIGHT / penRenderer.actualCanvasHeight
        love.graphics.draw(penCanvas, 0, 0, 0, scaleX, scaleY)
    end


    -- Draw candidate sprites that might be colliding
    for _, candidateInfo in ipairs(candidates) do
        local sp = candidateInfo.sprite -- Extract sprite from the structure
        if sp ~= sprite then
            -- Use runtime's renderer to draw sprite
            if runtime.renderer then
                runtime.renderer:drawSprite(sp)
            end
        end
    end

    -- Clear stencil test and restore state
    love.graphics.setStencilTest()
    love.graphics.setBlendMode(prev_blend_mode)
    love.graphics.setShader(prev_shader)
    love.graphics.setCanvas(prev_canvas)

    -- Calculate region to read (optimize by only reading sprite area)
    local diagonal = math.sqrt(sprite_width * sprite_width + sprite_height * sprite_height) * finalScale
    local half_diagonal = diagonal / 2

    -- Get DPI scale for pixel-perfect reading
    local dpiScale = love.graphics.getDPIScale()

    -- Calculate read region in pixels
    local region_x = math.max(0, math_floor((sprite_x - half_diagonal) * dpiScale))
    local region_y = math.max(0, math_floor((sprite_y - half_diagonal) * dpiScale))
    local region_w = math.min(love.graphics.getPixelWidth() - region_x, math.ceil(diagonal * dpiScale))
    local region_h = math.min(love.graphics.getPixelHeight() - region_y, math.ceil(diagonal * dpiScale))

    -- Boundary check
    if region_w <= 0 or region_h <= 0 then
        log.warn("[GPU-Collision] Region out of bounds, skipping check")
        return false, nil, nil
    end

    -- Read pixel data from the collision region
    local imagedata = temp_canvas:newImageData(1, 1, region_x, region_y, region_w, region_h)

    -- Convert target color to 0-255 range for comparison
    local target_r = math_floor(targetColor.r * 255 + 0.5)
    local target_g = math_floor(targetColor.g * 255 + 0.5)
    local target_b = math_floor(targetColor.b * 255 + 0.5)
    local epsilon = 25

    local pixels = ffi.cast("Pixel*", imagedata:getFFIPointer())
    local width = imagedata:getWidth()
    local height = imagedata:getHeight()

    -- Sample pixels for collision detection
    local step = 4 -- Step sampling for performance
    for y = 0, height - 1, step do
        local row_offset = y * width
        for x = 0, width - 1, step do
            local pixel = pixels[row_offset + x]

            if pixel.a > 25 then
                local dr = pixel.r > target_r and pixel.r - target_r or target_r - pixel.r
                if dr < epsilon then
                    local dg = pixel.g > target_g and pixel.g - target_g or target_g - pixel.g
                    if dg < epsilon then
                        local db = pixel.b > target_b and pixel.b - target_b or target_b - pixel.b
                        if db < epsilon then
                            local result_x = (region_x + x) / dpiScale
                            local result_y = (region_y + y) / dpiScale
                            return true, result_x, result_y
                        end
                    end
                end
            end
        end
    end

    return false, nil, nil
end

return GPUCollisionStrategy
