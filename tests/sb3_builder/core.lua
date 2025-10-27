-- SB3 Builder Core Module
-- Provides core functionality for building Scratch 3.0 projects programmatically

local Cast = require("utils.cast")
local json = require("lib.json")

local Core = {}

-- Import type definitions
---@type table
local types = require("tests.sb3_builder.types")

-- SB3 Constants
Core.INPUT_SAME_BLOCK_SHADOW = 1  -- unobscured shadow
Core.INPUT_BLOCK_NO_SHADOW = 2    -- no shadow
Core.INPUT_DIFF_BLOCK_SHADOW = 3  -- obscured shadow

-- Primitive type constants
Core.MATH_NUM_PRIMITIVE = 4       -- math_number
Core.POSITIVE_NUM_PRIMITIVE = 5   -- math_positive_number
Core.WHOLE_NUM_PRIMITIVE = 6      -- math_whole_number
Core.INTEGER_NUM_PRIMITIVE = 7    -- math_integer
Core.ANGLE_NUM_PRIMITIVE = 8      -- math_angle
Core.COLOR_PICKER_PRIMITIVE = 9   -- colour_picker
Core.TEXT_PRIMITIVE = 10          -- text
Core.BROADCAST_PRIMITIVE = 11     -- event_broadcast_menu
Core.VAR_PRIMITIVE = 12           -- data_variable
Core.LIST_PRIMITIVE = 13          -- data_listcontents

-- ID counter for unique block/variable IDs
local idCounter = 1

---Generate next unique ID
---@return string id Unique block/variable ID
local function nextId()
    local id = "testblock_" .. idCounter
    idCounter = idCounter + 1
    return id
end

---Reset ID counter for clean tests
function Core.resetCounter()
    idCounter = 1
end

---Get next ID without incrementing counter (for preview)
---@return string id Next ID that would be generated
function Core.peekNextId()
    return "testblock_" .. idCounter
end

-- Asset ID generator (32-character hex string)
---Generate a mock 32-character asset ID
---@return string assetId 32-character hex string
local function generateAssetId()
    local chars = "0123456789abcdef"
    local result = ""
    for i = 1, 32 do
        local idx = math.random(1, 16)
        result = result .. chars:sub(idx, idx)
    end
    return result
end

-- ===== PRIMITIVE AND INPUT CREATION =====

---Create a primitive input value
---@param value SB3Builder.ScalarValue The primitive value
---@param primitiveType SB3Builder.PrimitiveType|nil Primitive type (auto-detected if nil)
---@return SB3Builder.Input input SB3 input descriptor
function Core.primitiveInput(value, primitiveType)
    if not primitiveType then
        primitiveType = type(value) == "number" and Core.MATH_NUM_PRIMITIVE or Core.TEXT_PRIMITIVE
    end

    -- Convert boolean values to strings when using TEXT_PRIMITIVE
    if primitiveType == Core.TEXT_PRIMITIVE and type(value) == "boolean" then
        value = Cast.toString(value)
    end

    return { Core.INPUT_SAME_BLOCK_SHADOW, { primitiveType, value } }
end

---Create a block reference input
---@param blockId string Block ID to reference
---@param shadowId string|nil Optional shadow block ID
---@return SB3Builder.Input input SB3 input descriptor
function Core.blockInput(blockId, shadowId)
    if shadowId then
        return { Core.INPUT_DIFF_BLOCK_SHADOW, blockId, shadowId }
    else
        return { Core.INPUT_BLOCK_NO_SHADOW, blockId }
    end
end

---Create a substack input (for control blocks)
---@param blockId string|nil Block ID of first block in substack
---@return SB3Builder.Input input SB3 input descriptor
function Core.substackInput(blockId)
    return { Core.INPUT_BLOCK_NO_SHADOW, blockId }
end

---Normalize any input value to proper SB3 format
---@param input any Input value to normalize
---@return SB3Builder.Input|nil input Normalized SB3 input
function Core.normalizeInput(input)
    if input == nil then
        return nil
    end

    -- Already a proper input structure
    if type(input) == "table" and type(input[1]) == "number" and input[1] >= 1 and input[1] <= 3 then
        return input
    end

    -- Block ID reference
    if type(input) == "string" and input:match("^testblock_") then
        return Core.blockInput(input)
    end

    -- Primitive value
    return Core.primitiveInput(input)
end

-- ===== FIELD CREATION =====

---Create a field with optional ID
---@param value string Field value
---@param id string|nil Field ID (for variables/lists/broadcasts)
---@return SB3Builder.Field field SB3 field descriptor
function Core.field(value, id)
    if id then
        return { value, id }
    else
        return { value }
    end
end

-- ===== BLOCK CREATION =====

---Create a block with specified parameters
---@param opcode string Block opcode
---@param inputs table<string, any>|nil Block inputs (will be normalized)
---@param fields table<string, any>|nil Block fields
---@param options SB3Builder.BlockOptions|nil Additional options
---@param mutation SB3Builder.Mutation|nil Block mutation data
---@return string id Generated block ID
---@return SB3Builder.Block block Block data structure
function Core.createBlock(opcode, inputs, fields, options, mutation)
    options = options or {}
    local id = nextId()

    -- Normalize all inputs
    local normalizedInputs = {}
    if inputs then
        for key, value in pairs(inputs) do
            normalizedInputs[key] = Core.normalizeInput(value)
        end
    end

    -- Create the block structure
    local block = {
        opcode = opcode,
        inputs = normalizedInputs,
        fields = fields or {},
        next = options.next,
        parent = options.parent,
        shadow = options.shadow or false,
        topLevel = options.topLevel or false
    }

    -- Add mutation if provided
    if mutation then
        block.mutation = mutation
    end

    -- Add position for top-level blocks
    if options.topLevel then
        block.x = options.x or 0
        block.y = options.y or 0
    end

    return id, block
end

-- ===== TARGET CREATION =====

---Create a stage target
---@param options SB3Builder.TargetOptions|nil Stage options
---@return SB3Builder.Stage stage Stage target
function Core.createStage(options)
    options = options or {}
    local blocks = {}
    -- Initialize with metatable for stable compilation order
    setmetatable(blocks, { __keyOrder = {} })

    return {
        isStage = true,
        name = "Stage",
        variables = {},
        lists = {},
        broadcasts = {},
        blocks = blocks,
        comments = {},
        currentCostume = options.currentCostume or 0,
        costumes = options.costumes or {},
        sounds = options.sounds or {},
        layerOrder = 0,
        volume = options.volume or 100,
        tempo = options.tempo or 60,
        videoTransparency = options.videoTransparency or 50,
        videoState = options.videoState or "off",
        textToSpeechLanguage = options.textToSpeechLanguage
    }
end

---Create a sprite target
---@param name string Sprite name
---@param options SB3Builder.TargetOptions|nil Sprite options
---@return SB3Builder.Sprite sprite Sprite target
function Core.createSprite(name, options)
    options = options or {}
    local blocks = {}
    -- Initialize with metatable for stable compilation order
    setmetatable(blocks, { __keyOrder = {} })

    return {
        isStage = false,
        name = name or "Sprite1",
        variables = {},
        lists = {},
        broadcasts = {},
        blocks = blocks,
        comments = {},
        currentCostume = options.currentCostume or 0,
        costumes = options.costumes or {},
        sounds = options.sounds or {},
        layerOrder = options.layerOrder or 1,
        volume = options.volume or 100,
        visible = options.visible ~= false,
        x = options.x or 0,
        y = options.y or 0,
        size = options.size or 100,
        direction = options.direction or 90,
        draggable = options.draggable or false,
        rotationStyle = options.rotationStyle or "all around",
        soundEffects = options.soundEffects
    }
end

-- ===== DATA MANAGEMENT =====

---Add a variable to target
---@param target SB3Builder.Target Target to add variable to
---@param name string Variable name
---@param value SB3Builder.ScalarValue Variable value
---@param idOrIsCloud string|boolean|nil Variable ID (auto-generated if nil) or cloud flag
---@return string id Variable ID
function Core.addVariable(target, name, value, idOrIsCloud)
    local id, isCloud
    if type(idOrIsCloud) == "boolean" then
        -- Fourth parameter is cloud flag
        isCloud = idOrIsCloud
        id = nextId()
    else
        -- Fourth parameter is ID or nil
        id = idOrIsCloud or nextId()
        isCloud = false
    end

    if value == nil then
        value = 0
    end

    if isCloud then
        target.variables[id] = { name, value, true }
    else
        target.variables[id] = { name, value }
    end
    return id
end

---Add a list to target
---@param target SB3Builder.Target Target to add list to
---@param name string List name
---@param items SB3Builder.ScalarValue[] List items
---@param id string|nil List ID (auto-generated if nil)
---@return string id List ID
function Core.addList(target, name, items, id)
    id = id or nextId()
    target.lists[id] = { name, items or {} }
    return id
end

---Add a broadcast to target
---@param target SB3Builder.Target Target to add broadcast to
---@param name string Broadcast name
---@param id string|nil Broadcast ID (auto-generated if nil)
---@return string id Broadcast ID
function Core.addBroadcast(target, name, id)
    id = id or nextId()
    target.broadcasts[id] = name
    return id
end

---Add a block to target
---@param target SB3Builder.Target Target to add block to
---@param blockId string Block ID
---@param block SB3Builder.Block Block data
function Core.addBlock(target, blockId, block)
    target.blocks[blockId] = block

    -- Maintain __keyOrder in metatable for stable compilation
    local mt = getmetatable(target.blocks)
    if not mt then
        mt = { __keyOrder = {} }
        setmetatable(target.blocks, mt)
    end
    if not mt.__keyOrder then
        mt.__keyOrder = {}
    end

    -- Add to order if not already present
    local alreadyExists = false
    for _, id in ipairs(mt.__keyOrder) do
        if id == blockId then
            alreadyExists = true
            break
        end
    end
    if not alreadyExists then
        table.insert(mt.__keyOrder, blockId)
    end
end

-- ===== BLOCK LINKING =====

---Link blocks together in a chain
---@param target SB3Builder.Target Target containing the blocks
---@param blockChain string[] Array of block IDs to link in order
function Core.linkBlocks(target, blockChain)
    if #blockChain == 0 then
        return
    end

    -- Link consecutive blocks
    for i = 1, #blockChain - 1 do
        local currentBlockId = blockChain[i]
        local nextBlockId = blockChain[i + 1]
        local currentBlock = target.blocks[currentBlockId]
        local nextBlock = target.blocks[nextBlockId]
        
        if currentBlock and nextBlock then
            currentBlock.next = nextBlockId
            nextBlock.parent = currentBlockId
        end
    end

    -- Mark first block as top-level
    local firstBlock = target.blocks[blockChain[1]]
    if firstBlock then
        firstBlock.topLevel = true
    end
end

-- ===== ASSET CREATION =====

---Create a costume object
---@param name string Costume name
---@param format string Image format
---@param assetId string|nil Asset ID (auto-generated if nil)
---@param options table|nil Additional options
---@return SB3Builder.Costume costume Costume object
function Core.createCostume(name, format, assetId, options)
    options = options or {}
    assetId = assetId or generateAssetId()

    local costume = {
        assetId = assetId,
        dataFormat = format,
        name = name,
        md5ext = assetId .. "." .. format
    }

    -- Add optional properties
    if format ~= "svg" and options.bitmapResolution then
        costume.bitmapResolution = options.bitmapResolution
    end
    if options.rotationCenterX then
        costume.rotationCenterX = options.rotationCenterX
    end
    if options.rotationCenterY then
        costume.rotationCenterY = options.rotationCenterY
    end

    -- Add mock image data for testing boundary calculations
    -- This ensures costumes have realistic size for edge bounce detection
    local width = options.width or 64
    local height = options.height or 64

    costume.image = love.graphics.newImage(love.graphics.newImageData(width, height))
    costume.imageData = love.graphics.newImageData(width, height)

    -- Set default rotation center if not provided
    if not costume.rotationCenterX then
        costume.rotationCenterX = width / 2
    end
    if not costume.rotationCenterY then
        costume.rotationCenterY = height / 2
    end

    return costume
end

---Create a sound object
---@param name string Sound name
---@param format string Sound format
---@param assetId string|nil Asset ID (auto-generated if nil)
---@param options table|nil Additional options
---@return SB3Builder.Sound sound Sound object
function Core.createSound(name, format, assetId, options)
    options = options or {}
    assetId = assetId or generateAssetId()

    local sound = {
        assetId = assetId,
        dataFormat = format,
        name = name,
        md5ext = assetId .. "." .. format
    }

    -- Add optional properties
    if options.rate then
        sound.rate = options.rate
    end
    if options.sampleCount then
        sound.sampleCount = options.sampleCount
    end

    return sound
end

-- ===== PROJECT CREATION =====

---Create a complete SB3 project
---@param targets (SB3Builder.Stage|SB3Builder.Sprite)[]|nil Array of targets
---@param options table|nil Project options
---@return SB3Builder.Project project Complete SB3 project
function Core.createProject(targets, options)
    options = options or {}
    targets = targets or { Core.createStage() }

    -- Collect assets from all costumes and sounds
    local assets = {}
    for _, target in ipairs(targets) do
        -- Collect costume assets
        if target.costumes then
            for _, costume in ipairs(target.costumes) do
                if costume.assetId and costume.image and costume.imageData then
                    assets[costume.assetId] = {
                        type = "image",
                        data = costume.image,
                        imageData = costume.imageData,
                        originalFormat = costume.dataFormat
                    }
                end
            end
        end

        -- Collect sound assets
        if target.sounds then
            for _, sound in ipairs(target.sounds) do
                if sound.assetId then
                    assets[sound.assetId] = {
                        type = "sound",
                        data = sound.data or {},
                        originalFormat = sound.dataFormat
                    }
                end
            end
        end
    end

    return {
        targets = targets,
        monitors = options.monitors or {},
        extensions = options.extensions or {},
        meta = options.meta or {
            semver = "3.0.0",
            vm = "0.1.0",
            agent = "sb3_builder_test"
        },
        assets = assets
    }
end

return Core