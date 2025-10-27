
local enums = require("compiler.enums")
local intermediate = require("compiler.intermediate")
local log = require("lib.log")

local InputType = enums.InputType
local StackOpcode = enums.StackOpcode
local InputOpcode = enums.InputOpcode

---@class TypeState
---@field variables table<string, InputType> Variable type mapping
local TypeState = {}
TypeState.__index = TypeState

---Create new type state
---@return TypeState
function TypeState:new()
    local state = setmetatable({}, TypeState)
    state.variables = {}
    return state
end

---Get variable type
---@param varId string Variable ID
---@return InputType type Variable type
function TypeState:getVariableType(varId)
    local varType = self.variables[varId]
    return varType and type(varType) == "number" and varType or InputType.ANY
end

---Set variable type
---@param varId string Variable ID
---@param inputType InputType Type to set
function TypeState:setVariableType(varId, inputType)
    if varId then
        self.variables[varId] = inputType
    end
end


---Merge with another state (union operation)
---@param other TypeState Other state
---@return boolean modified Whether this state was modified
function TypeState:or_(other)
    local modified = false
    for varId, otherType in pairs(other.variables) do
        local thisType = self.variables[varId] or InputType.ANY
        local newType = bit.bor(thisType, otherType)
        if newType ~= thisType then
            self.variables[varId] = newType
            modified = true
        end
    end
    -- Also check variables only in self
    for varId, thisType in pairs(self.variables) do
        if not other.variables[varId] then
            local newType = bit.bor(thisType, InputType.ANY)
            if newType ~= thisType then
                self.variables[varId] = newType
                modified = true
            end
        end
    end
    return modified
end

---Apply sequential state change
---@param other TypeState State to apply after
---@return boolean modified Whether this state was modified
function TypeState:after(other)
    local modified = false
    for varId, otherType in pairs(other.variables) do
        if otherType and otherType ~= self.variables[varId] then
            self.variables[varId] = otherType
            modified = true
        end
    end
    return modified
end

---Overwrite with another state
---@param other TypeState State to overwrite with
---@return boolean modified Whether this state was modified
function TypeState:overwrite(other)
    local modified = false
    for varId, otherType in pairs(other.variables) do
        if otherType ~= self.variables[varId] then
            self.variables[varId] = otherType
            modified = true
        end
    end
    -- Clear variables not in other
    for varId in pairs(self.variables) do
        if not other.variables[varId] then
            self.variables[varId] = InputType.ANY
            modified = true
        end
    end
    return modified
end

---Clear all variable types
---@return boolean modified Whether state was modified
function TypeState:clear()
    local modified = false
    for varId, varType in pairs(self.variables) do
        if varType ~= InputType.ANY then
            modified = true
            break
        end
    end
    self.variables = {}
    return modified
end

---Clone this state
---@return TypeState clone Cloned state
function TypeState:clone()
    local clone = TypeState:new()
    for varId, varType in pairs(self.variables) do
        clone.variables[varId] = varType
    end
    return clone
end

---@class IROptimizer
---@field private ir IntermediateRepresentation
---@field private ignoreYields boolean
local IROptimizer = {}
IROptimizer.__index = IROptimizer

---Create new IR optimizer
---@param ir IntermediateRepresentation IR to optimize
---@return IROptimizer
function IROptimizer:new(ir)
    local optimizer = setmetatable({}, IROptimizer)
    optimizer.ir = ir
    optimizer.ignoreYields = false
    return optimizer
end

---Optimize the intermediate representation
function IROptimizer:optimize()
    log.debug("Starting IR optimization")
    self:optimizeScript(self.ir.entry, {})
    log.debug("IR optimization complete")
end

---Optimize a single script
---@param script IntermediateScript Script to optimize
---@param alreadyOptimized table<string, boolean> Set of already optimized procedures
function IROptimizer:optimizeScript(script, alreadyOptimized)
    -- Avoid re-optimizing procedures
    if script.isProcedure then
        if alreadyOptimized[script.procedureCode] then
            return
        end
        alreadyOptimized[script.procedureCode] = true
    end

    -- First optimize all depended procedures
    if script.dependedProcedures then
        for _, procVariant in ipairs(script.dependedProcedures) do
            local depProc = self.ir.procedures[procVariant]
            if depProc then
                self:optimizeScript(depProc, alreadyOptimized)
            end
        end
    end

    -- Analyze the script to compute type information
    self.exitState = nil
    local exitState = TypeState:new()
    self:analyzeStack(script.stack, exitState)

    -- Save exit state for this script
    self:addPossibleExitState(exitState)
    script.cachedAnalysisEndState = self.exitState

    -- Now optimize the stack with the computed type information
    self:optimizeStack(script.stack, TypeState:new())
end

---Add possible exit state
---@param state TypeState Exit state to add
function IROptimizer:addPossibleExitState(state)
    if not self.exitState then
        self.exitState = state:clone()
        return
    end

    self.exitState:or_(state)
end

---Optimize a stack
---@param stack IntermediateStack|nil Stack to optimize
---@param state TypeState Current state
function IROptimizer:optimizeStack(stack, state)
    if not stack or not stack.blocks then return end

    for _, stackBlock in ipairs(stack.blocks) do
        -- Update state from entry state
        if stackBlock.entryState then
            state = stackBlock.entryState
        end

        -- Optimize inputs
        for inputKey, input in pairs(stackBlock.inputs) do
            if type(input) == "table" and input.opcode then
                stackBlock.inputs[inputKey] = self:optimizeInput(input, state)
            elseif type(input) == "table" and input.blocks then
                -- Nested stack
                self:optimizeStack(input, state)
            end
        end

        -- Update state from exit state
        if stackBlock.exitState then
            state = stackBlock.exitState
        end
    end
end

---Analyze a stack of blocks
---@param stack IntermediateStack Stack to analyze
---@param state TypeState Current type state
---@return boolean modified Whether analysis resulted in changes
function IROptimizer:analyzeStack(stack, state)
    if not stack or not stack.blocks then return false end

    local modified = false
    for _, stackBlock in ipairs(stack.blocks) do
        local stateChanged = self:analyzeStackBlock(stackBlock, state)

        if not stackBlock.ignoreState then
            -- Clear state after yields
            if stackBlock.yields and not self.ignoreYields then
                stateChanged = state:clear() or stateChanged
            end

            -- Save exit state if state changed
            if stateChanged then
                if stackBlock.exitState then
                    stackBlock.exitState:or_(state)
                else
                    stackBlock.exitState = state:clone()
                end
                modified = true
            end
        end
    end
    return modified
end

---Analyze a single stack block
---@param stackBlock IntermediateStackBlock Block to analyze
---@param state TypeState Current type state
---@return boolean modified Whether analysis resulted in changes
function IROptimizer:analyzeStackBlock(stackBlock, state)
    local inputs = stackBlock.inputs
    local modified = false

    -- Clone state if ignoreState is set
    if stackBlock.ignoreState then
        state = state:clone()
    end

    local opcode = stackBlock.opcode

    -- Handle different stack opcodes
    if opcode == StackOpcode.VAR_SET then
        modified = self:analyzeInputs(inputs, state) or modified
        local variable = inputs.variable
        local value = inputs.value
        if variable and value then
            local changed = (state:getVariableType(variable.id) ~= value.type)
            state:setVariableType(variable.id, value.type)
            modified = changed or modified
        end

    elseif opcode == StackOpcode.CONTROL_WHILE or
           opcode == StackOpcode.CONTROL_FOR or
           opcode == StackOpcode.CONTROL_REPEAT then
        modified = self:analyzeInputs(inputs, state) or modified
        modified = self:analyzeLoopedStack(inputs.do_, state, stackBlock) or modified

    elseif opcode == StackOpcode.CONTROL_IF_ELSE then
        modified = self:analyzeInputs(inputs, state) or modified
        local trueState = state:clone()
        modified = self:analyzeStack(inputs.whenTrue, trueState) or modified
        modified = self:analyzeStack(inputs.whenFalse, state) or modified
        modified = state:or_(trueState) or modified

    elseif opcode == StackOpcode.CONTROL_STOP_SCRIPT then
        modified = self:analyzeInputs(inputs, state) or modified
        self:addPossibleExitState(state)

    elseif opcode == StackOpcode.CONTROL_WAIT_UNTIL then
        modified = state:clear() or modified
        modified = self:analyzeInputs(inputs, state) or modified

    elseif opcode == StackOpcode.PROCEDURE_CALL then
        modified = self:analyzeInputs(inputs, state) or modified
        modified = self:analyzeInputs(inputs.inputs, state) or modified
        local script = self.ir.procedures[inputs.variant]

        if not script or not script.cachedAnalysisEndState then
            modified = state:clear() or modified
        elseif script.yields then
            modified = state:overwrite(script.cachedAnalysisEndState) or modified
        else
            modified = state:after(script.cachedAnalysisEndState) or modified
        end

    elseif opcode == StackOpcode.COMPATIBILITY_LAYER then
        modified = self:analyzeInputs(inputs, state) or modified
        self:analyzeInputs(inputs.inputs, state)
        for substackName, substack in pairs(inputs.substacks) do
            local newState = state:clone()
            modified = self:analyzeStack(substack, newState) or modified
            modified = state:or_(newState) or modified
        end

    else
        modified = self:analyzeInputs(inputs, state) or modified
    end

    return modified
end

---Analyze looped stack (with fixpoint iteration)
---@param stack IntermediateStack Loop body stack
---@param state TypeState Current state
---@param block IntermediateStackBlock Loop block
---@return boolean modified Whether analysis resulted in changes
function IROptimizer:analyzeLoopedStack(stack, state, block)
    if block.yields and not self.ignoreYields then
        -- Yielding loops: conservative analysis
        local modified = state:clear()
        return self:analyzeStack(stack, state) or modified
    end

    -- Non-yielding loops: fixpoint iteration
    local iterations = 0
    local modified = false
    local keepLooping

    repeat
        -- Prevent infinite loops
        if iterations > 10000 then
            local errorTitle = "Compiler Optimization Error"
            local errorMessage = "Infinite loop detected during IR optimization"
            local errorDetails = string.format(
                "Loop analysis exceeded 10000 iterations\n\n" ..
                "Block opcode: %s\n" ..
                "Block yields: %s\n" ..
                "ignoreYields: %s\n" ..
                "Stack blocks count: %s",
                tostring(block.opcode),
                tostring(block.yields),
                tostring(self.ignoreYields),
                (stack.blocks and #stack.blocks or "nil")
            )

            if stack.blocks then
                errorDetails = errorDetails .. "\n\nStack block opcodes:"
                for i, stackBlock in ipairs(stack.blocks) do
                    errorDetails = errorDetails .. string.format("\n  %d: %s", i, tostring(stackBlock.opcode))
                end
            end

            log.error("[IROptimizer] Infinite loop detected in stack analysis")
            log.error(errorDetails)

            -- Throw detailed error - outer layer will show error dialog
            error(string.format(
                "%s\n\n%s\n\nDetails:\n%s",
                errorTitle,
                errorMessage,
                errorDetails
            ))
        end
        iterations = iterations + 1

        -- Analyze loop body
        local newState = state:clone()
        local bodyModified = self:analyzeStack(stack, newState)
        modified = bodyModified or modified

        -- Check convergence
        keepLooping = state:or_(newState)
        modified = keepLooping or modified

        -- Re-analyze inputs with updated state
        local inputModified = self:analyzeInputs(block.inputs, state)
        modified = inputModified or modified

    until not keepLooping

    return modified
end

---Analyze input expressions
---@param inputs table Input table
---@param state TypeState Current state
---@return boolean modified Whether analysis resulted in changes
function IROptimizer:analyzeInputs(inputs, state)
    if not inputs then return false end

    local modified = false
    for _, input in pairs(inputs) do
        if type(input) == "table" and input.opcode then
            local inputModified = self:analyzeInputBlock(input, state)
            modified = inputModified or modified
        end
    end
    return modified
end

---Analyze single input block
---Updates the input's type based on current state
---@param inputBlock IntermediateInput Input to analyze
---@param state TypeState Current state
---@return boolean modified Whether analysis resulted in changes
function IROptimizer:analyzeInputBlock(inputBlock, state)
    local inputs = inputBlock.inputs

    -- First analyze nested inputs
    local modified = self:analyzeInputs(inputs, state)

    -- Get the new type for this input based on current state
    local newType = self:getInputType(inputBlock, state)

    -- Check if type changed
    modified = modified or (newType ~= inputBlock.type)
    inputBlock.type = newType

    -- Handle special opcodes
    local opcode = inputBlock.opcode
    if opcode == InputOpcode.PROCEDURE_CALL then
        modified = self:analyzeInputs(inputs.inputs, state) or modified
        local script = self.ir.procedures[inputs.variant]

        if not script or not script.cachedAnalysisEndState then
            modified = state:clear() or modified
        elseif script.yields then
            modified = state:overwrite(script.cachedAnalysisEndState) or modified
        else
            modified = state:after(script.cachedAnalysisEndState) or modified
        end
    end

    return modified
end

---Get type of input expression
---Default behavior: return input.type (not InputType.ANY)
---@param input IntermediateInput Input to analyze
---@param state TypeState Current type state
---@return InputType type Inferred type
function IROptimizer:getInputType(input, state)
    if not input then return InputType.ANY end

    local opcode = input.opcode
    local inputs = input.inputs

    -- VAR_GET: Get type from state
    if opcode == InputOpcode.VAR_GET then
        local variable = inputs.variable
        if variable then
            return state:getVariableType(variable.id)
        end
        return InputType.ANY

    -- CAST_NUMBER: Number cast optimization
    elseif opcode == InputOpcode.CAST_NUMBER then
        local innerType = inputs.target.type
        if bit.band(innerType, InputType.NUMBER) ~= 0 then
            return innerType
        end
        return InputType.NUMBER

    -- CAST_NUMBER_OR_NAN: Number or NaN cast optimization
    elseif opcode == InputOpcode.CAST_NUMBER_OR_NAN then
        local innerType = inputs.target.type
        if bit.band(innerType, InputType.NUMBER_OR_NAN) ~= 0 then
            return innerType
        end
        return InputType.NUMBER_OR_NAN

    -- OP_ADD: Addition type inference (complex logic)
    elseif opcode == InputOpcode.OP_ADD then
        local leftType = inputs.left.type
        local rightType = inputs.right.type
        return self:getAddType(leftType, rightType)

    -- OP_SUBTRACT: Subtraction type inference
    elseif opcode == InputOpcode.OP_SUBTRACT then
        local leftType = inputs.left.type
        local rightType = inputs.right.type
        return self:getSubtractType(leftType, rightType)

    -- OP_MULTIPLY: Multiplication type inference
    elseif opcode == InputOpcode.OP_MULTIPLY then
        local leftType = inputs.left.type
        local rightType = inputs.right.type
        return self:getMultiplyType(leftType, rightType)

    -- OP_DIVIDE: Division type inference
    elseif opcode == InputOpcode.OP_DIVIDE then
        local leftType = inputs.left.type
        local rightType = inputs.right.type
        return self:getDivideType(leftType, rightType)
    end

    return input.type
end

---Infer type for addition operation
---@param leftType InputType Left operand type
---@param rightType InputType Right operand type
---@return InputType resultType Result type
function IROptimizer:getAddType(leftType, rightType)
    local resultType = 0

    -- 1. NaN detection: Infinity + (-Infinity) = NaN
    if bit.band(leftType, InputType.NUMBER_POS_INF) ~= 0 and
       bit.band(rightType, InputType.NUMBER_NEG_INF) ~= 0 then
        resultType = bit.bor(resultType, InputType.NUMBER_NAN)
    end
    -- (-Infinity) + Infinity = NaN
    if bit.band(leftType, InputType.NUMBER_NEG_INF) ~= 0 and
       bit.band(rightType, InputType.NUMBER_POS_INF) ~= 0 then
        resultType = bit.bor(resultType, InputType.NUMBER_NAN)
    end

    -- 2. Check if result can be fractional
    -- For addition to return non-whole, one input must be non-whole
    local canBeFract = bit.band(leftType, InputType.NUMBER_FRACT) ~= 0 or
                      bit.band(rightType, InputType.NUMBER_FRACT) ~= 0

    -- 3. Positive result: POS + ANY ~= POS, ANY + POS ~= POS
    if bit.band(leftType, InputType.NUMBER_POS) ~= 0 or
       bit.band(rightType, InputType.NUMBER_POS) ~= 0 then
        resultType = bit.bor(resultType, InputType.NUMBER_POS_INT)
        resultType = bit.bor(resultType, InputType.NUMBER_POS_INF)
        if canBeFract then
            resultType = bit.bor(resultType, InputType.NUMBER_POS_FRACT)
        end
    end

    -- 4. Negative result: NEG + ANY ~= NEG, ANY + NEG ~= NEG
    if bit.band(leftType, InputType.NUMBER_NEG) ~= 0 or
       bit.band(rightType, InputType.NUMBER_NEG) ~= 0 then
        resultType = bit.bor(resultType, InputType.NUMBER_NEG_INT)
        resultType = bit.bor(resultType, InputType.NUMBER_NEG_INF)
        if canBeFract then
            resultType = bit.bor(resultType, InputType.NUMBER_NEG_FRACT)
        end
    end

    -- 5. Zero result cases
    -- POS_REAL + NEG_REAL ~= 0 (e.g., 3 + (-3) = 0)
    if (bit.band(leftType, InputType.NUMBER_POS_REAL) ~= 0 and
        bit.band(rightType, InputType.NUMBER_NEG_REAL) ~= 0) or
       (bit.band(leftType, InputType.NUMBER_NEG_REAL) ~= 0 and
        bit.band(rightType, InputType.NUMBER_POS_REAL) ~= 0) then
        resultType = bit.bor(resultType, InputType.NUMBER_ZERO)
    end
    -- 0 + 0 = 0
    if bit.band(leftType, InputType.NUMBER_ZERO) ~= 0 and
       bit.band(rightType, InputType.NUMBER_ZERO) ~= 0 then
        resultType = bit.bor(resultType, InputType.NUMBER_ZERO)
    end
    -- 0 + (-0) = 0
    if bit.band(leftType, InputType.NUMBER_ZERO) ~= 0 and
       bit.band(rightType, InputType.NUMBER_NEG_ZERO) ~= 0 then
        resultType = bit.bor(resultType, InputType.NUMBER_ZERO)
    end
    -- (-0) + 0 = 0
    if bit.band(leftType, InputType.NUMBER_NEG_ZERO) ~= 0 and
       bit.band(rightType, InputType.NUMBER_ZERO) ~= 0 then
        resultType = bit.bor(resultType, InputType.NUMBER_ZERO)
    end

    -- 6. Negative zero result: (-0) + (-0) = -0
    if bit.band(leftType, InputType.NUMBER_NEG_ZERO) ~= 0 and
       bit.band(rightType, InputType.NUMBER_NEG_ZERO) ~= 0 then
        resultType = bit.bor(resultType, InputType.NUMBER_NEG_ZERO)
    end

    return resultType
end

---Infer type for subtraction operation
---@param leftType InputType Left operand type
---@param rightType InputType Right operand type
---@return InputType resultType Result type
function IROptimizer:getSubtractType(leftType, rightType)
    local resultType = 0

    -- 1. NaN detection: Infinity - Infinity = NaN, (-Infinity) - (-Infinity) = NaN
    if bit.band(leftType, InputType.NUMBER_POS_INF) ~= 0 and
       bit.band(rightType, InputType.NUMBER_POS_INF) ~= 0 then
        resultType = bit.bor(resultType, InputType.NUMBER_NAN)
    end
    if bit.band(leftType, InputType.NUMBER_NEG_INF) ~= 0 and
       bit.band(rightType, InputType.NUMBER_NEG_INF) ~= 0 then
        resultType = bit.bor(resultType, InputType.NUMBER_NAN)
    end

    -- 2. Check if result can be fractional
    local canBeFract = bit.band(leftType, InputType.NUMBER_FRACT) ~= 0 or
                      bit.band(rightType, InputType.NUMBER_FRACT) ~= 0

    -- 3. Positive result: POS - ANY ~= POS, ANY - NEG ~= POS
    if bit.band(leftType, InputType.NUMBER_POS) ~= 0 or
       bit.band(rightType, InputType.NUMBER_NEG) ~= 0 then
        resultType = bit.bor(resultType, InputType.NUMBER_POS_INT)
        resultType = bit.bor(resultType, InputType.NUMBER_POS_INF)
        if canBeFract then
            resultType = bit.bor(resultType, InputType.NUMBER_POS_FRACT)
        end
    end

    -- 4. Negative result: NEG - ANY ~= NEG, ANY - POS ~= NEG
    if bit.band(leftType, InputType.NUMBER_NEG) ~= 0 or
       bit.band(rightType, InputType.NUMBER_POS) ~= 0 then
        resultType = bit.bor(resultType, InputType.NUMBER_NEG_INT)
        resultType = bit.bor(resultType, InputType.NUMBER_NEG_INF)
        if canBeFract then
            resultType = bit.bor(resultType, InputType.NUMBER_NEG_FRACT)
        end
    end

    -- 5. Zero result cases
    -- POS_REAL - POS_REAL ~= 0 (e.g., 3 - 3 = 0)
    if bit.band(leftType, InputType.NUMBER_POS_REAL) ~= 0 and
       bit.band(rightType, InputType.NUMBER_POS_REAL) ~= 0 then
        resultType = bit.bor(resultType, InputType.NUMBER_ZERO)
    end
    -- NEG_REAL - NEG_REAL ~= 0 (e.g., -3 - (-3) = 0)
    if bit.band(leftType, InputType.NUMBER_NEG_REAL) ~= 0 and
       bit.band(rightType, InputType.NUMBER_NEG_REAL) ~= 0 then
        resultType = bit.bor(resultType, InputType.NUMBER_ZERO)
    end
    -- 0 - 0 = 0
    if bit.band(leftType, InputType.NUMBER_ZERO) ~= 0 and
       bit.band(rightType, InputType.NUMBER_ZERO) ~= 0 then
        resultType = bit.bor(resultType, InputType.NUMBER_ZERO)
    end
    -- 0 - (-0) = 0
    if bit.band(leftType, InputType.NUMBER_ZERO) ~= 0 and
       bit.band(rightType, InputType.NUMBER_NEG_ZERO) ~= 0 then
        resultType = bit.bor(resultType, InputType.NUMBER_ZERO)
    end
    -- (-0) - (-0) = 0
    if bit.band(leftType, InputType.NUMBER_NEG_ZERO) ~= 0 and
       bit.band(rightType, InputType.NUMBER_NEG_ZERO) ~= 0 then
        resultType = bit.bor(resultType, InputType.NUMBER_ZERO)
    end

    -- 6. Negative zero result: (-0) - 0 = -0
    if bit.band(leftType, InputType.NUMBER_NEG_ZERO) ~= 0 and
       bit.band(rightType, InputType.NUMBER_ZERO) ~= 0 then
        resultType = bit.bor(resultType, InputType.NUMBER_NEG_ZERO)
    end

    return resultType
end

---Infer type for multiplication operation
---@param leftType InputType Left operand type
---@param rightType InputType Right operand type
---@return InputType resultType Result type
function IROptimizer:getMultiplyType(leftType, rightType)
    local resultType = 0

    -- 1. NaN detection: 0 × Infinity = NaN
    if (bit.band(leftType, InputType.NUMBER_ANY_ZERO) ~= 0 and
        bit.band(rightType, InputType.NUMBER_INF) ~= 0) or
       (bit.band(leftType, InputType.NUMBER_INF) ~= 0 and
        bit.band(rightType, InputType.NUMBER_ANY_ZERO) ~= 0) then
        resultType = bit.bor(resultType, InputType.NUMBER_NAN)
    end

    -- 2. Check if result can be fractional
    local canBeFract = bit.band(leftType, InputType.NUMBER_FRACT) ~= 0 or
                      bit.band(rightType, InputType.NUMBER_FRACT) ~= 0

    -- 3. Positive result: (POS × POS) or (NEG × NEG)
    if (bit.band(leftType, InputType.NUMBER_POS) ~= 0 and
        bit.band(rightType, InputType.NUMBER_POS) ~= 0) or
       (bit.band(leftType, InputType.NUMBER_NEG) ~= 0 and
        bit.band(rightType, InputType.NUMBER_NEG) ~= 0) then
        resultType = bit.bor(resultType, InputType.NUMBER_POS_INT)
        resultType = bit.bor(resultType, InputType.NUMBER_POS_INF)
        if canBeFract then
            resultType = bit.bor(resultType, InputType.NUMBER_POS_FRACT)
        end
    end

    -- 4. Negative result: (POS × NEG) or (NEG × POS)
    if (bit.band(leftType, InputType.NUMBER_POS) ~= 0 and
        bit.band(rightType, InputType.NUMBER_NEG) ~= 0) or
       (bit.band(leftType, InputType.NUMBER_NEG) ~= 0 and
        bit.band(rightType, InputType.NUMBER_POS) ~= 0) then
        resultType = bit.bor(resultType, InputType.NUMBER_NEG_INT)
        resultType = bit.bor(resultType, InputType.NUMBER_NEG_INF)
        if canBeFract then
            resultType = bit.bor(resultType, InputType.NUMBER_NEG_FRACT)
        end
    end

    -- 5. Zero result: X × 0 = 0
    if bit.band(leftType, InputType.NUMBER_ZERO) ~= 0 or
       bit.band(rightType, InputType.NUMBER_ZERO) ~= 0 then
        resultType = bit.bor(resultType, InputType.NUMBER_ZERO)
    end

    -- 6. Negative zero result: (POS × -0) or (-0 × POS) = -0
    --                          (NEG × 0) or (0 × NEG) = -0
    if (bit.band(leftType, InputType.NUMBER_POS) ~= 0 and
        bit.band(rightType, InputType.NUMBER_NEG_ZERO) ~= 0) or
       (bit.band(leftType, InputType.NUMBER_NEG_ZERO) ~= 0 and
        bit.band(rightType, InputType.NUMBER_POS) ~= 0) or
       (bit.band(leftType, InputType.NUMBER_NEG) ~= 0 and
        bit.band(rightType, InputType.NUMBER_ZERO) ~= 0) or
       (bit.band(leftType, InputType.NUMBER_ZERO) ~= 0 and
        bit.band(rightType, InputType.NUMBER_NEG) ~= 0) then
        resultType = bit.bor(resultType, InputType.NUMBER_NEG_ZERO)
    end

    return resultType
end

---Infer type for division operation
---@param leftType InputType Left operand type
---@param rightType InputType Right operand type
---@return InputType resultType Result type
function IROptimizer:getDivideType(leftType, rightType)
    local resultType = 0

    -- 1. NaN detection: 0 / 0 = NaN, Infinity / Infinity = NaN
    if bit.band(leftType, InputType.NUMBER_ANY_ZERO) ~= 0 and
       bit.band(rightType, InputType.NUMBER_ANY_ZERO) ~= 0 then
        resultType = bit.bor(resultType, InputType.NUMBER_NAN)
    end
    if bit.band(leftType, InputType.NUMBER_INF) ~= 0 and
       bit.band(rightType, InputType.NUMBER_INF) ~= 0 then
        resultType = bit.bor(resultType, InputType.NUMBER_NAN)
    end

    -- 2. Division always can be fractional (except special cases)
    local canBeFract = true

    -- 3. Positive Infinity: (POS / 0) or (POS_INF / POS_REAL) or (NEG_INF / NEG_REAL)
    if (bit.band(leftType, InputType.NUMBER_POS) ~= 0 and
        bit.band(rightType, InputType.NUMBER_ZERO) ~= 0) or
       (bit.band(leftType, InputType.NUMBER_POS_INF) ~= 0 and
        bit.band(rightType, InputType.NUMBER_POS_REAL) ~= 0) or
       (bit.band(leftType, InputType.NUMBER_NEG_INF) ~= 0 and
        bit.band(rightType, InputType.NUMBER_NEG_REAL) ~= 0) then
        resultType = bit.bor(resultType, InputType.NUMBER_POS_INF)
    end

    -- 4. Negative Infinity: (NEG / 0) or (NEG_INF / POS_REAL) or (POS_INF / NEG_REAL)
    if (bit.band(leftType, InputType.NUMBER_NEG) ~= 0 and
        bit.band(rightType, InputType.NUMBER_ZERO) ~= 0) or
       (bit.band(leftType, InputType.NUMBER_NEG_INF) ~= 0 and
        bit.band(rightType, InputType.NUMBER_POS_REAL) ~= 0) or
       (bit.band(leftType, InputType.NUMBER_POS_INF) ~= 0 and
        bit.band(rightType, InputType.NUMBER_NEG_REAL) ~= 0) then
        resultType = bit.bor(resultType, InputType.NUMBER_NEG_INF)
    end

    -- 5. Positive result: (POS / POS) or (NEG / NEG)
    if (bit.band(leftType, InputType.NUMBER_POS) ~= 0 and
        bit.band(rightType, InputType.NUMBER_POS) ~= 0) or
       (bit.band(leftType, InputType.NUMBER_NEG) ~= 0 and
        bit.band(rightType, InputType.NUMBER_NEG) ~= 0) then
        resultType = bit.bor(resultType, InputType.NUMBER_POS_INT)
        if canBeFract then
            resultType = bit.bor(resultType, InputType.NUMBER_POS_FRACT)
        end
    end

    -- 6. Negative result: (POS / NEG) or (NEG / POS)
    if (bit.band(leftType, InputType.NUMBER_POS) ~= 0 and
        bit.band(rightType, InputType.NUMBER_NEG) ~= 0) or
       (bit.band(leftType, InputType.NUMBER_NEG) ~= 0 and
        bit.band(rightType, InputType.NUMBER_POS) ~= 0) then
        resultType = bit.bor(resultType, InputType.NUMBER_NEG_INT)
        if canBeFract then
            resultType = bit.bor(resultType, InputType.NUMBER_NEG_FRACT)
        end
    end

    -- 7. Zero result: 0 / X = 0 (where X != 0)
    if bit.band(leftType, InputType.NUMBER_ZERO) ~= 0 then
        resultType = bit.bor(resultType, InputType.NUMBER_ZERO)
    end

    -- 8. Negative zero result: (-0 / POS) or (0 / NEG)
    if (bit.band(leftType, InputType.NUMBER_NEG_ZERO) ~= 0 and
        bit.band(rightType, InputType.NUMBER_POS) ~= 0) or
       (bit.band(leftType, InputType.NUMBER_ZERO) ~= 0 and
        bit.band(rightType, InputType.NUMBER_NEG) ~= 0) then
        resultType = bit.bor(resultType, InputType.NUMBER_NEG_ZERO)
    end

    return resultType
end

---Optimize input expression
---@param input IntermediateInput Input to optimize
---@param state TypeState Current state
---@return IntermediateInput optimized Optimized input
function IROptimizer:optimizeInput(input, state)
    if not input then return input end

    -- Recursively optimize nested inputs first
    for inputKey, inputInput in pairs(input.inputs) do
        if type(inputInput) == "table" and inputInput.opcode then
            input.inputs[inputKey] = self:optimizeInput(inputInput, state)
        end
    end

    local opcode = input.opcode

    -- Remove unnecessary CAST_NUMBER
    if opcode == InputOpcode.CAST_NUMBER then
        local targetType = input.inputs.target.type
        -- If target is already NUMBER, remove cast
        if bit.band(targetType, InputType.NUMBER) == targetType then
            return input.inputs.target
        end
        return input

    -- Remove unnecessary CAST_NUMBER_OR_NAN
    elseif opcode == InputOpcode.CAST_NUMBER_OR_NAN then
        local targetType = input.inputs.target.type
        -- If target is already NUMBER_OR_NAN, remove cast
        if bit.band(targetType, InputType.NUMBER_OR_NAN) == targetType then
            return input.inputs.target
        end
        return input
    end

    return input
end

return {
    IROptimizer = IROptimizer,
    TypeState = TypeState
}