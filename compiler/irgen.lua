
local enums = require("compiler.enums")
local intermediate = require("compiler.intermediate")
local blockCompilers = require("compiler.blocks.init")
local cast = require("utils.cast")
local log = require("lib.log")
local json = require("lib.json")

local InputType = enums.InputType
local StackOpcode = enums.StackOpcode
local InputOpcode = enums.InputOpcode
local IntermediateStackBlock = intermediate.IntermediateStackBlock
local IntermediateInput = intermediate.IntermediateInput
local IntermediateStack = intermediate.IntermediateStack
local IntermediateScript = intermediate.IntermediateScript
local IntermediateRepresentation = intermediate.IntermediateRepresentation

local SCALAR_TYPE = ""
local LIST_TYPE = "list"

---Generate procedure variant identifier
---@param code string Procedure code
---@param warp boolean Whether warp enabled
---@return string variant Variant identifier
local function generateProcedureVariant(code, warp)
    if warp then
        return "W" .. code
    end
    return "Z" .. code
end

---Parse procedure code from variant
---@param variant string Variant from generateProcedureVariant
---@return string code Original procedure code
local function parseProcedureCode(variant)
    return variant:sub(2)
end

---Parse warp flag from variant
---@param variant string Variant from generateProcedureVariant
---@return boolean isWarp True if warp enabled
local function parseIsWarp(variant)
    return variant:sub(1, 1) == "W"
end

---@class ScriptTreeGenerator
---@field private thread Thread
---@field private target Sprite|Stage
---@field private blocks table
---@field private runtime Runtime
---@field script IntermediateScript
---@field private variableCache table<string, table>
---@field private usesTimer boolean
---@field private namesOfCostumesAndSounds table<string, boolean>
---@field private argumentNameMap table<string, string>
---@field private argumentNamesUsed table<string, boolean>
---@field private procedureDefinitionCache table<string, {definitionId: string, isWarp: boolean}>
local ScriptTreeGenerator = {}
ScriptTreeGenerator.__index = ScriptTreeGenerator

---Create new script tree generator
---@param thread Thread The thread to generate IR for
---@param procedureDefinitionCache table<string, {definitionId: string, isWarp: boolean}>|nil Optional shared cache
---@return ScriptTreeGenerator
function ScriptTreeGenerator:new(thread, procedureDefinitionCache)
    local generator = setmetatable({}, ScriptTreeGenerator)
    generator.thread = thread
    generator.target = thread.target
    generator.blocks = thread.blockContainer or {}
    generator.runtime = thread.target.runtime

    generator.script = IntermediateScript:new()
    generator.script.warpTimer = generator.runtime.compilerOptions.warpTimer or false

    generator.variableCache = {}
    generator.usesTimer = false
    generator.namesOfCostumesAndSounds = {}
    generator.argumentNameMap = {}
    generator.argumentNamesUsed = {}
    generator.script.argumentDefaults = {}

    -- Use shared procedure definition cache if provided (from IRGenerator)
    -- This avoids rebuilding the cache for every ScriptTreeGenerator instance
    generator.procedureDefinitionCache = procedureDefinitionCache or {}

    -- Cache costume and sound names for optimization
    for _, target in ipairs(generator.runtime.targets) do
        if not target.isClone then
            if target.costumes then
                for _, costume in ipairs(target.costumes) do
                    generator.namesOfCostumesAndSounds[costume.name] = true
                end
            end
            if target.sounds then
                for _, sound in ipairs(target.sounds) do
                    generator.namesOfCostumesAndSounds[sound.name] = true
                end
            end
        end
    end

    return generator
end

---Normalize procedure argument name into a Lua identifier
---@param name string
---@return string normalized
function ScriptTreeGenerator:sanitizeArgumentName(name)
    if type(name) ~= "string" then
        return "arg"
    end

    local sanitized = name:gsub("%s+", "_")
    sanitized = sanitized:gsub("[^%w_]", "_")
    if sanitized == "" or sanitized == "_" then
        sanitized = "arg"
    end

    if sanitized:match("^[0-9]") then
        sanitized = "_" .. sanitized
    end

    return sanitized
end

---Register a procedure argument by original name
---@param rawName string
---@param defaultValue any
---@return string argName
function ScriptTreeGenerator:registerArgument(rawName, defaultValue)
    local key = tostring(rawName or "arg")
    local baseName = self:sanitizeArgumentName(key)
    local uniqueName = baseName
    local suffix = 2

    while self.argumentNamesUsed[uniqueName] do
        uniqueName = baseName .. "_" .. suffix
        suffix = suffix + 1
    end

    self.argumentNameMap[key] = uniqueName
    self.argumentNamesUsed[uniqueName] = true
    table.insert(self.script.arguments, uniqueName)
    self.script.argumentDefaults[#self.script.arguments] = defaultValue

    return uniqueName
end

---Get a registered argument name, registering if necessary
---@param rawName string
---@return string argName
function ScriptTreeGenerator:getArgumentName(rawName)
    local key = tostring(rawName or "arg")
    if self.argumentNameMap[key] then
        return self.argumentNameMap[key]
    end
    return self:registerArgument(key, nil)
end

---Prepare procedure arguments from definition block
---@param definitionId string|nil
---@param blocks table<string, table>|nil
function ScriptTreeGenerator:prepareProcedureArguments(definitionId, blocks)
    if not definitionId then
        return
    end

    local blockMap = blocks or self.blocks
    local definition = blockMap and blockMap[definitionId] or nil
    if not definition or not definition.inputs or not definition.inputs.custom_block then
        return
    end

    local customBlock = definition.inputs.custom_block
    local prototypeId = customBlock.value or customBlock.block
    if not prototypeId then
        return
    end

    local prototype = blockMap[prototypeId]
    if not prototype or not prototype.mutation then
        return
    end

    local rawNames = prototype.mutation.argumentnames
    local decodedNames
    if type(rawNames) == "string" then
        local ok, value = pcall(json.decode, rawNames)
        if ok and type(value) == "table" then
            decodedNames = value
        elseif not ok then
            log.warn("Failed to decode procedure argument names JSON: " .. tostring(value))
        else
            log.warn("Procedure argument names decoded but not a table: " .. tostring(type(value)))
        end
    elseif type(rawNames) == "table" then
        decodedNames = rawNames
    end

    local rawDefaults = prototype.mutation.argumentdefaults
    local decodedDefaults
    if type(rawDefaults) == "string" then
        local ok, value = pcall(json.decode, rawDefaults)
        if ok and type(value) == "table" then
            decodedDefaults = value
        elseif not ok then
            log.warn("Failed to decode procedure argument defaults JSON: " .. tostring(value))
        else
            log.warn("Procedure argument defaults decoded but not a table: " .. tostring(type(value)))
        end
    elseif type(rawDefaults) == "table" then
        decodedDefaults = rawDefaults
    end

    if not decodedNames or #decodedNames == 0 then
        return
    end

    self.argumentNameMap = {}
    self.argumentNamesUsed = {}
    self.script.arguments = {}
    self.script.argumentDefaults = {}

    for index, rawName in ipairs(decodedNames) do
        local defaultValue = nil
        if decodedDefaults then
            defaultValue = decodedDefaults[index]
        end
        self:registerArgument(rawName, defaultValue)
    end
end

---Create constant input
---@param value any Constant value
---@return IntermediateInput input Constant input
function ScriptTreeGenerator:createConstantInput(value)
    local inputType
    if type(value) == "number" then
        inputType = IntermediateInput.getNumberInputType(value)
    elseif type(value) == "string" then
        inputType = InputType.STRING
    elseif type(value) == "boolean" then
        inputType = InputType.BOOLEAN
    else
        inputType = InputType.ANY
    end

    return IntermediateInput:new(InputOpcode.CONSTANT, inputType, { value = value })
end

---Create list contents input for direct list references
---@param list table List object
---@return IntermediateInput input Generated list contents input
function ScriptTreeGenerator:createListContentsInput(list)
    return IntermediateInput:new(InputOpcode.LIST_CONTENTS, InputType.STRING, { list = list })
end

---Descend input block and convert to IntermediateInput
---@param block table Scratch block
---@return IntermediateInput input Generated input
function ScriptTreeGenerator:descendInput(block)
    if not block then
        return self:createConstantInput("")
    end

    local opcode = block.opcode

    -- Handle built-in literal blocks first
    if opcode == "math_number" then
        local value = cast.toNumber(block.fields.NUM.value)
        return self:createConstantInput(value)
    elseif opcode == "text" then
        local value = cast.toString(block.fields.TEXT.value)
        return self:createConstantInput(value)
    elseif opcode == "argument_reporter_string_number" or opcode == "argument_reporter_boolean" then
        -- Handle procedure argument reporter
        local field = block.fields and block.fields.VALUE
        local rawName = field and field.value or "arg"
        local registeredName = self:getArgumentName(rawName)

        return IntermediateInput:new(InputOpcode.ARG_REF, InputType.ANY, {
            argName = registeredName
        })
    elseif opcode == "sound_sounds_menu" then
        -- Special menu block that has opcode function but should be treated as constant
        local soundMenuValue = block.fields and block.fields.SOUND_MENU and block.fields.SOUND_MENU.value
        return self:createConstantInput(soundMenuValue or "")
    else
        -- Try block compilers for other blocks first
        -- Note: Some blocks like looks_costumenumbername have no inputs and single field
        -- but need special handling, so compilers must handle them before menu detection
        local result = blockCompilers.compile(self, block)
        if result and result.opcode then
            return result
        end

        -- Generic menu block detection
        -- If block has no inputs and exactly one field, it's a menu block
        -- This catches pure menu blocks like pen_menu_colorParam after compilers have a chance
        local hasInputs = block.inputs and next(block.inputs) ~= nil
        local fieldCount = 0
        local singleFieldName = nil
        if block.fields then
            for fieldName, _ in pairs(block.fields) do
                fieldCount = fieldCount + 1
                singleFieldName = fieldName
            end
        end

        if not hasInputs and fieldCount == 1 then
            -- It's a menu block - return the field value as constant
            -- Examples: pen_menu_colorParam, control_create_clone_of_menu, music_menu_DRUM, etc.
            local fieldValue = block.fields[singleFieldName].value
            return self:createConstantInput(fieldValue or "")
        end

        -- Unknown block type - this is an error!
        error("Unhandled input block opcode: " .. tostring(opcode) .. " - block not implemented in compiler")
    end
end

---Get input of a block's field
---@param block table Parent block
---@param fieldName string Field name
---@return IntermediateInput input Generated input
function ScriptTreeGenerator:descendInputOfBlock(block, fieldName)
    -- Check if field exists in inputs first
    if block.inputs and block.inputs[fieldName] then
        local input = block.inputs[fieldName]
        -- Continue with normal input processing...
    else
        -- If no input found, check fields for menu values (e.g., effect menus)
        if block.fields and block.fields[fieldName] then
            local field = block.fields[fieldName]
            -- Field has been processed by ProjectModel:parseFields, structure: {value=..., id=...}
            if type(field) == "table" and field.value ~= nil then
                return self:createConstantInput(field.value)
            elseif type(field) == "string" then
                return self:createConstantInput(field)
            end
        end

        -- If neither inputs nor fields contain the field, return empty string
        return self:createConstantInput("")
    end

    local input = block.inputs[fieldName]

    if type(input) == "table" and #input > 0 then
        if #input > 1 and type(input[2]) == "table" then
        end
    end

    -- Check if input is in ProjectModel's parsed format {shadowType, value, obscuredShadow}
    if type(input) == "table" and input.shadowType and input.value ~= nil then
        local value = input.value

        -- If value is a table (literal value), extract the actual value
        if type(value) == "table" and #value >= 2 then
            local primitiveType = value[1]
            local actualValue = value[2]

            if primitiveType == 12 then
                -- For primitiveType 12, the format is {12, "variableName", variableId}
                -- So we need value[2] (variableName) and value[3] (variableId)
                if #value >= 3 then
                    local variableName = value[2]
                    local variableId = value[3]

                    -- Look up the actual variable scope instead of defaulting to stage
                    local variable = self:_descendVariable(variableId, variableName, "scalar")

                    -- Create variable reference input to match native Scratch behavior
                    local variableInfo = {
                        name = variableName,
                        id = variableId,
                        scope = variable and variable.scope or "stage" -- Use actual scope from lookup
                    }
                    return IntermediateInput:new(InputOpcode.VAR_GET, InputType.ANY, {
                        variable = variableInfo
                    })
                else
                    return self:createConstantInput("")
                end
            end

            if primitiveType == 13 then
                -- For primitiveType 13, the format is {13, "listName", listId}
                -- So we need value[2] (listName) and value[3] (listId)
                if #value >= 3 then
                    local listName = value[2]
                    local listId = value[3]

                    -- Look up the actual list scope instead of defaulting to stage
                    local listVariable = self:_descendVariable(listId, listName, "list")

                    -- Create list contents input to match native Scratch behavior
                    -- For primitiveType 13, we need to create a special input that will generate
                    -- runtime code to get the list contents by name and id
                    local listInfo = {
                        name = listName,
                        id = listId,
                        scope = listVariable and listVariable.scope or "stage" -- Use actual scope from lookup
                    }
                    return self:createListContentsInput(listInfo)
                else
                    return self:createConstantInput("")
                end
            end

            -- Convert string infinity values to numbers
            if type(actualValue) == "string" then
                if actualValue == "Infinity" then
                    actualValue = math.huge
                elseif actualValue == "-Infinity" then
                    actualValue = -math.huge
                end
            end

            return self:createConstantInput(actualValue)
        end

        -- If value is a string (block reference), process as block
        if type(value) == "string" then
            local inputBlock = self.blocks[value]
            if inputBlock then
                return self:descendInput(inputBlock)
            end

            -- Special case: shadowType 3 with string value might be field name
            -- In this case, we should probably return nil to use fallback
            if input.shadowType == 3 then
                return nil
            end
        end

        -- If value is a direct primitive, use it
        return self:createConstantInput(value)
    end

    -- Check if input is a raw Scratch array format [inputType, value, shadow] (fallback)
    if type(input) == "table" and #input >= 2 then
        local inputType = input[1]
        local value = input[2]


        -- If value is a table (literal value), extract the actual value
        if type(value) == "table" and #value >= 2 then
            local primitiveType = value[1]
            local actualValue = value[2]

            if primitiveType == 12 then
                -- For primitiveType 12, the format is {12, "variableName", variableId}
                -- So we need value[2] (variableName) and value[3] (variableId)
                if #value >= 3 then
                    local variableName = value[2]
                    local variableId = value[3]

                    -- Look up the actual variable scope instead of defaulting to stage
                    local variable = self:_descendVariable(variableId, variableName, "scalar")

                    -- Create variable reference input to match native Scratch behavior
                    local variableInfo = {
                        name = variableName,
                        id = variableId,
                        scope = variable and variable.scope or "stage" -- Use actual scope from lookup
                    }
                    return IntermediateInput:new(InputOpcode.VAR_GET, InputType.ANY, {
                        variable = variableInfo
                    })
                else
                    return self:createConstantInput("")
                end
            end

            -- Convert string infinity values to numbers
            if type(actualValue) == "string" then
                if actualValue == "Infinity" then
                    actualValue = math.huge
                elseif actualValue == "-Infinity" then
                    actualValue = -math.huge
                end
            end

            return self:createConstantInput(actualValue)
        end

        -- If value is a string (block reference), process as block
        if type(value) == "string" then
            local inputBlock = self.blocks[value]
            if inputBlock then
                return self:descendInput(inputBlock)
            end
        end
    end

    if input.block then
        -- Input is another block
        local inputBlock = self.blocks[input.block]
        if inputBlock then
            return self:descendInput(inputBlock)
        end
    elseif input.shadow then
        -- Input has shadow block
        local shadowBlock = self.blocks[input.shadow]
        if shadowBlock then
            return self:descendInput(shadowBlock)
        end
    end

    return self:createConstantInput("")
end

---Infer type for addition operation
---@param leftType InputType Left operand type
---@param rightType InputType Right operand type
---@return InputType resultType Result type
function ScriptTreeGenerator:getAddType(leftType, rightType)
    local resultType = 0

    -- If both operands are numbers, result is number
    if bit.band(leftType, InputType.NUMBER) ~= 0 and bit.band(rightType, InputType.NUMBER) ~= 0 then
        -- Sign inference
        if bit.band(leftType, InputType.NUMBER_POS) ~= 0 and bit.band(rightType, InputType.NUMBER_POS) ~= 0 then
            resultType = bit.bor(resultType, InputType.NUMBER_POS)
        end
        if bit.band(leftType, InputType.NUMBER_NEG) ~= 0 and bit.band(rightType, InputType.NUMBER_NEG) ~= 0 then
            resultType = bit.bor(resultType, InputType.NUMBER_NEG)
        end

        -- Integer inference
        if bit.band(leftType, InputType.NUMBER_INT) ~= 0 and bit.band(rightType, InputType.NUMBER_INT) ~= 0 then
            resultType = bit.bor(resultType, InputType.NUMBER_INT)
        else
            resultType = bit.bor(resultType, InputType.NUMBER_REAL)
        end
    end

    -- If either operand could be string, result could be string concatenation
    if bit.band(leftType, InputType.STRING) ~= 0 or bit.band(rightType, InputType.STRING) ~= 0 then
        resultType = bit.bor(resultType, InputType.STRING)
    end

    return resultType ~= 0 and resultType or InputType.ANY
end

---Descend stack block and convert to IntermediateStackBlock
---@param block table Scratch block
---@param blockId string|nil Original Scratch block ID
---@return IntermediateStackBlock stackBlock Generated stack block
function ScriptTreeGenerator:descendStackedBlock(block, blockId)
    if not block then
        return IntermediateStackBlock:new(StackOpcode.NOP, nil, nil, nil)
    end

    -- Handle event_broadcast and event_broadcastandwait directly to avoid warning
    if block.opcode == "event_broadcast" then
        local broadcastInput = self:descendInputOfBlock(block, "BROADCAST_INPUT")
        if not broadcastInput then
            broadcastInput = self:createConstantInput("message1")
        end
        return IntermediateStackBlock:new(StackOpcode.EVENT_BROADCAST, {
            broadcast = broadcastInput
        }, false, blockId)
    elseif block.opcode == "event_broadcastandwait" then
        local broadcastInput = self:descendInputOfBlock(block, "BROADCAST_INPUT")
        if not broadcastInput then
            broadcastInput = self:createConstantInput("message1")
        end
        return IntermediateStackBlock:new(StackOpcode.EVENT_BROADCAST_AND_WAIT, {
            broadcast = broadcastInput
        }, true, blockId) -- Yields waiting for broadcast completion
    end

    -- Handle procedures_call specially - compile as direct function call
    if block.opcode == "procedures_call" then
        local procedureCode = block.mutation and block.mutation.proccode
        if not procedureCode then
            return IntermediateStackBlock:new(StackOpcode.NOP, nil, nil, blockId)
        end

        -- Determine warp mode: inherit from caller OR use definition's warp flag
        local isWarp = self.script.isWarp -- Inherit caller's warp mode first!
        if not isWarp then
            -- If caller is not warp, check if the called procedure itself is defined as warp
            -- Use cached definition from procedure definitions (built in constructor)
            local procedureInfo = self.procedureDefinitionCache[procedureCode]
            if procedureInfo and procedureInfo.isWarp then
                isWarp = true
            end
        end

        -- Create procedure variant based on warp mode
        local variant = generateProcedureVariant(procedureCode, isWarp)

        -- Add to procedures to compile (dependency tracking)
        if not self.script.dependedProcedures then
            self.script.dependedProcedures = {}
        end
        if not self.script.dependedProcedures[variant] then
            self.script.dependedProcedures[variant] = {
                procedureCode = procedureCode,
                warp = isWarp
            }
        else
        end

        -- Process arguments
        local args = {}
        if block.mutation and block.mutation.argumentids then
            local argumentIds = {}
            -- Parse argumentids JSON string if it's a string
            if type(block.mutation.argumentids) == "string" then
                argumentIds = json.decode(block.mutation.argumentids)
            else
                argumentIds = block.mutation.argumentids
            end

            for i, argId in ipairs(argumentIds) do
                if block.inputs and block.inputs[argId] then
                    args[i] = self:descendInputOfBlock(block, argId)
                else
                    args[i] = self:createConstantInput("")
                end
            end
        end

        return IntermediateStackBlock:new(StackOpcode.PROCEDURE_CALL, {
            procedureCode = procedureCode,
            variant = variant,
            arguments = args
        }, false, blockId)
    end

    -- Try block compilers first
    local result = blockCompilers.compile(self, block, blockId)
    if result then
        return result
    elseif block.opcode == "procedures_definition" then
        -- Handle procedure definition
        local mutation = block.mutation
        if mutation and mutation.proccode then
            -- Determine warp mode from mutation
            local isWarp = false
            if mutation.warp then
                isWarp = (mutation.warp == "true")
            end

            -- Create procedure variant name
            local variant = (isWarp and "W" or "Z") .. mutation.proccode

            -- Mark this as a procedure definition for compilation
            if not self.script.procedureDefinitions then
                self.script.procedureDefinitions = {}
            end
            self.script.procedureDefinitions[variant] = {
                procedureCode = mutation.proccode,
                blockId = blockId,
                mutation = mutation,
                warp = isWarp
            }
        end

        -- For now, treat procedure definition as NOP in the main execution flow
        -- The actual procedure body will be compiled separately
        return IntermediateStackBlock:new(StackOpcode.NOP, nil, nil, blockId)
    else
        -- Unknown block type - this is an error!
        error("Unhandled stack block opcode: " .. tostring(block.opcode) .. " - block not implemented in compiler")
    end
end

---Descend substack (nested blocks)
---@param block table Parent block
---@param stackName string Stack field name
---@return IntermediateStack|nil stack Generated stack or nil
function ScriptTreeGenerator:descendSubstack(block, stackName)
    if not block.inputs or not block.inputs[stackName] then
        return nil
    end

    local input = block.inputs[stackName]
    if type(input) == "table" then
        local keys = {}
        for k in pairs(input) do
            table.insert(keys, tostring(k))
        end
    end
    local firstBlockId = nil

    -- Handle ProjectModel's parsed format {shadowType, value}
    if type(input) == "table" and input.shadowType and input.value ~= nil then
        firstBlockId = input.value
        -- Handle raw format {block, shadow}
    elseif input.block then
        firstBlockId = input.block
    end

    if not firstBlockId then
        return nil
    end
    local stack = IntermediateStack:new()

    local currentBlockId = firstBlockId
    while currentBlockId do
        local currentBlock = self.blocks[currentBlockId]
        if not currentBlock then break end

        local stackBlock = self:descendStackedBlock(currentBlock, currentBlockId)
        table.insert(stack.blocks, stackBlock)

        currentBlockId = currentBlock.next
    end

    return stack
end

---Descend variable reference
---@param block table Block containing variable reference
---@param fieldName string Field name
---@return IntermediateInput result Field value as input
function ScriptTreeGenerator:descendFieldOfBlock(block, fieldName)
    if not block.fields or not block.fields[fieldName] then
        return self:createConstantInput("")
    end

    local field = block.fields[fieldName]
    local value = field.value or field[1] or ""

    return self:createConstantInput(value)
end

function ScriptTreeGenerator:descendVariable(block, fieldName, variableType)
    if not block.fields or not block.fields[fieldName] then
        error("Variable field not found: " .. fieldName)
    end

    local variable = block.fields[fieldName]
    local id = variable.id or variable.value

    -- Use cache to avoid repeated lookups
    if id and self.variableCache[id] then
        return self.variableCache[id]
    end

    -- Look up variable data
    local variableData = self:_descendVariable(id, variable.value, variableType)

    -- Cache result
    if variableData.id then
        self.variableCache[variableData.id] = variableData
    end

    return variableData
end

---Internal variable lookup with scope resolution
---@param id string Variable ID
---@param name string Variable name
---@param variableType string Variable type ("" for scalar, "list" for list)
---@return table variable Variable data {scope, id, name, isCloud}
function ScriptTreeGenerator:_descendVariable(id, name, variableType)
    local target = self.target
    local stage = self.runtime.stage

    -- Look for by ID in target...
    if target.variables and target.variables[id] then
        local currVar = target.variables[id]
        return {
            scope = "target",
            id = currVar.id or id,
            name = currVar.name,
            isCloud = currVar.cloud or currVar.isCloud or false
        }
    end

    -- Look for by ID in stage...
    if not target.isStage then
        if stage and stage.variables and stage.variables[id] then
            local currVar = stage.variables[id]
            return {
                scope = "stage",
                id = currVar.id or id,
                name = currVar.name,
                isCloud = currVar.cloud or currVar.isCloud or false
            }
        end
    end

    -- Look for by name and type in target...
    if target.variables then
        for varId, currVar in pairs(target.variables) do
            -- Check if variable name matches and type matches (if type specified)
            local varType = currVar.type or ""
            if currVar.name == name and varType == variableType then
                return {
                    scope = "target",
                    id = currVar.id or varId,
                    name = currVar.name,
                    isCloud = currVar.cloud or currVar.isCloud or false
                }
            end
        end
    end

    -- Look for by name and type in stage...
    if not target.isStage and stage and stage.variables then
        for varId, currVar in pairs(stage.variables) do
            -- Check if variable name matches and type matches (if type specified)
            local varType = currVar.type or ""
            if currVar.name == name and varType == variableType then
                return {
                    scope = "stage",
                    id = currVar.id or varId,
                    name = currVar.name,
                    isCloud = currVar.cloud or currVar.isCloud or false
                }
            end
        end
    end

    -- Create it locally...
    -- This matches vanilla Scratch quirks regarding handling of null variable IDs
    log.debug("[IRGenerator] Auto-creating variable (Scratch compatibility): " ..
        tostring(name) .. " (ID: " .. tostring(id) .. ") in " .. tostring(target.name))

    local newVariable = {
        id = id,
        name = name,
        type = variableType,
        value = (variableType == "list") and {} or 0,
        cloud = false,
        isCloud = false
    }

    -- Intentionally not using newVariable.id so that this matches vanilla Scratch quirks regarding
    -- handling of null variable IDs.
    target.variables[tostring(id)] = newVariable

    -- Create the variable in all instances of this sprite.
    -- This is necessary because the script cache is shared between clones.
    -- sprite.clones has all instances of this sprite including the original and all clones
    if target.spriteTemplate then
        -- Get all clones from spriteTemplate
        local clones = target.spriteTemplate.clones
        if clones then
            for _, clone in ipairs(clones) do
                if not clone.variables[id] then
                    clone.variables[tostring(id)] = {
                        id = id,
                        name = name,
                        type = variableType,
                        value = (variableType == "list") and {} or 0,
                        cloud = false,
                        isCloud = false
                    }
                end
            end
        end
    end

    return {
        scope = "target",
        -- If the given ID was null, this won't match the .id property of the Variable object.
        -- This is intentional to match vanilla Scratch quirks.
        id = id,
        name = newVariable.name,
        isCloud = newVariable.isCloud
    }
end

---@class IRGenerator
---@field private thread Thread
---@field private blocks table
---@field private proceduresToCompile table
---@field private procedures table
---@field private procedureDefinitionCache table<string, {definitionId: string, isWarp: boolean}>
local IRGenerator = {}
IRGenerator.__index = IRGenerator

---Create new IR generator
---@param thread Thread Thread to generate IR for
---@return IRGenerator
function IRGenerator:new(thread)
    local generator = setmetatable({}, IRGenerator)
    generator.thread = thread
    generator.blocks = thread.blockContainer or {}
    generator.proceduresToCompile = {}
    generator.procedures = {}

    -- Get blockOrder from thread's target (for stable procedure definition cache)
    -- The blockOrder is stored alongside blocks in the target or template
    local blockOrder = nil
    if thread.target then
        if thread.target.blockOrder then
            blockOrder = thread.target.blockOrder
        elseif thread.target.spriteTemplate and thread.target.spriteTemplate.blockOrder then
            blockOrder = thread.target.spriteTemplate.blockOrder
        end
    end

    if not blockOrder then
        error("IRGenerator:new: blockOrder is required for stable procedure definition cache")
    end

    -- Build procedure definition cache for fast lookup (shared across all generators)
    -- Use blockOrder to ensure stable iteration order
    generator.procedureDefinitionCache = {}
    for _, blockId in ipairs(blockOrder) do
        local block = generator.blocks[blockId]
        if block and block.opcode == "procedures_definition" and block.inputs and block.inputs.custom_block then
            local customBlockInput = block.inputs.custom_block
            local prototypeId = customBlockInput.value or customBlockInput.block or (type(customBlockInput) == "table" and customBlockInput[2])

            if prototypeId and generator.blocks[prototypeId] then
                local prototype = generator.blocks[prototypeId]
                if prototype.mutation and prototype.mutation.proccode then
                    local isWarp = false
                    local warp = prototype.mutation.warp
                    if type(warp) == "boolean" then
                        isWarp = warp
                    elseif type(warp) == "string" then
                        isWarp = (warp == "true")
                    end

                    generator.procedureDefinitionCache[prototype.mutation.proccode] = {
                        definitionId = blockId,
                        isWarp = isWarp
                    }
                end
            end
        end
    end

    return generator
end

---Generate complete intermediate representation
---@return IntermediateRepresentation ir Generated IR
function IRGenerator:generate()
    log.debug("Generating IR for thread: " .. tostring(self.thread.topBlock))

    -- Generate main script with shared cache
    local scriptGenerator = ScriptTreeGenerator:new(self.thread, self.procedureDefinitionCache)
    local entry = self:generateScriptTree(scriptGenerator, self.thread.topBlock)

    -- Add depended procedures to compilation queue
    if scriptGenerator.script.dependedProcedures then
        local count = 0
        for _ in pairs(scriptGenerator.script.dependedProcedures) do count = count + 1 end
        for variant, data in pairs(scriptGenerator.script.dependedProcedures) do
            if not self.proceduresToCompile[variant] then
                self.proceduresToCompile[variant] = data
            end
        end
    else
    end

    -- Compile all dependent procedures
    while next(self.proceduresToCompile) do
        local variant, data = next(self.proceduresToCompile)
        self.proceduresToCompile[variant] = nil

        if not self.procedures[variant] then
            -- Share cache with procedure generators for efficiency
            local procedureGenerator = ScriptTreeGenerator:new(self.thread, self.procedureDefinitionCache)
            procedureGenerator.script.isWarp = data.warp
            procedureGenerator.script.isProcedure = true
            procedureGenerator.script.procedureCode = data.procedureCode

            -- Inline cache lookup for procedure definition (O(1) instead of method call)
            local procedureInfo = self.procedureDefinitionCache[data.procedureCode]
            local procedureDefinition = procedureInfo and procedureInfo.definitionId
            if procedureDefinition then
                -- Set procedure definition info for parameter generation
                procedureGenerator.script.procedureDefId = procedureDefinition
                procedureGenerator.script.procedureBlocks = self.blocks

                procedureGenerator:prepareProcedureArguments(procedureDefinition, self.blocks)

                local script = self:generateScriptTree(procedureGenerator, procedureDefinition)
                self.procedures[variant] = script
            else
                -- Procedure definition not found - create a NOP procedure
                log.warn("Procedure definition not found for: " ..
                    tostring(data.procedureCode) .. " - creating NOP procedure")

                -- Create empty script with NOP block
                procedureGenerator.script.stack = IntermediateStack:new()
                table.insert(procedureGenerator.script.stack.blocks, IntermediateStackBlock:new(StackOpcode.NOP, nil, nil, nil))
                self.procedures[variant] = procedureGenerator.script
            end

            -- Add any nested procedure dependencies to compilation queue
            if procedureGenerator.script.dependedProcedures then
                for nestedVariant, nestedData in pairs(procedureGenerator.script.dependedProcedures) do
                    if not self.proceduresToCompile[nestedVariant] and not self.procedures[nestedVariant] then
                        self.proceduresToCompile[nestedVariant] = nestedData
                    end
                end
            end
        end
    end

    local procCount = 0
    for k, v in pairs(self.procedures) do
        procCount = procCount + 1
    end
    return IntermediateRepresentation:new(entry, self.procedures)
end

---Check if a block is a HAT block (event trigger)
---@param block table Scratch block
---@return boolean isHat True if block is a HAT block
function IRGenerator:isHatBlock(block)
    if not block or not block.opcode then
        return false
    end

    -- Only include actual HAT blocks (event triggers), not action blocks
    local hatOpcodes = {
        "event_whenflagclicked",
        "event_whenkeypressed",
        "event_whenthisspriteclicked",
        "event_whenstageclicked",
        "event_whenbackdropswitchesto",  -- SB2 opcode, also used in SB3
        "event_whengreaterthan",
        "event_whenbroadcastreceived",
        "control_start_as_clone"
        -- event_broadcast and event_broadcastandwait are NOT HAT blocks!
        -- They are action blocks that should be compiled normally
    }

    for _, hatOpcode in ipairs(hatOpcodes) do
        if block.opcode == hatOpcode then
            return true
        end
    end

    return false
end

---Generate script tree from block
---@param generator ScriptTreeGenerator Script generator
---@param blockId string Starting block ID
---@return IntermediateScript script Generated script
function IRGenerator:generateScriptTree(generator, blockId)
    if not blockId then
        return generator.script
    end

    -- Check if this is a HAT block and mark the generator
    local startBlockId = blockId
    local startBlock = self.blocks[blockId]
    local isHat = false
    if startBlock and self:isHatBlock(startBlock) then
        isHat = true
        startBlockId = startBlock.next
        log.debug("HAT block detected: " .. startBlock.opcode)
    end

    -- Mark that this script has a Hat block (for yield behavior)
    generator.script.hasHat = isHat

    -- Mark hat as executable ONLY for edge-activated hats
    -- Note: With Solution A, coroutine is created at load time, so we don't need to
    -- execute all hats immediately. Only edge-activated hats need immediate execution
    -- to evaluate their predicate conditions.
    if isHat and startBlock then
        local edgeActivatedHats = {
            "event_whentouchingobject",  -- edgeActivated: true
            "event_whengreaterthan"      -- edgeActivated: true (with predicate function)
        }

        for _, edgeHat in ipairs(edgeActivatedHats) do
            if startBlock.opcode == edgeHat then
                generator.script.executableHat = true
                log.debug("Edge-activated HAT marked as executable: " .. startBlock.opcode)
                break
            end
        end
    end

    if not startBlockId then
        return generator.script
    end

    local stack = IntermediateStack:new()

    local currentBlockId = startBlockId
    while currentBlockId do
        local block = self.blocks[currentBlockId]
        if not block then break end

        local stackBlock = generator:descendStackedBlock(block, currentBlockId)
        table.insert(stack.blocks, stackBlock)

        currentBlockId = block.next
    end

    generator.script.stack = stack
    return generator.script
end

return {
    IRGenerator = IRGenerator,
    ScriptTreeGenerator = ScriptTreeGenerator,
    generateProcedureVariant = generateProcedureVariant,
    parseProcedureCode = parseProcedureCode,
    parseIsWarp = parseIsWarp
}
