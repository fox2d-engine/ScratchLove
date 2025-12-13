-- Text-to-Speech extension block compilation
-- Implements TTS functionality using Scratch synthesis service

local enums = require("compiler.enums")
local intermediate = require("compiler.intermediate")

local InputType = enums.InputType
local StackOpcode = enums.StackOpcode
local IntermediateStackBlock = intermediate.IntermediateStackBlock

---@class Text2SpeechBlockCompiler
local Text2SpeechBlockCompiler = {}

---Compile text2speech blocks during IR generation
---@param generator ScriptTreeGenerator Generator instance
---@param block table Scratch block
---@return IntermediateStackBlock|nil result Compiled IR block
function Text2SpeechBlockCompiler.compile(generator, block)
    local opcode = block.opcode

    if opcode == "text2speech_speakAndWait" then
        return IntermediateStackBlock:new(StackOpcode.TEXT2SPEECH_SPEAK, {
            words = generator:descendInputOfBlock(block, "WORDS"):toType(InputType.STRING)
        }, true)

    elseif opcode == "text2speech_setVoice" then
        return IntermediateStackBlock:new(StackOpcode.TEXT2SPEECH_SET_VOICE, {
            voice = generator:descendInputOfBlock(block, "VOICE"):toType(InputType.STRING)
        })

    elseif opcode == "text2speech_setLanguage" then
        return IntermediateStackBlock:new(StackOpcode.TEXT2SPEECH_SET_LANGUAGE, {
            language = generator:descendInputOfBlock(block, "LANGUAGE"):toType(InputType.STRING)
        })
    end

    return nil
end

---Generate Lua code for text2speech stack blocks
---@param generator LuaGenerator Generator instance
---@param opcode string Stack opcode
---@param inputs table Block inputs
---@return boolean handled True if opcode was handled
function Text2SpeechBlockCompiler.generateStackBlock(generator, opcode, inputs)
    if opcode == StackOpcode.TEXT2SPEECH_SPEAK then
        -- Simply call the helper function - it contains the state machine loop internally
        local wordsCode = generator:generateInput(inputs.words)
        generator:writeLine(string.format("BlockHelpers.Text2Speech.speak(target, %s, runtime, thread)", wordsCode))
        return true

    elseif opcode == StackOpcode.TEXT2SPEECH_SET_VOICE then
        generator:writeLine(string.format("BlockHelpers.Text2Speech.setVoice(target, %s, runtime, thread)",
            generator:generateInput(inputs.voice)))
        return true

    elseif opcode == StackOpcode.TEXT2SPEECH_SET_LANGUAGE then
        generator:writeLine(string.format("BlockHelpers.Text2Speech.setLanguage(target, %s, runtime, thread)",
            generator:generateInput(inputs.language)))
        return true
    end

    return false
end

return Text2SpeechBlockCompiler
