-- @fileoverview Operators block compilation for Scratch to Lua compiler

local enums = require("compiler.enums")
local intermediate = require("compiler.intermediate")
local log = require("lib.log")

local InputType = enums.InputType
local StackOpcode = enums.StackOpcode
local InputOpcode = enums.InputOpcode
local IntermediateStackBlock = intermediate.IntermediateStackBlock
local IntermediateInput = intermediate.IntermediateInput

---@class OperatorsBlockCompiler
local OperatorsBlockCompiler = {}

---Compile operators blocks during IR generation
---@param generator ScriptTreeGenerator Generator instance
---@param block table Scratch block
---@return IntermediateStackBlock|IntermediateInput|nil result Compiled result
function OperatorsBlockCompiler.compile(generator, block)
    local opcode = block.opcode

    -- All operators blocks are reporter blocks (expressions)
    if opcode == "operator_add" then
        -- Arithmetic requires NUMBER type - insert CAST nodes via toType()
        local num1 = generator:descendInputOfBlock(block, "NUM1"):toType(InputType.NUMBER)
        local num2 = generator:descendInputOfBlock(block, "NUM2"):toType(InputType.NUMBER)

        -- Constant folding optimization (done in IR generation phase)
        if num1.opcode == InputOpcode.CONSTANT and num2.opcode == InputOpcode.CONSTANT then
            local val1 = num1.inputs.value
            local val2 = num2.inputs.value
            if type(val1) == "number" and type(val2) == "number" then
                local result = val1 + val2
                return IntermediateInput:new(InputOpcode.CONSTANT,
                    IntermediateInput.getNumberInputType(result),
                    {value = result})
            end
        end

        return IntermediateInput:new(InputOpcode.OP_ADD, InputType.NUMBER, {
            left = num1,
            right = num2
        })

    elseif opcode == "operator_subtract" then
        local num1 = generator:descendInputOfBlock(block, "NUM1"):toType(InputType.NUMBER)
        local num2 = generator:descendInputOfBlock(block, "NUM2"):toType(InputType.NUMBER)

        -- Constant folding
        if num1.opcode == InputOpcode.CONSTANT and num2.opcode == InputOpcode.CONSTANT then
            local val1 = num1.inputs.value
            local val2 = num2.inputs.value
            if type(val1) == "number" and type(val2) == "number" then
                local result = val1 - val2
                return IntermediateInput:new(InputOpcode.CONSTANT,
                    IntermediateInput.getNumberInputType(result),
                    {value = result})
            end
        end

        return IntermediateInput:new(InputOpcode.OP_SUBTRACT, InputType.NUMBER, {
            left = num1,
            right = num2
        })

    elseif opcode == "operator_multiply" then
        local num1 = generator:descendInputOfBlock(block, "NUM1"):toType(InputType.NUMBER)
        local num2 = generator:descendInputOfBlock(block, "NUM2"):toType(InputType.NUMBER)

        -- Constant folding
        if num1.opcode == InputOpcode.CONSTANT and num2.opcode == InputOpcode.CONSTANT then
            local val1 = num1.inputs.value
            local val2 = num2.inputs.value
            if type(val1) == "number" and type(val2) == "number" then
                local result = val1 * val2
                return IntermediateInput:new(InputOpcode.CONSTANT,
                    IntermediateInput.getNumberInputType(result),
                    {value = result})
            end
        end

        return IntermediateInput:new(InputOpcode.OP_MULTIPLY, InputType.NUMBER, {
            left = num1,
            right = num2
        })

    elseif opcode == "operator_divide" then
        local num1 = generator:descendInputOfBlock(block, "NUM1"):toType(InputType.NUMBER)
        local num2 = generator:descendInputOfBlock(block, "NUM2"):toType(InputType.NUMBER)

        -- Constant folding
        if num1.opcode == InputOpcode.CONSTANT and num2.opcode == InputOpcode.CONSTANT then
            local val1 = num1.inputs.value
            local val2 = num2.inputs.value
            if type(val1) == "number" and type(val2) == "number" then
                local result = val1 / val2
                return IntermediateInput:new(InputOpcode.CONSTANT,
                    IntermediateInput.getNumberInputType(result),
                    {value = result})
            end
        end

        return IntermediateInput:new(InputOpcode.OP_DIVIDE, InputType.NUMBER, {
            left = num1,
            right = num2
        })

    elseif opcode == "operator_random" then
        local from = generator:descendInputOfBlock(block, "FROM"):toType(InputType.NUMBER)
        local to = generator:descendInputOfBlock(block, "TO"):toType(InputType.NUMBER)
        return IntermediateInput:new(InputOpcode.OP_RANDOM, InputType.NUMBER, {
            from = from,
            to = to
        })

    elseif opcode == "operator_gt" then
        local operand1 = generator:descendInputOfBlock(block, "OPERAND1")
        local operand2 = generator:descendInputOfBlock(block, "OPERAND2")

        -- Constant folding for comparison (only for numeric constants)
        -- CRITICAL: Don't fold string comparisons as Scratch uses special comparison rules
        if operand1.opcode == InputOpcode.CONSTANT and operand2.opcode == InputOpcode.CONSTANT then
            local val1 = operand1.inputs.value
            local val2 = operand2.inputs.value
            -- Only fold if both are numbers (not strings)
            if type(val1) == "number" and type(val2) == "number" then
                local result = val1 > val2
                return IntermediateInput:new(InputOpcode.CONSTANT, InputType.BOOLEAN, {value = result})
            end
        end

        return IntermediateInput:new(InputOpcode.OP_GREATER, InputType.BOOLEAN, {
            left = operand1,
            right = operand2
        })

    elseif opcode == "operator_lt" then
        local operand1 = generator:descendInputOfBlock(block, "OPERAND1")
        local operand2 = generator:descendInputOfBlock(block, "OPERAND2")

        -- Constant folding for comparison (only for numeric constants)
        if operand1.opcode == InputOpcode.CONSTANT and operand2.opcode == InputOpcode.CONSTANT then
            local val1 = operand1.inputs.value
            local val2 = operand2.inputs.value
            -- Only fold if both are numbers (not strings)
            if type(val1) == "number" and type(val2) == "number" then
                local result = val1 < val2
                return IntermediateInput:new(InputOpcode.CONSTANT, InputType.BOOLEAN, {value = result})
            end
        end

        return IntermediateInput:new(InputOpcode.OP_LESS, InputType.BOOLEAN, {
            left = operand1,
            right = operand2
        })

    elseif opcode == "operator_equals" then
        local operand1 = generator:descendInputOfBlock(block, "OPERAND1")
        local operand2 = generator:descendInputOfBlock(block, "OPERAND2")

        -- Constant folding for equality (uses Scratch compare semantics)
        if operand1.opcode == InputOpcode.CONSTANT and operand2.opcode == InputOpcode.CONSTANT then
            local cast = require("utils.cast")
            local result = cast.compare(operand1.inputs.value, operand2.inputs.value) == 0
            return IntermediateInput:new(InputOpcode.CONSTANT, InputType.BOOLEAN, {value = result})
        end

        return IntermediateInput:new(InputOpcode.OP_EQUALS, InputType.BOOLEAN, {
            left = operand1,
            right = operand2
        })

    elseif opcode == "operator_and" then
        local operand1 = generator:descendInputOfBlock(block, "OPERAND1"):toType(InputType.BOOLEAN)
        local operand2 = generator:descendInputOfBlock(block, "OPERAND2"):toType(InputType.BOOLEAN)

        -- Constant folding with short-circuit evaluation
        if operand1.opcode == InputOpcode.CONSTANT then
            local cast = require("utils.cast")
            local val1 = cast.toBoolean(operand1.inputs.value)
            if not val1 then
                -- Short circuit: false && X = false
                return IntermediateInput:new(InputOpcode.CONSTANT, InputType.BOOLEAN, {value = false})
            elseif operand2.opcode == InputOpcode.CONSTANT then
                -- Both constants: true && X = X
                local val2 = cast.toBoolean(operand2.inputs.value)
                return IntermediateInput:new(InputOpcode.CONSTANT, InputType.BOOLEAN, {value = val2})
            end
        end

        return IntermediateInput:new(InputOpcode.OP_AND, InputType.BOOLEAN, {
            left = operand1,
            right = operand2
        })

    elseif opcode == "operator_or" then
        local operand1 = generator:descendInputOfBlock(block, "OPERAND1"):toType(InputType.BOOLEAN)
        local operand2 = generator:descendInputOfBlock(block, "OPERAND2"):toType(InputType.BOOLEAN)

        -- Constant folding with short-circuit evaluation
        if operand1.opcode == InputOpcode.CONSTANT then
            local cast = require("utils.cast")
            local val1 = cast.toBoolean(operand1.inputs.value)
            if val1 then
                -- Short circuit: true || X = true
                return IntermediateInput:new(InputOpcode.CONSTANT, InputType.BOOLEAN, {value = true})
            elseif operand2.opcode == InputOpcode.CONSTANT then
                -- Both constants: false || X = X
                local val2 = cast.toBoolean(operand2.inputs.value)
                return IntermediateInput:new(InputOpcode.CONSTANT, InputType.BOOLEAN, {value = val2})
            end
        end

        return IntermediateInput:new(InputOpcode.OP_OR, InputType.BOOLEAN, {
            left = operand1,
            right = operand2
        })

    elseif opcode == "operator_not" then
        local operand = generator:descendInputOfBlock(block, "OPERAND"):toType(InputType.BOOLEAN)

        -- Constant folding for NOT
        if operand.opcode == InputOpcode.CONSTANT then
            local cast = require("utils.cast")
            local val = cast.toBoolean(operand.inputs.value)
            return IntermediateInput:new(InputOpcode.CONSTANT, InputType.BOOLEAN, {value = not val})
        end

        return IntermediateInput:new(InputOpcode.OP_NOT, InputType.BOOLEAN, {
            operand = operand
        })

    elseif opcode == "operator_join" then
        local string1 = generator:descendInputOfBlock(block, "STRING1"):toType(InputType.STRING)
        local string2 = generator:descendInputOfBlock(block, "STRING2"):toType(InputType.STRING)
        return IntermediateInput:new(InputOpcode.OP_JOIN, InputType.STRING, {
            left = string1,
            right = string2
        })

    elseif opcode == "operator_letter_of" then
        -- NUMBER_INDEX for letter position (integers, infinity, NaN)
        local letter = generator:descendInputOfBlock(block, "LETTER"):toType(InputType.NUMBER_INDEX)
        local string = generator:descendInputOfBlock(block, "STRING"):toType(InputType.STRING)
        return IntermediateInput:new(InputOpcode.OP_LETTER_OF, InputType.STRING, {
            letter = letter,
            string = string
        })

    elseif opcode == "operator_length" then
        local string = generator:descendInputOfBlock(block, "STRING"):toType(InputType.STRING)
        return IntermediateInput:new(InputOpcode.OP_LENGTH, InputType.NUMBER, {
            string = string
        })

    elseif opcode == "operator_contains" then
        local string1 = generator:descendInputOfBlock(block, "STRING1"):toType(InputType.STRING)
        local string2 = generator:descendInputOfBlock(block, "STRING2"):toType(InputType.STRING)
        return IntermediateInput:new(InputOpcode.OP_CONTAINS, InputType.BOOLEAN, {
            string = string1,
            contains = string2
        })

    elseif opcode == "operator_mod" then
        local num1 = generator:descendInputOfBlock(block, "NUM1"):toType(InputType.NUMBER)
        local num2 = generator:descendInputOfBlock(block, "NUM2"):toType(InputType.NUMBER)
        return IntermediateInput:new(InputOpcode.OP_MOD, InputType.NUMBER, {
            left = num1,
            right = num2
        })

    elseif opcode == "operator_round" then
        local num = generator:descendInputOfBlock(block, "NUM"):toType(InputType.NUMBER)
        return IntermediateInput:new(InputOpcode.OP_ROUND, InputType.NUMBER, {
            num = num
        })

    elseif opcode == "operator_mathop" then
        local operator = block.fields and block.fields.OPERATOR and block.fields.OPERATOR.value
        local num = generator:descendInputOfBlock(block, "NUM"):toType(InputType.NUMBER)
        return IntermediateInput:new(InputOpcode.OP_MATHOP, InputType.NUMBER, {
            operator = generator:createConstantInput(operator),
            num = num
        })

    end

    return nil
end

---Generate Lua code for operators input blocks
---@param generator LuaGenerator Generator instance
---@param opcode string Input opcode
---@param inputs table Block inputs
---@return string|nil code Generated Lua expression or nil if not handled
function OperatorsBlockCompiler.generateInput(generator, opcode, inputs)
    local InputOpcode = enums.InputOpcode

    if opcode == InputOpcode.OP_ADD then
        -- Addition - IR already has CAST nodes from toType() calls
        local left = generator:generateInput(inputs.left)
        local right = generator:generateInput(inputs.right)
        return string.format("(%s + %s)", left, right)

    elseif opcode == InputOpcode.OP_SUBTRACT then
        -- Subtraction - Scratch converts to numbers first
        local left = generator:generateInput(inputs.left)
        local right = generator:generateInput(inputs.right)

        -- Try to perform compile-time constant folding
        local leftNum = tonumber(left)
        local rightNum = tonumber(right)
        if leftNum and rightNum then
            local result = leftNum - rightNum
            if result == math.huge then
                return "math.huge"
            elseif result == -math.huge then
                return "(-math.huge)"
            elseif result ~= result then -- NaN check
                return "(0/0)"
            else
                return tostring(result)
            end
        end

        return string.format("(%s - %s)", left, right)

    elseif opcode == InputOpcode.OP_MULTIPLY then
        -- Multiplication - Scratch converts to numbers first
        local left = generator:generateInput(inputs.left)
        local right = generator:generateInput(inputs.right)

        -- Try to perform compile-time constant folding
        local leftNum = tonumber(left)
        local rightNum = tonumber(right)
        if leftNum and rightNum then
            local result = leftNum * rightNum
            if result == math.huge then
                return "math.huge"
            elseif result == -math.huge then
                return "(-math.huge)"
            elseif result ~= result then -- NaN check
                return "(0/0)"
            else
                return tostring(result)
            end
        end

        return string.format("(%s * %s)", left, right)

    elseif opcode == InputOpcode.OP_DIVIDE then
        -- Division - Scratch converts to numbers first
        local left = generator:generateInput(inputs.left)
        local right = generator:generateInput(inputs.right)

        -- Try to perform compile-time constant folding
        local leftNum = tonumber(left)
        local rightNum = tonumber(right)
        if leftNum and rightNum then
            local result = leftNum / rightNum
            if result == math.huge then
                return "math.huge"
            elseif result == -math.huge then
                return "(-math.huge)"
            elseif result ~= result then -- NaN check
                return "(0/0)"
            else
                return tostring(result)
            end
        end

        return string.format("(%s / %s)", left, right)

    elseif opcode == InputOpcode.OP_EQUALS then
        -- Equality comparison
        local left = generator:generateInput(inputs.left)
        local right = generator:generateInput(inputs.right)
        return string.format("cast.compare(%s, %s) == 0", left, right)

    elseif opcode == InputOpcode.OP_GREATER then
        -- Greater than
        local left = generator:generateInput(inputs.left)
        local right = generator:generateInput(inputs.right)
        return string.format("cast.compare(%s, %s) > 0", left, right)

    elseif opcode == InputOpcode.OP_LESS then
        -- Less than
        local left = generator:generateInput(inputs.left)
        local right = generator:generateInput(inputs.right)
        return string.format("cast.compare(%s, %s) < 0", left, right)

    elseif opcode == InputOpcode.OP_AND then
        -- Logical AND
        -- Must use toBoolean to ensure boolean result (Lua's 'and' returns operand value)
        -- Even though operands have CAST_BOOLEAN, result must also be boolean
        local left = generator:generateInput(inputs.left)
        local right = generator:generateInput(inputs.right)
        return string.format("(toBoolean(%s) and toBoolean(%s))", left, right)

    elseif opcode == InputOpcode.OP_OR then
        -- Logical OR
        -- Must use toBoolean to ensure boolean result (Lua's 'or' returns operand value)
        local left = generator:generateInput(inputs.left)
        local right = generator:generateInput(inputs.right)
        return string.format("(toBoolean(%s) or toBoolean(%s))", left, right)

    elseif opcode == InputOpcode.OP_NOT then
        -- Logical NOT - Scratch converts to boolean first
        -- Phase 1: Don't wrap - operand already has CAST_BOOLEAN from toType()
        -- IMPORTANT: Inner parentheses protect comparison operators (not has higher precedence than ==, <, > in Lua)
        -- Example: not (a == b) prevents incorrect parsing as (not a) == b
        local operand = generator:generateInput(inputs.operand)
        return string.format("not (%s)", operand)

    elseif opcode == InputOpcode.OP_RANDOM then
        -- Random number generation - Scratch style
        local from = generator:generateInput(inputs.from)
        local to = generator:generateInput(inputs.to)
        return string.format("cast.random(%s, %s)", from, to)

    elseif opcode == InputOpcode.OP_JOIN then
        -- String join
        local left = generator:generateInput(inputs.left)
        local right = generator:generateInput(inputs.right)
        return string.format("cast.join(%s, %s)", left, right)

    elseif opcode == InputOpcode.OP_LETTER_OF then
        -- Get letter of string
        local letter = generator:generateInput(inputs.letter)
        local string = generator:generateInput(inputs.string)
        return string.format("cast.letterOf(%s, %s)", letter, string)

    elseif opcode == InputOpcode.OP_LENGTH then
        -- String length
        local string = generator:generateInput(inputs.string)
        return string.format("cast.length(%s)", string)

    elseif opcode == InputOpcode.OP_CONTAINS then
        -- String contains
        local string1 = generator:generateInput(inputs.string)
        local string2 = generator:generateInput(inputs.contains)
        return string.format("cast.contains(%s, %s)", string1, string2)

    elseif opcode == InputOpcode.OP_MOD then
        -- Modulo operation - Use Scratch-compatible modulo
        local left = generator:generateInput(inputs.left)
        local right = generator:generateInput(inputs.right)
        return string.format("cast.mod(%s, %s)", left, right)

    elseif opcode == InputOpcode.OP_ROUND then
        -- Round operation - JavaScript Math.round behavior
        local num = generator:generateInput(inputs.num)
        return string.format("math.floor(toNumber(%s) + 0.5)", num)

    elseif opcode == InputOpcode.OP_MATHOP then
        -- Math operation
        local operator = generator:generateInput(inputs.operator)
        local num = generator:generateInput(inputs.num)
        -- Use a function call to handle the operator dynamically
        return string.format(
        "((function(op, n) local num = toNumber(n); local operator = cast.toString(op):lower(); if operator == 'abs' then return math.abs(num) elseif operator == 'floor' then return math.floor(num) elseif operator == 'ceiling' then return math.ceil(num) elseif operator == 'sqrt' then return num < 0 and (0/0) or math.sqrt(num) elseif operator == 'sin' then local result = math.sin(math.rad(num)); return math.abs(result) < 1e-10 and 0 or result elseif operator == 'cos' then local result = math.cos(math.rad(num)); return math.abs(result) < 1e-10 and 0 or result elseif operator == 'tan' then local radians = math.rad(num); return math.abs(math.cos(radians)) < 1e-15 and (math.sin(radians) > 0 and math.huge or -math.huge) or math.tan(radians) elseif operator == 'asin' then return math.deg(math.asin(num)) elseif operator == 'acos' then return math.deg(math.acos(num)) elseif operator == 'atan' then return math.deg(math.atan(num)) elseif operator == 'ln' then return math.log(num) elseif operator == 'log' then return math.log10(num) elseif operator == 'e ^' then return math.exp(num) elseif operator == '10 ^' then return 10 ^ num else return 0 end end)(%s, %s))",
            operator, num)
    end

    return nil
end

return OperatorsBlockCompiler