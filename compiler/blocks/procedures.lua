-- @fileoverview Procedures block compilation for Scratch to Lua compiler

local enums = require("compiler.enums")
local intermediate = require("compiler.intermediate")

local InputType = enums.InputType
local StackOpcode = enums.StackOpcode
local InputOpcode = enums.InputOpcode
local IntermediateStackBlock = intermediate.IntermediateStackBlock
local IntermediateInput = intermediate.IntermediateInput

---@class ProceduresBlockCompiler
local ProceduresBlockCompiler = {}

---Compile procedures blocks during IR generation
---@param generator ScriptTreeGenerator Generator instance
---@param block table Scratch block
---@return IntermediateStackBlock|IntermediateInput|nil result Compiled result
function ProceduresBlockCompiler.compile(generator, block)
    local opcode = block.opcode

    -- Stack blocks (statements)
    if opcode == "procedures_call" then
        -- Procedure call is already handled in irgen.lua descendStackedBlock
        -- Return nil to let irgen handle it
        return nil

    elseif opcode == "procedures_definition" then
        -- Procedure definition - this is a hat block, not normally compiled as stack block
        -- Return nil to let irgen handle it as a HAT block
        return nil

    elseif opcode == "argument_reporter_string_number" then
        -- String/number argument reporter
        local field = block.fields and block.fields.VALUE
        local argName = field and field.value or "arg"

        return IntermediateInput:new(InputOpcode.ARG_REF, InputType.ANY, {
            argName = argName,
            argType = "string_number"
        })

    elseif opcode == "argument_reporter_boolean" then
        -- Boolean argument reporter
        local field = block.fields and block.fields.VALUE
        local argName = field and field.value or "arg"

        return IntermediateInput:new(InputOpcode.ARG_REF, InputType.ANY, {
            argName = argName,
            argType = "boolean"
        })

    elseif opcode == "procedures_return" then
        -- Return from procedure with value
        local value = generator:descendInputOfBlock(block, "VALUE")
        return IntermediateStackBlock:new(StackOpcode.PROCEDURE_RETURN, {
            value = value or generator:createConstantInput("")
        })
    end

    return nil
end

---Generate Lua code for procedures stack blocks
---@param generator LuaGenerator Generator instance
---@param opcode string Stack opcode
---@param inputs table Block inputs
---@param block table|nil Original block for blockId access
---@return boolean handled True if opcode was handled
function ProceduresBlockCompiler.generateStackBlock(generator, opcode, inputs, block)
    local StackOpcode = enums.StackOpcode

    if opcode == StackOpcode.PROCEDURE_CALL then
        -- Procedure call - direct function call
        local procedureCode = inputs.procedureCode
        local variant = inputs.variant
        local arguments = inputs.arguments

        if procedureCode and variant then
            generator:writeLine("-- Procedure call: " .. tostring(procedureCode))

            -- Check for recursion
            -- In non-warp mode, if calling the same procedure we're currently in, yield before call
            local yieldForRecursion = not generator.isWarp and
                                     generator.script.procedureCode and
                                     procedureCode == generator.script.procedureCode

            if yieldForRecursion then
                generator:writeLine("-- Recursive call detected: yield to prevent stack overflow")
                generator:yieldNotWarp()
            end

            -- Generate arguments
            local argCodes = {"runtime", "target", "thread"}  -- Always pass runtime, target, and thread first
            if arguments then
                for i, arg in ipairs(arguments) do
                    argCodes[#argCodes + 1] = generator:generateInput(arg)
                end
            end

            local callLine = "thread.procedures[" .. string.format("%q", variant) .. "](" .. table.concat(argCodes, ", ") .. ")"
            generator:writeLine(callLine)
        end
        return true

    elseif opcode == StackOpcode.PROCEDURE_RETURN then
        -- Return from procedure with value
        local value = inputs.value
        if value then
            local valueCode = generator:generateInput(value)
            generator:stopScriptAndReturn(valueCode)
        else
            -- No value: use stopScript instead (return empty string for procedure)
            -- Use forceStop=true for consistency with CONTROL_STOP_SCRIPT and stopScriptAndReturn
            generator:stopScript(true)
        end
        return true
    end

    return false
end

---Generate Lua code for procedures input blocks
---@param generator LuaGenerator Generator instance
---@param opcode string Input opcode
---@param inputs table Block inputs
---@return string|nil code Generated Lua expression or nil if not handled
function ProceduresBlockCompiler.generateInput(generator, opcode, inputs)
    local InputOpcode = enums.InputOpcode

    if opcode == InputOpcode.ARG_REF then
        -- Procedure argument reference
        local argName = inputs.argName
        if argName then
            return string.format("arg_%s", argName)
        end
        return "nil"

    elseif opcode == InputOpcode.PROCEDURE_CALL then
        -- Procedure call as reporter (custom block with return value)
        -- TurboWarp extension: procedure call used as input returns a value
        local procedureCode = inputs.procedureCode
        local variant = inputs.variant
        local arguments = inputs.arguments

        if procedureCode and variant then
            -- Note: For recursive calls in non-warp mode, the procedure itself handles yielding
            -- since this is an expression context and we can't yield mid-expression

            -- Generate arguments
            local argCodes = {"runtime", "target", "thread"}
            if arguments then
                for _, arg in ipairs(arguments) do
                    argCodes[#argCodes + 1] = generator:generateInput(arg)
                end
            end

            -- Generate the procedure call expression
            -- The procedure returns its value directly
            local callExpr = string.format(
                'thread.procedures[%q](%s)',
                variant,
                table.concat(argCodes, ", ")
            )

            return callExpr
        end

        -- Fallback: return empty string if procedure info is missing
        return '""'
    end

    return nil
end

return ProceduresBlockCompiler