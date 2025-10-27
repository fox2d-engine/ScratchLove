-- @fileoverview Motion block compilation for Scratch to Lua compiler

local enums = require("compiler.enums")
local intermediate = require("compiler.intermediate")

local InputType = enums.InputType
local StackOpcode = enums.StackOpcode
local InputOpcode = enums.InputOpcode
local IntermediateStackBlock = intermediate.IntermediateStackBlock
local IntermediateInput = intermediate.IntermediateInput

---@class MotionBlockCompiler
local MotionBlockCompiler = {}

---Compile motion blocks during IR generation
---@param generator ScriptTreeGenerator Generator instance
---@param block table Scratch block
---@param blockId string|nil Original Scratch block ID
---@return IntermediateStackBlock|IntermediateInput|nil result Compiled result
function MotionBlockCompiler.compile(generator, block, blockId)
    local opcode = block.opcode

    -- Stack blocks (statements)
    if opcode == "motion_movesteps" then
        local steps = generator:descendInputOfBlock(block, "STEPS"):toType(InputType.NUMBER)
        return IntermediateStackBlock:new(StackOpcode.MOTION_STEP, {
            steps = steps
        })

    elseif opcode == "motion_turnright" then
        local degrees = generator:descendInputOfBlock(block, "DEGREES"):toType(InputType.NUMBER)
        return IntermediateStackBlock:new(StackOpcode.MOTION_TURN_RIGHT, {
            degrees = degrees
        })

    elseif opcode == "motion_turnleft" then
        local degrees = generator:descendInputOfBlock(block, "DEGREES"):toType(InputType.NUMBER)
        return IntermediateStackBlock:new(StackOpcode.MOTION_TURN_LEFT, {
            degrees = degrees
        })

    elseif opcode == "motion_pointindirection" then
        local direction = generator:descendInputOfBlock(block, "DIRECTION"):toType(InputType.NUMBER)
        return IntermediateStackBlock:new(StackOpcode.MOTION_DIRECTION_SET, {
            direction = direction
        })

    elseif opcode == "motion_pointtowards" then
        local towards = generator:descendInputOfBlock(block, "TOWARDS")
        return IntermediateStackBlock:new(StackOpcode.MOTION_POINT_TOWARDS, {
            towards = towards
        })

    elseif opcode == "motion_pointtowards_menu" then
        -- Point towards menu reporter
        return generator:descendFieldOfBlock(block, "TOWARDS")

    elseif opcode == "motion_gotoxy" then
        local x = generator:descendInputOfBlock(block, "X"):toType(InputType.NUMBER)
        local y = generator:descendInputOfBlock(block, "Y"):toType(InputType.NUMBER)
        return IntermediateStackBlock:new(StackOpcode.MOTION_XY_SET, {
            x = x,
            y = y
        })

    elseif opcode == "motion_goto" then
        local to = generator:descendInputOfBlock(block, "TO")
        return IntermediateStackBlock:new(StackOpcode.MOTION_GOTO, {
            to = to
        })

    elseif opcode == "motion_goto_menu" then
        -- Go to menu reporter
        return generator:descendFieldOfBlock(block, "TO")

    elseif opcode == "motion_glideto" then
        local secs = generator:descendInputOfBlock(block, "SECS"):toType(InputType.NUMBER)
        local to = generator:descendInputOfBlock(block, "TO")
        return IntermediateStackBlock:new(StackOpcode.MOTION_GLIDE_TO, {
            secs = secs,
            to = to
        }, true, blockId) -- Yields during animation

    elseif opcode == "motion_glideto_menu" then
        -- Glide to menu reporter
        return generator:descendFieldOfBlock(block, "TO")

    elseif opcode == "motion_glidesecstoxy" then
        local secs = generator:descendInputOfBlock(block, "SECS"):toType(InputType.NUMBER)
        local x = generator:descendInputOfBlock(block, "X"):toType(InputType.NUMBER)
        local y = generator:descendInputOfBlock(block, "Y"):toType(InputType.NUMBER)

        return IntermediateStackBlock:new(StackOpcode.MOTION_GLIDE_TO_XY, {
            secs = secs,
            x = x,
            y = y
        }, true, blockId) -- Yields during animation

    elseif opcode == "motion_changexby" then
        local dx = generator:descendInputOfBlock(block, "DX"):toType(InputType.NUMBER)
        return IntermediateStackBlock:new(StackOpcode.MOTION_X_CHANGE, {
            dx = dx
        })

    elseif opcode == "motion_setx" then
        local x = generator:descendInputOfBlock(block, "X"):toType(InputType.NUMBER)
        return IntermediateStackBlock:new(StackOpcode.MOTION_X_SET, {
            x = x
        })

    elseif opcode == "motion_changeyby" then
        local dy = generator:descendInputOfBlock(block, "DY"):toType(InputType.NUMBER)
        return IntermediateStackBlock:new(StackOpcode.MOTION_Y_CHANGE, {
            dy = dy
        })

    elseif opcode == "motion_sety" then
        local y = generator:descendInputOfBlock(block, "Y"):toType(InputType.NUMBER)
        return IntermediateStackBlock:new(StackOpcode.MOTION_Y_SET, {
            y = y
        })

    elseif opcode == "motion_ifonedgebounce" then
        return IntermediateStackBlock:new(StackOpcode.MOTION_IF_ON_EDGE_BOUNCE)

    elseif opcode == "motion_setrotationstyle" then
        local style = generator:descendFieldOfBlock(block, "STYLE"):toType(InputType.STRING)
        return IntermediateStackBlock:new(StackOpcode.MOTION_SET_ROTATION_STYLE, {
            style = style
        })

    -- Stage-specific motion blocks
    elseif opcode == "motion_align_scene" then
        return IntermediateStackBlock:new(StackOpcode.MOTION_ALIGN_SCENE)

    elseif opcode == "motion_scroll_right" then
        local distance = generator:descendInputOfBlock(block, "DISTANCE"):toType(InputType.NUMBER)
        return IntermediateStackBlock:new(StackOpcode.MOTION_SCROLL_RIGHT, {
            distance = distance
        })

    elseif opcode == "motion_scroll_up" then
        local distance = generator:descendInputOfBlock(block, "DISTANCE"):toType(InputType.NUMBER)
        return IntermediateStackBlock:new(StackOpcode.MOTION_SCROLL_UP, {
            distance = distance
        })

    -- Reporter blocks (expressions)
    elseif opcode == "motion_xposition" then
        return IntermediateInput:new(InputOpcode.MOTION_X_GET, InputType.NUMBER)

    elseif opcode == "motion_yposition" then
        return IntermediateInput:new(InputOpcode.MOTION_Y_GET, InputType.NUMBER)

    elseif opcode == "motion_direction" then
        return IntermediateInput:new(InputOpcode.MOTION_DIRECTION_GET, InputType.NUMBER)

    -- Stage-specific scrolling inputs (for stage targets only)
    elseif opcode == "motion_xscroll" then
        return IntermediateInput:new(InputOpcode.MOTION_X_SCROLL, InputType.NUMBER)

    elseif opcode == "motion_yscroll" then
        return IntermediateInput:new(InputOpcode.MOTION_Y_SCROLL, InputType.NUMBER)

    end

    return nil
end

---Generate Lua code for motion stack blocks
---@param generator LuaGenerator Generator instance
---@param opcode string Stack opcode
---@param inputs table Block inputs
---@param block table|nil Original block for blockId access
---@return boolean handled True if opcode was handled
function MotionBlockCompiler.generateStackBlock(generator, opcode, inputs, block)
    local StackOpcode = enums.StackOpcode

    if opcode == StackOpcode.MOTION_STEP then
        -- Move steps
        local steps = inputs.steps
        if steps then
            local stepsCode = generator:generateInput(steps)
            generator:writeLine(string.format("target:move(%s)", stepsCode))
        end
        return true

    elseif opcode == StackOpcode.MOTION_TURN_RIGHT then
        -- Turn right (clockwise)
        local degrees = inputs.degrees
        if degrees then
            local degreesCode = generator:generateInput(degrees)
            generator:writeLine(string.format("target:turnRight(%s)", degreesCode))
        end
        return true

    elseif opcode == StackOpcode.MOTION_TURN_LEFT then
        -- Turn left (counter-clockwise)
        local degrees = inputs.degrees
        if degrees then
            local degreesCode = generator:generateInput(degrees)
            generator:writeLine(string.format("target:turnLeft(%s)", degreesCode))
        end
        return true

    elseif opcode == StackOpcode.MOTION_DIRECTION_SET then
        -- Set direction
        local direction = inputs.direction
        if direction then
            local directionCode = generator:generateInput(direction)
            generator:writeLine(string.format("if not target.isStage then target:setDirection(%s) end",
                directionCode))
        end
        return true

    elseif opcode == StackOpcode.MOTION_XY_SET then
        -- Go to x,y
        local x = inputs.x
        local y = inputs.y
        if x and y then
            local xCode = generator:generateInput(x)
            local yCode = generator:generateInput(y)
            generator:writeLine(string.format("target:setXY(%s, %s)", xCode, yCode))

            local hasModulo = generator:inputContainsModulo(x) or generator:inputContainsModulo(y)
            if hasModulo then
                generator:writeLine("if target.interpolationData then target.interpolationData = nil end")
            end
        end
        return true

    elseif opcode == StackOpcode.MOTION_GOTO then
        -- Go to (sprite/mouse/random) - use helper for cleaner code
        local to = inputs.to
        if to then
            local toCode = generator:generateInput(to)
            generator:writeLine(string.format("BlockHelpers.Motion.goTo(target, %s, runtime, thread)", toCode))
        end
        return true

    elseif opcode == StackOpcode.MOTION_POINT_TOWARDS then
        -- Point towards (sprite/mouse/random) - use helper for cleaner code
        local towards = inputs.towards
        if towards then
            local towardsCode = generator:generateInput(towards)
            generator:writeLine(string.format("BlockHelpers.Motion.pointTowards(target, %s, runtime, thread)", towardsCode))
        end
        return true

    elseif opcode == StackOpcode.MOTION_GLIDE_TO then
        -- Glide to (sprite/mouse/random) - use helper for cleaner code
        local secs = inputs.secs
        local to = inputs.to
        if secs and to then
            local secsCode = generator:generateInput(secs)
            local toCode = generator:generateInput(to)
            -- Generate unique state key using blockId
            local stateKey = string.format("glideto_%s", block and block.blockId or "unknown")
            generator:writeLine(string.format("BlockHelpers.Motion.glideTo(target, %s, %s, %q, runtime, thread)",
                secsCode, toCode, stateKey))
        end
        return true

    elseif opcode == StackOpcode.MOTION_GLIDE_TO_XY then
        -- Glide to x,y coordinates - use helper for cleaner code
        local secs = inputs.secs
        local x = inputs.x
        local y = inputs.y
        if secs and x and y then
            local secsCode = generator:generateInput(secs)
            local xCode = generator:generateInput(x)
            local yCode = generator:generateInput(y)
            -- Generate unique state key using blockId
            local stateKey = string.format("glide_%s", block and block.blockId or "unknown")
            generator:writeLine(string.format("BlockHelpers.Motion.glideToXY(target, %s, %s, %s, %q, runtime, thread)",
                secsCode, xCode, yCode, stateKey))
        end
        return true

    elseif opcode == StackOpcode.MOTION_X_CHANGE then
        -- Change X by amount
        local dx = inputs.dx
        if dx then
            local dxCode = generator:generateInput(dx)
            generator:writeLine(string.format("if not target.isStage then target:changeX(%s) end", dxCode))
        end
        return true

    elseif opcode == StackOpcode.MOTION_Y_CHANGE then
        -- Change Y by amount
        local dy = inputs.dy
        if dy then
            local dyCode = generator:generateInput(dy)
            generator:writeLine(string.format("if not target.isStage then target:changeY(%s) end", dyCode))
        end
        return true

    elseif opcode == StackOpcode.MOTION_X_SET then
        -- Set X position
        local x = inputs.x
        if x then
            local xCode = generator:generateInput(x)
            generator:writeLine(string.format("if not target.isStage then target:setX(%s) end", xCode))

            local hasModulo = generator:inputContainsModulo(x)
            if hasModulo then
                generator:writeLine("if target.interpolationData then target.interpolationData = nil end")
            end
        end
        return true

    elseif opcode == StackOpcode.MOTION_Y_SET then
        -- Set Y position
        local y = inputs.y
        if y then
            local yCode = generator:generateInput(y)
            generator:writeLine(string.format("if not target.isStage then target:setY(%s) end", yCode))

            local hasModulo = generator:inputContainsModulo(y)
            if hasModulo then
                generator:writeLine("if target.interpolationData then target.interpolationData = nil end")
            end
        end
        return true

    elseif opcode == StackOpcode.MOTION_IF_ON_EDGE_BOUNCE then
        -- Bounce if on edge
        generator:writeLine("if not target.isStage then target:ifOnEdgeBounce() end")
        return true

    elseif opcode == StackOpcode.MOTION_SET_ROTATION_STYLE then
        -- Set rotation style
        local style = inputs.style
        if style then
            local styleCode = generator:generateInput(style)
            generator:writeLine(string.format("if not target.isStage then target:setRotationStyle(%s) end",
                styleCode))
        end
        return true

    elseif opcode == StackOpcode.MOTION_ALIGN_SCENE then
        -- Align scene (stage only)
        generator:writeLine("if target.isStage then")
        generator:indent()
        generator:writeLine("-- Stage align scene - reset scroll position")
        generator:writeLine("target.scrollX = 0")
        generator:writeLine("target.scrollY = 0")
        generator:dedent()
        generator:writeLine("end")
        return true

    elseif opcode == StackOpcode.MOTION_SCROLL_RIGHT then
        -- Scroll right (stage only)
        local distance = inputs.distance
        if distance then
            local distanceCode = generator:generateInput(distance)
            generator:writeLine("if target.isStage then")
            generator:indent()
            generator:writeLine(string.format("target.scrollX = (target.scrollX or 0) + %s", distanceCode))
            generator:dedent()
            generator:writeLine("end")
        end
        return true

    elseif opcode == StackOpcode.MOTION_SCROLL_UP then
        -- Scroll up (stage only)
        local distance = inputs.distance
        if distance then
            local distanceCode = generator:generateInput(distance)
            generator:writeLine("if target.isStage then")
            generator:indent()
            generator:writeLine(string.format("target.scrollY = (target.scrollY or 0) + %s", distanceCode))
            generator:dedent()
            generator:writeLine("end")
        end
        return true
    end

    return false
end

---Generate Lua code for motion input blocks
---@param generator LuaGenerator Generator instance
---@param opcode string Input opcode
---@param inputs table Block inputs
---@return string|nil code Generated Lua expression or nil if not handled
function MotionBlockCompiler.generateInput(generator, opcode, inputs)
    local InputOpcode = enums.InputOpcode

    if opcode == InputOpcode.MOTION_X_GET then
        -- Get X position - Apply Scratch coordinate rounding
        return "cast.toScratchCoordinate(target.x)"

    elseif opcode == InputOpcode.MOTION_Y_GET then
        -- Get Y position - Apply Scratch coordinate rounding
        return "cast.toScratchCoordinate(target.y)"

    elseif opcode == InputOpcode.MOTION_DIRECTION_GET then
        -- Get direction
        return "target.direction"

    elseif opcode == InputOpcode.MOTION_X_SCROLL then
        -- Get X scroll position (stage only)
        return "(target.isStage and target.scrollX or 0)"

    elseif opcode == InputOpcode.MOTION_Y_SCROLL then
        -- Get Y scroll position (stage only)
        return "(target.isStage and target.scrollY or 0)"
    end

    return nil
end

return MotionBlockCompiler
