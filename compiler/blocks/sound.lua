-- @fileoverview Sound block compilation for Scratch to Lua compiler

local enums = require("compiler.enums")
local intermediate = require("compiler.intermediate")

local InputType = enums.InputType
local StackOpcode = enums.StackOpcode
local InputOpcode = enums.InputOpcode
local IntermediateStackBlock = intermediate.IntermediateStackBlock
local IntermediateInput = intermediate.IntermediateInput

---@class SoundBlockCompiler
local SoundBlockCompiler = {}

---Compile sound blocks during IR generation
---@param generator ScriptTreeGenerator Generator instance
---@param block table Scratch block
---@return IntermediateStackBlock|IntermediateInput|nil result Compiled result
function SoundBlockCompiler.compile(generator, block)
    local opcode = block.opcode

    -- Stack blocks (statements)
    if opcode == "sound_play" then
        local soundMenu = generator:descendInputOfBlock(block, "SOUND_MENU")
        return IntermediateStackBlock:new(StackOpcode.SOUND_PLAY, {
            sound = soundMenu
        })

    elseif opcode == "sound_playuntildone" then
        local soundMenu = generator:descendInputOfBlock(block, "SOUND_MENU")
        return IntermediateStackBlock:new(StackOpcode.SOUND_PLAY_UNTIL_DONE, {
            sound = soundMenu
        }, true) -- Yields until sound completes

    elseif opcode == "sound_stopallsounds" then
        return IntermediateStackBlock:new(StackOpcode.SOUND_STOP_ALL)

    elseif opcode == "sound_changevolumeby" then
        local volume = generator:descendInputOfBlock(block, "VOLUME"):toType(InputType.NUMBER)
        return IntermediateStackBlock:new(StackOpcode.SOUND_VOLUME_CHANGE, {
            volume = volume
        })

    elseif opcode == "sound_setvolumeto" then
        local volume = generator:descendInputOfBlock(block, "VOLUME"):toType(InputType.NUMBER)
        return IntermediateStackBlock:new(StackOpcode.SOUND_VOLUME_SET, {
            volume = volume
        })

    elseif opcode == "sound_changeeffectby" then
        local effect = generator:descendInputOfBlock(block, "EFFECT")
        local value = generator:descendInputOfBlock(block, "VALUE"):toType(InputType.NUMBER)
        return IntermediateStackBlock:new(StackOpcode.SOUND_EFFECT_CHANGE, {
            effect = effect,
            value = value
        })

    elseif opcode == "sound_seteffectto" then
        local effect = generator:descendInputOfBlock(block, "EFFECT")
        local value = generator:descendInputOfBlock(block, "VALUE"):toType(InputType.NUMBER)
        return IntermediateStackBlock:new(StackOpcode.SOUND_EFFECT_SET, {
            effect = effect,
            value = value
        })

    elseif opcode == "sound_cleareffects" then
        return IntermediateStackBlock:new(StackOpcode.SOUND_EFFECT_CLEAR)

    -- Reporter blocks (expressions)
    elseif opcode == "sound_volume" then
        return IntermediateInput:new(InputOpcode.SOUND_VOLUME, InputType.NUMBER)

    end

    return nil
end

---Generate Lua code for sound stack blocks (delegating to original implementation)
---@param generator LuaGenerator Generator instance
---@param opcode string Stack opcode
---@param inputs table Block inputs
---@param block table|nil Original block for blockId access
---@return boolean handled True if opcode was handled
function SoundBlockCompiler.generateStackBlock(generator, opcode, inputs, block)
    local StackOpcode = enums.StackOpcode

    if opcode == StackOpcode.SOUND_PLAY then
        local sound = inputs.sound
        if sound then
            local soundCode = generator:generateInput(sound)
            generator:writeLine("BlockHelpers.Sound.play(target, " .. soundCode .. ", runtime, thread)")
        end
        return true

    elseif opcode == StackOpcode.SOUND_PLAY_UNTIL_DONE then
        -- Play sound until done - use helper for cleaner code
        local sound = inputs.sound
        if sound then
            local soundCode = generator:generateInput(sound)
            generator:writeLine(string.format("BlockHelpers.Sound.playUntilDone(target, %s, runtime, thread)", soundCode))
        end
        return true

    elseif opcode == StackOpcode.SOUND_STOP_ALL then
        generator:writeLine("BlockHelpers.Sound.stopAllSounds(target, runtime, thread)")
        return true

    elseif opcode == StackOpcode.SOUND_VOLUME_CHANGE then
        local volume = inputs.volume
        if volume then
            local volumeCode = generator:generateInput(volume)
            generator:writeLine("BlockHelpers.Sound.changeVolumeBy(target, " .. volumeCode .. ", runtime, thread)")
        end
        return true

    elseif opcode == StackOpcode.SOUND_VOLUME_SET then
        local volume = inputs.volume
        if volume then
            local volumeCode = generator:generateInput(volume)
            generator:writeLine("BlockHelpers.Sound.setVolumeTo(target, " .. volumeCode .. ", runtime, thread)")
        end
        return true

    elseif opcode == StackOpcode.SOUND_EFFECT_CHANGE then
        local effect = inputs.effect
        local value = inputs.value
        if effect and value then
            local effectCode = generator:generateInput(effect)
            local valueCode = generator:generateInput(value)
            generator:writeLine("BlockHelpers.Sound.changeEffectBy(target, " .. effectCode .. ", " .. valueCode .. ", runtime, thread)")
        end
        return true

    elseif opcode == StackOpcode.SOUND_EFFECT_SET then
        local effect = inputs.effect
        local value = inputs.value
        if effect and value then
            local effectCode = generator:generateInput(effect)
            local valueCode = generator:generateInput(value)
            generator:writeLine("BlockHelpers.Sound.setEffectTo(target, " .. effectCode .. ", " .. valueCode .. ", runtime, thread)")
        end
        return true

    elseif opcode == StackOpcode.SOUND_EFFECT_CLEAR then
        generator:writeLine("BlockHelpers.Sound.clearEffects(target, runtime, thread)")
        return true
    end

    return false
end

---Generate Lua code for sound input blocks
---@param generator LuaGenerator Generator instance
---@param opcode string Input opcode
---@param inputs table Block inputs
---@return string|nil code Generated Lua expression or nil if not handled
function SoundBlockCompiler.generateInput(generator, opcode, inputs)
    local InputOpcode = enums.InputOpcode
    if opcode == InputOpcode.SOUND_VOLUME then
        return "BlockHelpers.Sound.getVolume(target, runtime, thread)"
    end
    return nil
end

return SoundBlockCompiler