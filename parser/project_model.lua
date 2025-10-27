-- Project Model
-- Represents a parsed Scratch 3.0 project
local log = require("lib.log")
local json = require("lib.json")

---@class TurboWarpRuntimeOptions
---@field maxClones number Maximum number of clones allowed (default: 300, can be math.huge for unlimited)
---@field miscLimits boolean Enable miscellaneous limits like sound effect ranges (default: true)
---@field fencing boolean Keep sprites within stage bounds (default: true)

---@class TurboWarpProjectOptions
---@field framerate number|nil Target frame rate (default: 30 FPS)
---@field width number|nil Stage width in pixels (default: 480)
---@field height number|nil Stage height in pixels (default: 360)
---@field turbo boolean|nil Enable turbo mode for faster execution (default: false)
---@field interpolation boolean|nil Enable frame interpolation for smoother rendering (default: false)
---@field hq boolean|nil Enable high quality rendering (default: false)
---@field runtimeOptions TurboWarpRuntimeOptions|nil Runtime behavior options (maxClones, miscLimits, fencing)

---@class ProjectModel
---@field meta table Project metadata
---@field targets Target[] List of all targets (sprites and stage)
---@field stage Target? Reference to the stage target
---@field monitors table[] Monitor widgets data
---@field extensions table[] Extensions used in project
---@field extensionIDs table<string, boolean> Set of extension IDs detected in project
---@field assets table<string, Asset> Asset storage indexed by MD5 hash
---@field projectPath string|nil Filesystem path (Love save directory relative) where project resources are stored
---@field projectOptions TurboWarpProjectOptions|nil TurboWarp project options (framerate, width, height, etc.) parsed from stage comments
local ProjectModel = {}
ProjectModel.__index = ProjectModel

-- TurboWarp configuration comment magic string 
local COMMENT_CONFIG_MAGIC = " // _twconfig_"

---@class Target
---@field isStage boolean Whether this is the stage target
---@field name string Target name
---@field drawableId integer|nil Unique drawable ID assigned by renderer
---@field variables table<string, Variable> Target variables
---@field lists table<string, List> Target lists
---@field broadcasts table<string, string> Broadcast messages
---@field blocks table<string, Block> Target blocks (dictionary for fast lookup)
---@field blockOrder string[] Ordered array of block IDs (preserves JSON order for stable compilation)
---@field comments table Target comments
---@field currentCostume integer Current costume index
---@field costumes Costume[] Available costumes
---@field sounds Sound[] Available sounds
---@field layerOrder integer Layer ordering
---@field volume number Volume level (0-100)
---@field visible? boolean Sprite visibility (sprites only)
---@field x? number Sprite X position (sprites only)
---@field y? number Sprite Y position (sprites only)
---@field size? number Sprite size percentage (sprites only)
---@field direction? number Sprite direction in degrees (sprites only)
---@field draggable? boolean Whether sprite is draggable (sprites only)
---@field rotationStyle? string Rotation style (sprites only)
---@field soundEffects? table<string, number> Sound effects state (sprites only)
---@field tempo? number Tempo setting (stage only)
---@field videoTransparency? number Video transparency (stage only)
---@field videoState? string Video state (stage only)
---@field textToSpeechLanguage? string TTS language (stage only)

---@class Variable
---@field name string Variable name
---@field value string|number|boolean Variable value (Scratch variables can be strings, numbers, or booleans)
---@field cloud boolean Whether it's a cloud variable

---@class List
---@field name string List name
---@field value (string|number|boolean)[] List contents (array of Scratch values)

---@class Block
---@field opcode string Block operation code
---@field next string|nil Next block ID
---@field parent string|nil Parent block ID
---@field inputs table<string, Input> Block inputs
---@field fields table<string, Field> Block fields
---@field shadow boolean Whether block is shadow
---@field topLevel boolean Whether block is top-level
---@field x? number Block X position (top-level only)
---@field y? number Block Y position (top-level only)
---@field mutation? table Block mutation data

---@alias CompressedPrimitive number[]|table Array representing compressed primitive block [type, value, ...extra]

---@class Input
---@field shadowType number Shadow type (1=same block+shadow, 2=block no shadow, 3=different block+shadow)
---@field value string|CompressedPrimitive|table Input value (block ID, compressed primitive array, or literal)
---@field obscuredShadow string|nil Obscured shadow block ID

---@class Field
---@field value any Field value (string, number, boolean, etc.)
---@field id string|nil Field ID (for variables, lists, broadcasts)
---@field variableType? string Variable type ("SCALAR_TYPE", "LIST_TYPE", "BROADCAST_MESSAGE_TYPE")


---@alias InputShadowType
---| 1 # INPUT_SAME_BLOCK_SHADOW - Block and shadow are the same
---| 2 # INPUT_BLOCK_NO_SHADOW - Block with no shadow
---| 3 # INPUT_DIFF_BLOCK_SHADOW - Block and shadow are different

---@alias PrimitiveType
---| 4 # MATH_NUM_PRIMITIVE - math_number
---| 5 # POSITIVE_NUM_PRIMITIVE - math_positive_number
---| 6 # WHOLE_NUM_PRIMITIVE - math_whole_number
---| 7 # INTEGER_NUM_PRIMITIVE - math_integer
---| 8 # ANGLE_NUM_PRIMITIVE - math_angle
---| 9 # COLOR_PICKER_PRIMITIVE - colour_picker
---| 10 # TEXT_PRIMITIVE - text
---| 11 # BROADCAST_PRIMITIVE - event_broadcast_menu
---| 12 # VAR_PRIMITIVE - data_variable
---| 13 # LIST_PRIMITIVE - data_listcontents

---@class Costume
---@field assetId string Asset ID
---@field name string Costume name
---@field md5ext string MD5 hash with extension
---@field dataFormat string Data format
---@field rotationCenterX number Rotation center X
---@field rotationCenterY number Rotation center Y
---@field bitmapResolution number|nil Bitmap resolution
---@field image love.Image|nil Loaded bitmap image (bitmap costumes or rasterized SVG)
---@field imageData love.ImageData|nil Loaded image data (bitmap costumes or rasterized SVG)
---@field _fastPixelSampler FastPixelSampler|nil Cached fast pixel sampler for imageData

---@class Sound
---@field assetId string Asset ID
---@field name string Sound name
---@field md5ext string MD5 hash with extension
---@field dataFormat string Data format
---@field rate number|nil Sample rate
---@field sampleCount number|nil Sample count
---@field source love.Source Loaded audio source
---@field duration number Duration in seconds

---Create a new project model from parsed data
---@param projectData table Raw project data from JSON
---@param assets table<string, Asset> Asset storage
---@param projectPath string|nil Filesystem path for extracted project (Love appdata relative)
---@return ProjectModel
function ProjectModel:new(projectData, assets, projectPath)
    local self = setmetatable({}, ProjectModel)

    self.meta = projectData.meta or {}
    self.targets = {}
    self.monitors = projectData.monitors or {}
    self.extensions = projectData.extensions or {}
    self.extensionIDs = {}
    self.assets = assets or {}
    self.projectPath = projectPath

    -- Parse targets (sprites and stage)
    for i, targetData in ipairs(projectData.targets or {}) do
        local target = self:parseTarget(targetData, i)
        table.insert(self.targets, target)

        -- Store stage reference
        if target.isStage then
            self.stage = target
        end
    end

    -- Parse TurboWarp project options from stage comments (framerate, width, height, etc.)
    self.projectOptions = self:parseProjectOptions()
    if self.projectOptions then
        log.info("ProjectModel: Loaded TurboWarp project options: framerate=%s, width=%s, height=%s",
            tostring(self.projectOptions.framerate),
            tostring(self.projectOptions.width),
            tostring(self.projectOptions.height))
    end

    return self
end

---Parse a target (sprite or stage) from raw data
---@param data table Raw target data
---@param i number target index
---@return Target target Parsed target
function ProjectModel:parseTarget(data, i)
    local blocks, blockOrder = self:parseBlocks(data.blocks)

    local target = {
        isStage = data.isStage or false,
        name = data.name,
        variables = self:parseVariables(data.variables),
        lists = self:parseLists(data.lists),
        broadcasts = self:parseBroadcasts(data.broadcasts),
        blocks = blocks,
        blockOrder = blockOrder,
        comments = data.comments or {},
        currentCostume = data.currentCostume or 0,
        costumes = self:parseCostumes(data.costumes),
        sounds = self:parseSounds(data.sounds),
        layerOrder = data.layerOrder or i,
        volume = data.volume or 100
    }

    -- Sprite-specific properties
    if not target.isStage then
        target.visible = data.visible ~= false
        target.x = data.x or 0
        target.y = data.y or 0
        target.size = data.size or 100
        target.direction = data.direction or 90
        target.draggable = data.draggable or false
        target.rotationStyle = data.rotationStyle or "all around"
        target.soundEffects = data.soundEffects
    else
        -- Stage-specific properties
        target.tempo = data.tempo or 60
        target.videoTransparency = data.videoTransparency or 50
        target.videoState = data.videoState or "on"
        target.textToSpeechLanguage = data.textToSpeechLanguage
    end

    return target
end

---Parse variables from raw data
---@param variables table|nil Raw variables data
---@return table<string, Variable> parsed Parsed variables
function ProjectModel:parseVariables(variables)
    local parsed = {}
    if variables then
        for id, varData in pairs(variables) do
            parsed[id] = {
                name = varData[1],
                value = varData[2],
                cloud = varData[3] or false
            }
        end
    end
    return parsed
end

---Parse lists from raw data
---@param lists table|nil Raw lists data
---@return table<string, List> parsed Parsed lists
function ProjectModel:parseLists(lists)
    local parsed = {}
    if lists then
        for id, listData in pairs(lists) do
            parsed[id] = {
                name = listData[1],
                value = listData[2] or {}
            }
        end
    end
    return parsed
end

---Parse broadcast messages from raw data
---@param broadcasts table|nil Raw broadcasts data
---@return table<string, string> parsed Parsed broadcasts
function ProjectModel:parseBroadcasts(broadcasts)
    local parsed = {}
    if broadcasts then
        for id, name in pairs(broadcasts) do
            parsed[id] = name
        end
    end
    return parsed
end

-- SB3 Primitive Constants (from official sb3.js documentation)
local MATH_NUM_PRIMITIVE = 4     -- math_number
local POSITIVE_NUM_PRIMITIVE = 5 -- math_positive_number
local WHOLE_NUM_PRIMITIVE = 6    -- math_whole_number
local INTEGER_NUM_PRIMITIVE = 7  -- math_integer
local ANGLE_NUM_PRIMITIVE = 8    -- math_angle
local COLOR_PICKER_PRIMITIVE = 9 -- colour_picker
local TEXT_PRIMITIVE = 10        -- text
local BROADCAST_PRIMITIVE = 11   -- event_broadcast_menu
local VAR_PRIMITIVE = 12         -- data_variable
local LIST_PRIMITIVE = 13        -- data_listcontents

---Parse blocks from raw data
---@param blocks table|nil Raw blocks data
---@return table<string, Block|any> parsed Parsed blocks dictionary
---@return string[] order Ordered array of block IDs (preserves JSON order)
function ProjectModel:parseBlocks(blocks)
    local parsed = {}
    local order = {}

    if blocks then
        -- Extract original key order from JSON metadata (stored in metatable by json.lua)
        local keyOrder = json.getKeyOrder(blocks)

        if not keyOrder then
            error("ProjectModel:parseBlocks: Block order information is required for stable compilation. Ensure JSON parser preserves key order in metatable.")
        end

        -- Use preserved JSON order for stable compilation
        for _, id in ipairs(keyOrder) do
            local blockData = blocks[id]
            if type(blockData) == "table" then
                if blockData[1] and type(blockData[1]) == "number" then
                    -- Array format - compressed primitive block
                    parsed[id] = self:parseCompressedBlock(blockData)
                elseif blockData.opcode then
                    -- Regular block object
                    parsed[id] = self:parseBlock(blockData)
                else
                    log.warn("ProjectModel: Block '%s' has invalid format - missing opcode, skipping", id)
                    parsed[id] = nil -- Skip invalid block instead of crashing
                end
            else
                -- Primitive value
                parsed[id] = blockData
            end

            -- Only add to order if successfully parsed
            if parsed[id] ~= nil then
                table.insert(order, id)
            end
        end
    end

    return parsed, order
end

---Parse compressed block from array format
---@param data CompressedPrimitive Compressed block data in array format [type, value, ...extra]
---@return Block block Decompressed block data
function ProjectModel:parseCompressedBlock(data)
    local primitiveType = data[1]

    if primitiveType == MATH_NUM_PRIMITIVE then
        -- Basic math number: [type, value]
        return {
            opcode = "math_number",
            shadow = true,
            topLevel = false,
            fields = {
                NUM = { value = data[2] }
            },
            inputs = {},
            mutation = nil,
            next = nil,
            parent = nil,
            x = data[4], -- optional position
            y = data[5]  -- optional position
        }
    elseif primitiveType == POSITIVE_NUM_PRIMITIVE then
        -- Positive number: [type, value]
        return {
            opcode = "math_positive_number",
            shadow = true,
            topLevel = false,
            fields = {
                NUM = { value = data[2] }
            },
            inputs = {},
            mutation = nil,
            next = nil,
            parent = nil,
            x = data[4], -- optional position
            y = data[5]  -- optional position
        }
    elseif primitiveType == WHOLE_NUM_PRIMITIVE then
        -- Whole number: [type, value]
        return {
            opcode = "math_whole_number",
            shadow = true,
            topLevel = false,
            fields = {
                NUM = { value = data[2] }
            },
            inputs = {},
            mutation = nil,
            next = nil,
            parent = nil,
            x = data[4], -- optional position
            y = data[5]  -- optional position
        }
    elseif primitiveType == INTEGER_NUM_PRIMITIVE then
        -- Integer: [type, value]
        return {
            opcode = "math_integer",
            shadow = true,
            topLevel = false,
            fields = {
                NUM = { value = data[2] }
            },
            inputs = {},
            mutation = nil,
            next = nil,
            parent = nil,
            x = data[4], -- optional position
            y = data[5]  -- optional position
        }
    elseif primitiveType == ANGLE_NUM_PRIMITIVE then
        -- Angle: [type, value]
        return {
            opcode = "math_angle",
            shadow = true,
            topLevel = false,
            fields = {
                NUM = { value = data[2] }
            },
            inputs = {},
            mutation = nil,
            next = nil,
            parent = nil,
            x = data[4], -- optional position
            y = data[5]  -- optional position
        }
    elseif primitiveType == COLOR_PICKER_PRIMITIVE then
        -- Color blocks: [type, color_value]
        return {
            opcode = "colour_picker",
            shadow = true,
            topLevel = false,
            fields = {
                COLOUR = { value = data[2] }
            },
            inputs = {},
            mutation = nil,
            next = nil,
            parent = nil
        }
    elseif primitiveType == TEXT_PRIMITIVE then
        -- Text blocks: [type, "text value"]
        return {
            opcode = "text",
            shadow = true,
            topLevel = false,
            fields = {
                TEXT = { value = data[2] }
            },
            inputs = {},
            mutation = nil,
            next = nil,
            parent = nil
        }
    elseif primitiveType == BROADCAST_PRIMITIVE then
        -- Broadcast blocks: [type, "broadcast name", "broadcast_id"]
        return {
            opcode = "event_broadcast_menu",
            shadow = true,
            topLevel = false,
            fields = {
                BROADCAST_OPTION = {
                    value = data[2],
                    id = data[3],
                    variableType = "broadcast_msg" -- Native Scratch: Variable.BROADCAST_MESSAGE_TYPE
                }
            },
            inputs = {},
            mutation = nil,
            next = nil,
            parent = nil
        }
    elseif primitiveType == VAR_PRIMITIVE then
        -- Variable blocks: [type, "variable name", "variable_id", ?x, ?y, ?block_id]
        return {
            opcode = "data_variable",
            shadow = true,
            topLevel = false,
            fields = {
                VARIABLE = {
                    value = data[2],
                    id = data[3],
                    variableType = "" -- Native Scratch: Variable.SCALAR_TYPE (empty string)
                }
            },
            inputs = {},
            mutation = nil,
            next = nil,
            parent = nil,
            x = data[4], -- optional position
            y = data[5]  -- optional position
        }
    elseif primitiveType == LIST_PRIMITIVE then
        -- List blocks: [type, "list name", "list_id", ?x, ?y, ?block_id]
        return {
            opcode = "data_listcontents",
            shadow = true,
            topLevel = false,
            fields = {
                LIST = {
                    value = data[2],
                    id = data[3],
                    variableType = "list" -- Native Scratch: Variable.LIST_TYPE
                }
            },
            inputs = {},
            mutation = nil,
            next = nil,
            parent = nil,
            x = data[4], -- optional position
            y = data[5]  -- optional position
        }
    else
        log.warn("ProjectModel: Found unknown primitive type during deserialization: %s",
            tostring(primitiveType))
        return nil
    end
end

---Parse a single block from raw data
---@param data table Raw block data
---@return Block block Parsed block
function ProjectModel:parseBlock(data)
    ---@type Block
    local block = {
        opcode = data.opcode,
        next = data.next,
        parent = data.parent,
        inputs = self:parseInputs(data.inputs),
        fields = self:parseFields(data.fields),
        shadow = data.shadow or false,
        topLevel = data.topLevel or false
    }

    -- Detect and record extensions used in this block
    self:detectExtension(data.opcode)

    -- Position for top-level blocks
    if block.topLevel then
        block.x = data.x
        block.y = data.y
    end

    -- Mutation for custom blocks
    if data.mutation then
        block.mutation = data.mutation
    end

    return block
end

-- SB3 Input Constants (from official documentation)
local INPUT_SAME_BLOCK_SHADOW = 1 -- Block and shadow are the same
local INPUT_BLOCK_NO_SHADOW = 2   -- Block with no shadow
local INPUT_DIFF_BLOCK_SHADOW = 3 -- Block and shadow are different

---Parse block inputs from raw data
---@param inputs table<string, number[]|string>|nil Raw inputs data - each input is [shadowType, value, ?obscuredShadow]
---@return table<string, Input> parsed Parsed inputs with proper structure
function ProjectModel:parseInputs(inputs)
    local parsed = {}
    if inputs then
        for name, input in pairs(inputs) do
            if type(input) == "table" and table.maxn(input) >= 1 then
                local inputType = input[1]

                if inputType == INPUT_SAME_BLOCK_SHADOW then
                    -- [1, block_id] - block and shadow are the same
                    parsed[name] = {
                        shadowType = 1,
                        value = input[2],
                        obscuredShadow = nil
                    }
                elseif inputType == INPUT_BLOCK_NO_SHADOW then
                    -- [2, block_id] - block with no shadow
                    parsed[name] = {
                        shadowType = 2,
                        value = input[2],
                        obscuredShadow = nil
                    }
                elseif inputType == INPUT_DIFF_BLOCK_SHADOW then
                    -- [3, block_id, shadow_id] - block and shadow are different
                    parsed[name] = {
                        shadowType = 3,
                        value = input[2],
                        obscuredShadow = input[3]
                    }
                else
                    log.warn(
                    "ProjectModel: Invalid input shadow type %s for '%s' - expected 1, 2, or 3, skipping",
                        tostring(inputType), name)
                    -- Skip invalid input instead of crashing
                end
            else
                log.warn("ProjectModel: Invalid input format for '%s', skipping", name)
                -- Skip invalid input instead of crashing
            end
        end
    end
    return parsed
end

---Parse block fields from raw data
---@param fields table<string, any[]|any>|nil Raw fields data - each field is [value, ?id] or direct value
---@return table<string, Field> parsed Parsed fields with value, id, and variableType
function ProjectModel:parseFields(fields)
    local parsed = {}
    if fields then
        for name, field in pairs(fields) do
            if type(field) == "table" and #field >= 1 then
                -- Field format: [value, ?id] - ID is optional
                parsed[name] = {
                    value = field[1],
                    id = field[2] -- Will be nil if not provided
                }
            else
                -- Non-array field - Native Scratch doesn't check this, treat as direct value
                parsed[name] = {
                    value = field, -- Use field directly as value
                    id = nil
                }
            end

            if name == "BROADCAST_OPTION" then
                parsed[name].variableType = "broadcast_msg" -- Native Scratch: Variable.BROADCAST_MESSAGE_TYPE
            elseif name == "VARIABLE" then
                parsed[name].variableType = ""              -- Native Scratch: Variable.SCALAR_TYPE (empty string)
            elseif name == "LIST" then
                parsed[name].variableType = "list"          -- Native Scratch: Variable.LIST_TYPE
            end
        end
    end
    return parsed
end

---Parse costumes from raw data
---@param costumes table[]|nil Raw costumes data
---@return Costume[] parsed Parsed costumes
function ProjectModel:parseCostumes(costumes)
    local parsed = {}
    if costumes then
        for _, costume in ipairs(costumes) do
            table.insert(parsed, {
                assetId = costume.assetId,
                name = costume.name,
                md5ext = costume.md5ext,
                dataFormat = costume.dataFormat,
                rotationCenterX = costume.rotationCenterX or 0,
                rotationCenterY = costume.rotationCenterY or 0,
                bitmapResolution = costume.bitmapResolution
            })
        end
    end
    return parsed
end

---Parse sounds from raw data
---@param sounds Sound[]|nil Raw sounds data
---@return Sound[] parsed Parsed sounds
function ProjectModel:parseSounds(sounds)
    local parsed = {}
    if sounds then
        for _, sound in ipairs(sounds) do
            table.insert(parsed, {
                assetId = sound.assetId,
                name = sound.name,
                md5ext = sound.md5ext,
                dataFormat = sound.dataFormat,
                rate = sound.rate,
                sampleCount = sound.sampleCount,
                duration = sound.source and sound.source:getDuration() or nil,
                source = sound.source
            })
        end
    end
    return parsed
end

---Get the stage target
---@return Target|nil stage The stage target or nil
function ProjectModel:getStage()
    return self.stage
end

---Get all sprite targets (excluding stage)
---@return Target[] sprites List of sprite targets
function ProjectModel:getSprites()
    local sprites = {}
    for _, target in ipairs(self.targets) do
        if not target.isStage then
            table.insert(sprites, target)
        end
    end
    return sprites
end

---Get an asset by MD5 hash
---@param md5 string Asset MD5 hash
---@return Asset|nil asset The asset or nil if not found
function ProjectModel:getAsset(md5)
    return self.assets[md5]
end

---Detect extension from block opcode and record it
---@param opcode string Block opcode to analyze
function ProjectModel:detectExtension(opcode)
    local extensionId = self:getExtensionIdForOpcode(opcode)
    if extensionId then
        self.extensionIDs[extensionId] = true
    end
end

---Get extension ID for a given opcode
---@param opcode string Block opcode
---@return string|nil extensionId Extension ID or nil if not an extension block
function ProjectModel:getExtensionIdForOpcode(opcode)
    -- Extension opcodes typically have format: extensionId_blockName
    -- Common Scratch extensions
    local extensionPrefixes = {
        "pen_",          -- Pen extension
        "music_",        -- Music extension
        "videoSensing_", -- Video Sensing extension
        "text2speech_",  -- Text to Speech extension
        "translate_",    -- Translate extension
        "makeymakey_",   -- MakeyMakey extension
        "microbit_",     -- micro:bit extension
        "wedo2_",        -- LEGO WeDo 2.0 extension
        "ev3_",          -- LEGO MINDSTORMS EV3 extension
        "boost_",        -- LEGO BOOST extension
        "gdxfor_",       -- Vernier Go Direct extension
    }

    for _, prefix in ipairs(extensionPrefixes) do
        if opcode:sub(1, #prefix) == prefix then
            return prefix:sub(1, -2) -- Remove trailing underscore
        end
    end

    -- Check for generic extension pattern (extensionId_something)
    local extensionId = opcode:match("^([^_]+)_")
    if extensionId and not self:isCoreOpcode(extensionId) then
        return extensionId
    end

    return nil
end

---Check if opcode prefix belongs to core Scratch blocks
---@param prefix string Opcode prefix to check
---@return boolean isCore True if this is a core Scratch opcode prefix
function ProjectModel:isCoreOpcode(prefix)
    local corePrefixes = {
        "motion", "looks", "sound", "event", "control", "sensing",
        "operator", "data", "procedures", "argument", "math", "colour", "text"
    }

    for _, corePrefix in ipairs(corePrefixes) do
        if prefix == corePrefix then
            return true
        end
    end

    return false
end

---Get all detected extension IDs
---@return table<string, boolean> extensions Set of extension IDs
function ProjectModel:getDetectedExtensions()
    return self.extensionIDs
end

---Parse TurboWarp project options from stage comments
---Searches for a comment containing the magic string " // _twconfig_" and extracts JSON configuration
---@return TurboWarpProjectOptions|nil options Parsed TurboWarp project options or nil if not found
function ProjectModel:parseProjectOptions()
    if not self.stage then
        return nil
    end

    -- Search for TurboWarp config comment in stage comments
    local comments = self.stage.comments
    if not comments then
        return nil
    end

    local configComment = nil
    for _, comment in pairs(comments) do
        if type(comment) == "table" and comment.text and type(comment.text) == "string" then
            if comment.text:find(COMMENT_CONFIG_MAGIC, 1, true) then -- plain text search
                configComment = comment
                break
            end
        end
    end

    if not configComment then
        return nil
    end

    -- Extract JSON from the line ending with the magic string
    -- Format: "Configuration for https://turbowarp.org/\n...\n{...json...} // _twconfig_"
    local lines = {}
    for line in configComment.text:gmatch("[^\r\n]+") do
        table.insert(lines, line)
    end

    local jsonLine = nil
    for _, line in ipairs(lines) do
        if line:find(COMMENT_CONFIG_MAGIC, 1, true) then -- plain text search
            jsonLine = line
            break
        end
    end

    if not jsonLine then
        log.warn("ProjectModel: TurboWarp config comment found but missing magic line")
        return nil
    end

    -- Remove the magic suffix to get pure JSON
    local magicPos = jsonLine:find(COMMENT_CONFIG_MAGIC, 1, true)
    local jsonText = jsonLine:sub(1, magicPos - 1)

    -- Parse JSON
    local success, parsed = pcall(json.decode, jsonText)
    if not success then
        log.warn("ProjectModel: Failed to parse TurboWarp config JSON: %s", tostring(parsed))
        return nil
    end

    if type(parsed) ~= "table" then
        log.warn("ProjectModel: TurboWarp config is not a valid object")
        return nil
    end

    -- Validate and return parsed options
    -- Expected fields: framerate, width, height, turbo, interpolation, hq, runtimeOptions
    return parsed
end

return ProjectModel
