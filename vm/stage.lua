-- Stage
-- Represents the Scratch stage
local log = require("lib.log")
local Global = require("global")
local Variable = require("vm.variable")
local ProjectModel = require("parser.project_model")

---@class Stage
---@field runtime Runtime Runtime instance
---@field name string Stage name (always "Stage")
---@field isStage boolean Always true for stage
---@field x number X position in Scratch coordinates
---@field y number Y position in Scratch coordinates
---@field size number Size percentage (100 = normal)
---@field direction number Direction in degrees (0 = up)
---@field rotationStyle string Rotation style (always "don't rotate" for stage)
---@field blocks table<string, Block> Stage blocks
---@field blockOrder string[] Ordered array of block IDs (preserves JSON order for stable compilation)
---@field hatBlockIndex table<string, table> Hat block index for fast lookups
---@field variables table<string, any> Stage variables
---@field lists table<string, any[]> Stage lists
---@field costumes Costume[] Available costumes
---@field sounds Sound[] Available sounds
---@field currentCostume integer Current costume index
---@field volume number Volume percentage (0-100)
---@field tempo number Tempo setting
---@field videoTransparency number Video transparency
---@field videoState string Video state
---@field effects table<string, number> Graphics effects
---@field _transformCache TransformCache Unified transform cache manager
---@field _compiledStates table<string, table> Compiled state storage for complex operations
---@field backgroundColor table Current background color (r,g,b)
local Stage = {}
Stage.__index = Stage

---Create a new stage
---@param data Target Stage data from project
---@param runtime Runtime Runtime instance
---@return Stage
function Stage:new(data, runtime)
    local self = setmetatable({}, Stage)

    self.runtime = runtime
    self.name = "Stage"
    self.isStage = true
    self.blocks = data.blocks or {}
    self.blockOrder = data.blockOrder or {}

    -- Initialize hat block index for fast lookups
    self.hatBlockIndex = {
        ["event_whenflagclicked"] = {},
        ["event_whenbroadcastreceived"] = {},
        ["event_whenkeypressed"] = {},
        ["event_whenstageclicked"] = {},
        ["event_whenbackdropswitchesto"] = {}
    }

    self.variables = {}
    self.costumes = data.costumes or {}
    self.sounds = data.sounds or {}
    self.currentCostume = data.currentCostume or 0
    self.volume = data.volume or 100
    self.tempo = data.tempo or 60
    self.videoTransparency = data.videoTransparency or 50
    self.videoState = data.videoState or "on"
    self.backgroundColor = { 255, 255, 255 } -- Default white background (array format for performance)

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

    -- Stage position (always at center)
    self.x = 0
    self.y = 0
    self.size = 100     -- Stage doesn't scale but we need this for TransformCache
    self.direction = 90 -- Stage doesn't rotate
    self.rotationStyle = "don't rotate"

    -- Create transform cache for stage (for backdrop coordinate transformation)
    local TransformCache = require("utils.transform_cache")
    self._transformCache = TransformCache:new(self)

    -- Compiled state storage for complex operations (glide, say/think timers, etc.)
    self._compiledStates = {}

    -- Initialize variables using Variable class
    for id, varData in pairs(data.variables or {}) do
        local variable = Variable:new(id, varData.name, Variable.SCALAR_TYPE, varData.cloud or false)
        variable.value = varData.value
        self.variables[id] = variable
    end

    -- Initialize lists using Variable class
    for id, listData in pairs(data.lists or {}) do
        local list = Variable:new(id, listData.name, Variable.LIST_TYPE, false)
        list.value = listData.value or {}
        self.variables[id] = list -- Store lists in variables table like original Scratch
    end

    -- Initialize broadcasts as special Variable objects (matching native Scratch behavior)
    -- Native Scratch stores broadcasts in stage.variables with type BROADCAST_MESSAGE_TYPE
    for id, broadcastName in pairs(data.broadcasts or {}) do
        local broadcast = Variable:new(id, broadcastName, Variable.BROADCAST_MESSAGE_TYPE, false)
        broadcast.value = broadcastName
        self.variables[id] = broadcast -- Store in variables table like original Scratch
    end

    -- Also store broadcasts on runtime for quick lookup (if runtime exists)
    if self.runtime then
        self.runtime.broadcasts = data.broadcasts or {}
    end

    -- Build hat block index
    self:buildHatBlockIndex()

    return self
end

function Stage:initialize()
    if self.initialized then
        return
    end
    self.initialized = true
    -- Load backdrops (lazy loading: store getImage closures, don't create textures yet)
    for i, backdrop in ipairs(self.costumes) do
        local asset = self.runtime.project:getAsset(backdrop.assetId)
        if asset and asset.type == "image" then
            -- Lazy loading: store closures instead of creating textures immediately
            backdrop.image = nil  -- Will be loaded on first access
            backdrop._getImage = asset.getImage  -- Closure to create Image on demand
            backdrop._getImageData = asset.getImageData  -- Closure for lazy ImageData loading

            if asset.originalFormat == "svg" and backdrop.bitmapResolution == 1 then
                -- SVG was rasterized at 2x resolution for better quality
                -- Override the bitmapResolution from project JSON
                -- Only adjust if not already adjusted (to avoid double-scaling)
                backdrop.bitmapResolution = Global.SVG_RESOLUTION_SCALE
                -- Rotation center values in project JSON are in CSS pixel units (1x).
                -- We need to scale them to match our 2x texture.
                if backdrop.rotationCenterX and type(backdrop.rotationCenterX) == "number" then
                    backdrop.rotationCenterX = backdrop.rotationCenterX * Global.SVG_RESOLUTION_SCALE
                end
                if backdrop.rotationCenterY and type(backdrop.rotationCenterY) == "number" then
                    backdrop.rotationCenterY = backdrop.rotationCenterY * Global.SVG_RESOLUTION_SCALE
                end

                -- Compensate for viewBox offset (matching native Scratch)
                -- In Scratch, rotationCenter is relative to viewBox coordinates
                -- When viewBox has non-zero origin, we need to subtract that offset
                if asset.viewBoxOffsetX and asset.viewBoxOffsetX ~= 0 then
                    local offsetX = asset.viewBoxOffsetX * Global.SVG_RESOLUTION_SCALE
                    backdrop.rotationCenterX = (backdrop.rotationCenterX or 0) - offsetX
                    log.debug("Applied viewBox X offset to backdrop: %.2f (scaled: %.2f)",
                        asset.viewBoxOffsetX, offsetX)
                end
                if asset.viewBoxOffsetY and asset.viewBoxOffsetY ~= 0 then
                    local offsetY = asset.viewBoxOffsetY * Global.SVG_RESOLUTION_SCALE
                    backdrop.rotationCenterY = (backdrop.rotationCenterY or 0) - offsetY
                    log.debug("Applied viewBox Y offset to backdrop: %.2f (scaled: %.2f)",
                        asset.viewBoxOffsetY, offsetY)
                end

                log.debug(
                    "Stage: SVG backdrop %s set to bitmapResolution=%d, rotation center: %.1f,%.1f",
                    backdrop.name,
                    backdrop.bitmapResolution,
                    backdrop.rotationCenterX or 0,
                    backdrop.rotationCenterY or 0)
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

function Stage:update(dt)
    -- Stage updates if needed
end

---Get the transform cache for this stage (used for backdrop coordinate transformation)
---@return TransformCache transformCache The stage's transform cache
function Stage:getTransformCache()
    return self._transformCache
end

function Stage:getCurrentBackdrop()
    local index = math.floor(self.currentCostume) + 1
    if index < 1 then index = 1 end
    if index > #self.costumes then index = #self.costumes end

    local costume = self.costumes[index]

    if costume then
        -- Lazy loading: ensure image is loaded before returning
        if not costume.image then
            ProjectModel.ensureImage(costume)
        end

        -- Track usage for consistency (though stage doesn't cleanup)
        costume.lastUsedTime = love.timer.getTime()
        costume.useCount = (costume.useCount or 0) + 1
    end

    return costume
end

---Get current costume (alias for getCurrentBackdrop for compatibility with TransformCache)
---@return Costume|nil costume Current backdrop
function Stage:getCurrentCostume()
    return self:getCurrentBackdrop()
end

---Switch to a backdrop by name or index (follows Scratch logic)
---@param requestedBackdrop any Backdrop name, index, or special value
---@return table threads Array of threads started by this switch
function Stage:switchBackdrop(requestedBackdrop)
    local startedThreads = {}
    local oldCostume = self.currentCostume

    if #self.costumes == 0 then
        return startedThreads
    end

    -- Handle different types like native Scratch
    if type(requestedBackdrop) == "number" then
        -- Numbers are always treated as indices (1-based)
        if requestedBackdrop ~= requestedBackdrop then -- NaN check
            self.currentCostume = 0                    -- First backdrop
        elseif requestedBackdrop == math.huge or requestedBackdrop == -math.huge then
            self.currentCostume = 0                    -- First backdrop
        else
            -- Wrap around using modulo, handling negative indices
            local index = math.floor(requestedBackdrop) - 1
            self.currentCostume = index % #self.costumes
            if self.currentCostume < 0 then
                self.currentCostume = self.currentCostume + #self.costumes
            end
        end
    elseif type(requestedBackdrop) == "boolean" then
        -- First check if there's a backdrop with the boolean's string name
        local boolStr = tostring(requestedBackdrop) -- "true" or "false"
        local found = false
        for i, backdrop in ipairs(self.costumes) do
            if backdrop.name == boolStr then
                self.currentCostume = i - 1
                found = true
                break
            end
        end
        if not found then
            -- Follow native Scratch behavior:
            -- true -> "true" -> Number("true") -> NaN -> index 0
            -- false -> "false" -> Number("false") -> NaN -> index 0
            -- But false is special: it's treated as index 0 which wraps to last backdrop
            if requestedBackdrop then
                -- true: index 0 (first backdrop)
                self.currentCostume = 0
            else
                -- false: index 0 but wraps to last backdrop
                self.currentCostume = #self.costumes - 1
            end
        end
    elseif type(requestedBackdrop) == "string" then
        -- First try to find by exact name
        local found = false
        for i, backdrop in ipairs(self.costumes) do
            if backdrop.name == requestedBackdrop then
                self.currentCostume = i - 1
                found = true
                break
            end
        end

        if not found then
            -- Check for special commands
            local lower = requestedBackdrop:lower()
            if lower == "next backdrop" then
                self.currentCostume = (self.currentCostume + 1) % #self.costumes
            elseif lower == "previous backdrop" then
                self.currentCostume = (self.currentCostume - 1) % #self.costumes
                if self.currentCostume < 0 then
                    self.currentCostume = self.currentCostume + #self.costumes
                end
            elseif lower == "random backdrop" then
                -- Pick a random backdrop different from current (like Scratch)
                if #self.costumes > 1 then
                    local newIndex
                    repeat
                        newIndex = math.random(0, #self.costumes - 1)
                    until newIndex ~= self.currentCostume
                    self.currentCostume = newIndex
                end
            elseif lower == "next costume" or lower == "previous costume" then
                -- Backdrop switching ignores costume commands
                -- Do nothing, keep current backdrop
            else
                -- Try to parse as number if it's not whitespace-only
                local isWhitespace = requestedBackdrop:match("^%s*$")
                if not isWhitespace then
                    -- Special handling for boolean strings (native Scratch behavior)
                    if requestedBackdrop == "true" then
                        -- "true" -> Number("true") -> NaN -> index 0 (first backdrop)
                        self.currentCostume = 0
                    elseif requestedBackdrop == "false" then
                        -- "false" -> Number("false") -> NaN -> index 0 but wraps to last backdrop
                        self.currentCostume = #self.costumes - 1
                    else
                        local num = tonumber(requestedBackdrop)
                        if num then
                            -- Recursive call with number
                            return self:switchBackdrop(num)
                        end
                    end
                end
                -- If nothing matches, keep current backdrop
            end
        end
    else
        -- Other types (nil, table, etc.) - keep current backdrop
    end

    -- If backdrop actually changed, trigger events
    if oldCostume ~= self.currentCostume then
        local backdrop = self:getCurrentBackdrop()
        if backdrop then
            -- Trigger backdrop change event for stage
            local t = self.runtime:startHatBlocks(self, "event_whenbackdropswitchesto", backdrop.name)
            for _, thr in ipairs(t) do table.insert(startedThreads, thr) end

            -- Also trigger for all targets (sprites and clones)
            for _, target in ipairs(self.runtime.targets) do
                local tt = self.runtime:startHatBlocks(target, "event_whenbackdropswitchesto", backdrop.name)
                for _, thr in ipairs(tt) do table.insert(startedThreads, thr) end
            end
        end
    end

    return startedThreads
end

function Stage:nextBackdrop()
    self.currentCostume = (self.currentCostume + 1) % #self.costumes

    local startedThreads = {}
    local backdrop = self:getCurrentBackdrop()
    if backdrop then
        -- Trigger backdrop change event
        local t = self.runtime:startHatBlocks(self, "event_whenbackdropswitchesto", backdrop.name)
        for _, thr in ipairs(t) do table.insert(startedThreads, thr) end

        for _, target in ipairs(self.runtime.targets) do
            local tt = self.runtime:startHatBlocks(target, "event_whenbackdropswitchesto", backdrop.name)
            for _, thr in ipairs(tt) do table.insert(startedThreads, thr) end
        end
    end
    return startedThreads
end

function Stage:setEffect(effect, value)
    effect = effect:lower()
    if self.effects[effect] ~= nil then
        self.effects[effect] = value
    end
end

function Stage:changeEffect(effect, delta)
    effect = effect:lower()
    if self.effects[effect] ~= nil then
        self.effects[effect] = self.effects[effect] + delta
    end
end

---Get a graphics effect value
---@param effect string Effect name
---@return number value Effect value
function Stage:getEffect(effect)
    return self.effects[effect] or 0
end

function Stage:clearEffects()
    for effect in pairs(self.effects) do
        self.effects[effect] = 0
    end
end

---Show stage (no-op - Stage is always visible)
---Matches native Scratch behavior where RenderedTarget.setVisible() returns early for Stage
function Stage:show()
    -- Stage cannot be hidden in Scratch, so this is a no-op
end

---Hide stage (no-op - Stage is always visible)
---Matches native Scratch behavior where RenderedTarget.setVisible() returns early for Stage
function Stage:hide()
    -- Stage cannot be hidden in Scratch, so this is a no-op
end

function Stage:playSound(soundName)
    for _, sound in ipairs(self.sounds) do
        if sound.name == soundName and sound.source then
            sound.source:play()
            return sound.source
        end
    end
end

function Stage:stopAllSounds()
    love.audio.stop()
end

function Stage:setVolume(volume)
    self.volume = math.max(0, math.min(100, volume))
    love.audio.setVolume(self.volume / 100)
end

function Stage:changeVolume(delta)
    self:setVolume(self.volume + delta)
end

---Build hat block index for fast lookups
function Stage:buildHatBlockIndex()
    -- Clear existing index
    for opcode in pairs(self.hatBlockIndex) do
        self.hatBlockIndex[opcode] = {}
    end

    -- Index all hat blocks using stable order from JSON
    if not self.blockOrder then
        error("Stage:buildHatBlockIndex: blockOrder is required for stable compilation order")
    end

    for _, blockId in ipairs(self.blockOrder) do
        local block = self.blocks[blockId]
        if block and block.topLevel and self.hatBlockIndex[block.opcode] then
            table.insert(self.hatBlockIndex[block.opcode], blockId)
        end
    end
end

---Add a block and update hat block index
---@param blockId string Block ID
---@param block Block Block data
function Stage:addBlock(blockId, block)
    self.blocks[blockId] = block

    -- Update hat block index if this is a hat block
    if block.topLevel and self.hatBlockIndex[block.opcode] then
        table.insert(self.hatBlockIndex[block.opcode], blockId)
    end
end

---Get hat blocks by opcode and parameter
---@param opcode string Hat block opcode
---@param param any Optional parameter for matching
---@return string[] blockIds Array of matching block IDs
function Stage:getHatBlocks(opcode, param)
    if not self.hatBlockIndex[opcode] then
        return {}
    end

    local matchingBlocks = {}
    for _, blockId in ipairs(self.hatBlockIndex[opcode]) do
        local block = self.blocks[blockId]
        if block then
            local shouldMatch = false

            if opcode == "event_whenflagclicked" or opcode == "event_whenstageclicked" then
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
            end

            if shouldMatch then
                table.insert(matchingBlocks, blockId)
            end
        end
    end

    return matchingBlocks
end

-- Variable Management Methods (matching original Scratch behavior)

---Look up a variable by ID (stage only checks its own variables)
---@param id string Variable ID
---@return Variable|nil Variable object if found
function Stage:lookupVariableById(id)
    return self.variables[id]
end

---Look up a variable by name and type
---@param name string Variable name
---@param type string Variable type (SCALAR_TYPE, LIST_TYPE, etc.)
---@param skipStage? boolean Ignored for stage (for API compatibility)
---@return Variable|nil Variable object if found
function Stage:lookupVariableByNameAndType(name, variableType, skipStage)
    if type(name) ~= "string" then
        return nil
    end

    variableType = variableType or Variable.SCALAR_TYPE

    -- Check stage variables
    for id, variable in pairs(self.variables) do
        if variable.name == name and variable.type == variableType then
            return variable
        end
    end

    return nil
end

---Look up or create a scalar variable (matching original Scratch behavior)
---@param id string Variable ID
---@param name string Variable name
---@return Variable Variable object (existing or newly created)
function Stage:lookupOrCreateVariable(id, name)
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

    -- Create new variable on stage if not found
    local newVariable = Variable:new(id, name, Variable.SCALAR_TYPE, false)
    self.variables[id] = newVariable
    return newVariable
end

---Look up or create a list variable (matching original Scratch behavior)
---@param id string List ID
---@param name string List name
---@return Variable List object (existing or newly created)
function Stage:lookupOrCreateList(id, name)
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

    -- Create new list on stage if not found
    local newList = Variable:new(id, name, Variable.LIST_TYPE, false)
    self.variables[id] = newList
    return newList
end

---Get compiled state for a specific operation
---@param stateKey string Unique state key for the operation
---@return table|nil state The state data, or nil if not found
function Stage:getCompiledState(stateKey)
    return self._compiledStates[stateKey]
end

---Set compiled state for a specific operation
---@param stateKey string Unique state key for the operation
---@param stateData table|nil State data to store, or nil to clear
function Stage:setCompiledState(stateKey, stateData)
    self._compiledStates[stateKey] = stateData
end

---Clear all compiled states (used when stage is reset)
function Stage:clearCompiledStates()
    self._compiledStates = {}
end

return Stage
