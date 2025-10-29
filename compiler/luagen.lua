local enums = require("compiler.enums")
local intermediate = require("compiler.intermediate")
local log = require("lib.log")

-- Import block code generators
local MotionBlockCompiler = require("compiler.blocks.motion")
local LooksBlockCompiler = require("compiler.blocks.looks")
local ControlBlockCompiler = require("compiler.blocks.control")
local DataBlockCompiler = require("compiler.blocks.data")
local OperatorsBlockCompiler = require("compiler.blocks.operators")
local EventsBlockCompiler = require("compiler.blocks.events")
local ProceduresBlockCompiler = require("compiler.blocks.procedures")
local SensingBlockCompiler = require("compiler.blocks.sensing")
local SoundBlockCompiler = require("compiler.blocks.sound")
local PenBlockCompiler = require("compiler.blocks.pen")

local InputType = enums.InputType
local StackOpcode = enums.StackOpcode
local InputOpcode = enums.InputOpcode

---@class LuaGenerator
---@field private script IntermediateScript
---@field private ir IntermediateRepresentation
---@field private target Sprite|Stage
---@field private source string Generated Lua source
---@field private isWarp boolean
---@field private isProcedure boolean
---@field private warpTimer boolean
---@field private localVariables table
---@field private indentLevel number
---@field private variableCache table Cache for frequently accessed variables
---@field private variableCacheCounter number Counter for generating unique cache names
---@field private declaredHashVars table Track which hash variables have been declared
---@field private collectedVars table Collect variables during generation for later insertion
---@field private variableDeclarations string Store variable declarations to insert later
---@field private isInHat boolean Whether we're currently processing a Hat block
---@field private scriptEnded boolean Whether script has already terminated (retire called)
local LuaGenerator = {}
LuaGenerator.__index = LuaGenerator

---Create new Lua generator
---@param script IntermediateScript Script to compile
---@param ir IntermediateRepresentation Complete IR
---@param target Sprite|Stage Target sprite/stage
---@return LuaGenerator
function LuaGenerator:new(script, ir, target)
    local generator = setmetatable({}, LuaGenerator)
    generator.script = script
    generator.ir = ir
    generator.target = target
    generator.source = ""
    generator.isWarp = script.isWarp or false
    generator.isProcedure = script.isProcedure or false
    generator.warpTimer = script.warpTimer or false
    generator.isInHat = false     -- Track if we're in a Hat block
    generator.scriptEnded = false -- Track if script has already terminated
    generator.localVariables = {}
    generator.indentLevel = 0
    generator.variableCache = {}
    generator.variableCacheCounter = 0
    generator.declaredHashVars = {}
    generator.collectedVars = {}        -- Collect variables during generation
    generator.variableDeclarations = "" -- Store variable declarations
    return generator
end

---Compile script to Lua function
---@return function compiledFunction Compiled Lua function
---@return string source Generated Lua source
function LuaGenerator:compile(options)
    options = options or {}
    log.debug("Generating Lua code for script")

    -- Store options for use in header/footer generation
    self.options = options

    -- Reset for each compilation
    self.functionHashVars = {}
    self.collectedVars = {}
    self.variableDeclarations = ""

    -- Generate function header and main logic, collecting variables
    self:generateFunctionHeader()

    -- If script starts with a Hat block, always yield once to ensure proper event timing
    if self.script.hasHat and self.script.executableHat then
        self:writeLine("-- Hat block: always yield once for proper event timing")
        self:writeLine("coroutine.yield(\"yield\")")
    end

    if self.script.stack then
        self:generateStack(self.script.stack)
    end

    -- This ensures scripts/procedures terminate correctly
    self:stopScript()

    self:generateFunctionFooter()

    -- Insert collected variable declarations after the header
    self:insertVariableDeclarations()

    -- Compile the generated Lua source
    local compiledFunction, err = load(self.source, "compiled_script", "t")
    if not compiledFunction then
        local errorTitle = "Lua Code Generation Error"
        local errorMessage = "Failed to compile generated Lua code"
        local scriptType = self.isProcedure and "procedure" or "main script"
        local errorDetails = string.format(
            "Script type: %s\n" ..
            "Warp mode: %s\n" ..
            "Source length: %d characters\n\n" ..
            "Compilation error:\n%s\n\n" ..
            "Generated source (first 500 chars):\n%s",
            scriptType,
            tostring(self.isWarp),
            #self.source,
            tostring(err),
            self.source:sub(1, 500)
        )

        if #self.source > 500 then
            errorDetails = errorDetails ..
            string.format("\n\nGenerated source (last 500 chars):\n%s", self.source:sub(-500))
        end

        errorDetails = errorDetails .. "\n\nFull source dump:\n" .. self.source

        log.error("CRITICAL: [LuaGenerator] Failed to compile generated Lua")
        log.error("Compilation error: " .. tostring(err))
        log.error("Source length: " .. tostring(#self.source) .. " characters")
        log.error("Script type: " .. scriptType)
        log.error("Warp mode: " .. tostring(self.isWarp))

        -- Throw detailed error - outer layer will show error dialog
        error(string.format(
            "%s\n\n%s\n\nDetails:\n%s",
            errorTitle,
            errorMessage,
            errorDetails
        ))
    end

    log.info("Lua compilation successful")
    -- log.info("Generated Lua source:\n" .. self.source)
    return compiledFunction, self.source
end

---Generate function header
function LuaGenerator:generateFunctionHeader()
    -- Skip function wrapper if functionBodyOnly is true
    if not self.options.functionBodyOnly then
        if self.isProcedure then
            self:writeLine("return function(runtime, target, thread, ...)")
        else
            self:writeLine("return function(runtime, target, thread)")
        end
    else
        -- For function body only mode, assume runtime, target, thread are already available
    end

    -- Skip require statements and shared variable declarations in functionBodyOnly mode
    -- These are assumed to be provided by the outer closure
    if not self.options.functionBodyOnly then
        self:writeLine("  local Global = require('global')")
        self:writeLine("  local cast = require('utils.cast')")
        self:writeLine("  local BlockHelpers = require('runtime.block_helpers')")
        self:writeLine("")
        self:writeLine("  -- Performance optimizations: cache frequently used functions and objects")
        self:writeLine("  local stage = runtime.stage")
        self:writeLine("  local toNumber = cast.toNumber")
        self:writeLine("  local toNumberOrNaN = cast.toNumberOrNaN")
        self:writeLine("  local toBoolean = cast.toBoolean")
        self:writeLine("  local toString = cast.toString")
    end

    -- For procedures, create argument variables from varargs
    if self.isProcedure then
        self:writeLine("")
        self:writeLine("  -- Setup procedure arguments")
        self:writeLine("  local args = {...}")

        if self.script and self.script.arguments and #self.script.arguments > 0 then
            local defaults = self.script.argumentDefaults or {}
            for index, argName in ipairs(self.script.arguments) do
                self:writeLine(string.format("  local arg_%s = args[%d]", argName, index))
                local defaultValue = defaults[index]
                if defaultValue ~= nil then
                    local literal = self:formatLiteral(defaultValue)
                    self:writeLine(string.format("  if arg_%s == nil then arg_%s = %s end", argName, argName, literal))
                end
            end
        end
    end

    -- Generate local variable cache for performance optimization
    self:generateVariableCache()

    self:writeLine("")
    self:indent()
end

---Format a Lua literal for default values
---@param value any
---@return string literal
function LuaGenerator:formatLiteral(value)
    local valueType = type(value)
    if valueType == "string" then
        return string.format("%q", value)
    elseif valueType == "number" then
        if value == math.huge then
            return "math.huge"
        elseif value == -math.huge then
            return "(-math.huge)"
        elseif value ~= value then
            return "(0/0)"
        else
            return tostring(value)
        end
    elseif valueType == "boolean" then
        return tostring(value)
    elseif value == nil then
        return "nil"
    end

    return "nil"
end

---Generate hash-based variable name from variable ID, name and scope
---@param variableId string Variable ID/hash
---@param originalName string Original variable name (for comment)
---@param scope string Variable scope ("target" or "stage")
---@return string cacheVarName Generated cache variable name
function LuaGenerator:generateCacheVariableName(variableId, originalName, scope)
    -- Create a hash from the variable ID + name + scope for uniqueness
    local combinedString = variableId .. ":" .. originalName .. ":" .. scope
    local hash = 0
    for i = 1, #combinedString do
        hash = ((hash * 31) + string.byte(combinedString, i)) % 0x7FFFFFFF
    end

    -- Generate a Lua-compatible variable name from the hash
    -- Use base36 encoding to get letters and numbers
    local function toBase36(num)
        local chars = "0123456789abcdefghijklmnopqrstuvwxyz"
        if num == 0 then return "0" end
        local result = ""
        while num > 0 do
            result = chars:sub(num % 36 + 1, num % 36 + 1) .. result
            num = math.floor(num / 36)
        end
        return result
    end

    -- Ensure the variable name starts with a letter (Lua requirement)
    local hashName = toBase36(hash)
    return "v" .. hashName -- prefix with 'v' to ensure it starts with a letter
end

---Get or declare a hash variable for a given variable
---@param variable table Variable info with id, name, scope
---@return string hashVarName The hash variable name to use
function LuaGenerator:getHashVariable(variable)
    -- CRITICAL FIX: Use variable ID as cache key instead of scope:name
    -- This ensures the same variable ID always gets the same hash variable,
    -- regardless of how many times it's referenced with different scopes
    local cacheKey = variable.id

    -- Check if we already have a hash variable for this variable ID
    if self.collectedVars[cacheKey] then
        -- Variable already cached, reuse the hash name
        return self.collectedVars[cacheKey].hashName
    end

    -- Create new hash variable name and collect it for later declaration
    local hashName = self:generateCacheVariableName(variable.id, variable.name, variable.scope)

    -- Collect this variable for later declaration at the top
    self.collectedVars[cacheKey] = {
        hashName = hashName,
        variable = variable
    }

    return hashName
end

---Insert variable declarations into the generated source
function LuaGenerator:insertVariableDeclarations()
    if not self.collectedVars or next(self.collectedVars) == nil then
        -- No variables to insert, just remove the placeholder
        self.source = self.source:gsub("  %-%- HASH_VARIABLES_PLACEHOLDER\n", "")
        return
    end

    -- Build the variable declarations section
    local declarations = "  -- Hash variable declarations (generated on-demand)\n"

    -- Sort variables for consistent output
    local sortedVars = {}
    for cacheKey, varData in pairs(self.collectedVars) do
        table.insert(sortedVars, { key = cacheKey, data = varData })
    end
    table.sort(sortedVars, function(a, b) return a.key < b.key end)

    for _, entry in ipairs(sortedVars) do
        local varData = entry.data
        local variable = varData.variable
        local hashName = varData.hashName

        -- Helper function to escape strings for Lua code generation
        local function escapeLuaString(str)
            return str:gsub("\\", "\\\\"):gsub("'", "\\'"):gsub("\n", "\\n"):gsub("\r", "\\r"):gsub("\t", "\\t")
        end

        local escapedId = escapeLuaString(variable.id)
        local escapedName = escapeLuaString(variable.name)

        -- Direct access based on compile-time determined scope
        if variable.scope == "target" then
            declarations = declarations ..
            "  local " .. hashName .. " = target.variables['" .. escapedId .. "']  -- " .. escapedName .. "\n"
        else
            declarations = declarations ..
            "  local " .. hashName .. " = stage.variables['" .. escapedId .. "']  -- " .. escapedName .. "\n"
        end
    end

    -- Simple replacement of placeholder (escape special characters in replacement string)
    declarations = declarations:gsub("%%", "%%%%") -- Escape % characters for gsub replacement
    self.source = self.source:gsub("  %-%- HASH_VARIABLES_PLACEHOLDER\n", declarations)
end

---Generate local variable cache for frequently accessed variables
function LuaGenerator:generateVariableCache()
    -- Analyze script to find frequently accessed variables
    local variableUsage = {}
    self:analyzeVariableUsage(self.script.stack, variableUsage)

    -- Generate local caches for ALL variables (even single-use ones for cleaner code)
    self:writeLine("")
    self:writeLine("  -- Local variable cache for performance (Lua optimization)")

    -- PLACEHOLDER for hash variable declarations (will be replaced later)
    self:writeLine("  -- HASH_VARIABLES_PLACEHOLDER")

    -- Sort variables by usage count (most used first) for better cache locality
    local sortedVars = {}
    for varKey, usage in pairs(variableUsage) do
        table.insert(sortedVars, { key = varKey, usage = usage })
    end
    table.sort(sortedVars, function(a, b) return a.usage.count > b.usage.count end)

    -- Variable declarations are now handled by the collectedVars system in insertVariableDeclarations()
    -- This eliminates duplicate variable declarations
end

---Analyze variable usage in the script
---@param stack IntermediateStack|nil Stack to analyze
---@param usage table Usage tracking table
function LuaGenerator:analyzeVariableUsage(stack, usage)
    if not stack or not stack.blocks then return end

    for _, block in ipairs(stack.blocks) do
        self:analyzeBlockVariableUsage(block, usage)
    end
end

---Analyze variable usage in a single block
---@param block IntermediateStackBlock Block to analyze
---@param usage table Usage tracking table
function LuaGenerator:analyzeBlockVariableUsage(block, usage)
    if not block then return end

    -- Track variables used in the block's inputs
    if block.inputs then
        for _, input in pairs(block.inputs) do
            if type(input) == "table" then
                if input.variable then
                    local var = input.variable
                    local key = var.scope .. ":" .. var.name
                    if not usage[key] then
                        usage[key] = { count = 0, name = var.name, scope = var.scope, id = var.id }
                    end
                    usage[key].count = usage[key].count + 1
                end

                -- Also check for list variables
                if input.list then
                    local list = input.list
                    local key = list.scope .. ":" .. list.name
                    if not usage[key] then
                        usage[key] = { count = 0, name = list.name, scope = list.scope, id = list.id, isList = true }
                    end
                    usage[key].count = usage[key].count + 1
                end

                -- Recursively check nested inputs and substacks
                if input.left then self:analyzeInputVariableUsage(input.left, usage) end
                if input.right then self:analyzeInputVariableUsage(input.right, usage) end
                if input.operand then self:analyzeInputVariableUsage(input.operand, usage) end
                if input.target then self:analyzeInputVariableUsage(input.target, usage) end
                if input.condition then self:analyzeInputVariableUsage(input.condition, usage) end
                if input.whenTrue then self:analyzeVariableUsage(input.whenTrue, usage) end
                if input.whenFalse then self:analyzeVariableUsage(input.whenFalse, usage) end
                if input.do_ then self:analyzeVariableUsage(input.do_, usage) end
            end
        end
    end

    local StackOpcode = require("compiler.enums").StackOpcode
    local opcode = block.opcode
    local inputs = block.inputs or {}

    if opcode == StackOpcode.VAR_SET then
        local variable = inputs.variable
        if variable then
            local key = variable.scope .. ":" .. variable.name
            if not usage[key] then
                usage[key] = { count = 0, name = variable.name, scope = variable.scope, id = variable.id }
            end
            usage[key].count = usage[key].count + 1
        end
    elseif opcode == StackOpcode.LIST_ADD or opcode == StackOpcode.LIST_REPLACE or
        opcode == StackOpcode.LIST_DELETE or opcode == StackOpcode.LIST_INSERT then
        local list = inputs.list
        if list then
            local key = list.scope .. ":" .. list.name
            if not usage[key] then
                usage[key] = { count = 0, name = list.name, scope = list.scope, id = list.id, isList = true }
            end
            usage[key].count = usage[key].count + 1
        end
    end
end

---Analyze variable usage in an input
---@param input IntermediateInput|nil Input to analyze
---@param usage table Usage tracking table
function LuaGenerator:analyzeInputVariableUsage(input, usage)
    if not input or type(input) ~= "table" then return end

    if input.inputs and input.inputs.variable then
        local var = input.inputs.variable
        local key = var.scope .. ":" .. var.name
        if not usage[key] then
            usage[key] = { count = 0, name = var.name, scope = var.scope, id = var.id }
        end
        usage[key].count = usage[key].count + 1
    end

    -- Also check for list variables in nested inputs
    if input.inputs and input.inputs.list then
        local list = input.inputs.list
        local key = list.scope .. ":" .. list.name
        if not usage[key] then
            usage[key] = { count = 0, name = list.name, scope = list.scope, id = list.id, isList = true }
        end
        usage[key].count = usage[key].count + 1
    end

    -- Recursively check nested inputs
    if input.inputs then
        for _, nestedInput in pairs(input.inputs) do
            if type(nestedInput) == "table" then
                self:analyzeInputVariableUsage(nestedInput, usage)
            end
        end
    end
end

---Generate function footer
function LuaGenerator:generateFunctionFooter()
    self:writeLine("")
    -- Skip closing 'end' if functionBodyOnly is true
    if not self.options.functionBodyOnly then
        self:dedent()
        self:writeLine("end")
    end
end

---Generate code for stack of blocks
---@param stack IntermediateStack Stack to generate
function LuaGenerator:generateStack(stack)
    if not stack or not stack.blocks then return end

    for i, block in ipairs(stack.blocks) do
        self:generateStackBlock(block)
        -- Yields are explicitly inserted by control structures (loops, waits, etc.)
    end
end

---Generate code for single stack block
---@param block IntermediateStackBlock Block to generate
function LuaGenerator:generateStackBlock(block)
    local opcode = block.opcode
    local inputs = block.inputs

    self:writeBlockComment(block)

    -- Try modular block generators - all categories
    local generators = {
        MotionBlockCompiler,
        LooksBlockCompiler,
        ControlBlockCompiler,
        DataBlockCompiler,
        EventsBlockCompiler,
        ProceduresBlockCompiler,
        SensingBlockCompiler,
        SoundBlockCompiler,
        PenBlockCompiler
    }

    for _, generator in ipairs(generators) do
        if generator.generateStackBlock and generator.generateStackBlock(self, opcode, inputs, block) then
            return
        end
    end

    -- All opcodes are now handled by modular generators
    log.warn("Unhandled stack opcode: " .. tostring(opcode))
    self:writeLine("-- unhandled: " .. tostring(opcode))
end

---Write a comment annotating the current block with its Scratch block ID
---@param block IntermediateStackBlock|nil Stack block being generated
function LuaGenerator:writeBlockComment(block)
    if not block then
        log.warn("Warning: [LuaGenerator] Attempted to annotate a nil block")
        return
    end

    local blockId = block.blockId
    if not blockId then
        if block.opcode ~= StackOpcode.NOP then
            log.warn("Warning: [LuaGenerator] Missing blockId for opcode: " .. tostring(block.opcode))
        end
        return
    end

    self:writeLine(string.format("-- block %s '%s'", block.opcode, blockId))
end

---Generate code for input expression
---@param input IntermediateInput Input to generate
---@return string code Generated Lua expression
function LuaGenerator:generateInput(input)
    if not input then return "nil" end

    local opcode = input.opcode
    local inputs = input.inputs

    -- Try modular block generators - all categories
    local generators = {
        MotionBlockCompiler,
        LooksBlockCompiler,
        ControlBlockCompiler,
        DataBlockCompiler,
        OperatorsBlockCompiler,
        ProceduresBlockCompiler,
        SensingBlockCompiler,
        SoundBlockCompiler
    }

    for _, generator in ipairs(generators) do
        if generator.generateInput then
            local result = generator.generateInput(self, opcode, inputs)
            if result then return result end
        end
    end

    -- Handle built-in input types (constants, variables, operators)
    if opcode == InputOpcode.CONSTANT then
        -- Constant value
        local value = inputs.value
        if type(value) == "string" then
            -- Properly escape all special characters in Lua string literals
            local escaped = value:gsub("\\", "\\\\") -- Escape backslashes first
                :gsub('"', '\\"')                    -- Escape double quotes
                :gsub("\n", "\\n")                   -- Escape newlines
                :gsub("\r", "\\r")                   -- Escape carriage returns
                :gsub("\t", "\\t")                   -- Escape tabs
            return string.format('"%s"', escaped)
        elseif type(value) == "number" then
            -- Handle special number values properly
            if value == math.huge then
                return "math.huge"
            elseif value == -math.huge then
                return "(-math.huge)"
            elseif value ~= value then -- NaN check
                return "(0/0)"
            else
                return tostring(value)
            end
        elseif type(value) == "boolean" then
            return tostring(value)
        else
            return "nil"
        end
    elseif opcode == InputOpcode.ARG_REF then
        -- Procedure argument reference
        local argName = inputs.argName
        if argName then
            return string.format("arg_%s", argName)
        end
        return "nil"
    elseif opcode == InputOpcode.CAST_NUMBER then
        -- Cast to number (NaN → 0)
        return string.format("toNumber(%s)", self:generateInput(inputs.target))
    elseif opcode == InputOpcode.CAST_NUMBER_OR_NAN then
        -- Cast to number (preserves NaN)
        return string.format("toNumberOrNaN(%s)", self:generateInput(inputs.target))
    elseif opcode == InputOpcode.CAST_STRING then
        -- Cast to string
        return string.format("toString(%s)", self:generateInput(inputs.target))
    elseif opcode == InputOpcode.CAST_BOOLEAN then
        -- Cast to boolean
        return string.format("toBoolean(%s)", self:generateInput(inputs.target))
    else
        log.warn("Unhandled input opcode: " .. tostring(opcode))
        return "nil"
    end
end

---Get a local variable name
---@param prefix string Variable prefix
---@return string varName Generated variable name
function LuaGenerator:getLocalVariable(prefix)
    local counter = self.localVariables[prefix] or 0
    counter = counter + 1
    self.localVariables[prefix] = counter

    if counter == 1 then
        return prefix
    else
        return prefix .. tostring(counter)
    end
end

---Write a line of code with proper indentation
---@param line string Line to write
function LuaGenerator:writeLine(line)
    local indent = string.rep("  ", self.indentLevel)
    self.source = self.source .. indent .. line .. "\n"
end

---Increase indentation level
function LuaGenerator:indent()
    self.indentLevel = self.indentLevel + 1
end

---Decrease indentation level
function LuaGenerator:dedent()
    if self.indentLevel > 0 then
        self.indentLevel = self.indentLevel - 1
    end
end

function LuaGenerator:yieldNotWarp()
    if not self.isWarp then
        self:writeLine("coroutine.yield(\"yield\")")
    end
end

---In warp mode, checks if execution is stuck (taking too long)
---In non-warp mode, always yields
function LuaGenerator:yieldStuckOrNotWarp()
    if self.isWarp then
        -- In warp mode, only yield if stuck (execution taking too long)
        self:writeLine("if runtime:isStuck() then")
        self:indent()
        self:writeLine("coroutine.yield(\"yield\")")
        self:dedent()
        self:writeLine("end")
    else
        -- In non-warp mode, always yield
        self:writeLine("coroutine.yield(\"yield\")")
    end
end

---Uses warpTimer setting if enabled, otherwise uses standard yield
function LuaGenerator:yieldLoop()
    if self.warpTimer then
        -- warpTimer mode: use stuck detection even in warp mode
        self:yieldStuckOrNotWarp()
    else
        -- Standard mode: yield in non-warp only
        self:yieldNotWarp()
    end
end

---After running retire() (sets thread status and cleans up), we need to return to the event loop.
---When in a procedure, return will only send us back to the previous procedure, so instead we yield back to the sequencer.
---Outside of a procedure, return will correctly bring us back to the sequencer.
function LuaGenerator:retire()
    -- Call thread:stop() to mark thread as done
    self:writeLine("thread:stop()")

    if self.isProcedure then
        -- In procedure: yield back to sequencer (return would only go back to caller)
        self:writeLine("coroutine.yield(\"yield\")")
    else
        -- In main script: return to sequencer
        self:writeLine("return")
    end

    -- Mark script as ended to prevent duplicate termination
    self.scriptEnded = true
end

---Called at the end of script generation to ensure proper termination
---@param forceStop boolean|nil If true, always generate stop code even if scriptEnded is set
function LuaGenerator:stopScript(forceStop)
    if self.scriptEnded and not forceStop then
        return
    end

    if self.isProcedure then
        -- In procedure: return empty string (no value)
        self:writeLine('return ""')
    else
        -- In main script: retire
        self:retire()
    end

    -- Mark script as ended
    self.scriptEnded = true
end

---Used by PROCEDURE_RETURN to return a value from procedure or retire from main script
---@param valueCode string Lua code for the return value
function LuaGenerator:stopScriptAndReturn(valueCode)
    if self.isProcedure then
        -- In procedure: return the value
        self:writeLine("return " .. valueCode)
    else
        self:retire()
    end

    -- Mark script as ended
    self.scriptEnded = true
end

---Check if an input is a constant value
---@param input IntermediateInput Input to check
---@return boolean isConstant True if input is a constant
---@return any value The constant value if applicable
function LuaGenerator:isConstantInput(input)
    if not input or type(input) ~= "table" then return false, nil end

    local InputOpcode = require("compiler.enums").InputOpcode
    if input.opcode == InputOpcode.CONSTANT and input.inputs and input.inputs.value ~= nil then
        return true, input.inputs.value
    end

    return false, nil
end

---Check if an input contains a modulo operation
---@param input IntermediateInput Input to check
---@return boolean hasModulo True if input contains a modulo operation
function LuaGenerator:inputContainsModulo(input)
    if not input or type(input) ~= "table" then
        return false
    end

    local InputOpcode = require("compiler.enums").InputOpcode

    -- Check if this input itself is a modulo operation
    if input.opcode == InputOpcode.OP_MOD then
        return true
    end

    -- Recursively check nested inputs
    if input.inputs then
        for _, nestedInput in pairs(input.inputs) do
            if type(nestedInput) == "table" then
                if self:inputContainsModulo(nestedInput) then
                    return true
                end
            end
        end
    end

    return false
end

---Get cached list reference or generate direct access
---@param list table List variable reference
---@return string listRef List reference code
function LuaGenerator:referenceList(list)
    local cacheKey = list.scope .. ":" .. list.name
    local cacheName = self.variableCache[cacheKey]

    if cacheName then
        -- Use cached list object reference
        return cacheName
    else
        -- Use hash variable for direct access
        local hashVarName = self:getHashVariable(list)
        return hashVarName
    end
end

return {
    LuaGenerator = LuaGenerator
}
