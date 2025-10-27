-- @fileoverview Data (variables and lists) block compilation for Scratch to Lua compiler

local enums = require("compiler.enums")
local intermediate = require("compiler.intermediate")
local log = require("lib.log")

local InputType = enums.InputType
local StackOpcode = enums.StackOpcode
local InputOpcode = enums.InputOpcode
local IntermediateStackBlock = intermediate.IntermediateStackBlock
local IntermediateInput = intermediate.IntermediateInput

local SCALAR_TYPE = ""
local LIST_TYPE = "list"

---@class DataBlockCompiler
local DataBlockCompiler = {}

---Compile data blocks during IR generation
---@param generator ScriptTreeGenerator Generator instance
---@param block table Scratch block
---@return IntermediateStackBlock|IntermediateInput|nil result Compiled result
function DataBlockCompiler.compile(generator, block)
    local opcode = block.opcode

    -- Variable blocks
    if opcode == "data_variable" then
        local variable = generator:descendVariable(block, "VARIABLE", SCALAR_TYPE)
        return IntermediateInput:new(InputOpcode.VAR_GET, InputType.ANY, {
            variable = variable
        })

    elseif opcode == "data_setvariableto" then
        local variable = generator:descendVariable(block, "VARIABLE", SCALAR_TYPE)
        local value = generator:descendInputOfBlock(block, "VALUE")
        return IntermediateStackBlock:new(StackOpcode.VAR_SET, {
            variable = variable,
            value = value
        })

    elseif opcode == "data_changevariableby" then
        -- Pattern: VAR_SET(variable, OP_ADD(VAR_GET(variable), value))
        -- This allows type inference optimization on the OP_ADD operation
        local variable = generator:descendVariable(block, "VARIABLE", SCALAR_TYPE)

        -- Create VAR_GET to read current value
        local varGet = IntermediateInput:new(InputOpcode.VAR_GET, InputType.ANY, {
            variable = variable
        }):toType(InputType.NUMBER)

        -- Get delta value
        local delta = generator:descendInputOfBlock(block, "VALUE"):toType(InputType.NUMBER)

        -- Create OP_ADD for variable + delta
        local addOp = IntermediateInput:new(InputOpcode.OP_ADD, InputType.NUMBER_OR_NAN, {
            left = varGet,
            right = delta
        })

        -- Use VAR_SET to assign the result
        return IntermediateStackBlock:new(StackOpcode.VAR_SET, {
            variable = variable,
            value = addOp
        })

    elseif opcode == "data_showvariable" then
        local variable = generator:descendVariable(block, "VARIABLE", SCALAR_TYPE)
        return IntermediateStackBlock:new(StackOpcode.VAR_SHOW, {
            variable = variable
        })

    elseif opcode == "data_hidevariable" then
        local variable = generator:descendVariable(block, "VARIABLE", SCALAR_TYPE)
        return IntermediateStackBlock:new(StackOpcode.VAR_HIDE, {
            variable = variable
        })

    -- List blocks
    elseif opcode == "data_listcontents" then
        local list = generator:descendVariable(block, "LIST", LIST_TYPE)
        local result = IntermediateInput:new(InputOpcode.LIST_CONTENTS, InputType.STRING, {
            list = list
        })
        return result

    elseif opcode == "data_addtolist" then
        local item = generator:descendInputOfBlock(block, "ITEM")
        local list = generator:descendVariable(block, "LIST", LIST_TYPE)
        return IntermediateStackBlock:new(StackOpcode.LIST_ADD, {
            item = item,
            list = list
        })

    elseif opcode == "data_deleteoflist" then
        local index = generator:descendInputOfBlock(block, "INDEX")
        local list = generator:descendVariable(block, "LIST", LIST_TYPE)

        -- Handle "all" index at IR generation time
        if index.isConstant and index:isConstant('all') then
            return IntermediateStackBlock:new(StackOpcode.LIST_DELETE_ALL, {
                list = list
            })
        end

        return IntermediateStackBlock:new(StackOpcode.LIST_DELETE, {
            index = index,
            list = list
        })

    elseif opcode == "data_deletealloflist" then
        local list = generator:descendVariable(block, "LIST", LIST_TYPE)
        return IntermediateStackBlock:new(StackOpcode.LIST_DELETE_ALL, {
            list = list
        })

    elseif opcode == "data_insertatlist" then
        local item = generator:descendInputOfBlock(block, "ITEM")
        local index = generator:descendInputOfBlock(block, "INDEX")
        local list = generator:descendVariable(block, "LIST", LIST_TYPE)
        return IntermediateStackBlock:new(StackOpcode.LIST_INSERT, {
            item = item,
            index = index,
            list = list
        })

    elseif opcode == "data_replaceitemoflist" then
        local index = generator:descendInputOfBlock(block, "INDEX")
        local item = generator:descendInputOfBlock(block, "ITEM")
        local list = generator:descendVariable(block, "LIST", LIST_TYPE)
        return IntermediateStackBlock:new(StackOpcode.LIST_REPLACE, {
            index = index,
            item = item,
            list = list
        })

    elseif opcode == "data_itemoflist" then
        local index = generator:descendInputOfBlock(block, "INDEX")
        local list = generator:descendVariable(block, "LIST", LIST_TYPE)
        return IntermediateInput:new(InputOpcode.LIST_GET, InputType.ANY, {
            index = index,
            list = list
        })

    elseif opcode == "data_itemnumoflist" then
        local item = generator:descendInputOfBlock(block, "ITEM")
        local list = generator:descendVariable(block, "LIST", LIST_TYPE)
        return IntermediateInput:new(InputOpcode.LIST_INDEX_OF, InputType.NUMBER, {
            item = item,
            list = list
        })

    elseif opcode == "data_lengthoflist" then
        local list = generator:descendVariable(block, "LIST", LIST_TYPE)
        return IntermediateInput:new(InputOpcode.LIST_LENGTH, InputType.NUMBER, {
            list = list
        })

    elseif opcode == "data_listcontainsitem" then
        local item = generator:descendInputOfBlock(block, "ITEM")
        local list = generator:descendVariable(block, "LIST", LIST_TYPE)
        return IntermediateInput:new(InputOpcode.LIST_CONTAINS, InputType.BOOLEAN, {
            item = item,
            list = list
        })

    elseif opcode == "data_showlist" then
        local list = generator:descendVariable(block, "LIST", LIST_TYPE)
        return IntermediateStackBlock:new(StackOpcode.LIST_SHOW, {
            list = list
        })

    elseif opcode == "data_hidelist" then
        local list = generator:descendVariable(block, "LIST", LIST_TYPE)
        return IntermediateStackBlock:new(StackOpcode.LIST_HIDE, {
            list = list
        })

    end

    return nil
end

---Generate Lua code for data stack blocks
---@param generator LuaGenerator Generator instance
---@param opcode string Stack opcode
---@param inputs table Block inputs
---@param block table|nil Original block for blockId access
---@return boolean handled True if opcode was handled
function DataBlockCompiler.generateStackBlock(generator, opcode, inputs, block)
    local StackOpcode = enums.StackOpcode

    if opcode == StackOpcode.VAR_SET then
        -- Variable assignment
        local variable = inputs.variable
        local value = inputs.value
        if variable and value then
            local valueCode = generator:generateInput(value)
            local hashVarName = generator:getHashVariable(variable)
            generator:writeLine(hashVarName .. ".value = " .. valueCode)

            -- Save cloud variable to persistent storage (async, no blocking)
            -- CloudVariableStorage:set will coerce value to number and mark for async save
            if variable.isCloud then
                generator:writeLine(string.format("runtime:saveCloudVariable(%q, %s.value)", variable.id, hashVarName))
            end
        end
        return true

    elseif opcode == StackOpcode.VAR_SHOW then
        -- Show variable monitor
        local variable = inputs.variable
        if variable then
            generator:writeLine(string.format("runtime.monitorManager:setVisible(%q, true)", variable.id))
        end
        return true

    elseif opcode == StackOpcode.VAR_HIDE then
        -- Hide variable monitor
        local variable = inputs.variable
        if variable then
            generator:writeLine(string.format("runtime.monitorManager:setVisible(%q, false)", variable.id))
        end
        return true

    elseif opcode == StackOpcode.LIST_ADD then
        -- Add item to list
        local item = inputs.item
        local list = inputs.list
        if item and list then
            local itemCode = generator:generateInput(item)
            local listRef = generator:referenceList(list)
            generator:writeLine(string.format("if #%s.value < cast.LIST_ITEM_LIMIT then", listRef))
            generator:indent()
            generator:writeLine(string.format("table.insert(%s.value, %s)", listRef, itemCode))
            generator:dedent()
            generator:writeLine("end")
        end
        return true

    elseif opcode == StackOpcode.LIST_DELETE then
        -- Delete item from list
        local index = inputs.index
        local list = inputs.list
        if index and list then
            local indexCode = generator:generateInput(index)
            local listRef = generator:referenceList(list)
            local indexVar = generator:getLocalVariable("delIdx")
            generator:writeLine(string.format("local %s = cast.toListIndex(%s, #%s.value, true)", indexVar, indexCode, listRef))
            generator:writeLine(string.format("if %s == cast.LIST_INVALID then return end", indexVar))
            generator:writeLine(string.format("if %s == cast.LIST_ALL then %s.value = {}; return end", indexVar, listRef))
            generator:writeLine(string.format("table.remove(%s.value, %s)", listRef, indexVar))
        end
        return true

    elseif opcode == StackOpcode.LIST_DELETE_ALL then
        -- Delete all items from list
        local list = inputs.list
        if list then
            local listRef = generator:referenceList(list)
            generator:writeLine(string.format("%s.value = {}", listRef))
        end
        return true

    elseif opcode == StackOpcode.LIST_INSERT then
        -- Insert item at position in list
        local item = inputs.item
        local index = inputs.index
        local list = inputs.list
        if item and index and list then
            local itemCode = generator:generateInput(item)
            local indexCode = generator:generateInput(index)
            local listRef = generator:referenceList(list)
            local indexVar = generator:getLocalVariable("insIdx")
            generator:writeLine(string.format("local %s = cast.toListIndex(%s, #%s.value + 1, false)", indexVar, indexCode, listRef))
            generator:writeLine(string.format("if %s == cast.LIST_INVALID or %s > cast.LIST_ITEM_LIMIT then return end", indexVar, indexVar))
            generator:writeLine(string.format("table.insert(%s.value, %s, %s)", listRef, indexVar, itemCode))
            generator:writeLine(string.format("if #%s.value > cast.LIST_ITEM_LIMIT then table.remove(%s.value) end", listRef, listRef))
        end
        return true

    elseif opcode == StackOpcode.LIST_REPLACE then
        -- Replace item at position in list
        local item = inputs.item
        local index = inputs.index
        local list = inputs.list
        if item and index and list then
            local itemCode = generator:generateInput(item)
            local indexCode = generator:generateInput(index)
            local listRef = generator:referenceList(list)
            local indexVar = generator:getLocalVariable("repIdx")
            generator:writeLine(string.format("local %s = cast.toListIndex(%s, #%s.value, false)", indexVar, indexCode, listRef))
            generator:writeLine(string.format("if %s ~= cast.LIST_INVALID then", indexVar))
            generator:writeLine(string.format("  %s.value[%s] = %s", listRef, indexVar, itemCode))
            generator:writeLine("end")
        end
        return true

    elseif opcode == StackOpcode.LIST_SHOW then
        -- Show list monitor
        local list = inputs.list
        if list then
            generator:writeLine(string.format("runtime.monitorManager:setVisible(%q, true)", list.id))
        end
        return true

    elseif opcode == StackOpcode.LIST_HIDE then
        -- Hide list monitor
        local list = inputs.list
        if list then
            generator:writeLine(string.format("runtime.monitorManager:setVisible(%q, false)", list.id))
        end
        return true
    end

    return false
end

---Generate Lua code for data input blocks
---@param generator LuaGenerator Generator instance
---@param opcode string Input opcode
---@param inputs table Block inputs
---@return string|nil code Generated Lua expression or nil if not handled
function DataBlockCompiler.generateInput(generator, opcode, inputs)
    local InputOpcode = enums.InputOpcode

    if opcode == InputOpcode.VAR_GET then
        -- Variable reference
        local variable = inputs.variable
        if variable then
            local hashVarName = generator:getHashVariable(variable)
            return hashVarName .. ".value"
        end
        return "nil"

    elseif opcode == InputOpcode.LIST_GET then
        -- Get item from list
        local index = generator:generateInput(inputs.index)
        local list = inputs.list
        if list then
            local listRef = generator:referenceList(list)
            return string.format("cast.listGet(%s.value, %s)", listRef, index)
        end
        return "\"\""

    elseif opcode == InputOpcode.LIST_LENGTH then
        -- Get list length
        local list = inputs.list
        if list then
            local listRef = generator:referenceList(list)
            return string.format("#%s.value", listRef)
        end
        return "0"

    elseif opcode == InputOpcode.LIST_CONTAINS then
        -- Check if list contains item
        local item = generator:generateInput(inputs.item)
        local list = inputs.list
        if list then
            local listRef = generator:referenceList(list)
            return string.format("cast.listContains(%s.value, %s)", listRef, item)
        end
        return "false"

    elseif opcode == InputOpcode.LIST_INDEX_OF then
        -- Find item position in list
        local item = generator:generateInput(inputs.item)
        local list = inputs.list
        if list then
            local listRef = generator:referenceList(list)
            return string.format("cast.listIndexOf(%s.value, %s)", listRef, item)
        end
        return "0"

    elseif opcode == InputOpcode.LIST_CONTENTS then
        -- Get list contents as string
        local list = inputs.list
        if list then
            local listRef = generator:referenceList(list)
            return string.format("cast.listContents(%s.value)", listRef)
        end
        return '""'
    end

    return nil
end

return DataBlockCompiler