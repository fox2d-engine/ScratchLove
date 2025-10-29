-- @fileoverview Control block compilation for Scratch to Lua compiler

local enums = require("compiler.enums")
local intermediate = require("compiler.intermediate")
local log = require("lib.log")

local InputType = enums.InputType
local StackOpcode = enums.StackOpcode
local InputOpcode = enums.InputOpcode
local IntermediateStackBlock = intermediate.IntermediateStackBlock
local IntermediateInput = intermediate.IntermediateInput

---@class ControlBlockCompiler
local ControlBlockCompiler = {}

---Compile control blocks during IR generation
---@param generator ScriptTreeGenerator Generator instance
---@param block table Scratch block
---@return IntermediateStackBlock|IntermediateInput|nil result Compiled result
function ControlBlockCompiler.compile(generator, block)
    local opcode = block.opcode

    -- Stack blocks (statements)
    if opcode == "control_wait" then
        local duration = generator:descendInputOfBlock(block, "DURATION"):toType(InputType.NUMBER)
        return IntermediateStackBlock:new(StackOpcode.CONTROL_WAIT, {
            duration = duration
        }, true) -- Yields during wait

    elseif opcode == "control_repeat" then
        local times = generator:descendInputOfBlock(block, "TIMES"):toType(InputType.NUMBER)
        local substack = generator:descendSubstack(block, "SUBSTACK")
        return IntermediateStackBlock:new(StackOpcode.CONTROL_REPEAT, {
            times = times,
            do_ = substack
        }, true) -- Yields for iteration

    elseif opcode == "control_forever" then
        local substack = generator:descendSubstack(block, "SUBSTACK")
        return IntermediateStackBlock:new(StackOpcode.CONTROL_FOREVER, {
            do_ = substack
        }, true) -- Yields for iteration

    elseif opcode == "control_if" then
        local condition = generator:descendInputOfBlock(block, "CONDITION"):toType(InputType.BOOLEAN)
        local substack = generator:descendSubstack(block, "SUBSTACK")
        return IntermediateStackBlock:new(StackOpcode.CONTROL_IF_ELSE, {
            condition = condition,
            whenTrue = substack,
            whenFalse = nil
        })

    elseif opcode == "control_if_else" then
        local condition = generator:descendInputOfBlock(block, "CONDITION"):toType(InputType.BOOLEAN)
        local substackTrue = generator:descendSubstack(block, "SUBSTACK")
        local substackFalse = generator:descendSubstack(block, "SUBSTACK2")
        return IntermediateStackBlock:new(StackOpcode.CONTROL_IF_ELSE, {
            condition = condition,
            whenTrue = substackTrue,
            whenFalse = substackFalse
        })

    elseif opcode == "control_wait_until" then
        -- Phase 3: Similar to repeat_until, use OP_NOT pattern for consistency
        -- wait until C → while NOT C (with special yield behavior)
        local condition = generator:descendInputOfBlock(block, "CONDITION"):toType(InputType.BOOLEAN)
        local notCondition = IntermediateInput:new(InputOpcode.OP_NOT, InputType.BOOLEAN, {
            operand = condition
        })
        return IntermediateStackBlock:new(StackOpcode.CONTROL_WAIT_UNTIL, {
            condition = notCondition
        }, true) -- Yields until condition met

    elseif opcode == "control_repeat_until" then
        -- Phase 2: repeat until C → while NOT C pattern
        -- This eliminates double negation in the IR structure
        -- IMPORTANT: condition must be converted to boolean BEFORE wrapping in OP_NOT
        local condition = generator:descendInputOfBlock(block, "CONDITION"):toType(InputType.BOOLEAN)
        local notCondition = IntermediateInput:new(InputOpcode.OP_NOT, InputType.BOOLEAN, {
            operand = condition
        })
        local substack = generator:descendSubstack(block, "SUBSTACK")
        return IntermediateStackBlock:new(StackOpcode.CONTROL_WHILE, {
            condition = notCondition,
            do_ = substack
        }, true) -- Yields for iteration

    elseif opcode == "control_while" then
        local condition = generator:descendInputOfBlock(block, "CONDITION"):toType(InputType.BOOLEAN)
        local substack = generator:descendSubstack(block, "SUBSTACK")
        return IntermediateStackBlock:new(StackOpcode.CONTROL_WHILE, {
            condition = condition,
            do_ = substack
        }, true) -- Yields for iteration

    elseif opcode == "control_for_each" then
        local variable = generator:descendVariable(block, "VARIABLE", "")
        local value = generator:descendInputOfBlock(block, "VALUE")
        local substack = generator:descendSubstack(block, "SUBSTACK")
        return IntermediateStackBlock:new(StackOpcode.CONTROL_FOR, {
            variable = variable,
            value = value,
            do_ = substack
        }, true) -- Yields for iteration

    elseif opcode == "control_stop" then
        local stopOption = block.fields and block.fields.STOP_OPTION and block.fields.STOP_OPTION.value
        if stopOption == "all" then
            return IntermediateStackBlock:new(StackOpcode.CONTROL_STOP_ALL)
        elseif stopOption == "this script" then
            return IntermediateStackBlock:new(StackOpcode.CONTROL_STOP_SCRIPT)
        elseif stopOption == "other scripts in sprite" or stopOption == "other scripts in stage" then
            return IntermediateStackBlock:new(StackOpcode.CONTROL_STOP_OTHERS, {
                stopOption = stopOption
            })
        else
            return IntermediateStackBlock:new(StackOpcode.CONTROL_STOP_SCRIPT)
        end

    elseif opcode == "control_create_clone_of" then
        local cloneOption = generator:descendInputOfBlock(block, "CLONE_OPTION")
        return IntermediateStackBlock:new(StackOpcode.CONTROL_CLONE_CREATE, {
            cloneOption = cloneOption
        })

    elseif opcode == "control_delete_this_clone" then
        return IntermediateStackBlock:new(StackOpcode.CONTROL_CLONE_DELETE)

    elseif opcode == "control_get_counter" then
        return IntermediateInput:new(InputOpcode.CONTROL_COUNTER_GET, InputType.NUMBER)

    elseif opcode == "control_incr_counter" then
        return IntermediateStackBlock:new(StackOpcode.CONTROL_INCR_COUNTER)

    elseif opcode == "control_clear_counter" then
        return IntermediateStackBlock:new(StackOpcode.CONTROL_CLEAR_COUNTER)

    elseif opcode == "control_all_at_once" then
        -- "Run without screen refresh" - treat as warp mode
        local substack = generator:descendSubstack(block, "SUBSTACK")
        return IntermediateStackBlock:new(StackOpcode.CONTROL_WARP, {
            do_ = substack
        })

    elseif opcode == "control_create_clone_of_menu" then
        -- Menu blocks return their field value directly
        local cloneOption = block.fields and block.fields.CLONE_OPTION
        if cloneOption then
            return generator:createConstantInput(cloneOption.value or cloneOption.name or cloneOption)
        end
        return generator:createConstantInput("")

    end

    return nil
end

---Generate Lua code for control stack blocks
---@param generator LuaGenerator Generator instance
---@param opcode string Stack opcode
---@param inputs table Block inputs
---@param block table|nil Original block for blockId access
---@return boolean handled True if opcode was handled
function ControlBlockCompiler.generateStackBlock(generator, opcode, inputs, block)
    local StackOpcode = enums.StackOpcode

    if opcode == StackOpcode.CONTROL_IF_ELSE then
        -- If-else conditional
        local condition = inputs.condition
        local whenTrue = inputs.whenTrue
        local whenFalse = inputs.whenFalse

        if condition then
            local conditionCode = generator:generateInput(condition)
            -- Phase 1: Don't wrap - condition already has CAST_BOOLEAN from toType()
            generator:writeLine(string.format("if %s then", conditionCode))
            generator:indent()

            if whenTrue then
                generator:generateStack(whenTrue)
            end

            -- Only add the else branch if it has content (optimization)
            if whenFalse and whenFalse.blocks and #whenFalse.blocks > 0 then
                generator:dedent()
                generator:writeLine("else")
                generator:indent()
                generator:generateStack(whenFalse)
            end

            generator:dedent()
            generator:writeLine("end")
        end
        return true

    elseif opcode == StackOpcode.CONTROL_REPEAT then
        -- Repeat loop - optimized for better performance
        local times = inputs.times
        local doStack = inputs.do_

        if times then
            local timesCode = generator:generateInput(times)
            local loopVar = generator:getLocalVariable("iterations")

            -- Performance optimization: pre-calculate iterations and use integer for loop
            generator:writeLine(string.format("local %s = math.max(0, math.floor(%s + 0.5))", loopVar, timesCode))
            generator:writeLine(string.format("for _ = 1, %s do", loopVar))
            generator:indent()

            if doStack then
                generator:generateStack(doStack)
            else
                generator:writeLine("-- empty loop body")
            end

            -- Use unified yield method
            generator:yieldLoop()

            generator:dedent()
            generator:writeLine("end")
        end
        return true

    elseif opcode == StackOpcode.CONTROL_FOREVER then
        -- Forever loop - but only if there's a substack (matches native Scratch behavior)
        local doStack = inputs.do_

        if doStack then
            generator:writeLine("while true do")
            generator:indent()
            generator:generateStack(doStack)

            -- Use unified yield method
            generator:yieldLoop()

            generator:dedent()
            generator:writeLine("end")
        else
            -- No substack - forever block does nothing (matches native Scratch)
            generator:writeLine("-- forever with no substack - no operation")
        end
        return true

    elseif opcode == StackOpcode.CONTROL_REPEAT_UNTIL then
        -- DEPRECATED: repeat_until now uses CONTROL_WHILE + OP_NOT in IR generation (Phase 2)
        -- This code path is preserved for backward compatibility with old compiled IR
        -- New compilations will never reach here as repeat_until generates CONTROL_WHILE
        local condition = inputs.condition
        local doStack = inputs.do_

        if condition then
            local conditionCode = generator:generateInput(condition)
            -- In Scratch, "repeat until" means keep repeating while condition is false
            -- Phase 1: Don't wrap - condition already has CAST_BOOLEAN from toType()
            generator:writeLine(string.format("while not %s do", conditionCode))
            generator:indent()

            if doStack then
                generator:generateStack(doStack)
            else
                generator:writeLine("-- empty repeat until body")
            end

            -- Use unified yield method
            generator:yieldLoop()

            generator:dedent()
            generator:writeLine("end")
        end
        return true

    elseif opcode == StackOpcode.CONTROL_WHILE then
        -- While loop
        local condition = inputs.condition
        local doStack = inputs.do_

        if condition then
            local conditionCode = generator:generateInput(condition)
            -- Phase 1: Don't wrap - condition already has CAST_BOOLEAN from toType()
            generator:writeLine(string.format("while %s do", conditionCode))
            generator:indent()

            if doStack then
                generator:generateStack(doStack)
            else
                generator:writeLine("-- empty while body")
            end

            -- Use unified yield method
            generator:yieldLoop()

            generator:dedent()
            generator:writeLine("end")
        end
        return true

    elseif opcode == StackOpcode.CONTROL_WAIT_UNTIL then
        -- Wait until condition
        -- Phase 3: condition is already OP_NOT(...) from IR generation
        local condition = inputs.condition
        if condition then
            local conditionCode = generator:generateInput(condition)
            -- Don't add extra 'not' - condition already contains negation
            generator:writeLine(string.format("while %s do", conditionCode))
            generator:indent()
            -- Use yieldStuckOrNotWarp for stuck detection in warp mode
            generator:yieldStuckOrNotWarp()
            generator:dedent()
            generator:writeLine("end")
        end
        return true

    elseif opcode == StackOpcode.CONTROL_WAIT then
        -- Wait for specified duration
        local duration = inputs.duration
        if duration then
            local durationCode = generator:generateInput(duration)
            local durationVar = generator:getLocalVariable("waitDuration")

            -- Pre-calculate duration in seconds
            generator:writeLine(string.format("local %s = math.max(0, %s)", durationVar, durationCode))

            generator:writeLine("runtime:requestRedraw()")

            -- CRITICAL: Always yield at least once, even for duration=0 (Scratch compatibility)
            generator:yieldNotWarp()

            -- Wait loop with stuck detection
            generator:writeLine(string.format("local waitStartTime = love.timer.getTime()"))
            generator:writeLine(string.format("while love.timer.getTime() - waitStartTime < %s do", durationVar))
            generator:indent()
            generator:yieldStuckOrNotWarp()
            generator:dedent()
            generator:writeLine("end")
        end
        return true

    elseif opcode == StackOpcode.CONTROL_CLONE_CREATE then
        -- Create clone - use original blocks implementation
        local cloneOption = inputs.cloneOption
        if cloneOption then
            local cloneCode = generator:generateInput(cloneOption)
            generator:writeLine("BlockHelpers.Control.create_clone_of(target, { CLONE_OPTION = " .. cloneCode .. " }, runtime, thread)")
        end
        return true

    elseif opcode == StackOpcode.CONTROL_CLONE_DELETE then
        -- Delete this clone
        -- CRITICAL: Only retire if it's actually a clone (helper returns "stop" for clones, nil for original)
        -- Native Scratch behavior:
        --   - Clones: deleted and script stops immediately via retire()
        --   - Original sprite: nothing happens, script continues
        generator:writeLine("if BlockHelpers.Control.delete_this_clone(target, {}, runtime, thread) == \"stop\" then")
        generator:indent()
        generator:retire()  -- Use retire() method for proper procedure/script handling
        generator:dedent()
        generator:writeLine("end")
        return true

    elseif opcode == StackOpcode.CONTROL_WARP then
        -- Run without screen refresh (all at once) - execute substack immediately without yielding
        local doStack = inputs.do_
        if doStack then
            generator:writeLine("-- Execute all at once (warp mode)")
            generator:generateStack(doStack)
        end
        return true

    elseif opcode == StackOpcode.CONTROL_STOP_SCRIPT then
        -- Stop this script - terminate the thread
        generator:writeLine("-- Stop this script")
        -- Use forceStop=true to always generate code, even if scriptEnded is set
        generator:stopScript(true)
        return true

    elseif opcode == StackOpcode.CONTROL_STOP_ALL then
        -- Stop all scripts - must terminate current script too
        generator:writeLine("-- Stop all scripts")
        generator:writeLine("BlockHelpers.Control.stop(target, {STOP_OPTION = 'all'}, runtime, thread)")
        generator:retire()  -- Use retire() method for proper procedure/script handling
        return true

    elseif opcode == StackOpcode.CONTROL_STOP_OTHERS then
        -- Stop other scripts in sprite - use original blocks implementation
        local stopOption = inputs.stopOption or 'other scripts in sprite'
        generator:writeLine("-- Stop other scripts in sprite")
        generator:writeLine(string.format("BlockHelpers.Control.stop(target, {STOP_OPTION = %q}, runtime, thread)", stopOption))
        return true

    elseif opcode == StackOpcode.CONTROL_INCR_COUNTER then
        -- Increment counter (Scratch 2 legacy)
        generator:writeLine("BlockHelpers.Control.incrCounter()")
        return true

    elseif opcode == StackOpcode.CONTROL_CLEAR_COUNTER then
        -- Clear counter (Scratch 2 legacy)
        generator:writeLine("BlockHelpers.Control.clearCounter()")
        return true
    end

    return false
end

---Generate Lua code for control input blocks
---@param generator LuaGenerator Generator instance
---@param opcode string Input opcode
---@param inputs table Block inputs
---@return string|nil code Generated code or nil if not handled
function ControlBlockCompiler.generateInput(generator, opcode, inputs)
    local InputOpcode = enums.InputOpcode

    if opcode == InputOpcode.CONTROL_COUNTER_GET then
        -- Get counter value (Scratch 2 legacy)
        return "BlockHelpers.Control.getCounter()"
    end

    return nil
end

return ControlBlockCompiler