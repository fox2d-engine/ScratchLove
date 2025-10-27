-- @fileoverview Sensing block compilation for Scratch to Lua compiler

local enums = require("compiler.enums")
local intermediate = require("compiler.intermediate")

local InputType = enums.InputType
local StackOpcode = enums.StackOpcode
local InputOpcode = enums.InputOpcode
local IntermediateStackBlock = intermediate.IntermediateStackBlock
local IntermediateInput = intermediate.IntermediateInput

---@class SensingBlockCompiler
local SensingBlockCompiler = {}

---Compile sensing blocks during IR generation
---@param generator ScriptTreeGenerator Generator instance
---@param block table Scratch block
---@return IntermediateStackBlock|IntermediateInput|nil result Compiled result
function SensingBlockCompiler.compile(generator, block)
    local opcode = block.opcode

    -- All sensing blocks are reporter blocks (expressions)
    if opcode == "sensing_touchingobject" then
        local touchingObjectMenu = generator:descendInputOfBlock(block, "TOUCHINGOBJECTMENU")
        return IntermediateInput:new(InputOpcode.SENSING_TOUCHING_OBJECT, InputType.BOOLEAN, {
            object = touchingObjectMenu
        })

    elseif opcode == "sensing_touchingobjectmenu" then
        -- Touching object menu reporter
        return generator:descendFieldOfBlock(block, "TOUCHINGOBJECTMENU")

    elseif opcode == "sensing_touchingcolor" then
        local color = generator:descendInputOfBlock(block, "COLOR"):toType(InputType.COLOR)
        return IntermediateInput:new(InputOpcode.SENSING_TOUCHING_COLOR, InputType.BOOLEAN, {
            color = color
        })

    elseif opcode == "sensing_coloristouchingcolor" then
        local color = generator:descendInputOfBlock(block, "COLOR"):toType(InputType.COLOR)
        local color2 = generator:descendInputOfBlock(block, "COLOR2"):toType(InputType.COLOR)
        return IntermediateInput:new(InputOpcode.SENSING_COLOR_TOUCHING_COLOR, InputType.BOOLEAN, {
            color1 = color,
            color2 = color2
        })

    elseif opcode == "sensing_distanceto" then
        local distanceToMenu = generator:descendInputOfBlock(block, "DISTANCETOMENU")
        return IntermediateInput:new(InputOpcode.SENSING_DISTANCE_TO, InputType.NUMBER, {
            target = distanceToMenu
        })

    elseif opcode == "sensing_distancetomenu" then
        -- Distance to menu reporter
        return generator:descendFieldOfBlock(block, "DISTANCETOMENU")

    elseif opcode == "sensing_askandwait" then
        local question = generator:descendInputOfBlock(block, "QUESTION"):toType(InputType.STRING)
        return IntermediateStackBlock:new(StackOpcode.SENSING_ASK_AND_WAIT, {
            question = question
        }, true) -- Yields waiting for user input

    elseif opcode == "sensing_answer" then
        return IntermediateInput:new(InputOpcode.SENSING_ANSWER, InputType.STRING)

    elseif opcode == "sensing_keypressed" then
        local keyOption = generator:descendInputOfBlock(block, "KEY_OPTION")
        return IntermediateInput:new(InputOpcode.SENSING_KEY_DOWN, InputType.BOOLEAN, {
            key = keyOption
        })

    elseif opcode == "sensing_keyoptions" then
        -- Key options menu reporter
        return generator:descendFieldOfBlock(block, "KEY_OPTION")

    elseif opcode == "sensing_mousedown" then
        return IntermediateInput:new(InputOpcode.SENSING_MOUSE_DOWN, InputType.BOOLEAN)

    elseif opcode == "sensing_mousex" then
        return IntermediateInput:new(InputOpcode.SENSING_MOUSE_X, InputType.NUMBER)

    elseif opcode == "sensing_mousey" then
        return IntermediateInput:new(InputOpcode.SENSING_MOUSE_Y, InputType.NUMBER)

    elseif opcode == "sensing_setdragmode" then
        local dragMode = block.fields and block.fields.DRAG_MODE and block.fields.DRAG_MODE.value
        return IntermediateStackBlock:new(StackOpcode.SENSING_SET_DRAG_MODE, {
            dragMode = generator:createConstantInput(dragMode)
        })

    elseif opcode == "sensing_loudness" then
        return IntermediateInput:new(InputOpcode.SENSING_LOUDNESS, InputType.NUMBER)

    elseif opcode == "sensing_timer" then
        return IntermediateInput:new(InputOpcode.SENSING_TIMER_GET, InputType.NUMBER)

    elseif opcode == "sensing_resettimer" then
        return IntermediateStackBlock:new(StackOpcode.SENSING_TIMER_RESET)

    elseif opcode == "sensing_of" then
        local property = generator:descendInputOfBlock(block, "PROPERTY")
        local object = generator:descendInputOfBlock(block, "OBJECT")
        return IntermediateInput:new(InputOpcode.SENSING_OF, InputType.ANY, {
            property = property,
            object = object
        })

    elseif opcode == "sensing_of_object_menu" then
        -- "of" block target menu reporter
        return generator:descendFieldOfBlock(block, "OBJECT")

    elseif opcode == "sensing_current" then
        local currentMenu = block.fields and block.fields.CURRENTMENU and block.fields.CURRENTMENU.value
        return IntermediateInput:new(InputOpcode.SENSING_CURRENT, InputType.NUMBER, {
            currentMenu = generator:createConstantInput(currentMenu)
        })

    elseif opcode == "sensing_dayssince2000" then
        return IntermediateInput:new(InputOpcode.SENSING_DAYS_SINCE_2000, InputType.NUMBER)

    elseif opcode == "sensing_username" then
        return IntermediateInput:new(InputOpcode.SENSING_USERNAME, InputType.STRING)

    elseif opcode == "sensing_userid" then
        return IntermediateInput:new(InputOpcode.SENSING_USER_ID, InputType.NUMBER)

    elseif opcode == "sensing_setdragmode" then
        local dragMode = generator:descendInputOfBlock(block, "DRAG_MODE")
        return IntermediateStackBlock:new(StackOpcode.SENSING_SET_DRAG_MODE, {
            dragMode = dragMode
        })

    -- Legacy sensing block (deprecated but still supported for compatibility)
    elseif opcode == "sensing_loud" then
        -- Legacy loudness block (same as loudness)
        return IntermediateInput:new(InputOpcode.SENSING_LOUDNESS, InputType.NUMBER)

    end

    return nil
end

---Generate Lua code for sensing stack blocks (minimal implementation)
---@param generator LuaGenerator Generator instance
---@param opcode string Stack opcode
---@param inputs table Block inputs
---@param block table|nil Original block for blockId access
---@return boolean handled True if opcode was handled
function SensingBlockCompiler.generateStackBlock(generator, opcode, inputs, block)
    local StackOpcode = enums.StackOpcode

    if opcode == StackOpcode.SENSING_TIMER_RESET then
        generator:writeLine("runtime:resetTimer()")
        return true
    elseif opcode == StackOpcode.SENSING_ASK_AND_WAIT then
        -- Ask and wait for answer - use helper for cleaner code
        local question = inputs.question
        if question then
            local questionCode = generator:generateInput(question)
            generator:writeLine(string.format("BlockHelpers.Sensing.askAndWait(target, %s, runtime, thread)", questionCode))
        end
        return true
    elseif opcode == StackOpcode.SENSING_SET_DRAG_MODE then
        local dragMode = inputs.dragMode
        if dragMode then
            local dragModeCode = generator:generateInput(dragMode)
            generator:writeLine("BlockHelpers.Sensing.setDragMode(target, " .. dragModeCode .. ", runtime, thread)")
        end
        return true
    end
    return false
end

---Generate Lua code for sensing input blocks (minimal implementation)
---@param generator LuaGenerator Generator instance
---@param opcode string Input opcode
---@param inputs table Block inputs
---@return string|nil code Generated Lua expression or nil if not handled
function SensingBlockCompiler.generateInput(generator, opcode, inputs)
    local InputOpcode = enums.InputOpcode

    if opcode == InputOpcode.SENSING_MOUSE_X then
        return "BlockHelpers.Sensing.mouseX(target, runtime, thread)"
    elseif opcode == InputOpcode.SENSING_MOUSE_Y then
        return "BlockHelpers.Sensing.mouseY(target, runtime, thread)"
    elseif opcode == InputOpcode.SENSING_TIMER_GET then
        return "runtime:getTimer()"
    elseif opcode == InputOpcode.SENSING_ANSWER then
        return "BlockHelpers.Sensing.answer(target, runtime, thread)"
    elseif opcode == InputOpcode.SENSING_TOUCHING_OBJECT then
        local objectCode = inputs.object and generator:generateInput(inputs.object) or '""'
        return string.format("BlockHelpers.Sensing.touchingObject(target, %s, runtime, thread)", objectCode)
    elseif opcode == InputOpcode.SENSING_TOUCHING_COLOR then
        local colorCode = inputs.color and generator:generateInput(inputs.color) or '""'
        return string.format("BlockHelpers.Sensing.touchingColor(target, %s, runtime, thread)", colorCode)
    elseif opcode == InputOpcode.SENSING_COLOR_TOUCHING_COLOR then
        local color1Code = inputs.color1 and generator:generateInput(inputs.color1) or '""'
        local color2Code = inputs.color2 and generator:generateInput(inputs.color2) or '""'
        return string.format("BlockHelpers.Sensing.colorIsTouchingColor(target, %s, %s, runtime, thread)", color1Code, color2Code)
    elseif opcode == InputOpcode.SENSING_DISTANCE_TO then
        local targetCode = inputs.target and generator:generateInput(inputs.target) or '""'
        return string.format("BlockHelpers.Sensing.distanceTo(target, %s, runtime, thread)", targetCode)
    elseif opcode == InputOpcode.SENSING_KEY_DOWN then
        local keyCode = inputs.key and generator:generateInput(inputs.key) or '""'
        return string.format("BlockHelpers.Sensing.keyPressed(target, %s, runtime, thread)", keyCode)
    elseif opcode == InputOpcode.SENSING_MOUSE_DOWN then
        return "BlockHelpers.Sensing.mouseDown(target, runtime, thread)"
    elseif opcode == InputOpcode.SENSING_LOUDNESS then
        return "BlockHelpers.Sensing.loudness(target, runtime, thread)"
    elseif opcode == InputOpcode.SENSING_OF then
        local propertyCode = inputs.property and generator:generateInput(inputs.property) or '""'
        local objectCode = inputs.object and generator:generateInput(inputs.object) or '""'
        return string.format("BlockHelpers.Sensing.of(target, %s, %s, runtime, thread)", propertyCode, objectCode)
    elseif opcode == InputOpcode.SENSING_CURRENT then
        local menuCode = inputs.currentMenu and generator:generateInput(inputs.currentMenu) or "'YEAR'"
        return string.format("BlockHelpers.Sensing.current(target, %s, runtime, thread)", menuCode)
    elseif opcode == InputOpcode.SENSING_DAYS_SINCE_2000 then
        return "BlockHelpers.Sensing.daysSince2000(target, runtime, thread)"
    elseif opcode == InputOpcode.SENSING_USERNAME then
        return "BlockHelpers.Sensing.username(target, runtime, thread)"
    elseif opcode == InputOpcode.SENSING_USER_ID then
        -- User ID is unsupported in Scratch 3 runtime - return 0 per native behavior
        return "0"
    end

    return nil
end

return SensingBlockCompiler
