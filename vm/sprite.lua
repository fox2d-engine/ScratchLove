-- Sprite
-- Represents a Scratch sprite
local Global = require("global")
local Variable = require("vm.variable")
local log = require("lib.log")
local Cast = require("utils.cast")
local TransformCache = require("utils.transform_cache")
local ProjectModel = require("parser.project_model")

---@class InterpolationData
---@field x number Position at frame start
---@field y number Position at frame start
---@field direction number Rotation at frame start (degrees)
---@field scaleX number Scale X at frame start (percentage)
---@field scaleY number Scale Y at frame start (percentage)
---@field costumeIndex number Costume index at frame start
---@field ghost number Ghost effect at frame start (0-100)

---@class Sprite : SpriteTemplate
---@field runtime Runtime Runtime instance
---@field spriteTemplate SpriteTemplate Reference to sprite template (shared data)
---@field isStage boolean Whether this is the stage (always false)
---@field drawableId string Unique drawable ID assigned by renderer
---@field layerOrder number|nil Layer order for rendering (Z-index, lower = behind)
---@field isClone boolean Whether this is a clone
---@field variables table<string, Variable> Sprite-specific variables
---@field currentCostume integer Current costume index
---@field visible boolean Whether sprite is visible
---@field x number X position in Scratch coordinates
---@field y number Y position in Scratch coordinates
---@field size number Size percentage (100 = normal)
---@field direction number Direction in degrees (0 = up)
---@field draggable boolean Whether sprite can be dragged
---@field rotationStyle string Rotation style ("all around", "left-right", "don't rotate")
---@field volume number Volume percentage (0-100)
---@field effects table<string, number> Graphics effects
---@field penDown boolean Whether pen is down
---@field penSize number Pen stroke size
---@field penColor number[] Pen color [r,g,b]
---@field sayText string|nil Current say text
---@field sayUntil number|nil Say text expiration time
---@field thinkText string|nil Current think text
---@field thinkUntil number|nil Think text expiration time
---@field bubbleOnRight boolean|nil Whether bubble should appear on sprite's right side
---@field penState PenState|nil Pen state (if sprite uses pen)
---@field _transformCache TransformCache Unified transform cache manager
---@field _compiledStates table<string, table> Compiled state storage for complex operations
---@field interpolationData InterpolationData|nil Interpolation state (nil = not interpolating)
local Sprite = {}
Sprite.__index = Sprite

---Create a new sprite from a sprite template (for clones)
---@param spriteTemplate SpriteTemplate Sprite template with shared data
---@param runtime Runtime Runtime instance
---@return Sprite
function Sprite:newFromTemplate(spriteTemplate, runtime)
    -- Set up inheritance: Sprite inherits from SpriteTemplate
    local self = setmetatable({}, {
        __index = function(t, k)
            -- First check Sprite methods/fields
            local spriteValue = Sprite[k]
            if spriteValue ~= nil then
                return spriteValue
            end
            -- Then check SpriteTemplate for shared data (blocks, costumes, etc.)
            return spriteTemplate[k]
        end
    })


    self.runtime = runtime
    self.spriteTemplate = spriteTemplate

    -- Clone state (to be set by SpriteTemplate:createClone)
    self.isClone = true

    -- Instance-specific runtime state
    self.variables = {}
    self.currentCostume = 1
    self.visible = true
    self.x = 0
    self.y = 0
    self.size = 100
    self.direction = 90
    self.draggable = false
    self.rotationStyle = "all around"
    self.volume = 100

    -- Sound effects (pitch and pan)
    self.soundEffects = { pitch = 0, pan = 0 }

    -- Graphics effects
    self.effects = {
        color = 0,
        fisheye = 0,
        whirl = 0,
        pixelate = 0,
        mosaic = 0,
        brightness = 0,
        ghost = 0
    }

    -- Say/think bubble
    self.sayText = nil
    self.sayUntil = nil
    self.thinkText = nil
    self.thinkUntil = nil
    self.bubbleOnRight = true

    -- Unified transform cache
    self._transformCache = TransformCache:new(self)

    -- Compiled state storage for complex operations (glide, say/think timers, etc.)
    self._compiledStates = {}

    -- Interpolation data for frame smoothing
    -- nil means: not interpolating (sprite hidden, is stage, or first frame)
    self.interpolationData = nil

    return self
end

---Initialize sprite variables and lists
function Sprite:initialize()
    if self.initialized then
        return
    end
    self.initialized = true
    -- Load costumes (lazy loading: store getImage closures, don't create textures yet)
    for i, costume in ipairs(self.costumes) do
        local asset = self.runtime.project:getAsset(costume.assetId)
        if asset and asset.type == "image" then
            -- Lazy loading: store closures instead of creating textures immediately
            costume.image = nil                        -- Will be loaded on first access
            costume._getImage = asset.getImage         -- Closure to create Image on demand
            costume._getImageData = asset.getImageData -- Closure for lazy ImageData loading

            if asset.originalFormat == "svg" then
                -- SVG was rasterized at 2x resolution for better quality
                -- Override the bitmapResolution from project JSON
                -- Only adjust if not already adjusted (to avoid double-scaling on clones)
                costume.bitmapResolution = Global.SVG_RESOLUTION_SCALE
                -- Rotation center values in project JSON are in CSS pixel units (1x).
                -- We need to scale them to match our 2x texture.
                -- Only scale if this is the first time loading (not a clone)
                if costume.rotationCenterX then
                    costume.rotationCenterX = costume.rotationCenterX * Global.SVG_RESOLUTION_SCALE
                end
                if costume.rotationCenterY then
                    costume.rotationCenterY = costume.rotationCenterY * Global.SVG_RESOLUTION_SCALE
                end

                -- Compensate for viewBox offset (matching native Scratch)
                -- In Scratch, rotationCenter is relative to viewBox coordinates
                -- When viewBox has non-zero origin, we need to subtract that offset
                if asset.viewBoxOffsetX and asset.viewBoxOffsetX ~= 0 then
                    local offsetX = asset.viewBoxOffsetX * Global.SVG_RESOLUTION_SCALE
                    costume.rotationCenterX = (costume.rotationCenterX or 0) - offsetX
                    log.debug("Applied viewBox X offset: %.2f (scaled: %.2f)",
                        asset.viewBoxOffsetX, offsetX)
                end
                if asset.viewBoxOffsetY and asset.viewBoxOffsetY ~= 0 then
                    local offsetY = asset.viewBoxOffsetY * Global.SVG_RESOLUTION_SCALE
                    costume.rotationCenterY = (costume.rotationCenterY or 0) - offsetY
                    log.debug("Applied viewBox Y offset: %.2f (scaled: %.2f)",
                        asset.viewBoxOffsetY, offsetY)
                end

                log.debug(
                    "Sprite %s: SVG costume %s set to bitmapResolution=%d, rotation center: %.1f,%.1f",
                    self.name, costume.name,
                    costume.bitmapResolution,
                    costume.rotationCenterX or 0,
                    costume.rotationCenterY or 0)
            end
        end
    end

    -- Load sounds
    for i, sound in ipairs(self.sounds) do
        local asset = self.runtime.project:getAsset(sound.assetId)
        if asset and asset.type == "sound" then
            sound.source = asset.data
        end
    end
end

---Update sprite for one frame
---@param dt number Delta time in seconds
function Sprite:update(dt)
    -- Update say/think bubbles
    if self.sayUntil and love.timer.getTime() >= self.sayUntil then
        self.sayText = nil
        self.sayUntil = nil
    end

    if self.thinkUntil and love.timer.getTime() >= self.thinkUntil then
        self.thinkText = nil
        self.thinkUntil = nil
    end
end

---Get the current costume
---@return Costume|nil costume Current costume or nil
function Sprite:getCurrentCostume()
    local index = math.floor(self.currentCostume) + 1
    if index < 1 then
        index = 1
    end
    if index > #self.costumes then
        index = #self.costumes
    end

    local costume = self.costumes[index]

    if costume then
        -- Lazy loading: ensure image is loaded before returning
        if not costume.image then
            ProjectModel.ensureImage(costume)
        end

        -- Track usage for LRU cache management
        costume.lastUsedTime = love.timer.getTime()
        costume.useCount = (costume.useCount or 0) + 1
    end

    return costume
end

---Switch to a costume by name or index (follows Scratch logic)
---@param requestedCostume any Costume name, index, or special value
function Sprite:switchCostume(requestedCostume)
    local oldCostume = self.currentCostume

    if #self.costumes == 0 then
        return
    end

    local index

    -- Handle different types following native Scratch logic
    if type(requestedCostume) == "number" then
        -- Numbers are treated as indices (1-based, convert to 0-based)
        index = requestedCostume - 1
    else
        -- All other types: convert to string and try different approaches
        local costumeStr = tostring(requestedCostume)

        -- 1. Try to find by exact name first
        local found = false
        for i, costume in ipairs(self.costumes) do
            if costume.name == costumeStr then
                index = i - 1
                found = true
                break
            end
        end

        if not found then
            -- 2. Check for special commands
            local lower = costumeStr:lower()
            if lower == "next costume" then
                index = self.currentCostume + 1
            elseif lower == "previous costume" then
                index = self.currentCostume - 1
            elseif lower == "next backdrop" or lower == "previous backdrop" then
                -- Costume switching ignores backdrop commands - do nothing
                return
            else
                -- 3. Try to parse as number (only if not whitespace-only)
                local isWhitespace = costumeStr:match("^%s*$")
                if not isWhitespace then
                    local num = tonumber(costumeStr)
                    if num then
                        index = num - 1 -- Convert to 0-based
                    else
                        -- Special handling for boolean strings like native Scratch
                        if costumeStr == "true" then
                            index = 0  -- First costume (Number("true") -> NaN -> 0)
                        elseif costumeStr == "false" then
                            index = -1 -- Will wrap to last costume
                        else
                            -- Invalid input - do nothing
                            return
                        end
                    end
                else
                    -- Whitespace-only - do nothing
                    return
                end
            end
        end
    end

    -- Unified processing: round and handle special values like native Scratch
    index = math.floor(index + 0.5) -- Round to nearest integer

    -- Handle special values (Infinity, -Infinity, NaN)
    if index == math.huge or index == -math.huge or index ~= index then
        index = 0 -- First costume
    end

    self.currentCostume = Cast.wrapClamp(index, 0, #self.costumes - 1)

    -- Notify renderer if costume actually changed
    if oldCostume ~= self.currentCostume then
        -- Trigger texture cleanup (time-based LRU)
        if Global.ENABLE_TEXTURE_CLEANUP then
            self:cleanupUnusedCostumes()
        end

        -- Mark transform cache as dirty
        if self._transformCache then
            self._transformCache:markDirty()
        end
        if self.runtime and self.runtime.renderer then
            self.runtime.renderer:markSpriteDirty(self, "costume")
        end
        if self.visible and self.runtime then
            self.runtime:requestRedraw()
        end
    end
end

---Switch to the next costume
function Sprite:nextCostume()
    local oldCostume = self.currentCostume
    self.currentCostume = (self.currentCostume + 1) % #self.costumes

    -- Notify renderer if costume changed
    if oldCostume ~= self.currentCostume then
        -- Trigger texture cleanup (time-based LRU)
        if Global.ENABLE_TEXTURE_CLEANUP then
            self:cleanupUnusedCostumes()
        end

        -- Mark transform cache as dirty
        if self._transformCache then
            self._transformCache:markDirty()
        end
        if self.runtime and self.runtime.renderer then
            self.runtime.renderer:markSpriteDirty(self, "costume")
        end
        if self.visible and self.runtime then
            self.runtime:requestRedraw()
        end
    end
end

---Clean up unused costume textures based on time-based LRU
---Removes textures that haven't been used for Global.COSTUME_EXPIRE_SECONDS
---@param expireSeconds number|nil Override expire time (defaults to Global.COSTUME_EXPIRE_SECONDS)
---@return number cleaned Number of costumes cleaned up
function Sprite:cleanupUnusedCostumes(expireSeconds)
    expireSeconds = expireSeconds or Global.COSTUME_EXPIRE_SECONDS

    local currentTime = love.timer.getTime()
    local currentCostumeIndex = self.currentCostume + 1
    local cleaned = 0

    -- Iterate through all costumes and clean up expired ones
    for i, costume in ipairs(self.costumes) do
        -- Skip current costume (never clean up what's being displayed)
        if i ~= currentCostumeIndex and costume.image then
            local timeSinceUse = currentTime - (costume.lastUsedTime or 0)

            -- Check if costume has expired
            if timeSinceUse > expireSeconds then
                -- Release the texture (allow GC)
                costume.image = nil
                costume._imageData = nil
                costume._fastPixelSampler = nil

                log.info("[Sprite %s] Cleaned up expired costume '%s': unused for %.1fs",
                    self.name or "unknown",
                    costume.name or "unknown", timeSinceUse)
                cleaned = cleaned + 1
            end
        end
    end

    return cleaned
end

---Move forward by the specified number of steps
---@param steps number Number of steps to move
function Sprite:move(steps)
    -- Use native Scratch angle calculation: 90 - direction (not direction - 90)
    local radians = math.rad(90 - self.direction)
    local newX = self.x + steps * math.cos(radians)
    local newY = self.y + steps * math.sin(radians)
    if self.x ~= newX or self.y ~= newY then
        self:setXY(newX, newY)
    end

    -- Update pen drawing if sprite has pen state
    if self.penState and self.runtime and self.runtime.penRenderer then
        self.penState:updatePosition(self.x, self.y, self.runtime.penRenderer)
    end
end

---Turn right by the specified degrees
---@param degrees number Degrees to turn
function Sprite:turnRight(degrees)
    self:setDirection(self.direction + degrees)
end

---Turn left by the specified degrees
---@param degrees number Degrees to turn
function Sprite:turnLeft(degrees)
    self:setDirection(self.direction - degrees)
end

---Set the sprite direction
---@param direction number Direction in degrees
function Sprite:setDirection(direction)
    -- Keep direction between -179 and +180 (matching official Scratch)
    local newDirection = Cast.wrapClamp(direction, -179, 180)
    if self.direction ~= newDirection then
        self.direction = newDirection
        -- Mark transform cache as dirty when direction changes
        if self._transformCache then
            self._transformCache:markDirty()
        end
        if self.visible and self.runtime then
            self.runtime:requestRedraw()
        end
    else
        self.direction = newDirection
    end
end

---Point towards a target position
---@param targetX number Target X coordinate
---@param targetY number Target Y coordinate
function Sprite:pointTowards(targetX, targetY)
    local dx = targetX - self.x
    local dy = targetY - self.y

    if dx == 0 and dy == 0 then
        return
    end

    -- Use native Scratch calculation: 90 - atan2(dy, dx)
    local direction = 90 - math.deg(math.atan2(dy, dx))
    self:setDirection(direction)
end

---Go to a specific position
---@param x number Target X coordinate
---@param y number Target Y coordinate
function Sprite:goTo(x, y)
    self.x = x
    self.y = y
    -- Native Scratch does NOT automatically keep sprites in bounds

    -- Update pen drawing if sprite has pen state
    if self.penState and self.runtime and self.runtime.penRenderer then
        self.penState:updatePosition(self.x, self.y, self.runtime.penRenderer)
    end

    if self.visible and self.runtime then
        self.runtime:requestRedraw()
    end
end

---Glide to a position over time (placeholder)
---@param x number Target X coordinate
---@param y number Target Y coordinate
---@param duration number Glide duration in seconds
function Sprite:glide(x, y, duration)
    -- This would need to be handled by the thread
    -- Return target position and duration
    return {
        x = x,
        y = y,
        duration = duration
    }
end

---Change X position by delta
---@param dx number X position change
function Sprite:changeX(dx)
    self.x = self.x + dx
    -- Native Scratch does NOT automatically keep sprites in bounds

    -- Update pen drawing if sprite has pen state
    if self.penState and self.runtime and self.runtime.penRenderer then
        self.penState:updatePosition(self.x, self.y, self.runtime.penRenderer)
    end

    if self.visible and self.runtime then
        self.runtime:requestRedraw()
    end
end

---Change Y position by delta
---@param dy number Y position change
function Sprite:changeY(dy)
    self.y = self.y + dy
    -- Native Scratch does NOT automatically keep sprites in bounds

    -- Update pen drawing if sprite has pen state
    if self.penState and self.runtime and self.runtime.penRenderer then
        self.penState:updatePosition(self.x, self.y, self.runtime.penRenderer)
    end

    if self.visible and self.runtime then
        self.runtime:requestRedraw()
    end
end

---Set X position
---@param x number New X position
function Sprite:setX(x)
    -- Use setXY to ensure fencing is applied
    self:setXY(x, self.y)
end

---@param x number New X position
---@param y number New Y position
function Sprite:setXY(x, y)
    if self.isStage then return end

    -- Apply fencing if enabled (native Scratch always has fencing enabled)
    if self.runtime and self.runtime.runtimeOptions.fencing then
        x, y = self:keepInFence(x, y)
    end

    self.x = x
    self.y = y

    -- Update pen drawing if sprite has pen state
    if self.penState and self.runtime and self.runtime.penRenderer then
        self.penState:updatePosition(self.x, self.y, self.runtime.penRenderer)
    end

    if self.visible and self.runtime then
        self.runtime:requestRedraw()
    end
end

---Set Y position
---@param y number New Y position
function Sprite:setY(y)
    -- Use setXY to ensure fencing is applied
    self:setXY(self.x, y)
end

---Get sprite's bounding box considering size and costume dimensions
---@return number left Left boundary
---@return number right Right boundary
---@return number top Top boundary
---@return number bottom Bottom boundary
function Sprite:getBounds()
    local costume = self:getCurrentCostume()
    if not costume then
        -- Fallback to point if no costume
        return self.x, self.x, self.y, self.y
    end

    local width, height = 64, 64 -- Default dimensions

    -- Get dimensions from raster image if present, else fallback
    if costume.image then
        local bitmapResolution = costume.bitmapResolution or 1
        local costumeScale = 1.0 / bitmapResolution
        width = costume.image:getWidth() * costumeScale
        height = costume.image:getHeight() * costumeScale
    end

    -- Apply sprite scaling
    local scale = self.size / 100
    width = width * scale
    height = height * scale

    -- Calculate bounds around center point
    local halfWidth = width / 2
    local halfHeight = height / 2

    return self.x - halfWidth, self.x + halfWidth, -- left, right
        self.y + halfHeight, self.y - halfHeight   -- top, bottom (Y is flipped)
end

---Get fast bounds using smart selection between precise and AABB
---Mimics native Scratch getFastBounds behavior for optimal performance
---@param result Rectangle|nil Optional result rectangle to reuse (avoids allocation)
---@return Rectangle rect The best available bounds
function Sprite:getFastBounds(result)
    return self._transformCache:getFastBounds(result)
end

---Get snapped (integer bounds) bounds for collision detection
---This is more efficient than calling getFastBounds + snapToInt separately
---@param result Rectangle|nil Optional result rectangle to reuse (avoids allocation)
---@return Rectangle rect Snapped bounds with integer coordinates
function Sprite:getSnappedBounds(result)
    return self._transformCache:getSnappedBounds(result)
end

---Get AABB bounds (fast but less accurate)
---@return Rectangle rect Axis-aligned bounding box
function Sprite:getAABB()
    return self._transformCache:getTransformedAABB()
end

function Sprite:keepInBounds()
    -- Keep sprite within stage bounds
    self.x = math.max(Global.SCRATCH_MIN_X, math.min(Global.SCRATCH_MAX_X, self.x))
    self.y = math.max(Global.SCRATCH_MIN_Y, math.min(Global.SCRATCH_MAX_Y, self.y))
end

---Keep a desired position within stage bounds
---Matches native Scratch fencing behavior with FENCE_WIDTH inset
---@param newX number New desired X position
---@param newY number New desired Y position
---@return number fencedX Fenced X coordinate
---@return number fencedY Fenced Y coordinate
function Sprite:keepInFence(newX, newY)
    -- Native: "For compatibility with Scratch 2, we always use getAABB."
    local aabb = self:getAABB()
    local currentLeft, currentRight = aabb.left, aabb.right
    local currentTop, currentBottom = aabb.top, aabb.bottom

    -- Calculate AABB dimensions
    local width = currentRight - currentLeft
    local height = currentTop - currentBottom

    -- Calculate inset: smaller of (half sprite size) or FENCE_WIDTH
    -- This ensures small sprites can have up to half their size off-screen
    -- and large sprites can have up to FENCE_WIDTH pixels off-screen
    local inset = math.floor(math.min(width, height) / 2)
    local fenceInset = math.min(Global.FENCE_WIDTH, inset)

    -- Adjust fence boundaries by inset
    -- This allows sprite to go beyond stage edge, but must keep fenceInset pixels visible
    local sx = Global.SCRATCH_MAX_X - fenceInset -- Right boundary
    local sy = Global.SCRATCH_MAX_Y - fenceInset -- Top boundary

    -- Calculate proposed bounds at new position
    local dx = newX - self.x
    local dy = newY - self.y
    local newRight = currentRight + dx
    local newLeft = currentLeft + dx
    local newTop = currentTop + dy
    local newBottom = currentBottom + dy

    -- Start with desired position
    local x = newX
    local y = newY

    -- Check left boundary (sprite going too far left)
    if newRight < -sx then
        x = math.ceil(self.x - (sx + currentRight))
        -- Check right boundary (sprite going too far right)
    elseif newLeft > sx then
        x = math.floor(self.x + (sx - currentLeft))
    end

    -- Check bottom boundary (sprite going too far down)
    if newTop < -sy then
        y = math.ceil(self.y - (sy + currentTop))
        -- Check top boundary (sprite going too far up)
    elseif newBottom > sy then
        y = math.floor(self.y + (sy - currentBottom))
    end

    return x, y
end

function Sprite:ifOnEdgeBounce()
    local rect = self:getFastBounds()

    -- Calculate distance to each edge (positive when far away, 0 when touching)
    -- Using Global constants which match native STAGE_WIDTH/2 and STAGE_HEIGHT/2
    local stageHalfWidth = (Global.SCRATCH_MAX_X - Global.SCRATCH_MIN_X) / 2  -- 240
    local stageHalfHeight = (Global.SCRATCH_MAX_Y - Global.SCRATCH_MIN_Y) / 2 -- 180

    local distLeft = math.max(0, stageHalfWidth + rect.left)                  -- distance from left edge
    local distTop = math.max(0, stageHalfHeight - rect.top)                   -- distance from top edge
    local distRight = math.max(0, stageHalfWidth - rect.right)                -- distance from right edge
    local distBottom = math.max(0, stageHalfHeight + rect.bottom)             -- distance from bottom edge

    -- Find the nearest edge
    local nearestEdge = ''
    local minDist = math.huge

    if distLeft < minDist then
        minDist = distLeft
        nearestEdge = 'left'
    end
    if distTop < minDist then
        minDist = distTop
        nearestEdge = 'top'
    end
    if distRight < minDist then
        minDist = distRight
        nearestEdge = 'right'
    end
    if distBottom < minDist then
        minDist = distBottom
        nearestEdge = 'bottom'
    end

    -- If not touching any edge, don't bounce
    if minDist > 0 then
        return
    end

    -- Convert current direction to movement vector (matching native algorithm)
    local radians = math.rad(90 - self.direction)
    local dx = math.cos(radians)
    local dy = -math.sin(radians) -- Y inverted

    -- Reflect based on nearest edge with minimum movement guarantee of 0.2
    if nearestEdge == 'left' then
        dx = math.max(0.2, math.abs(dx))  -- Force rightward, min 0.2
    elseif nearestEdge == 'top' then
        dy = math.max(0.2, math.abs(dy))  -- Force downward, min 0.2
    elseif nearestEdge == 'right' then
        dx = -math.max(0.2, math.abs(dx)) -- Force leftward, min -0.2
    elseif nearestEdge == 'bottom' then
        dy = -math.max(0.2, math.abs(dy)) -- Force upward, min -0.2
    end

    -- Convert back to Scratch direction
    -- Handle signed zero issue that differs between Lua and JavaScript
    if math.abs(dy) < 1e-15 then dy = 0 end
    if math.abs(dx) < 1e-15 then dx = (dx < 0) and -0.2 or 0.2 end

    local atan2Result = math.atan2(dy, dx)
    local atan2Degrees = math.deg(atan2Result)
    local newDirection = atan2Degrees + 90


    self:setDirection(newDirection)

    -- Keep within the stage (apply fencing if enabled)
    if self.runtime and self.runtime.runtimeOptions.fencing then
        local fencedX, fencedY = self:keepInFence(self.x, self.y)
        self.x = fencedX
        self.y = fencedY
    end
end

function Sprite:setRotationStyle(style)
    self.rotationStyle = style
    -- Mark transform cache as dirty when rotation style changes
    if self._transformCache then
        self._transformCache:markDirty()
    end
    if self.visible and self.runtime then
        self.runtime:requestRedraw()
    end
end

---Say text for a duration with Scratch-style behavior
---@param text any Text to say (any type will be converted)
---@param duration number|nil Duration in seconds (nil for forever)
function Sprite:say(text, duration)
    -- Clear any existing think text (mutual exclusion like Scratch)
    self.thinkText = nil
    self.thinkUntil = nil

    -- Set say text (already formatted by blocks/looks.lua)
    if text == "" or text == nil then
        self.sayText = nil
        self.sayUntil = nil
        self.currentMessage = nil
    else
        self.sayText = text
        self.currentMessage = text -- Store for testing

        if duration and duration > 0 then
            self.sayUntil = love.timer.getTime() + duration
        else
            self.sayUntil = nil
        end
    end
end

---Think text for a duration with Scratch-style behavior
---@param text any Text to think (any type will be converted)
---@param duration number|nil Duration in seconds (nil for forever)
function Sprite:think(text, duration)
    -- Clear any existing say text (mutual exclusion like Scratch)
    self.sayText = nil
    self.sayUntil = nil

    -- Set think text (already formatted by blocks/looks.lua)
    if text == "" or text == nil then
        self.thinkText = nil
        self.thinkUntil = nil
    else
        self.thinkText = text

        if duration and duration > 0 then
            self.thinkUntil = love.timer.getTime() + duration
        else
            self.thinkUntil = nil
        end
    end
end

---Show the sprite
function Sprite:show()
    self.visible = true
    -- Mark draw order cache as dirty since visibility affects rendering
    if self.runtime and self.runtime.renderer then
        self.runtime.renderer:markSpriteDirty(self, "visibility")
    end
    if self.runtime then
        self.runtime:requestRedraw()
    end
    -- Clear interpolation data on visibility change
    -- Prevents visual glitches when sprite becomes visible
    self.interpolationData = nil
end

---Hide the sprite
function Sprite:hide()
    self.visible = false
    -- Mark draw order cache as dirty since visibility affects rendering
    if self.runtime and self.runtime.renderer then
        self.runtime.renderer:markSpriteDirty(self, "visibility")
    end
    if self.runtime then
        self.runtime:requestRedraw()
    end
    -- Clear interpolation data on visibility change
    -- Prevents visual glitches when sprite becomes hidden
    self.interpolationData = nil
    if Global.ENABLE_TEXTURE_CLEANUP then
        self:cleanupUnusedCostumes()
    end
end

---Set sprite size
---@param size number Size percentage (100 = normal)
function Sprite:setSize(size)
    local newSize = math.max(0, size)
    if self.size ~= newSize then
        self.size = newSize
        -- Mark transform cache as dirty when size changes
        if self._transformCache then
            self._transformCache:markDirty()
        end
        if self.visible and self.runtime then
            self.runtime:requestRedraw()
        end
    else
        self.size = newSize
    end
end

---Change sprite size by delta
---@param delta number Size change amount
function Sprite:changeSize(delta)
    self:setSize(self.size + delta)
end

---Set a graphics effect value
---@param effect string Effect name
---@param value number Effect value
function Sprite:setEffect(effect, value)
    effect = effect:lower()
    if self.effects[effect] ~= nil then
        local oldValue = self.effects[effect]
        self.effects[effect] = value

        -- Notify renderer if effect actually changed
        if oldValue ~= value and self.runtime and self.runtime.renderer then
            self.runtime.renderer:markSpriteDirty(self, "effects")
        end

        -- Request redraw only if sprite is visible and effect actually changed
        if oldValue ~= value and self.visible and self.runtime then
            self.runtime:requestRedraw()
        end
    end
end

---Change a graphics effect by delta
---@param effect string Effect name
---@param delta number Change amount
function Sprite:changeEffect(effect, delta)
    effect = effect:lower()
    if self.effects[effect] ~= nil and delta ~= 0 then
        self.effects[effect] = self.effects[effect] + delta

        -- Notify renderer of effect change
        if self.runtime and self.runtime.renderer then
            self.runtime.renderer:markSpriteDirty(self, "effects")
        end

        if self.visible and self.runtime then
            self.runtime:requestRedraw()
        end
    end
end

---Get a graphics effect value
---@param effect string Effect name
---@return number value Effect value
function Sprite:getEffect(effect)
    return self.effects[effect] or 0
end

---Clear all graphics effects
function Sprite:clearEffects()
    local hasChanges = false
    for effect in pairs(self.effects) do
        if self.effects[effect] ~= 0 then
            hasChanges = true
        end
        self.effects[effect] = 0
    end

    -- Notify renderer if any effects were cleared
    if hasChanges and self.runtime and self.runtime.renderer then
        self.runtime.renderer:markSpriteDirty(self, "effects")
    end

    -- Request redraw only if sprite is visible and effects were actually cleared
    if hasChanges and self.visible and self.runtime then
        self.runtime:requestRedraw()
    end
end

---Move sprite to front layer
function Sprite:goToFront()
    -- Use renderer to move to front
    if self.runtime and self.runtime.renderer then
        self.runtime.renderer:moveToFront(self)
    end
end

---Move sprite to back layer
function Sprite:goToBack()
    -- Use renderer to move to back
    if self.runtime and self.runtime.renderer then
        self.runtime.renderer:moveToBack(self)
    end
end

function Sprite:goForwardLayers(num)
    -- Use renderer to move forward
    if self.runtime and self.runtime.renderer then
        self.runtime.renderer:moveSpriteForward(self, num)
    end
end

function Sprite:goBackwardLayers(num)
    -- Use renderer to move backward
    if self.runtime and self.runtime.renderer then
        self.runtime.renderer:moveSpriteBackward(self, num)
    end
end

---Move sprite behind another sprite (Scratch behavior)
---@param otherSprite Sprite The sprite to go behind
function Sprite:goBehindOther(otherSprite)
    if not otherSprite or otherSprite.isStage then
        return
    end

    -- Native calls setDrawableOrder which returns null if target not found
    -- In that case, the sprite position is not changed (degraded behavior)
    if self.runtime and self.runtime.renderer and self.runtime.renderer.moveSpriteBehind then
        local position = self.runtime.renderer:moveSpriteBehind(self, otherSprite)
        if not position then
            -- Target drawable not found (target was deleted or invalid)
            -- Log this as an exception case for debugging
            log.debug("Sprite:goBehindOther - target sprite '%s' not found in draw order (may be deleted)",
                otherSprite.name or "unknown")
        end
    end
end

---Get the transform cache for this sprite
---@return TransformCache transformCache The sprite's transform cache
function Sprite:getTransformCache()
    return self._transformCache
end

---Transform world coordinates to local texture coordinates (manual implementation for testing/fallback)
---@param worldX number World X coordinate (Scratch coordinates)
---@param worldY number World Y coordinate (Scratch coordinates)
---@param textureWidth number Texture width
---@param textureHeight number Texture height
---@return number localX Local X coordinate in texture space
---@return number localY Local Y coordinate in texture space
function Sprite:worldToLocalManual(worldX, worldY, textureWidth, textureHeight)
    local costume = self:getCurrentCostume()
    if not costume then
        return textureWidth / 2, textureHeight / 2
    end

    -- Get sprite scale and bitmap resolution
    local spriteSize = self.size or 100
    local bitmapResolution = costume.bitmapResolution or 1
    local scale = (spriteSize / 100) / bitmapResolution

    -- Get rotation center in texture coordinates
    local centerX = costume.rotationCenterX or (textureWidth / 2)
    local centerY = costume.rotationCenterY or (textureHeight / 2)

    -- Translate to sprite space (relative to sprite center)
    local dx = worldX - self.x
    local dy = worldY - self.y

    -- Apply transformations based on rotation style
    local transformedX, transformedY

    if self.rotationStyle == "all around" then
        -- Apply inverse rotation
        local angle = math.rad(self.direction - 90)
        local cos_r = math.cos(-angle) -- Negative for inverse rotation
        local sin_r = math.sin(-angle)

        transformedX = dx * cos_r - dy * sin_r
        transformedY = dx * sin_r + dy * cos_r
    elseif self.rotationStyle == "left-right" then
        -- Handle horizontal flip when facing left (direction < 0)
        if self.direction < 0 then
            transformedX = -dx -- Flip horizontally
            transformedY = dy
        else
            transformedX = dx
            transformedY = dy
        end
    else -- "don't rotate"
        -- No transformation needed
        transformedX = dx
        transformedY = dy
    end

    -- Apply inverse scale and convert to texture coordinates
    local localX = (transformedX / scale) + centerX
    local localY = centerY - (transformedY / scale) -- Y-axis flip for texture space

    return localX, localY
end

---Transform world coordinates to local texture coordinates using cached Transform
---Performance optimized version using Love2D Transform API
---@param worldX number World X coordinate (Scratch coordinates)
---@param worldY number World Y coordinate (Scratch coordinates)
---@param textureWidth number Texture width
---@param textureHeight number Texture height
---@return number localX Local X coordinate in texture space
---@return number localY Local Y coordinate in texture space
function Sprite:worldToLocal(worldX, worldY, textureWidth, textureHeight)
    local costume = self:getCurrentCostume()
    if not costume then
        return textureWidth / 2, textureHeight / 2
    end

    -- Use cached inverse transform from transform_cache
    local inverseTransform = self._transformCache:getInverseTransform()

    -- Apply inverse transform using matrix multiplication
    -- Transform maps: world coords -> texture coords
    local e11, e12, _, e14, e21, e22, _, e24 = inverseTransform:getMatrix()

    local localX = e11 * worldX + e12 * worldY + e14
    local localY = e21 * worldX + e22 * worldY + e24

    return localX, localY
end

---Check if sprite contains a point (with pixel-perfect collision)
---@param x number Point X coordinate (Scratch coordinates)
---@param y number Point Y coordinate (Scratch coordinates)
---@return boolean contains Whether point is inside sprite
function Sprite:containsPoint(x, y)
    if not self.visible then
        return false
    end

    -- Fast AABB pre-check
    local rect = self:getTransformedAABB()
    if not rect:containsPoint(x, y) then
        return false
    end

    -- If low precision mode is enabled, return true after AABB check (skip pixel-level detection)
    if Global.COLLISION_LOW_PRECISION then
        return true
    end

    local costume = self:getCurrentCostume()
    if not costume then
        return true -- AABB check passed, no costume for precise check
    end

    -- Get sampler (lazy-loaded)
    local sampler = ProjectModel.getSampler(costume)
    if not sampler then
        log.warn("Sprite %s: Failed to get sampler for costume %s, using AABB for containsPoint",
            self.name, costume.name or "unknown")
        return true -- AABB check passed, no sampler available
    end

    -- Transform world coordinates to local texture coordinates
    local textureWidth = costume.image:getPixelWidth()
    local textureHeight = costume.image:getPixelHeight()
    local localX, localY = self:worldToLocal(x, y, textureWidth, textureHeight)

    -- Check bounds
    if localX < 0 or localX >= textureWidth or localY < 0 or localY >= textureHeight then
        return false
    end

    -- Sample pixel alpha channel using FastPixelSampler
    local alpha = sampler:getAlpha(math.floor(localX), math.floor(localY))
    return alpha >= Global.COLLISION_ALPHA_THRESHOLD
end

---Get transformed AABB (Axis-Aligned Bounding Box) considering rotation and scale
---@return Rectangle rect Rectangle in Scratch coordinates
function Sprite:getTransformedAABB()
    return self._transformCache:getTransformedAABB()
end

---Check if sprite is touching another sprite (uses AABB pre-check then sample-based collision)
---@param other Sprite Other sprite to check
---@return boolean touching Whether sprites are touching
function Sprite:touchingSprite(other)
    -- Quick visibility check
    if not self.visible or not other.visible then
        return false
    end

    -- Fast AABB pre-check using Rectangle
    local rect1 = self:getFastBounds()
    local rect2 = other:getFastBounds()

    -- Full pixel-perfect collision detection
    -- Get intersection of AABBs to minimize search area
    local intersection = rect1:intersection(rect2)
    if not intersection:isValid() then
        return false -- No intersection
    end

    -- If a drawable extends out into half a pixel, that half-pixel still needs to be tested
    intersection:snapToInt()

    -- Get samplers for both sprites (lazy-loaded)
    local costume1 = self:getCurrentCostume()
    local costume2 = other:getCurrentCostume()
    if not costume1 or not costume2 then
        return false
    end

    local sampler1 = ProjectModel.getSampler(costume1)
    local sampler2 = ProjectModel.getSampler(costume2)

    if not sampler1 then
        log.warn("Sprite %s: Failed to get sampler for costume %s, using AABB for touchingSprite",
            self.name, costume1.name or "unknown")
        return false
    end
    if not sampler2 then
        log.warn("Sprite %s: Failed to get sampler for costume %s, using AABB for touchingSprite",
            other.name, costume2.name or "unknown")
        return false
    end

    local width1 = costume1.image:getPixelWidth()
    local height1 = costume1.image:getPixelHeight()
    local width2 = costume2.image:getPixelWidth()
    local height2 = costume2.image:getPixelHeight()

    -- "This is an EXTREMELY brute force collision detector, but it is
    --  still faster than asking the GPU to give us the pixels."
    local step = 1
    if Global.COLLISION_LOW_PRECISION then
        step = 2 -- Use lower sampling precision for better performance
    end

    local alphaThreshold = Global.COLLISION_ALPHA_THRESHOLD

    -- Iterate through intersection area in world coordinates (Scratch space - +y is top)
    for worldY = intersection.bottom, intersection.top, step do
        for worldX = intersection.left, intersection.right, step do
            -- Convert world coordinates to local coordinates for both sprites
            local localX1, localY1 = self:worldToLocal(worldX, worldY, width1, height1)
            local localX2, localY2 = other:worldToLocal(worldX, worldY, width2, height2)

            -- Check if both sprites have non-transparent pixels at this location
            local alpha1 = 0
            local alpha2 = 0

            -- Check sprite 1
            if localX1 >= 0 and localX1 < width1 and localY1 >= 0 and localY1 < height1 then
                alpha1 = sampler1:getAlpha(math.floor(localX1), math.floor(localY1))
            end

            -- Check sprite 2
            if localX2 >= 0 and localX2 < width2 and localY2 >= 0 and localY2 < height2 then
                alpha2 = sampler2:getAlpha(math.floor(localX2), math.floor(localY2))
            end

            -- If both sprites have non-transparent pixels at this world position, collision detected
            if alpha1 >= alphaThreshold and alpha2 >= alphaThreshold then
                return true
            end
        end
    end

    return false
end

---Check if sprite is touching the screen edge
---@return boolean touching Whether sprite touches edge
function Sprite:touchingEdge()
    local box = self:getTransformedAABB()
    return box.left <= Global.SCRATCH_MIN_X or
        box.right >= Global.SCRATCH_MAX_X or
        box.bottom <= Global.SCRATCH_MIN_Y or
        box.top >= Global.SCRATCH_MAX_Y
end

---Calculate distance to a point
---@param x number Target X coordinate
---@param y number Target Y coordinate
---@return number distance Distance to target
function Sprite:distanceTo(x, y)
    local dx = x - self.x
    local dy = y - self.y
    return math.sqrt(dx * dx + dy * dy)
end

---Make a clone of this sprite (Scratch-style)
---@return Sprite|nil clone New clone or nil if limit reached
function Sprite:makeClone()
    if not self.runtime:clonesAvailable() then
        return nil -- Hit max clone limit
    end

    self.runtime:changeCloneCounter(1)

    -- All sprites now have spriteTemplate - create clone using template
    local newClone = self.spriteTemplate:createClone()

    -- Copy all runtime properties from this sprite
    newClone.x = self.x
    newClone.y = self.y
    newClone.direction = self.direction
    newClone.draggable = self.draggable
    newClone.visible = self.visible
    newClone.size = self.size
    newClone.currentCostume = self.currentCostume
    newClone.rotationStyle = self.rotationStyle
    newClone.volume = self.volume

    -- Copy effects
    for effect, value in pairs(self.effects) do
        newClone.effects[effect] = value
    end

    -- Copy variables (instance-specific values)
    for id, variable in pairs(self.variables) do
        local newVariable = Variable:new(variable.id, variable.name, variable.type, variable.isCloud)
        newVariable.value = variable.type == Variable.LIST_TYPE and self:deepCopyList(variable.value) or
            variable.value
        newClone.variables[id] = newVariable
    end

    if self.penState then
        newClone.penState = self.penState:clone()
    end

    -- Initialize clone-specific state
    newClone.isClone = true
    newClone.bubbleOnRight = true

    return newClone
end

---Add a block and update hat block index
---@param blockId string Block ID
---@param block Block Block data
function Sprite:addBlock(blockId, block)
    self.spriteTemplate:addBlock(blockId, block)
end

---Get hat blocks by opcode and parameter
---@param opcode string Hat block opcode
---@param param any Optional parameter for matching
---@return string[] blockIds Array of matching block IDs
function Sprite:getHatBlocks(opcode, param)
    if not self.hatBlockIndex[opcode] then
        return {}
    end

    local matchingBlocks = {}
    for _, blockId in ipairs(self.hatBlockIndex[opcode]) do
        local block = self.blocks[blockId]
        if block then
            local shouldMatch = false

            if opcode == "event_whenflagclicked" or opcode == "event_whenthisspriteclicked" or opcode ==
                "control_start_as_clone" then
                shouldMatch = true
            elseif opcode == "event_whenbroadcastreceived" then
                local broadcastField = block.fields and block.fields.BROADCAST_OPTION
                if broadcastField and broadcastField.id == param then
                    shouldMatch = true
                end
            elseif opcode == "event_whenkeypressed" then
                local keyField = block.fields and block.fields.KEY_OPTION
                if keyField then
                    -- Handle both array format ["key"] and object format {value: "key"}
                    local keyValue = type(keyField) == "table" and (keyField[1] or keyField.value) or keyField
                    -- Normalize both values to uppercase for single-letter keys (matching native Scratch behavior)
                    -- In .sb3 files, letter keys are stored as lowercase, but runtime uses uppercase internally
                    local normalizedKeyValue = (#keyValue == 1) and keyValue:upper() or keyValue
                    local normalizedParam = (#param == 1) and param:upper() or param
                    if normalizedKeyValue == normalizedParam then
                        shouldMatch = true
                    end
                end
            elseif opcode == "event_whenbackdropswitchesto" then
                local backdropField = block.fields and block.fields.BACKDROP
                if backdropField and backdropField.value == param then
                    shouldMatch = true
                end
            elseif opcode == "event_whentouchingobject" then
                local touchField = block.fields and block.fields.TOUCHINGOBJECTMENU
                if touchField and touchField.value == param then
                    shouldMatch = true
                end
            elseif opcode == "event_whengreaterthan" then
                -- For whengreaterthan, match all blocks if no param, or match by sensor type
                if not param then
                    shouldMatch = true
                else
                    local sensorField = block.fields and block.fields.WHENGREATERTHANMENU
                    if sensorField and sensorField.value == param then
                        shouldMatch = true
                    end
                end
            end

            if shouldMatch then
                table.insert(matchingBlocks, blockId)
            end
        end
    end

    return matchingBlocks
end

---Deep copy a list value
---@param listValue table List value array
---@return table Copied list value
function Sprite:deepCopyList(listValue)
    local copy = {}
    for i, item in ipairs(listValue) do
        copy[i] = item
    end
    return copy
end

-- Variable Management Methods (matching original Scratch behavior)

---Look up a variable by ID in local or stage variables
---@param id string Variable ID
---@return Variable|nil Variable object if found
function Sprite:lookupVariableById(id)
    -- First check local variables
    if self.variables[id] then
        return self.variables[id]
    end

    -- If not stage and runtime exists, check stage variables
    if self.runtime.stage then
        if self.runtime.stage.variables[id] then
            return self.runtime.stage.variables[id]
        end
    end

    return nil
end

---Look up a variable by name and type
---@param name string Variable name
---@param variableType string Variable type (SCALAR_TYPE, LIST_TYPE, etc.)
---@param skipStage? boolean Whether to skip stage variables (default: false)
---@return Variable|nil Variable object if found
function Sprite:lookupVariableByNameAndType(name, variableType, skipStage)
    if type(name) ~= "string" then
        return nil
    end

    variableType = variableType or Variable.SCALAR_TYPE
    skipStage = skipStage or false

    -- First check local variables
    for id, variable in pairs(self.variables) do
        if variable.name == name and variable.type == variableType then
            return variable
        end
    end

    -- If not skipping stage and this is not stage, check stage variables
    if not skipStage and self.runtime and self.runtime.stage then
        for id, variable in pairs(self.runtime.stage.variables) do
            if variable.name == name and variable.type == variableType then
                return variable
            end
        end
    end

    return nil
end

---Look up or create a scalar variable (matching original Scratch behavior)
---@param id string Variable ID
---@param name string Variable name
---@return Variable Variable object (existing or newly created)
function Sprite:lookupOrCreateVariable(id, name)
    -- First try to find by ID
    local variable = self:lookupVariableById(id)
    if variable then
        return variable
    end

    -- Then try to find by name and type
    variable = self:lookupVariableByNameAndType(name, Variable.SCALAR_TYPE)
    if variable then
        return variable
    end

    -- Create new variable locally if not found
    local newVariable = Variable:new(id, name, Variable.SCALAR_TYPE, false)
    self.variables[id] = newVariable
    return newVariable
end

---Look up or create a list variable (matching original Scratch behavior)
---@param id string List ID
---@param name string List name
---@return Variable List object (existing or newly created)
function Sprite:lookupOrCreateList(id, name)
    -- First try to find by ID
    local list = self:lookupVariableById(id)
    if list then
        return list
    end

    -- Then try to find by name and type
    list = self:lookupVariableByNameAndType(name, Variable.LIST_TYPE)
    if list then
        return list
    end

    -- Create new list locally if not found
    local newList = Variable:new(id, name, Variable.LIST_TYPE, false)
    self.variables[id] = newList
    return newList
end

---Get compiled state for a specific operation
---@param stateKey string Unique state key for the operation
---@return table|nil state The state data, or nil if not found
function Sprite:getCompiledState(stateKey)
    return self._compiledStates[stateKey]
end

---Set compiled state for a specific operation
---@param stateKey string Unique state key for the operation
---@param stateData table|nil State data to store, or nil to clear
function Sprite:setCompiledState(stateKey, stateData)
    self._compiledStates[stateKey] = stateData
end

---Clear all compiled states (used when sprite is reset or cloned)
function Sprite:clearCompiledStates()
    self._compiledStates = {}
end

return Sprite
