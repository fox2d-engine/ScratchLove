-- @fileoverview Events block compilation for Scratch to Lua compiler

local enums = require("compiler.enums")
local intermediate = require("compiler.intermediate")

local InputType = enums.InputType
local StackOpcode = enums.StackOpcode
local InputOpcode = enums.InputOpcode
local IntermediateStackBlock = intermediate.IntermediateStackBlock
local IntermediateInput = intermediate.IntermediateInput

---@class EventsBlockCompiler
local EventsBlockCompiler = {}

---Compile events blocks during IR generation
---@param generator ScriptTreeGenerator Generator instance
---@param block table Scratch block
---@return IntermediateStackBlock|IntermediateInput|nil result Compiled result
function EventsBlockCompiler.compile(generator, block)
    local opcode = block.opcode

    -- Hat blocks (event triggers) - These are thread entry points and should be ignored during compilation
    -- They don't generate executable code since they're handled by the runtime's event system
    if opcode == "event_whenflagclicked" or
        opcode == "event_whenkeypressed" or
        opcode == "event_whenthisspriteclicked" or
        opcode == "event_whenstageclicked" or
        opcode == "event_whenbackdropswitchesto" or -- SB2 opcode, also used in SB3
        opcode == "event_whengreaterthan" or
        opcode == "event_whenbroadcastreceived" then
        -- HAT blocks are entry points, return NOP to skip them in compiled code
        return IntermediateStackBlock:new(StackOpcode.NOP)

        -- Stack blocks (event actions)
    elseif opcode == "event_broadcast" then
        -- Handle broadcast block - always return valid result to prevent warning
        local broadcastInput = generator:descendInputOfBlock(block, "BROADCAST_INPUT")
        if not broadcastInput then
            -- Try alternative field names
            broadcastInput = generator:descendInputOfBlock(block, "MESSAGE")
        end
        if not broadcastInput then
            -- Create a fallback constant
            broadcastInput = generator:createConstantInput("message1")
        end
        return IntermediateStackBlock:new(StackOpcode.EVENT_BROADCAST, {
            broadcast = broadcastInput
        })
    elseif opcode == "event_broadcastandwait" then
        local broadcastInput = generator:descendInputOfBlock(block, "BROADCAST_INPUT")
        return IntermediateStackBlock:new(StackOpcode.EVENT_BROADCAST_AND_WAIT, {
            broadcast = broadcastInput
        }, true) -- Yields waiting for broadcast completion
    end

    return nil
end

---Generate Lua code for events stack blocks
---@param generator LuaGenerator Generator instance
---@param opcode string Stack opcode
---@param inputs table Block inputs
---@param block table|nil Original block for blockId access
---@return boolean handled True if opcode was handled
function EventsBlockCompiler.generateStackBlock(generator, opcode, inputs, block)
    local StackOpcode = enums.StackOpcode

    if opcode == StackOpcode.NOP then
        -- No operation - just skip, don't generate any code
        return true
    elseif opcode == StackOpcode.EVENT_BROADCAST then
        -- Broadcast
        local broadcast = inputs.broadcast
        if broadcast then
            local messageCode = generator:generateInput(broadcast)
            generator:writeLine(string.format("runtime:broadcast(%s)", messageCode))
        end
        return true
    elseif opcode == StackOpcode.EVENT_BROADCAST_AND_WAIT then
        -- Broadcast and wait - use helper for cleaner code
        local broadcast = inputs.broadcast
        if broadcast then
            local messageCode = generator:generateInput(broadcast)
            generator:writeLine(string.format("BlockHelpers.Events.broadcastAndWait(target, %s, runtime, thread)",
                messageCode))
        end
        return true
    end

    return false
end

return EventsBlockCompiler
