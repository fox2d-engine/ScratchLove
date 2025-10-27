-- Renderer
-- Handles rendering of sprites and stage
local Global = require("global")
local PolygonManager = require("utils.polygon")
local BubbleRenderer = require("renderer.bubble_renderer")
local DrawOrderManager = require("renderer.draw_order_manager")
local StageLayering = require("renderer.stage_layering")
local MonitorRenderer = require("renderer.monitor_renderer")
local CollisionDetector = require("renderer.collision.collision_detector")
local log = require("lib.log")

---@class Renderer
---@field runtime Runtime Runtime instance
---@field _nextDrawableId integer Counter for generating unique drawable IDs
---@field penCanvas love.Canvas Canvas for pen drawing
---@field shaders table<string, love.Shader> Loaded shaders
---@field effectOrder string[] Ordered list of shader effects
---@field shaderParamMap table<string, string> Map effect names to shader parameter names
---@field bubbleRenderer BubbleRenderer Simple bubble renderer
---@field drawOrderManager DrawOrderManager Manager for drawable ordering
---@field stageLayering StageLayering Layer management system
---@field monitorRenderer MonitorRenderer|nil Monitor display renderer
---@field collisionDetector CollisionDetector Collision detection manager
---@field _orderedSpritesCache Sprite[]|nil Cached array of ordered sprites
---@field _cacheValid boolean Whether the ordered sprites cache is valid
---@field _polygonManager PolygonManager Manager for polygon shapes and caching
-- batching removed
local Renderer = {}
Renderer.__index = Renderer

---Create a new renderer
---@param runtime Runtime Runtime instance
---@return Renderer
function Renderer:new(runtime)
    local self = setmetatable({}, Renderer)
    self.runtime = runtime

    -- Initialize drawable ID counter (like Scratch's _nextDrawableId)
    self._nextDrawableId = 1

    -- Pen rendering is now handled by Runtime's PenRenderer

    -- Load shaders and set effect order
    self.shaders = {}
    self.effectOrder = { "fisheye", "whirl", "pixelate", "mosaic", "brightness", "color" }
    -- Map effect names to shader parameter names
    self.shaderParamMap = {
        color = "colorEffect" -- Map 'color' effect to 'colorEffect' shader parameter
    }
    self:loadShaders()

    -- Initialize simple bubble renderer
    self.bubbleRenderer = BubbleRenderer:new()

    -- Initialize draw order management
    self.drawOrderManager = DrawOrderManager:new()
    self.stageLayering = StageLayering

    -- Initialize monitor renderer
    self.monitorRenderer = MonitorRenderer:new(runtime.monitorManager)

    -- Initialize sprite order cache
    self._orderedSpritesCache = nil
    self._cacheValid = false
    -- Sprite batching disabled for now

    self._polygonManager = PolygonManager:new()

    -- Initialize collision detector with a function to get ordered sprites
    self.collisionDetector = CollisionDetector:new(runtime, function()
        return self:_getOrderedSprites()
    end)

    return self
end

-- Batching path completely removed

---Invalidate the ordered sprites cache
function Renderer:_invalidateOrderCache()
    self._cacheValid = false
    self._orderedSpritesCache = nil
end

---Get ordered sprites from cache or rebuild cache
---@return Sprite[] orderedSprites Array of sprites in draw order
function Renderer:_getOrderedSprites()
    if self._cacheValid and self._orderedSpritesCache then
        return self._orderedSpritesCache
    end

    -- Rebuild cache
    local orderedDrawableIds = self.drawOrderManager:getDrawOrder()
    local orderedSprites = {}

    -- Map drawable IDs back to sprite objects
    for _, drawableId in ipairs(orderedDrawableIds) do
        local sprite = self:getSpriteFromDrawableId(drawableId)
        if sprite and sprite.visible then
            table.insert(orderedSprites, sprite)
        end
    end

    -- Cache the result
    self._orderedSpritesCache = orderedSprites
    self._cacheValid = true

    return orderedSprites
end

---Mark sprite as dirty for specific change type
---@param sprite table Sprite that changed
---@param changeType "costume"|"effects"|"transform"|"visibility"
function Renderer:markSpriteDirty(sprite, changeType)
    if changeType == "costume" then
    elseif changeType == "effects" then
    elseif changeType == "transform" then
    elseif changeType == "visibility" then
        -- Visibility changes affect the ordered sprites cache since only visible sprites are included
        self:_invalidateOrderCache()
    end
end

---Add a sprite to the draw order
---@param sprite Sprite Sprite to add
function Renderer:addSprite(sprite)
    -- Native behavior: Only create drawable if not already created
    if sprite.drawableId then
        log.warn("Renderer:addSprite - sprite already has drawableId: %s", sprite.drawableId)
        return
    end

    sprite.drawableId = tostring(self._nextDrawableId)
    self._nextDrawableId = self._nextDrawableId + 1
    local layer = self.stageLayering:getTargetLayer(sprite)
    -- layerOrder determines drawing order (lower values drawn first, appear behind)
    -- This ensures sprites render in correct visual stacking order regardless of execution order
    self.drawOrderManager:addDrawable(sprite.drawableId, layer, sprite.layerOrder)
    self:_invalidateOrderCache()
end

---Remove a sprite from the draw order
---@param sprite Sprite Sprite to remove
function Renderer:removeSprite(sprite)
    -- Native behavior: destroyDrawable but DO NOT clear drawableID
    if sprite.drawableId then
        self.drawOrderManager:removeDrawable(sprite.drawableId)
        self:_invalidateOrderCache()
        -- Note: Native Scratch does NOT clear drawableID here
        -- It remains set but the drawable is destroyed in the renderer
    end
end

---Move sprite behind another sprite
---@param sprite Sprite Sprite to move
---@param targetSprite Sprite Target sprite to move behind
---@return number|nil position New position, or nil if failed
function Renderer:moveSpriteBehind(sprite, targetSprite)
    local position = self.drawOrderManager:moveDrawableBehind(sprite.drawableId, targetSprite.drawableId)
    if position then
        self:_invalidateOrderCache()
    end
    return position
end

---Move sprite forward by positions
---@param sprite Sprite Sprite to move
---@param positions number Number of positions to move forward
function Renderer:moveSpriteForward(sprite, positions)
    self.drawOrderManager:moveDrawableForward(sprite.drawableId, positions)
    self:_invalidateOrderCache()
end

---Move sprite backward by positions
---@param sprite Sprite Sprite to move
---@param positions number Number of positions to move backward
function Renderer:moveSpriteBackward(sprite, positions)
    self.drawOrderManager:moveDrawableBackward(sprite.drawableId, positions)
    self:_invalidateOrderCache()
end

---Move sprite to front of its layer
---@param sprite Sprite Sprite to move to front
function Renderer:moveToFront(sprite)
    self.drawOrderManager:moveDrawableToFront(sprite.drawableId)
    self:_invalidateOrderCache()
end

---Move sprite to back of its layer
---@param sprite Sprite Sprite to move to back
function Renderer:moveToBack(sprite)
    self.drawOrderManager:moveDrawableToBack(sprite.drawableId)
    self:_invalidateOrderCache()
end

---Get sprite from drawable ID
---@param drawableId string Drawable ID to find sprite for
---@return Sprite|nil target Target object or nil if not found
function Renderer:getSpriteFromDrawableId(drawableId)
    if not drawableId then
        return nil
    end

    -- Search through runtime targets to find matching sprite
    for _, target in ipairs(self.runtime.targets) do
        if target.drawableId == drawableId then
            return target
        end
    end
    return nil
end

---Draw all sprites and stage
function Renderer:draw()
    -- Flush pen drawing commands at the START of draw
    -- This ensures pen content is synchronized with sprite rendering and interpolation
    -- Safe to call multiple times per frame - pen renderer tracks dirty state internally
    if self.runtime.penRenderer then
        self.runtime.penRenderer:flush()
    end

    -- Save graphics state
    love.graphics.push()

    -- Draw stage backdrop
    if self.runtime.stage then
        self:drawStage(self.runtime.stage)
    end

    -- Draw pen layer using runtime's pen renderer
    if self.runtime.penRenderer then
        local penCanvas = self.runtime.penRenderer:getCanvas()
        local penRenderer = self.runtime.penRenderer
        -- Scale high-resolution pen canvas to fit stage size
        local scaleX = Global.STAGE_WIDTH / penRenderer.actualCanvasWidth
        local scaleY = Global.STAGE_HEIGHT / penRenderer.actualCanvasHeight
        love.graphics.draw(penCanvas, 0, 0, 0, scaleX, scaleY)
    end

    -- Get ordered sprites from cache (optimized to avoid double traversal)
    local orderedSprites = self:_getOrderedSprites()

    -- Draw sprites individually in layer order (batching disabled)
    for _, sprite in ipairs(orderedSprites) do
        self:drawSprite(sprite)
        self:drawSpeechBubble(sprite)
    end

    -- Draw monitors on top of everything (like native Scratch)
    if self.monitorRenderer then
        self.monitorRenderer:draw(self.runtime)
    end

    -- Restore graphics state
    love.graphics.pop()
end

---@param stage Stage Stage instance
function Renderer:drawStage(stage)
    local backdrop = stage:getCurrentBackdrop()
    if backdrop and backdrop.image then
        love.graphics.push()

        -- Apply effects (shaders and ghost alpha)
        if next(stage.effects) ~= nil then
            self:applyEffects(stage.effects)
        end

        -- Stage is always centered on the screen
        local screenX = Global.STAGE_WIDTH / 2
        local screenY = Global.STAGE_HEIGHT / 2

        -- Get image dimensions and properties
        local iw = backdrop.image:getWidth()
        local ih = backdrop.image:getHeight()
        local bitmapResolution = backdrop.bitmapResolution or 1

        -- Backdrops are scaled down by their resolution, but not by a "size" property.
        local finalScale = 1.0 / bitmapResolution


        -- Get rotation center coordinates (the origin for transformations).
        -- This allows backdrops to have a specific center, even though they don't rotate.
        local originX = backdrop.rotationCenterX or (iw / 2)
        local originY = backdrop.rotationCenterY or (ih / 2)

        -- Stage does not rotate.
        local rotation = 0

        -- Use the powerful love.graphics.draw() with an explicit origin (ox, oy).
        love.graphics.draw(backdrop.image, screenX, screenY, rotation, finalScale, finalScale, originX, originY)

        -- Reset effects and restore state
        self:resetEffects()
        love.graphics.pop()
    else
        -- Fallback for no backdrop, with more detailed logging
        if not backdrop then
            log.warn("Stage has no current backdrop (currentCostume: %d, total costumes: %d)",
                stage.currentCostume, #stage.costumes)
        elseif not backdrop.image then
            log.warn("Backdrop has no image: " .. tostring(backdrop.name))
        end
        -- Default white background
        love.graphics.setColor(1, 1, 1, 1)
        love.graphics.rectangle("fill", 0, 0, Global.STAGE_WIDTH, Global.STAGE_HEIGHT)
    end
end

--- @param sprite Sprite Sprite to draw
function Renderer:drawSprite(sprite)
    local costume = sprite:getCurrentCostume()
    if not costume or not costume.image then
        log.warn("Renderer: Sprite '%s' has no valid costume to render", sprite.name)
        return
    end

    love.graphics.push()

    -- Use interpolated effects if available, otherwise use actual effects
    local effectsToUse = sprite._interpolatedEffects or sprite.effects

    -- Apply effects (shaders and ghost alpha)
    if next(effectsToUse) ~= nil then
        self:applyEffects(effectsToUse)
    end

    -- Use interpolated position if available, otherwise use actual position
    local posX = sprite._interpolatedX or sprite.x
    local posY = sprite._interpolatedY or sprite.y

    -- Convert Scratch coordinates to screen coordinates for the final position
    local screenX = self.runtime:scratchToScreenX(posX)
    local screenY = self.runtime:scratchToScreenY(posY)

    -- Get image dimensions and properties
    local iw = costume.image:getWidth()
    local ih = costume.image:getHeight()
    local bitmapResolution = costume.bitmapResolution or 1

    -- Use interpolated size if available, otherwise use actual size
    local sizeToUse = sprite._interpolatedSize or sprite.size

    -- Determine the final scale factor
    local scale = sizeToUse / 100
    local finalScale = scale / bitmapResolution


    -- Get rotation center coordinates (the origin for transformations).
    -- These are in original image pixel coordinates (e.g., for a 2x image, it's in the 2x coordinate space).
    local originX = costume.rotationCenterX or (iw / 2)
    local originY = costume.rotationCenterY or (ih / 2)

    -- Use interpolated direction if available, otherwise use actual direction
    local directionToUse = sprite._interpolatedDirection or sprite.direction

    -- Determine rotation and scale based on rotation style
    local rotation = 0
    local scaleX = finalScale
    local scaleY = finalScale

    if sprite.rotationStyle == "all around" then
        rotation = math.rad(directionToUse - 90)
    elseif sprite.rotationStyle == "left-right" and directionToUse < 0 then
        -- For left-right, we flip the horizontal scale instead of rotating.
        scaleX = -finalScale
    end

    -- Use the powerful love.graphics.draw() with an explicit origin (ox, oy).
    -- This correctly handles position, rotation, and scaling around the specified center.
    love.graphics.draw(costume.image, screenX, screenY, rotation, scaleX, scaleY, originX, originY)

    -- Reset effects and restore state
    self:resetEffects()
    love.graphics.pop()
end

function Renderer:drawSpeechBubble(sprite)
    if sprite.sayText then
        self.bubbleRenderer:drawBubble(sprite, sprite.sayText, "say", self.runtime)
    elseif sprite.thinkText then
        self.bubbleRenderer:drawBubble(sprite, sprite.thinkText, "think", self.runtime)
    end
end

---Wrap text to fit within a maximum width
---@param text string Text to wrap
---@param maxWidth number Maximum width in pixels
---@param font love.Font Font to use for measurement
---@return string[] lines Array of wrapped text lines
function Renderer:wrapText(text, maxWidth, font)
    local lines = {}
    local words = {}

    -- Split text into words
    for word in text:gmatch("%S+") do
        table.insert(words, word)
    end

    if #words == 0 then
        return { text }
    end

    local currentLine = ""

    for i, word in ipairs(words) do
        local testLine = currentLine == "" and word or (currentLine .. " " .. word)
        local lineWidth = font:getWidth(testLine)

        if lineWidth <= maxWidth then
            currentLine = testLine
        else
            -- Current word doesn't fit, start new line
            if currentLine ~= "" then
                table.insert(lines, currentLine)
                currentLine = word
            else
                -- Single word is too long, just add it anyway
                table.insert(lines, word)
                currentLine = ""
            end
        end
    end

    -- Add the last line
    if currentLine ~= "" then
        table.insert(lines, currentLine)
    end

    return #lines > 0 and lines or { text }
end

---Calculate sprite bounds for bubble positioning (using 8px slice like Scratch)
---@param sprite Sprite The sprite to get bounds for
---@return table bounds Sprite bounds {left, right, top, bottom} in Scratch coords
function Renderer:getSpriteBoundsForBubble(sprite)
    local costume = sprite:getCurrentCostume()
    local bounds = {
        left = sprite.x,
        right = sprite.x,
        top = sprite.y,
        bottom = sprite.y
    }

    -- Get accurate sprite bounds based on costume
    if costume then
        if costume.image then
            local bitmapResolution = costume.bitmapResolution or 1
            local imageWidth = costume.image:getWidth()
            local imageHeight = costume.image:getHeight()

            -- Get rotation center (default to image center if not specified)
            local rotationCenterX = costume.rotationCenterX or (imageWidth / 2)
            local rotationCenterY = costume.rotationCenterY or (imageHeight / 2)

            -- Calculate actual sprite dimensions accounting for bitmap resolution and size
            local scale = sprite.size / 100
            local actualWidth = (imageWidth / bitmapResolution) * scale
            local actualHeight = (imageHeight / bitmapResolution) * scale

            -- Calculate bounds relative to sprite position
            -- The rotation center offset needs to be scaled
            local offsetX = (rotationCenterX - imageWidth / 2) / bitmapResolution * scale
            local offsetY = (rotationCenterY - imageHeight / 2) / bitmapResolution * scale

            bounds.left = sprite.x - actualWidth / 2 - offsetX
            bounds.right = sprite.x + actualWidth / 2 - offsetX
            bounds.top = sprite.y + actualHeight / 2 + offsetY -- Top of sprite in Scratch coords
            bounds.bottom = sprite.y - actualHeight / 2 + offsetY
        end
    else
        -- No costume, use a small default size
        local defaultSize = 20 * (sprite.size / 100)
        bounds.left = sprite.x - defaultSize
        bounds.right = sprite.x + defaultSize
        bounds.top = sprite.y + defaultSize
        bounds.bottom = sprite.y - defaultSize
    end

    return bounds
end

---Load shaders with error handling for system compatibility
function Renderer:loadShaders()
    -- Check if shaders are supported on this system
    if love.graphics and love.graphics.newShader then
        local success, shader = pcall(love.graphics.newShader, "renderer/shaders/effects.glsl")
        if success then
            self.shaders.effects = shader
        else
            log.warn("Could not load visual effects shader, effects will be disabled")
            log.debug("Shader compilation error: " .. tostring(shader))
        end
    else
        log.warn("Shader support not available on this system, visual effects will be disabled")
    end
end

---Reset shader and color state after drawing with effects
function Renderer:resetEffects()
    love.graphics.setShader()
    love.graphics.setColor(1, 1, 1, 1)
end

---Apply visual effects to sprites/stage using native Scratch conversion formulas
---@param effects table<string, number> Table of effect names and values
function Renderer:applyEffects(effects)
    local r, g, b, a = 1, 1, 1, 1

    -- Ghost effect (transparency) - handle on CPU side matching native conversion
    if effects.ghost and effects.ghost ~= 0 then
        -- Native: u_ghost = 1 - (Math.max(0, Math.min(x, 100)) / 100)
        local ghostValue = math.max(0, math.min(effects.ghost, 100))
        a = 1 - (ghostValue / 100)
    end

    -- All other effects are handled by shader with native Scratch conversions
    local shader = self.shaders and self.shaders.effects
    local useShader = false
    if shader then
        for _, name in ipairs(self.effectOrder) do
            local scratchValue = effects[name] or 0
            local convertedValue = self:convertEffectValue(name, scratchValue)

            if convertedValue ~= 0 then
                useShader = true
            end

            -- Map effect name to shader parameter name
            local shaderParam = self.shaderParamMap[name] or name
            shader:send(shaderParam, convertedValue)
        end
    end

    if useShader then
        love.graphics.setShader(shader)
    else
        love.graphics.setShader()
    end

    love.graphics.setColor(r, g, b, a)
end

---Convert effect values using native Scratch conversion formulas
---@param effectName string Name of the effect
---@param scratchValue number Scratch effect value (-100 to 100 typically)
---@return number convertedValue Value for shader uniform
function Renderer:convertEffectValue(effectName, scratchValue)
    if effectName == "color" then
        -- Native: (x / 200) % 1
        return (scratchValue / 200) % 1
    elseif effectName == "fisheye" then
        -- Native: Math.max(0, (x + 100) / 100)
        return math.max(0, (scratchValue + 100) / 100)
    elseif effectName == "whirl" then
        -- Native: -x * Math.PI / 180
        return -scratchValue * math.pi / 180
    elseif effectName == "pixelate" then
        -- Native: Math.abs(x) / 10
        return math.abs(scratchValue) / 10
    elseif effectName == "mosaic" then
        -- Native: Math.max(1, Math.min(Math.round((Math.abs(x) + 10) / 10), 512))
        local value = math.floor((math.abs(scratchValue) + 10) / 10 + 0.5) -- Round
        return math.max(1, math.min(value, 512))
    elseif effectName == "brightness" then
        -- Native: Math.max(-100, Math.min(x, 100)) / 100
        return math.max(-100, math.min(scratchValue, 100)) / 100
    else
        -- No conversion needed
        return scratchValue
    end
end

---Draw sprite to a specific canvas (used for stamping)
---@param sprite Sprite Sprite to draw
---@param canvas love.Canvas Canvas to draw to
function Renderer:drawSpriteToCanvas(sprite, canvas)
    canvas:renderTo(function()
        self:drawSprite(sprite)
    end)
end

---Update sprite position for interpolation (direct renderer update without touching sprite properties)
---@param sprite Sprite Sprite to update
---@param x number New X position
---@param y number New Y position
function Renderer:updateSpritePosition(sprite, x, y)
    -- This is a rendering-only update that doesn't modify sprite.x or sprite.y
    -- Used by interpolation system to render sprites at intermediate positions
    sprite._interpolatedX = x
    sprite._interpolatedY = y
end

---Update sprite rotation for interpolation (direct renderer update without touching sprite properties)
---@param sprite Sprite Sprite to update
---@param direction number New direction in degrees
function Renderer:updateSpriteRotation(sprite, direction)
    -- This is a rendering-only update that doesn't modify sprite.direction
    -- Used by interpolation system to render sprites at intermediate rotations
    sprite._interpolatedDirection = direction
end

---Update sprite size for interpolation (direct renderer update without touching sprite properties)
---@param sprite Sprite Sprite to update
---@param size number New size percentage
function Renderer:updateSpriteSize(sprite, size)
    -- This is a rendering-only update that doesn't modify sprite.size
    -- Used by interpolation system to render sprites at intermediate sizes
    sprite._interpolatedSize = size
end

---Update sprite effect for interpolation (direct renderer update without touching sprite properties)
---@param sprite Sprite Sprite to update
---@param effectName string Effect name (e.g., "ghost")
---@param value number Effect value
function Renderer:updateSpriteEffect(sprite, effectName, value)
    -- This is a rendering-only update that doesn't modify sprite.effects
    -- Used by interpolation system to render sprites with intermediate effect values
    if not sprite._interpolatedEffects then
        sprite._interpolatedEffects = {}
    end
    sprite._interpolatedEffects[effectName] = value
end

---Draw sprite using transform snapshot to a specific canvas (used for pen stamp with queue)
---@param transform table Transform snapshot with x, y, size, direction, rotationStyle, costume, effects
---@param canvas love.Canvas Canvas to draw to
---@param renderQuality number Canvas resolution multiplier (default 1)
function Renderer:drawSpriteWithTransform(transform, canvas, renderQuality)
    local costume = transform.costume
    if not costume or not costume.image then
        log.warn("Renderer: Transform has no valid costume to render")
        return
    end

    renderQuality = renderQuality or 1

    canvas:renderTo(function()
        love.graphics.push()

        -- Apply effects from transform snapshot
        if next(transform.effects) ~= nil then
            self:applyEffects(transform.effects)
        end

        -- Convert Scratch coordinates to screen coordinates
        local screenX = self.runtime:scratchToScreenX(transform.x)
        local screenY = self.runtime:scratchToScreenY(transform.y)

        -- Apply renderQuality scaling for high-resolution canvas
        screenX = screenX * renderQuality
        screenY = screenY * renderQuality

        -- Get image dimensions and properties
        local iw = costume.image:getWidth()
        local ih = costume.image:getHeight()
        local bitmapResolution = costume.bitmapResolution or 1

        -- Determine the final scale factor (include renderQuality)
        local scale = transform.size / 100
        local finalScale = scale / bitmapResolution * renderQuality

        -- Get rotation center coordinates
        local originX = costume.rotationCenterX or (iw / 2)
        local originY = costume.rotationCenterY or (ih / 2)

        -- Determine rotation and scale based on rotation style
        local rotation = 0
        local scaleX = finalScale
        local scaleY = finalScale

        if transform.rotationStyle == "all around" then
            rotation = math.rad(transform.direction - 90)
        elseif transform.rotationStyle == "left-right" and transform.direction < 0 then
            scaleX = -finalScale
        end

        -- Draw costume with transform parameters
        love.graphics.draw(costume.image, screenX, screenY, rotation, scaleX, scaleY, originX, originY)

        -- Reset effects and restore state
        self:resetEffects()
        love.graphics.pop()
    end)
end

---Get background color at Scratch coordinates by sampling stage and pen layers
---@param scratchX number Scratch coordinate X
---@param scratchY number Scratch coordinate Y
---@return table|nil color RGB color {r, g, b} or nil if out of bounds
function Renderer:getBackgroundColorAt(scratchX, scratchY)
    -- Convert Scratch coordinates to screen coordinates
    local screenX = self.runtime:scratchToScreenX(scratchX)
    local screenY = self.runtime:scratchToScreenY(scratchY)

    -- Check if coordinates are within stage bounds
    if screenX < 0 or screenX >= Global.STAGE_WIDTH or
        screenY < 0 or screenY >= Global.STAGE_HEIGHT then
        return nil
    end

    -- Create a 1x1 canvas for sampling
    local sampleCanvas = love.graphics.newCanvas(1, 1)
    love.graphics.setCanvas(sampleCanvas)

    -- Clear canvas to transparent
    love.graphics.clear(0, 0, 0, 0)

    -- Set up coordinate system for sampling just one pixel
    love.graphics.push()
    love.graphics.translate(-screenX, -screenY)

    -- Draw stage backdrop at the sampling position
    if self.runtime.stage then
        self:drawStage(self.runtime.stage)
    end

    -- Draw pen layer
    if self.runtime.penRenderer then
        local penCanvas = self.runtime.penRenderer:getCanvas()
        local penRenderer = self.runtime.penRenderer
        -- Scale high-resolution pen canvas to fit stage size
        local scaleX = Global.STAGE_WIDTH / penRenderer.actualCanvasWidth
        local scaleY = Global.STAGE_HEIGHT / penRenderer.actualCanvasHeight
        love.graphics.draw(penCanvas, 0, 0, 0, scaleX, scaleY)
    end

    love.graphics.pop()
    love.graphics.setCanvas()

    -- Read the pixel color
    local imageData = sampleCanvas:newImageData()
    local r, g, b, a = imageData:getPixel(0, 0)

    -- Clean up
    sampleCanvas:release()
    imageData:release()

    -- Return RGB color (ignore alpha for background sampling) - array format for performance
    return { r, g, b }
end

---Check pixel-perfect color collision between sprite and target color
---@param sprite Sprite Sprite to check collision for
---@param targetColor table RGB color to check collision with {r, g, b} (0-1 range)
---@param spriteColor table|nil Optional sprite color mask {r, g, b} (0-1 range)
---@return boolean collision True if collision detected
---@return number|nil x X coordinate of collision point (screen coordinates)
---@return number|nil y Y coordinate of collision point (screen coordinates)
function Renderer:checkColorCollision(sprite, targetColor, spriteColor)
    -- Delegate to collision detector
    return self.collisionDetector:checkColorCollision(sprite, targetColor, spriteColor)
end

-- Collision detection methods moved to renderer/collision/ module
-- See: CollisionDetector, CPUCollisionStrategy, GPUCollisionStrategy
return Renderer
