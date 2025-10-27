-- @fileoverview Text-to-Speech extension block compilation
-- NOTE: This extension is not fully implemented - blocks are treated as NOP
-- Text-to-speech functionality is not available in Love2D runtime

local enums = require("compiler.enums")
local intermediate = require("compiler.intermediate")
local log = require("lib.log")

local StackOpcode = enums.StackOpcode
local IntermediateStackBlock = intermediate.IntermediateStackBlock

---@class Text2SpeechBlockCompiler
local Text2SpeechBlockCompiler = {}

---Compile text2speech blocks during IR generation
---@param generator ScriptTreeGenerator Generator instance
---@param block table Scratch block
---@return IntermediateStackBlock|IntermediateInput|nil result Compiled result
function Text2SpeechBlockCompiler.compile(generator, block)
    local opcode = block.opcode

    -- Text-to-speech extension is not supported - throw error to make problem visible
    if opcode == "text2speech_speakAndWait" or
       opcode == "text2speech_setVoice" or
       opcode == "text2speech_setLanguage" then
        error("Text-to-speech extension block not supported: " .. opcode ..
              "\nThis project uses the Text-to-Speech extension which is not available in Love2D runtime.")
    end

    -- If we get here, it's an unknown text2speech block
    return nil
end

---Generate Lua code for text2speech stack blocks
---@param generator LuaGenerator Generator instance
---@param opcode string Stack opcode
---@param inputs table Block inputs
---@param block table|nil Original block for blockId access
---@return boolean handled True if opcode was handled
function Text2SpeechBlockCompiler.generateStackBlock(generator, opcode, inputs, block)
    -- Text2speech blocks compile to NOP, so nothing to generate
    -- This function is a no-op placeholder
    return false
end

return Text2SpeechBlockCompiler
