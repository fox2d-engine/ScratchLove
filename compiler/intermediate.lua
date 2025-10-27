
local enums = require("compiler.enums")
local InputType = enums.InputType
local InputOpcode = enums.InputOpcode
local cast = require("utils.cast")

---@class IntermediateStackBlock
---@field opcode StackOpcode Block operation type
---@field inputs table Block inputs
---@field yields boolean Whether block causes a yield
---@field ignoreState boolean Should state changes be ignored (testing)
---@field entryState TypeState|nil Type state when entering
---@field exitState TypeState|nil Type state when exiting
---@field blockId string|nil Original Scratch block ID for unique state keys
local IntermediateStackBlock = {}
IntermediateStackBlock.__index = IntermediateStackBlock

---Create a new stack block
---@param opcode StackOpcode The block operation
---@param inputs table? Block inputs
---@param yields boolean? Whether the block yields
---@param blockId string? Original Scratch block ID
---@return IntermediateStackBlock
    function IntermediateStackBlock:new(opcode, inputs, yields, blockId)
    local block = setmetatable({}, IntermediateStackBlock)
    block.opcode = opcode or ""
    block.inputs = inputs or {}
    block.yields = yields or false
    block.blockId = blockId
    block.ignoreState = false
    block.entryState = nil
    block.exitState = nil
    return block
end

---@class IntermediateInput
---@field opcode InputOpcode Operation type
---@field type InputType Type information
---@field inputs table Nested inputs
---@field yields boolean Whether input causes yield
local IntermediateInput = {}
IntermediateInput.__index = IntermediateInput

---Get type for a number value with IEEE 754 precision
---@param number number The number to analyze
---@return InputType type The precise type
function IntermediateInput.getNumberInputType(number)
    if type(number) ~= "number" then
        error("Expected a number")
    end

    -- 1. Special numbers (Infinity, NaN)
    if number == math.huge then
        return InputType.NUMBER_POS_INF
    end
    if number == -math.huge then
        return InputType.NUMBER_NEG_INF
    end
    if number ~= number then
        return InputType.NUMBER_NAN -- NaN check: NaN ~= NaN
    end

    -- 2. Zero detection with IEEE 754 negative zero support
    if number == 0 then
        -- IEEE 754 negative zero detection: 1/0 = +Infinity, 1/(-0) = -Infinity
        -- Note: LuaJIT supports IEEE 754 negative zero
        local inverse = 1 / number
        if inverse == math.huge then
            return InputType.NUMBER_ZERO      -- positive zero
        elseif inverse == -math.huge then
            return InputType.NUMBER_NEG_ZERO  -- negative zero
        else
            -- Fallback if division by zero returns unexpected value
            return InputType.NUMBER_ZERO
        end
    end

    -- 3. Positive numbers
    if number > 0 then
        if math.floor(number) == number then
            return InputType.NUMBER_POS_INT   -- positive integer
        else
            return InputType.NUMBER_POS_FRACT -- positive fraction
        end
    end

    -- 4. Negative numbers
    -- (number < 0, already ruled out zero, infinity, and NaN)
    if math.floor(number) == number then
        return InputType.NUMBER_NEG_INT   -- negative integer
    else
        return InputType.NUMBER_NEG_FRACT -- negative fraction
    end
end

---Create a new input
---@param opcode InputOpcode The operation
---@param inputType InputType? Type information
---@param inputs table? Nested inputs
---@param yields boolean? Whether input yields
---@return IntermediateInput
function IntermediateInput:new(opcode, inputType, inputs, yields)
    local input = setmetatable({}, IntermediateInput)
    input.opcode = opcode or InputOpcode.CONSTANT
    input.type = inputType or InputType.ANY
    input.inputs = inputs or {}
    input.yields = yields or false
    return input
end

---Check if this input is a constant with specific value
---@param value any The value to check
---@return boolean isConstant True if constant with this value
function IntermediateInput:isConstant(value)
    if self.opcode ~= InputOpcode.CONSTANT then return false end
    local equal = self.inputs.value == value
    if not equal and type(value) == "number" then
        equal = tonumber(self.inputs.value) == value
    end
    return equal
end

---Check if type is guaranteed to always be the given type
---@param inputType InputType Type to check
---@return boolean isAlways True if always this type
function IntermediateInput:isAlwaysType(inputType)
    return bit.band(self.type, inputType) == self.type
end

---Check if type can sometimes be the given type
---@param inputType InputType Type to check
---@return boolean isSometimes True if sometimes this type
function IntermediateInput:isSometimesType(inputType)
    return bit.band(self.type, inputType) ~= 0
end

---Convert input to target type with casting
---@param targetType InputType Target type
---@return IntermediateInput input Input with new type
function IntermediateInput:toType(targetType)
    local castOpcode

    -- Select appropriate cast opcode
    if targetType == InputType.BOOLEAN or targetType == InputType.BOOLEAN_INTERPRETABLE then
        castOpcode = InputOpcode.CAST_BOOLEAN
        targetType = InputType.BOOLEAN
    elseif targetType == InputType.NUMBER then
        castOpcode = InputOpcode.CAST_NUMBER
    elseif targetType == InputType.NUMBER_OR_NAN or targetType == InputType.NUMBER_INTERPRETABLE then
        castOpcode = InputOpcode.CAST_NUMBER_OR_NAN
        targetType = InputType.NUMBER_OR_NAN
    elseif targetType == InputType.STRING then
        castOpcode = InputOpcode.CAST_STRING
    elseif targetType == InputType.COLOR then
        -- COLOR type doesn't need casting, return as-is
        return self
    else
        -- For specific number subtypes, use NUMBER cast
        if bit.band(targetType, InputType.NUMBER_OR_NAN) == targetType then
            castOpcode = InputOpcode.CAST_NUMBER_OR_NAN
        else
            error("Cannot cast to type: " .. tostring(targetType))
        end
    end

    -- If already correct type, return as-is (optimization)
    if self:isAlwaysType(targetType) then
        return self
    end

    -- For constants, perform cast at compile time (constant folding)
    if self.opcode == InputOpcode.CONSTANT then
        local newInput = IntermediateInput:new(InputOpcode.CONSTANT, targetType, {})

        if castOpcode == InputOpcode.CAST_BOOLEAN then
            newInput.inputs.value = cast.toBoolean(self.inputs.value)
            newInput.type = InputType.BOOLEAN
        elseif castOpcode == InputOpcode.CAST_NUMBER or castOpcode == InputOpcode.CAST_NUMBER_OR_NAN then
            local numValue = cast.toNumber(self.inputs.value)
            newInput.inputs.value = numValue
            newInput.type = IntermediateInput.getNumberInputType(numValue)
        elseif castOpcode == InputOpcode.CAST_STRING then
            newInput.inputs.value = cast.toString(self.inputs.value)
            newInput.type = InputType.STRING
        end

        return newInput
    end

    -- For non-constants, create runtime cast
    return IntermediateInput:new(castOpcode, targetType, {target = self})
end

---@class IntermediateStack
---@field blocks IntermediateStackBlock[] Array of stack blocks
local IntermediateStack = {}
IntermediateStack.__index = IntermediateStack

---Create a new stack
---@return IntermediateStack
function IntermediateStack:new()
    local stack = setmetatable({}, IntermediateStack)
    stack.blocks = {}
    return stack
end

---@class IntermediateScript
---@field stack IntermediateStack|nil Instruction stack
---@field procedureCode string|nil Procedure code
---@field arguments string[] Argument list
---@field argumentDefaults table<number, any> Argument default values
---@field yields boolean Whether script yields
---@field warpTimer boolean Whether to use warp timer
---@field hasHat boolean Whether script starts with a Hat block (for yield behavior)
---@field dependedProcedures table<string, any> Procedures this script depends on
---@field cachedCompileResult {chunk:function, source:string}|nil Cached compile result
---@field isWarp boolean Whether script runs in warp mode
---@field isProcedure boolean Whether this is a procedure
---@field executableHat boolean Whether hat is executable
local IntermediateScript = {}
IntermediateScript.__index = IntermediateScript

---Create a new script
---@return IntermediateScript
function IntermediateScript:new()
    local script = setmetatable({}, IntermediateScript)
    script.stack = nil
    script.procedureCode = nil
    script.arguments = {}
    script.argumentDefaults = {}
    script.yields = false
    script.warpTimer = false
    script.hasHat = false  -- Whether script starts with a Hat block
    script.dependedProcedures = {}
    script.cachedCompileResult = nil
    script.isWarp = false
    script.isProcedure = false
    script.executableHat = false
    return script
end

---@class IntermediateRepresentation
---@field entry IntermediateScript Main script
---@field procedures table<string, IntermediateScript> Procedure map
local IntermediateRepresentation = {}
IntermediateRepresentation.__index = IntermediateRepresentation

---Create a new IR
---@param entry IntermediateScript Main script
---@param procedures table<string, IntermediateScript> Procedures
---@return IntermediateRepresentation
function IntermediateRepresentation:new(entry, procedures)
    local ir = setmetatable({}, IntermediateRepresentation)
    ir.entry = entry
    ir.procedures = procedures or {}
    return ir
end

return {
    IntermediateStackBlock = IntermediateStackBlock,
    IntermediateInput = IntermediateInput,
    IntermediateStack = IntermediateStack,
    IntermediateScript = IntermediateScript,
    IntermediateRepresentation = IntermediateRepresentation
}
