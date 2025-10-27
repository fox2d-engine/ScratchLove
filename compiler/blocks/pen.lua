-- @fileoverview Pen block compilation for Scratch to Lua compiler

local enums = require("compiler.enums")
local intermediate = require("compiler.intermediate")
local log = require("lib.log")

local InputType = enums.InputType
local StackOpcode = enums.StackOpcode
local InputOpcode = enums.InputOpcode
local IntermediateStackBlock = intermediate.IntermediateStackBlock
local IntermediateInput = intermediate.IntermediateInput

---@class PenBlockCompiler
local PenBlockCompiler = {}

---Compile pen blocks during IR generation
---@param generator ScriptTreeGenerator Generator instance
---@param block table Scratch block
---@return IntermediateStackBlock|IntermediateInput|nil result Compiled result
function PenBlockCompiler.compile(generator, block)
    local opcode = block.opcode

    -- Menu blocks - return nil to let irgen.lua handle them with generic menu logic
    -- This is necessary because menu blocks have "pen_" prefix and get routed here
    if opcode == "pen_menu_colorParam" then
        return nil
    end

    -- Stack blocks (statements)
    if opcode == "pen_clear" then
        return IntermediateStackBlock:new(StackOpcode.PEN_CLEAR, {})

    elseif opcode == "pen_penDown" then
        return IntermediateStackBlock:new(StackOpcode.PEN_DOWN, {})

    elseif opcode == "pen_penUp" then
        return IntermediateStackBlock:new(StackOpcode.PEN_UP, {})

    elseif opcode == "pen_setPenColorToColor" then
        local color = generator:descendInputOfBlock(block, "COLOR"):toType(InputType.COLOR)
        return IntermediateStackBlock:new(StackOpcode.PEN_COLOR_SET, {
            color = color
        })

    elseif opcode == "pen_changePenColorParamBy" then
        local colorParam = generator:descendInputOfBlock(block, "COLOR_PARAM"):toType(InputType.STRING)
        local value = generator:descendInputOfBlock(block, "VALUE"):toType(InputType.NUMBER)
        return IntermediateStackBlock:new(StackOpcode.PEN_COLOR_CHANGE_PARAM, {
            colorParam = colorParam,
            value = value
        })

    elseif opcode == "pen_setPenColorParamTo" then
        local colorParam = generator:descendInputOfBlock(block, "COLOR_PARAM"):toType(InputType.STRING)
        local value = generator:descendInputOfBlock(block, "VALUE"):toType(InputType.NUMBER)
        return IntermediateStackBlock:new(StackOpcode.PEN_COLOR_SET_PARAM, {
            colorParam = colorParam,
            value = value
        })

    elseif opcode == "pen_changePenSizeBy" then
        local size = generator:descendInputOfBlock(block, "SIZE"):toType(InputType.NUMBER)
        return IntermediateStackBlock:new(StackOpcode.PEN_SIZE_CHANGE, {
            size = size
        })

    elseif opcode == "pen_setPenSizeTo" then
        local size = generator:descendInputOfBlock(block, "SIZE"):toType(InputType.NUMBER)
        return IntermediateStackBlock:new(StackOpcode.PEN_SIZE_SET, {
            size = size
        })

    elseif opcode == "pen_stamp" then
        return IntermediateStackBlock:new(StackOpcode.PEN_STAMP, {})

    elseif opcode == "pen_setPenShadeToNumber" then
        local shade = generator:descendInputOfBlock(block, "SHADE"):toType(InputType.NUMBER)
        return IntermediateStackBlock:new(StackOpcode.PEN_SHADE_SET, {
            shade = shade
        })

    elseif opcode == "pen_changePenShadeBy" then
        local shade = generator:descendInputOfBlock(block, "SHADE"):toType(InputType.NUMBER)
        return IntermediateStackBlock:new(StackOpcode.PEN_SHADE_CHANGE, {
            shade = shade
        })

    elseif opcode == "pen_setPenHueToNumber" then
        local hue = generator:descendInputOfBlock(block, "HUE"):toType(InputType.NUMBER)
        return IntermediateStackBlock:new(StackOpcode.PEN_HUE_SET, {
            hue = hue
        })

    elseif opcode == "pen_changePenHueBy" then
        local hue = generator:descendInputOfBlock(block, "HUE"):toType(InputType.NUMBER)
        return IntermediateStackBlock:new(StackOpcode.PEN_HUE_CHANGE, {
            hue = hue
        })

    else
        -- Unknown pen block - this is an error!
        error("Unhandled pen block: " .. tostring(opcode) .. " - block not implemented in compiler")
    end
end

---Generate Lua code for pen stack blocks (delegating to original implementation)
---@param generator LuaGenerator Generator instance
---@param opcode string Stack opcode
---@param inputs table Block inputs
---@param block table|nil Original block for blockId access
---@return boolean handled True if opcode was handled
function PenBlockCompiler.generateStackBlock(generator, opcode, inputs, block)
    local StackOpcode = enums.StackOpcode

    if opcode == StackOpcode.PEN_CLEAR then
        generator:writeLine("BlockHelpers.Pen.clear(target, {}, runtime, thread)")
        return true

    elseif opcode == StackOpcode.PEN_DOWN then
        generator:writeLine("BlockHelpers.Pen.penDown(target, {}, runtime, thread)")
        return true

    elseif opcode == StackOpcode.PEN_UP then
        generator:writeLine("BlockHelpers.Pen.penUp(target, {}, runtime, thread)")
        return true

    elseif opcode == StackOpcode.PEN_COLOR_SET then
        local color = inputs.color
        if color then
            local colorCode = generator:generateInput(color)
            generator:writeLine("BlockHelpers.Pen.setPenColorToColor(target, { COLOR = " .. colorCode .. " }, runtime, thread)")
        end
        return true

    elseif opcode == StackOpcode.PEN_COLOR_CHANGE_PARAM then
        local colorParam = inputs.colorParam
        local value = inputs.value
        if colorParam and value then
            local colorParamCode = generator:generateInput(colorParam)
            local valueCode = generator:generateInput(value)
            generator:writeLine("BlockHelpers.Pen.changePenColorParamBy(target, { COLOR_PARAM = " .. colorParamCode .. ", VALUE = " .. valueCode .. " }, runtime, thread)")
        end
        return true

    elseif opcode == StackOpcode.PEN_COLOR_SET_PARAM then
        local colorParam = inputs.colorParam
        local value = inputs.value
        if colorParam and value then
            local colorParamCode = generator:generateInput(colorParam)
            local valueCode = generator:generateInput(value)
            generator:writeLine("BlockHelpers.Pen.setPenColorParamTo(target, { COLOR_PARAM = " .. colorParamCode .. ", VALUE = " .. valueCode .. " }, runtime, thread)")
        end
        return true

    elseif opcode == StackOpcode.PEN_SIZE_CHANGE then
        local size = inputs.size
        if size then
            local sizeCode = generator:generateInput(size)
            generator:writeLine("BlockHelpers.Pen.changePenSizeBy(target, { SIZE = " .. sizeCode .. " }, runtime, thread)")
        end
        return true

    elseif opcode == StackOpcode.PEN_SIZE_SET then
        local size = inputs.size
        if size then
            local sizeCode = generator:generateInput(size)
            generator:writeLine("BlockHelpers.Pen.setPenSizeTo(target, { SIZE = " .. sizeCode .. " }, runtime, thread)")
        end
        return true

    elseif opcode == StackOpcode.PEN_STAMP then
        generator:writeLine("BlockHelpers.Pen.stamp(target, {}, runtime, thread)")
        return true

    elseif opcode == StackOpcode.PEN_TRANSPARENCY_SET then
        local transparency = inputs.transparency
        if transparency then
            local transparencyCode = generator:generateInput(transparency)
            generator:writeLine("BlockHelpers.Pen.setPenTransparencyTo(target, { TRANSPARENCY = " .. transparencyCode .. " }, runtime, thread)")
        end
        return true

    elseif opcode == StackOpcode.PEN_TRANSPARENCY_CHANGE then
        local transparency = inputs.transparency
        if transparency then
            local transparencyCode = generator:generateInput(transparency)
            generator:writeLine("BlockHelpers.Pen.changePenTransparencyBy(target, { TRANSPARENCY = " .. transparencyCode .. " }, runtime, thread)")
        end
        return true

    elseif opcode == StackOpcode.PEN_SHADE_SET then
        local shade = inputs.shade
        if shade then
            local shadeCode = generator:generateInput(shade)
            generator:writeLine("BlockHelpers.Pen.setPenShadeToNumber(target, { SHADE = " .. shadeCode .. " }, runtime, thread)")
        end
        return true

    elseif opcode == StackOpcode.PEN_SHADE_CHANGE then
        local shade = inputs.shade
        if shade then
            local shadeCode = generator:generateInput(shade)
            generator:writeLine("BlockHelpers.Pen.changePenShadeBy(target, { SHADE = " .. shadeCode .. " }, runtime, thread)")
        end
        return true

    elseif opcode == StackOpcode.PEN_HUE_SET then
        local hue = inputs.hue
        if hue then
            local hueCode = generator:generateInput(hue)
            generator:writeLine("BlockHelpers.Pen.setPenHueToNumber(target, { HUE = " .. hueCode .. " }, runtime, thread)")
        end
        return true

    elseif opcode == StackOpcode.PEN_HUE_CHANGE then
        local hue = inputs.hue
        if hue then
            local hueCode = generator:generateInput(hue)
            generator:writeLine("BlockHelpers.Pen.changePenHueBy(target, { HUE = " .. hueCode .. " }, runtime, thread)")
        end
        return true
    end

    return false
end

return PenBlockCompiler