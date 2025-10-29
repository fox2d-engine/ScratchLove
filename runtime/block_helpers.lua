-- These functions are called by compiled Lua code generated from Scratch blocks
-- They provide shared functionality that would otherwise be duplicated in generated code

local Cast = require("utils.cast")
local log = require("lib.log")
local socket = require("socket")

---@class BlockHelpers
local BlockHelpers = {}

-- ============================================================================
-- Sound Helpers
-- ============================================================================

---@class BlockHelpers.Sound
BlockHelpers.Sound = {}

-- Helper function to get sound index using Scratch's logic
local function getSoundIndex(soundName, target)
    if not target.sounds or #target.sounds == 0 then
        return nil
    end

    -- First try to find by name (exact match)
    for i, currentSound in ipairs(target.sounds) do
        if currentSound.name == soundName then
            return i
        end
    end

    -- Then try using the sound name as a 1-indexed index
    local oneIndexedIndex = tonumber(soundName)
    if oneIndexedIndex then
        local zeroIndexed = Cast.wrapClamp(oneIndexedIndex - 1, 0, #target.sounds - 1)
        return zeroIndexed + 1
    end

    return nil
end

-- Helper function to get sound ID from sound data
-- Must match AudioSound:new() logic for consistency
local function getSoundId(soundData)
    return soundData.assetId or soundData.md5ext or soundData.name
end

---Play a sound by menu value (direct runtime call)
---@param target Sprite|Stage The sprite or stage executing the block
---@param soundMenu any Sound identifier (name, index, or menu value)
---@param runtime Runtime The runtime environment
---@param thread Thread The executing thread
function BlockHelpers.Sound.play(target, soundMenu, runtime, thread)
    if not target.sounds then
        return
    end

    local soundIndex = getSoundIndex(soundMenu, target)
    if soundIndex then
        local selectedSound = target.sounds[soundIndex]
        local soundId = getSoundId(selectedSound)
        if soundId then
            runtime.audioEngine:playSound(target, soundId, false)
        end
    end
end

---Get sound index by name (exposed for compiled code)
---@param soundName string Sound name to look up
---@param target Sprite|Stage The sprite or stage with the sound
---@return number|nil index 1-based sound index or nil if not found
function BlockHelpers.Sound.getSoundIndex(soundName, target)
    return getSoundIndex(soundName, target)
end

---Get sound ID from sound data (exposed for compiled code)
---@param sound table Sound data object
---@return string|nil soundId Sound asset ID
function BlockHelpers.Sound.getSoundId(sound)
    return getSoundId(sound)
end

---Stop all sounds in the project
---@param target Sprite|Stage The sprite or stage executing the block
---@param runtime Runtime The runtime environment
---@param thread Thread The executing thread
function BlockHelpers.Sound.stopAllSounds(target, runtime, thread)
    runtime.audioEngine:stopAllSounds()
end

---Change volume by amount
---@param target Sprite|Stage The sprite or stage executing the block
---@param volume number Volume change amount
---@param runtime Runtime The runtime environment
---@param thread Thread The executing thread
function BlockHelpers.Sound.changeVolumeBy(target, volume, runtime, thread)
    local change = Cast.toNumber(volume)
    target.volume = math.max(0, math.min(100, (target.volume or 100) + change))
    runtime.audioEngine:updateVolume(target)

    if runtime.runtimeOptions and runtime.runtimeOptions.miscLimits then
        -- Yield until the next tick when miscLimits enabled
        coroutine.yield("yield")
    else
        -- Request redraw without yielding for better performance
        runtime:requestRedraw()
    end
end

---Set volume to value
---@param target Sprite|Stage The sprite or stage executing the block
---@param volume number Volume value to set (0-100)
---@param runtime Runtime The runtime environment
---@param thread Thread The executing thread
function BlockHelpers.Sound.setVolumeTo(target, volume, runtime, thread)
    local vol = Cast.toNumber(volume)
    target.volume = math.max(0, math.min(100, vol))
    runtime.audioEngine:updateVolume(target)

    if runtime.runtimeOptions and runtime.runtimeOptions.miscLimits then
        -- Yield until the next tick when miscLimits enabled
        coroutine.yield("yield")
    else
        -- Request redraw without yielding for better performance
        runtime:requestRedraw()
    end
end

---Change sound effect by amount
---@param target Sprite|Stage The sprite or stage executing the block
---@param effect string Effect name (pitch, pan)
---@param value number Effect change amount
---@param runtime Runtime The runtime environment
---@param thread Thread The executing thread
function BlockHelpers.Sound.changeEffectBy(target, effect, value, runtime, thread)
    local effectName = Cast.toString(effect)
    local val = Cast.toNumber(value)

    if not target.soundEffects then
        target.soundEffects = { pitch = 0, pan = 0 }
    end

    local miscLimits = runtime.runtimeOptions and runtime.runtimeOptions.miscLimits
    local pitchMin, pitchMax, panMin, panMax

    if miscLimits then
        -- Standard Scratch limits
        pitchMin, pitchMax = -360, 360 -- -3 to +3 octaves
        panMin, panMax = -100, 100
    else
        -- Extended limits when miscLimits disabled
        pitchMin, pitchMax = -1000, 1000
        panMin, panMax = -100, 100
    end

    if effectName == "pitch" then
        target.soundEffects.pitch = math.max(pitchMin, math.min(pitchMax, (target.soundEffects.pitch or 0) + val))
    elseif effectName == "pan left/right" or effectName == "pan" then
        target.soundEffects.pan = math.max(panMin, math.min(panMax, (target.soundEffects.pan or 0) + val))
    end

    runtime.audioEngine:setEffects(target)

    if miscLimits then
        -- Yield until the next tick when miscLimits enabled
        coroutine.yield("yield")
    else
        -- Request redraw without yielding for better performance
        runtime:requestRedraw()
    end
end

---Set sound effect to value
---@param target Sprite|Stage The sprite or stage executing the block
---@param effect string Effect name (pitch, pan)
---@param value number Effect value to set
---@param runtime Runtime The runtime environment
---@param thread Thread The executing thread
function BlockHelpers.Sound.setEffectTo(target, effect, value, runtime, thread)
    local effectName = Cast.toString(effect)
    local val = Cast.toNumber(value)

    if not target.soundEffects then
        target.soundEffects = { pitch = 0, pan = 0 }
    end

    local miscLimits = runtime.runtimeOptions and runtime.runtimeOptions.miscLimits
    local pitchMin, pitchMax, panMin, panMax

    if miscLimits then
        -- Standard Scratch limits
        pitchMin, pitchMax = -360, 360 -- -3 to +3 octaves
        panMin, panMax = -100, 100
    else
        -- Extended limits when miscLimits disabled
        pitchMin, pitchMax = -1000, 1000
        panMin, panMax = -100, 100
    end

    if effectName == "pitch" then
        target.soundEffects.pitch = math.max(pitchMin, math.min(pitchMax, val))
    elseif effectName == "pan left/right" or effectName == "pan" then
        target.soundEffects.pan = math.max(panMin, math.min(panMax, val))
    end

    runtime.audioEngine:setEffects(target)

    if miscLimits then
        -- Yield until the next tick when miscLimits enabled
        coroutine.yield("yield")
    else
        -- Request redraw without yielding for better performance
        runtime:requestRedraw()
    end
end

---Clear all sound effects
---@param target Sprite|Stage The sprite or stage executing the block
---@param runtime Runtime The runtime environment
---@param thread Thread The executing thread
function BlockHelpers.Sound.clearEffects(target, runtime, thread)
    target.soundEffects = { pitch = 0, pan = 0 }
    runtime.audioEngine:setEffects(target)
end

---Get current volume
---@param target Sprite|Stage The sprite or stage executing the block
---@param runtime Runtime The runtime environment
---@param thread Thread The executing thread
---@return number volume Current volume (0-100)
function BlockHelpers.Sound.getVolume(target, runtime, thread)
    return target.volume or 100
end

---Play sound until done
---@param target Sprite|Stage The sprite or stage executing the block
---@param soundMenu any Sound identifier (name, index, or menu value)
---@param runtime Runtime The runtime environment
---@param thread Thread The executing thread
function BlockHelpers.Sound.playUntilDone(target, soundMenu, runtime, thread)
    if not target.sounds then
        return
    end

    local soundIndex = getSoundIndex(soundMenu, target)
    if soundIndex then
        local selectedSound = target.sounds[soundIndex]
        local soundId = getSoundId(selectedSound)
        if soundId then
            -- Play sound and wait for timer completion
            local timer = runtime.audioEngine:playSound(target, soundId, true)
            if timer then
                thread:waitForTimer(timer)
                coroutine.yield("wait")
            end
        end
    end
end

-- ============================================================================
-- Sensing Helpers
-- ============================================================================

---@class BlockHelpers.Sensing
BlockHelpers.Sensing = {}

---Set drag mode for sprite
---@param target Sprite|Stage The sprite or stage executing the block
---@param dragMode string Drag mode ("draggable" or "not draggable")
---@param runtime Runtime The runtime environment
---@param thread Thread The executing thread
function BlockHelpers.Sensing.setDragMode(target, dragMode, runtime, thread)
    if target.isStage then return end
    local mode = Cast.toString(dragMode)
    target.draggable = (mode == "draggable")
end

---@param value number Value to round
---@return number rounded Rounded value
local function roundToThreeDecimals(value)
    return math.floor(value * 1000 + 0.5) / 1000
end

---Get mouse X position
---@param target Sprite|Stage The sprite or stage executing the block
---@param runtime Runtime The runtime environment
---@param thread Thread The executing thread
---@return number x Mouse X position in Scratch coordinates
function BlockHelpers.Sensing.mouseX(target, runtime, thread)
    if runtime.runtimeOptions and runtime.runtimeOptions.miscLimits then
        -- Round to integer when miscLimits enabled (native Scratch behavior)
        return math.floor(runtime.mouseX + 0.5)
    else
        -- Three decimal precision when miscLimits disabled (extended precision)
        return roundToThreeDecimals(runtime.mouseX)
    end
end

---Get mouse Y position
---@param target Sprite|Stage The sprite or stage executing the block
---@param runtime Runtime The runtime environment
---@param thread Thread The executing thread
---@return number y Mouse Y position in Scratch coordinates
function BlockHelpers.Sensing.mouseY(target, runtime, thread)
    if runtime.runtimeOptions and runtime.runtimeOptions.miscLimits then
        -- Round to integer when miscLimits enabled (native Scratch behavior)
        return math.floor(runtime.mouseY + 0.5)
    else
        -- Three decimal precision when miscLimits disabled (extended precision)
        return roundToThreeDecimals(runtime.mouseY)
    end
end

---Get answer from last ask
---@param target Sprite|Stage The sprite or stage executing the block
---@param runtime Runtime The runtime environment
---@param thread Thread The executing thread
---@return string answer User's answer
function BlockHelpers.Sensing.answer(target, runtime, thread)
    if runtime.askState and runtime.askState.answer then
        return runtime.askState.answer
    else
        return ""
    end
end

---Check if touching object
---@param target Sprite|Stage The sprite or stage executing the block
---@param object any Object to check collision with
---@param runtime Runtime The runtime environment
---@param thread Thread The executing thread
---@return boolean touching True if touching
function BlockHelpers.Sensing.touchingObject(target, object, runtime, thread)
    if target.isStage then return false end

    local touchingObject = Cast.toString(object)

    if touchingObject == "_edge_" then
        return target:touchingEdge()
    elseif touchingObject == "_mouse_" then
        return target:containsPoint(runtime.mouseX, runtime.mouseY)
    else
        -- Check collision with named sprite and all its clones
        local firstSprite = runtime:getSpriteTargetByName(touchingObject)
        if not firstSprite then
            return false
        end

        -- Get all clones of this sprite (including original sprite)
        local clones = firstSprite.spriteTemplate and firstSprite.spriteTemplate.clones or firstSprite.clones
        if not clones then
            return false
        end

        -- Check collision with any clone of the sprite
        for _, sprite in ipairs(clones) do
            if sprite ~= target and target:touchingSprite(sprite) then
                return true
            end
        end
    end

    return false
end

---Check if touching color
---@param target Sprite|Stage The sprite or stage executing the block
---@param color any Color to check
---@param runtime Runtime The runtime environment
---@param thread Thread The executing thread
---@return boolean touching True if touching color
function BlockHelpers.Sensing.touchingColor(target, color, runtime, thread)
    if target.isStage then return false end

    local colorHex = color
    if not colorHex then return false end

    -- Convert hex color to RGB using Cast utility
    local targetColor = Cast.hexToRGB(colorHex)
    if not targetColor then return false end

    -- Use renderer for color collision detection
    if runtime.renderer and runtime.renderer.checkColorCollision then
        return runtime.renderer:checkColorCollision(target, targetColor)
    else
        log.warn("[Sensing] - Renderer not available for color collision detection")
        return false
    end
end

---Check if color is touching color
---@param target Sprite|Stage The sprite or stage executing the block
---@param color1 any First color
---@param color2 any Second color
---@param runtime Runtime The runtime environment
---@param thread Thread The executing thread
---@return boolean touching True if colors are touching
function BlockHelpers.Sensing.colorIsTouchingColor(target, color1, color2, runtime, thread)
    if target.isStage then return false end

    local color1Hex = color1
    local color2Hex = color2
    if not color1Hex or not color2Hex then return false end

    -- Convert hex colors to RGB using Cast utility
    local spriteColor = Cast.hexToRGB(color1Hex)
    local backgroundColorTarget = Cast.hexToRGB(color2Hex)
    if not spriteColor or not backgroundColorTarget then return false end

    -- Use renderer for color-to-color collision detection
    if runtime.renderer and runtime.renderer.checkColorCollision then
        return runtime.renderer:checkColorCollision(target, backgroundColorTarget, spriteColor)
    else
        log.warn("[Sensing] - Renderer not available for color-to-color collision detection")
        return false
    end
end

---Get distance to object
---@param target Sprite|Stage The sprite or stage executing the block
---@param object any Target object
---@param runtime Runtime The runtime environment
---@param thread Thread The executing thread
---@return number distance Distance to object
function BlockHelpers.Sensing.distanceTo(target, object, runtime, thread)
    if target.isStage then return 10000 end -- Native Scratch behavior

    local distanceTo = Cast.toString(object)

    if distanceTo == "_mouse_" then
        return target:distanceTo(runtime.mouseX, runtime.mouseY)
    elseif distanceTo == "_stage_" then
        return 10000 -- Native Scratch behavior: distance to stage is always 10000
    else
        -- Distance to another sprite or clone
        local sprite = runtime:getSpriteTargetByName(distanceTo)
        if sprite then
            return target:distanceTo(sprite.x, sprite.y)
        end
    end

    return 0
end

---Check if key is pressed
---@param target Sprite|Stage The sprite or stage executing the block
---@param key any Key to check
---@param runtime Runtime The runtime environment
---@param thread Thread The executing thread
---@return boolean pressed True if key is pressed
function BlockHelpers.Sensing.keyPressed(target, key, runtime, thread)
    local keyOption = Cast.toString(key)

    -- Normalize key to Scratch format (matching native _keyArgToScratchKey behavior)
    -- - Special keys stay as-is ("space", "up arrow", etc.)
    -- - Single character keys are converted to UPPERCASE
    if #keyOption == 1 then
        keyOption = keyOption:upper()
    end

    -- Register this key as actively monitored (for dynamic key detection)
    if keyOption ~= "any" then
        runtime:registerActiveKey(keyOption)
    end

    -- Use runtime:isKeyPressed which handles "any" and all key checking
    return runtime:isKeyPressed(keyOption)
end

---Check if mouse is down
---@param target Sprite|Stage The sprite or stage executing the block
---@param runtime Runtime The runtime environment
---@param thread Thread The executing thread
---@return boolean down True if mouse is down
function BlockHelpers.Sensing.mouseDown(target, runtime, thread)
    return runtime.mouseDown
end

---Get loudness (microphone level)
---@param target Sprite|Stage The sprite or stage executing the block
---@param runtime Runtime The runtime environment
---@param thread Thread The executing thread
---@return number loudness Loudness value (0-100)
function BlockHelpers.Sensing.loudness(target, runtime, thread)
    -- Microphone not implemented
    return 0
end

---Get property of object
---@param target Sprite|Stage The sprite or stage executing the block
---@param property string Property name
---@param object any Target object
---@param runtime Runtime The runtime environment
---@param thread Thread The executing thread
---@return any value Property value
function BlockHelpers.Sensing.of(target, property, object, runtime, thread)
    local prop = Cast.toString(property)
    local obj = Cast.toString(object)

    -- Find the target object
    local targetObject = nil

    if obj == "_stage_" then
        targetObject = runtime.stage
    else
        targetObject = runtime:getSpriteTargetByName(obj)
    end

    if not targetObject then
        return 0
    end

    -- Get the property
    if prop == "x position" then
        return targetObject.x or 0
    elseif prop == "y position" then
        return targetObject.y or 0
    elseif prop == "direction" then
        return targetObject.direction or 90
    elseif prop == "costume #" then
        return targetObject.currentCostume + 1
    elseif prop == "costume name" then
        local costume = targetObject:getCurrentCostume()
        return costume and costume.name or ""
    elseif prop == "size" then
        return targetObject.size or 100
    elseif prop == "volume" then
        return targetObject.volume or 100
    else
        -- Check if it's a variable
        for id, var in pairs(targetObject.variables) do
            if var.name == prop then
                return var.value
            end
        end

        -- Check global variables if not found in target
        if runtime.globalVariables and runtime.globalVariables[prop] then
            return runtime.globalVariables[prop]
        end
    end

    -- Return empty string for variable properties, 0 for others
    if prop and prop ~= "x position" and prop ~= "y position" and
        prop ~= "direction" and prop ~= "costume #" and prop ~= "costume name" and
        prop ~= "size" and prop ~= "volume" then
        return ""
    end
    return 0
end

---Get current time value
---@param target Sprite|Stage The sprite or stage executing the block
---@param menu string Time menu option (year, month, date, etc.)
---@param runtime Runtime The runtime environment
---@param thread Thread The executing thread
---@return number value Current time value
function BlockHelpers.Sensing.current(target, menu, runtime, thread)
    local currentMenu = Cast.toString(menu):upper()

    local date = os.date("*t")

    if currentMenu == "YEAR" then
        return date.year
    elseif currentMenu == "MONTH" then
        return date.month
    elseif currentMenu == "DATE" then
        return date.day
    elseif currentMenu == "DAYOFWEEK" then
        return date.wday
    elseif currentMenu == "HOUR" then
        return date.hour
    elseif currentMenu == "MINUTE" then
        return date.min
    elseif currentMenu == "SECOND" then
        return date.sec
    end

    return 0
end

-- Calculate timezone offsets (in minutes, negative means ahead of UTC)
-- Note: Lua's os.date('!*t') returns UTC time
local function getTimezoneOffset(timestamp)
    local utc = os.time(os.date('!*t', timestamp))
    return -(timestamp - utc) / 60
end

-- Get start time: 2000-01-01 00:00:00 in local time
local start2000 = os.time({ year = 2000, month = 1, day = 1, hour = 0, min = 0, sec = 0 })
local start2000Offset = getTimezoneOffset(start2000)
local msPerDay = 24 * 60 * 60 * 1000

---Get days since 2000
---@param target Sprite|Stage The sprite or stage executing the block
---@param runtime Runtime The runtime environment
---@param thread Thread The executing thread
---@param customTime number|nil Optional custom timestamp for testing (defaults to high precision time)
---@return number days Days since January 1, 2000
function BlockHelpers.Sensing.daysSince2000(target, runtime, thread, customTime)
    -- Get current time (or use custom time for testing)
    -- Use high precision time instead of os.time()
    local today = customTime or socket.gettime()

    -- For timezone offset calculation, we need integer seconds
    -- Round to nearest second for timezone calculation
    local todaySeconds = math.floor(today + 0.5)
    local todayOffset = getTimezoneOffset(todaySeconds)
    local dstAdjust = todayOffset - start2000Offset

    -- Calculate milliseconds since start (keep full precision)
    local mSecsSinceStart = (today - start2000) * 1000

    -- Apply DST adjustment
    mSecsSinceStart = mSecsSinceStart + ((todayOffset - dstAdjust) * 60 * 1000)

    return mSecsSinceStart / msPerDay
end

---Get username
---@param target Sprite|Stage The sprite or stage executing the block
---@param runtime Runtime The runtime environment
---@param thread Thread The executing thread
---@return string username User's username
function BlockHelpers.Sensing.username(target, runtime, thread)
    return "Player"
end

---Ask question and wait for answer
---@param target Sprite|Stage The sprite or stage executing the block
---@param question any Question to ask
---@param runtime Runtime The runtime environment
---@param thread Thread The executing thread
function BlockHelpers.Sensing.askAndWait(target, question, runtime, thread)
    local questionText = Cast.toString(question or '')

    -- Initialize askState if needed
    if not runtime.askState then
        runtime.askState = {
            active = false,
            question = '',
            answer = '',
            answered = false
        }
    end

    -- Start asking if not already active
    if not runtime.askState.active then
        runtime.askState.active = true
        runtime.askState.question = questionText
        runtime.askState.answer = ''
        runtime.askState.answered = false

        -- Platform-specific input handling
        local os = love.system.getOS()
        if (os == "Android" or os == "iOS") and love.system.mobile then
            -- Mobile platforms: use native input dialog
            love.system.mobile.showTextInput(questionText)
        else
            -- Desktop/other platforms: auto-answer for now (TODO: implement keyboard input)
            runtime.askState.answer = questionText .. ' (desktop echo)'
            runtime.askState.answered = true
        end

        -- Yield at least once behavior)
        coroutine.yield('yield')
    end

    -- Wait for answer
    while not runtime.askState.answered do
        -- Check if mobile input is complete
        if love.system.mobile and love.system.mobile.isTextInputComplete() then
            runtime.askState.answer = love.system.mobile.getTextInputResult()
            runtime.askState.answered = true
        end

        coroutine.yield('yield')
    end

    -- Clear state and continue
    runtime.askState.active = false
end

-- ============================================================================
-- Looks Helpers
-- ============================================================================

---@class BlockHelpers.Looks
BlockHelpers.Looks = {}

---Get sprite size percentage
---@param target Sprite|Stage The sprite or stage executing the block
---@param runtime Runtime The runtime environment
---@param thread Thread The executing thread
---@return number size Size percentage (100 = normal size)
function BlockHelpers.Looks.getSize(target, runtime, thread)
    return target.size or 100
end

---Switch backdrop and wait for backdrop-switch scripts to complete
---@param target Sprite|Stage The sprite or stage executing the block
---@param backdropName any Backdrop identifier
---@param runtime Runtime The runtime environment
---@param thread Thread The executing thread
function BlockHelpers.Looks.switchBackdropAndWait(target, backdropName, runtime, thread)
    if not runtime.stage or not backdropName or backdropName == "" then
        return
    end

    -- Switch backdrop and get started threads
    local startedThreads = runtime.stage:switchBackdrop(backdropName)

    -- Wait for all started threads to complete
    if #startedThreads > 0 then
        while true do
            local waiting = false
            local allWaiting = true
            for _, threadObj in ipairs(startedThreads) do
                if runtime:isThreadScheduled(threadObj) then
                    waiting = true
                    if not runtime:isWaitingThread(threadObj) then
                        allWaiting = false
                    end
                end
            end

            -- Exit loop if no threads are waiting
            if not waiting then break end

            -- Yield based on thread state
            if allWaiting then
                coroutine.yield("yield_tick")
            else
                coroutine.yield("yield")
            end
        end
    end
end

---Say message for seconds
---@param target Sprite|Stage The sprite or stage executing the block
---@param message any Message to say
---@param secs number Duration in seconds
---@param runtime Runtime The runtime environment
---@param thread Thread The executing thread
function BlockHelpers.Looks.sayForSecs(target, message, secs, runtime, thread)
    local duration = Cast.toNumber(secs)
    target:say(Cast.toScratchDisplayString(message))
    if duration > 0 then
        thread:wait(duration)
        coroutine.yield("wait")
    end
end

---Think message for seconds
---@param target Sprite|Stage The sprite or stage executing the block
---@param message any Message to think
---@param secs number Duration in seconds
---@param runtime Runtime The runtime environment
---@param thread Thread The executing thread
function BlockHelpers.Looks.thinkForSecs(target, message, secs, runtime, thread)
    target:think(Cast.toScratchDisplayString(message))
    local duration = Cast.toNumber(secs)
    if duration > 0 then
        thread:wait(duration)
        coroutine.yield("wait")
    end
end

---Set graphic effect to value
---@param target Sprite|Stage The sprite or stage executing the block
---@param args table Block arguments {EFFECT = string, VALUE = number}
---@param runtime Runtime The runtime environment
---@param thread Thread The executing thread
function BlockHelpers.Looks.seteffectto(target, args, runtime, thread)
    local effect = Cast.toString(args.EFFECT):lower()
    local value = Cast.toNumber(args.VALUE)

    -- Apply clamping based on native Scratch behavior
    if effect == "brightness" then
        -- Brightness: -100 to 100
        value = math.max(-100, math.min(100, value))
    elseif effect == "ghost" then
        -- Ghost (transparency): 0 to 100
        value = math.max(0, math.min(100, value))
    elseif effect == "pixelate" or effect == "mosaic" then
        -- Pixelate/Mosaic: minimum 0 (no maximum)
        value = math.max(0, value)
    end
    -- Other effects (color, fisheye, whirl) have no clamping

    target:setEffect(effect, value)
end

-- ============================================================================
-- Events Helpers
-- ============================================================================

---@class BlockHelpers.Events
BlockHelpers.Events = {}

---Broadcast and wait for all started threads to complete
---@param target Sprite|Stage The sprite or stage executing the block
---@param message any Broadcast message
---@param runtime Runtime The runtime environment
---@param thread Thread The executing thread
function BlockHelpers.Events.broadcastAndWait(target, message, runtime, thread)
    local msg = Cast.toString(message)
    local startedThreads = runtime:broadcast(msg, true) or {}

    if #startedThreads > 0 then
        -- Wait for all started threads to complete
        local waiting = true
        while waiting do
            waiting = false
            for _, startedThread in ipairs(startedThreads) do
                if runtime:isThreadScheduled(startedThread) then
                    waiting = true
                    break
                end
            end

            if waiting then
                local allWaiting = true
                for _, startedThread in ipairs(startedThreads) do
                    if runtime:isThreadScheduled(startedThread) and not runtime:isWaitingThread(startedThread) then
                        allWaiting = false
                        break
                    end
                end

                if allWaiting then
                    coroutine.yield("yield_tick")
                else
                    coroutine.yield("yield")
                end
            end
        end
    end
end

-- ============================================================================
-- Motion Helpers
-- ============================================================================

---@class BlockHelpers.Motion
BlockHelpers.Motion = {}

---Go to a target (sprite/mouse/random)
---@param target Sprite|Stage The sprite or stage executing the block
---@param to any Target identifier
---@param runtime Runtime The runtime environment
---@param thread Thread The executing thread
function BlockHelpers.Motion.goTo(target, to, runtime, thread)
    if target.isStage then return end

    local toStr = Cast.toString(to)

    if toStr == "_random_" then
        local Global = require("global")
        local x = math.floor(Global.STAGE_WIDTH * (math.random() - 0.5) + 0.5)
        local y = math.floor(Global.STAGE_HEIGHT * (math.random() - 0.5) + 0.5)
        target:setXY(x, y)
    elseif toStr == "_mouse_" then
        target:setXY(runtime.mouseX, runtime.mouseY)
    else
        local sprite = runtime:getSpriteTargetByName(toStr)
        if sprite then
            target:setXY(sprite.x, sprite.y)
        end
    end
end

---Point towards a target (sprite/mouse/random)
---@param target Sprite|Stage The sprite or stage executing the block
---@param towards any Target identifier
---@param runtime Runtime The runtime environment
---@param thread Thread The executing thread
function BlockHelpers.Motion.pointTowards(target, towards, runtime, thread)
    if target.isStage then return end

    local towardsStr = Cast.toString(towards)

    if towardsStr == "_mouse_" then
        target:pointTowards(runtime.mouseX, runtime.mouseY)
    elseif towardsStr == "_random_" then
        local randomDirection = math.floor(math.random() * 360 + 0.5) - 180
        target:setDirection(randomDirection)
    else
        local sprite = runtime:getSpriteTargetByName(towardsStr)
        if sprite then
            target:pointTowards(sprite.x, sprite.y)
        end
    end
end

---Glide to target coordinates over time
---@param target Sprite|Stage The sprite or stage executing the block
---@param secs number Duration in seconds
---@param targetX number Target X coordinate
---@param targetY number Target Y coordinate
---@param stateKey string Unique state key for this glide operation
---@param runtime Runtime The runtime environment
---@param thread Thread The executing thread
function BlockHelpers.Motion.glideToXY(target, secs, targetX, targetY, stateKey, runtime, thread)
    if target.isStage then return end

    if secs <= 0 then
        target:setXY(targetX, targetY)
        return
    end

    -- Initialize glide state
    local glideState = target:getCompiledState(stateKey)
    if not glideState then
        target:setCompiledState(stateKey, {
            startTime = love.timer.getTime(),
            duration = secs,
            startX = target.x,
            startY = target.y,
            endX = targetX,
            endY = targetY
        })
        glideState = target:getCompiledState(stateKey)
    end

    -- Glide animation loop
    while glideState do
        local elapsed = love.timer.getTime() - glideState.startTime
        if elapsed >= glideState.duration then
            target:setXY(glideState.endX, glideState.endY)
            target:setCompiledState(stateKey, nil)
            break
        else
            local progress = elapsed / glideState.duration
            local currentX = glideState.startX + (glideState.endX - glideState.startX) * progress
            local currentY = glideState.startY + (glideState.endY - glideState.startY) * progress
            target:setXY(currentX, currentY)
            coroutine.yield("yield")
            glideState = target:getCompiledState(stateKey)
        end
    end
end

---Glide to a target (sprite/mouse/random) over time
---@param target Sprite|Stage The sprite or stage executing the block
---@param secs number Duration in seconds
---@param to any Target identifier
---@param stateKey string Unique state key for this glide operation
---@param runtime Runtime The runtime environment
---@param thread Thread The executing thread
function BlockHelpers.Motion.glideTo(target, secs, to, stateKey, runtime, thread)
    if target.isStage then return end

    local toStr = Cast.toString(to)
    local targetX, targetY
    local Global = require("global")

    if toStr == "_random_" then
        targetX = math.random(Global.SCRATCH_MIN_X, Global.SCRATCH_MAX_X)
        targetY = math.random(Global.SCRATCH_MIN_Y, Global.SCRATCH_MAX_Y)
    elseif toStr == "_mouse_" then
        targetX = runtime.mouseX
        targetY = runtime.mouseY
    else
        local sprite = runtime:getSpriteTargetByName(toStr)
        if sprite then
            targetX = sprite.x
            targetY = sprite.y
        else
            -- Invalid target, skip glide
            return
        end
    end

    if targetX and targetY then
        BlockHelpers.Motion.glideToXY(target, secs, targetX, targetY, stateKey, runtime, thread)
    end
end

-- ============================================================================
-- Control Helpers
-- ============================================================================

---@class BlockHelpers.Control
BlockHelpers.Control = {}

-- Counter functionality (for compatibility with native Scratch tests)
local counter = 0

---Stop script execution
---@param target Sprite|Stage The sprite or stage executing the block
---@param args table Block arguments {STOP_OPTION = "all"|"this script"|"other scripts in sprite"}
---@param runtime Runtime The runtime environment
---@param thread Thread The executing thread
function BlockHelpers.Control.stop(target, args, runtime, thread)
    local stopOption = args.STOP_OPTION or "all"

    if stopOption == "all" then
        -- Stop all scripts)
        runtime:stopAll()
    elseif stopOption == "this script" then
        -- In compiled mode, "stop this script" generates a direct `return` statement
        -- This branch should never be reached in compiled code, but kept for safety
        thread:stop()
        return nil
    elseif stopOption == "other scripts in sprite" or stopOption == "other scripts in stage" then
        -- Stop other scripts in this target)
        runtime:stopForTarget(target, thread)
    end
    return nil
end

---Create a clone of a sprite
---@param target Sprite|Stage The sprite or stage executing the block
---@param args table Block arguments {CLONE_OPTION = "_myself_"|spriteName}
---@param runtime Runtime The runtime environment
---@param thread Thread The executing thread
function BlockHelpers.Control.create_clone_of(target, args, runtime, thread)
    local cloneOption = Cast.toString(args.CLONE_OPTION)

    -- Check clone limit first (Scratch has a limit of 300 clones)
    if not runtime:clonesAvailable() then
        log.debug("Control: Clone limit reached, cannot create clone of '%s'", cloneOption)
        return
    end

    -- Set clone target
    local cloneTarget
    if cloneOption == "_myself_" then
        cloneTarget = target
    else
        cloneTarget = runtime:getSpriteTargetByName(cloneOption)
    end

    -- If clone target is not found, return
    if not cloneTarget then
        log.warn("Control: Sprite '%s' tried to clone non-existent sprite '%s'", target.name, cloneOption)
        return
    end

    -- Create clone using makeClone
    local newClone = cloneTarget:makeClone()
    if newClone then
        runtime:addTarget(newClone)

        -- Place behind the original target (Scratch behavior)
        newClone:goBehindOther(cloneTarget)

        runtime:startHatBlocks(newClone, "control_start_as_clone")
    end
end

---Delete this clone
---@param target Sprite|Stage The sprite or stage executing the block
---@param args table Block arguments (unused)
---@param runtime Runtime The runtime environment
---@param thread Thread The executing thread
function BlockHelpers.Control.delete_this_clone(target, args, runtime, thread)
    -- Only delete clones, not original sprites
    if not target.isClone then
        return nil -- Continue execution, do nothing to original sprites
    end

    runtime:deleteClone(target)
    thread:stop()
    return "stop"
end

---Get current counter value
---@return number counter Current counter value
function BlockHelpers.Control.getCounter()
    return counter
end

---Increment counter by 1
function BlockHelpers.Control.incrCounter()
    counter = counter + 1
end

---Clear counter (reset to 0)
function BlockHelpers.Control.clearCounter()
    counter = 0
end

---Get clone option from menu (menu reporter block)
---@param target Sprite|Stage The sprite or stage executing the block
---@param args table Block arguments {CLONE_OPTION = string}
---@param runtime Runtime The runtime environment
---@param thread Thread The executing thread
---@return string option Clone option value
function BlockHelpers.Control.create_clone_of_menu(target, args, runtime, thread)
    return args.CLONE_OPTION
end

-- ============================================================================
-- Pen Helpers
-- ============================================================================

---@class BlockHelpers.Pen
BlockHelpers.Pen = {}

---Ensure target has pen state initialized
---@param target Sprite|Stage The sprite or stage
local function ensurePenState(target)
    if not target.penState then
        local PenState = require("pen.pen_state")
        target.penState = PenState:new()
        log.debug("Pen: Initialized pen state for " .. (target.name or "stage"))
    end
end

---Clear all pen drawings (erase all)
---@param target Sprite|Stage The sprite or stage executing the block
---@param args table Block arguments (unused)
---@param runtime Runtime The runtime environment
---@param thread Thread The executing thread
function BlockHelpers.Pen.clear(target, args, runtime, thread)
    if runtime.penRenderer then
        runtime.penRenderer:queueClear()
    end
end

---Put pen down (start drawing)
---@param target Sprite|Stage The sprite or stage executing the block
---@param args table Block arguments (unused)
---@param runtime Runtime The runtime environment
---@param thread Thread The executing thread
function BlockHelpers.Pen.penDown(target, args, runtime, thread)
    if target.isStage then return end

    ensurePenState(target)
    target.penState:setDown(true, target.x, target.y)

    -- Native Scratch behavior: immediately draw a point when pen goes down
    if runtime.penRenderer then
        runtime.penRenderer:queuePoint(
            target.x, target.y,
            target.penState.size, target.penState.hue,
            target.penState.saturation, target.penState.brightness,
            target.penState.transparency
        )
        runtime:requestRedraw()
    end
end

---Put pen up (stop drawing)
---@param target Sprite|Stage The sprite or stage executing the block
---@param args table Block arguments (unused)
---@param runtime Runtime The runtime environment
---@param thread Thread The executing thread
function BlockHelpers.Pen.penUp(target, args, runtime, thread)
    if target.isStage then return end

    ensurePenState(target)
    target.penState:setDown(false)
end

---Set pen color to a specific color (RGB hex value)
---@param target Sprite|Stage The sprite or stage executing the block
---@param args table Block arguments {COLOR = number|string}
---@param runtime Runtime The runtime environment
---@param thread Thread The executing thread
function BlockHelpers.Pen.setPenColorToColor(target, args, runtime, thread)
    if target.isStage then return end

    ensurePenState(target)
    local color = args.COLOR or 0

    -- Handle string hex colors (e.g., "#FF0000")
    if type(color) == "string" and color:match("^#%x%x%x%x%x%x$") then
        local hex = color:sub(2) -- Remove # prefix
        color = tonumber(hex, 16) or 0
    else
        color = Cast.toNumber(color)
    end

    -- Convert RGB to HSV
    target.penState:setColorFromRGB(color)

    -- Native Scratch also updates the legacy _shade value
    target.penState._shade = target.penState.brightness / 2
end

---Change pen color parameter by amount
---@param target Sprite|Stage The sprite or stage executing the block
---@param args table Block arguments {COLOR_PARAM = string, VALUE = number}
---@param runtime Runtime The runtime environment
---@param thread Thread The executing thread
function BlockHelpers.Pen.changePenColorParamBy(target, args, runtime, thread)
    if target.isStage then return end

    ensurePenState(target)
    local param = args.COLOR_PARAM or "color"
    local change = Cast.toNumber(args.VALUE)

    if param == "color" then
        target.penState:changeHue(change)
    elseif param == "saturation" then
        target.penState:changeSaturation(change)
    elseif param == "brightness" then
        target.penState:changeBrightness(change)
    elseif param == "transparency" then
        target.penState:changeTransparency(change)
    end
end

---Set pen color parameter to specific value
---@param target Sprite|Stage The sprite or stage executing the block
---@param args table Block arguments {COLOR_PARAM = string, VALUE = number}
---@param runtime Runtime The runtime environment
---@param thread Thread The executing thread
function BlockHelpers.Pen.setPenColorParamTo(target, args, runtime, thread)
    if target.isStage then return end

    ensurePenState(target)
    local param = args.COLOR_PARAM or "color"
    local value = Cast.toNumber(args.VALUE)

    if param == "color" then
        target.penState:setHue(value)
    elseif param == "saturation" then
        target.penState:setSaturation(value)
    elseif param == "brightness" then
        target.penState:setBrightness(value)
    elseif param == "transparency" then
        target.penState:setTransparency(value)
    end
end

---Clamp pen size based on miscLimits and renderer settings
---Clamp pen size
---@param size number Requested pen size
---@param runtime Runtime The runtime environment
---@return number clampedSize Clamped pen size
local function clampPenSize(size, runtime)
    -- Check if high quality rendering is enabled or miscLimits is disabled
    local useHighQuality = runtime.renderer and runtime.renderer.useHighQualityRender
    local miscLimits = runtime.runtimeOptions and runtime.runtimeOptions.miscLimits

    if useHighQuality or not miscLimits then
        -- No upper limit when high quality render or miscLimits disabled
        return math.max(0, size)
    else
        -- Standard Scratch limits: 1-1200
        return math.max(1, math.min(1200, size))
    end
end

---Change pen size by amount
---@param target Sprite|Stage The sprite or stage executing the block
---@param args table Block arguments {SIZE = number}
---@param runtime Runtime The runtime environment
---@param thread Thread The executing thread
function BlockHelpers.Pen.changePenSizeBy(target, args, runtime, thread)
    if target.isStage then return end

    ensurePenState(target)
    local change = Cast.toNumber(args.SIZE)
    local newSize = target.penState.size + change
    target.penState.size = clampPenSize(newSize, runtime)
end

---Set pen size to specific value
---@param target Sprite|Stage The sprite or stage executing the block
---@param args table Block arguments {SIZE = number}
---@param runtime Runtime The runtime environment
---@param thread Thread The executing thread
function BlockHelpers.Pen.setPenSizeTo(target, args, runtime, thread)
    if target.isStage then return end

    ensurePenState(target)
    local size = Cast.toNumber(args.SIZE or 1)
    target.penState.size = clampPenSize(size, runtime)
end

---Stamp the sprite onto the pen canvas
---@param target Sprite|Stage The sprite or stage executing the block
---@param args table Block arguments (unused)
---@param runtime Runtime The runtime environment
---@param thread Thread The executing thread
function BlockHelpers.Pen.stamp(target, args, runtime, thread)
    if target.isStage or not runtime.penRenderer then
        return
    end

    -- Create deep copy of effects to preserve snapshot
    local effectsCopy = {}
    for k, v in pairs(target.effects) do
        effectsCopy[k] = v
    end

    -- Get current costume object (not index)
    local currentCostume = target:getCurrentCostume()
    if not currentCostume then
        return -- No costume to stamp
    end

    -- Create stamp drawing function that uses transform snapshot
    local function stampDraw(transform)
        -- Use renderer with transform snapshot, applying pen canvas renderQuality
        runtime.renderer:drawSpriteWithTransform(
            transform,
            runtime.penRenderer:getCanvas(),
            runtime.penRenderer.renderQuality
        )
    end

    -- Queue stamp command with transform snapshot
    runtime.penRenderer:queueStamp(stampDraw, {
        x = target.x,
        y = target.y,
        size = target.size,
        direction = target.direction,
        rotationStyle = target.rotationStyle,
        costume = currentCostume,
        effects = effectsCopy
    })
    runtime:requestRedraw()
end

---Set pen transparency to specific value
---@param target Sprite|Stage The sprite or stage executing the block
---@param args table Block arguments {TRANSPARENCY = number}
---@param runtime Runtime The runtime environment
---@param thread Thread The executing thread
function BlockHelpers.Pen.setPenTransparencyTo(target, args, runtime, thread)
    if target.isStage then return end

    ensurePenState(target)
    local transparency = Cast.toNumber(args.TRANSPARENCY or 0)
    target.penState:setTransparency(transparency)
end

---Change pen transparency by amount
---@param target Sprite|Stage The sprite or stage executing the block
---@param args table Block arguments {TRANSPARENCY = number}
---@param runtime Runtime The runtime environment
---@param thread Thread The executing thread
function BlockHelpers.Pen.changePenTransparencyBy(target, args, runtime, thread)
    if target.isStage then return end

    ensurePenState(target)
    local change = Cast.toNumber(args.TRANSPARENCY)
    target.penState:changeTransparency(change)
end

---Set pen shade to specific value (legacy Scratch 2.0)
---@param target Sprite|Stage The sprite or stage executing the block
---@param args table Block arguments {SHADE = number}
---@param runtime Runtime The runtime environment
---@param thread Thread The executing thread
function BlockHelpers.Pen.setPenShadeToNumber(target, args, runtime, thread)
    if target.isStage then return end

    ensurePenState(target)
    local shade = Cast.toNumber(args.SHADE)
    target.penState:setShade(shade)
end

---Change pen shade by amount (legacy Scratch 2.0)
---@param target Sprite|Stage The sprite or stage executing the block
---@param args table Block arguments {SHADE = number}
---@param runtime Runtime The runtime environment
---@param thread Thread The executing thread
function BlockHelpers.Pen.changePenShadeBy(target, args, runtime, thread)
    if target.isStage then return end

    ensurePenState(target)
    local change = Cast.toNumber(args.SHADE)
    target.penState:changeShade(change)
end

---Set pen hue to specific value (legacy Scratch 2.0)
---@param target Sprite|Stage The sprite or stage executing the block
---@param args table Block arguments {HUE = number}
---@param runtime Runtime The runtime environment
---@param thread Thread The executing thread
function BlockHelpers.Pen.setPenHueToNumber(target, args, runtime, thread)
    if target.isStage then return end

    ensurePenState(target)
    local hueValue = Cast.toNumber(args.HUE or 0)

    -- Convert Scratch 2 hue to Scratch 3 color (divide by 2)
    local colorValue = hueValue / 2
    target.penState:setHue(colorValue)

    -- Also reset transparency and update legacy pen color
    target.penState:setTransparency(0)
    target.penState:legacyUpdatePenColor()
end

---Change pen hue by amount (legacy Scratch 2.0)
---@param target Sprite|Stage The sprite or stage executing the block
---@param args table Block arguments {HUE = number}
---@param runtime Runtime The runtime environment
---@param thread Thread The executing thread
function BlockHelpers.Pen.changePenHueBy(target, args, runtime, thread)
    if target.isStage then return end

    ensurePenState(target)
    local hueChange = Cast.toNumber(args.HUE or 0)

    -- Convert Scratch 2 hue to Scratch 3 color (divide by 2)
    local colorChange = hueChange / 2
    target.penState:changeHue(colorChange)

    -- Update legacy pen color
    target.penState:legacyUpdatePenColor()
end

return BlockHelpers
