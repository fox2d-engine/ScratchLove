-- @fileoverview Block compilers registry for Scratch to Lua compiler

-- Import all block category compilers
local MotionBlockCompiler = require("compiler.blocks.motion")
local LooksBlockCompiler = require("compiler.blocks.looks")
local SoundBlockCompiler = require("compiler.blocks.sound")
local EventsBlockCompiler = require("compiler.blocks.events")
local ControlBlockCompiler = require("compiler.blocks.control")
local SensingBlockCompiler = require("compiler.blocks.sensing")
local OperatorsBlockCompiler = require("compiler.blocks.operators")
local DataBlockCompiler = require("compiler.blocks.data")
local ProceduresBlockCompiler = require("compiler.blocks.procedures")
local PenBlockCompiler = require("compiler.blocks.pen")
local Text2SpeechBlockCompiler = require("compiler.blocks.text2speech")

---@class BlockCompilers
local BlockCompilers = {}

---Mapping from block category to compiler
local categoryCompilers = {
    motion = MotionBlockCompiler,
    looks = LooksBlockCompiler,
    sound = SoundBlockCompiler,
    events = EventsBlockCompiler,
    control = ControlBlockCompiler,
    sensing = SensingBlockCompiler,
    operator = OperatorsBlockCompiler,  -- Note: 'operator' not 'operators'
    operators = OperatorsBlockCompiler, -- Keep both for compatibility
    data = DataBlockCompiler,
    procedures = ProceduresBlockCompiler,
    pen = PenBlockCompiler,
    text2speech = Text2SpeechBlockCompiler, -- Text-to-speech extension (throws error)
}

---Get category from block opcode
---@param opcode string Block opcode
---@return string|nil category Block category
local function getCategoryFromOpcode(opcode)
    local parts = {}
    for part in string.gmatch(opcode, "[^_]+") do
        table.insert(parts, part)
    end

    if #parts > 0 then
        return parts[1]
    end

    return nil
end

---Compile a block using appropriate category compiler
---@param generator ScriptTreeGenerator Generator instance
---@param block table Scratch block
---@param blockId string|nil Original Scratch block ID
---@return IntermediateStackBlock|IntermediateInput|nil result Compiled result
function BlockCompilers.compile(generator, block, blockId)
    if not block or not block.opcode then
        return nil
    end

    local category = getCategoryFromOpcode(block.opcode)
    if not category then
        return nil
    end

    local compiler = categoryCompilers[category]
    if not compiler then
        return nil
    end

    -- Call compiler with blockId (Lua automatically ignores extra parameters)
    local result = compiler.compile(generator, block, blockId)

    -- Attach blockId if not already set by the compiler
    -- Only attach to IntermediateStackBlock (which has yields field)
    if result and result.yields ~= nil and result.blockId == nil and blockId then
        result.blockId = blockId
    end

    return result
end

---Get all supported block categories
---@return string[] categories List of supported categories
function BlockCompilers.getSupportedCategories()
    local categories = {}
    for category, _ in pairs(categoryCompilers) do
        table.insert(categories, category)
    end
    table.sort(categories)
    return categories
end

---Check if a block opcode is supported
---@param opcode string Block opcode
---@return boolean supported True if supported
function BlockCompilers.isSupported(opcode)
    local category = getCategoryFromOpcode(opcode)
    return category ~= nil and categoryCompilers[category] ~= nil
end

return BlockCompilers