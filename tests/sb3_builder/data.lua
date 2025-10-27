-- Data Blocks Module
-- Implements all data-related blocks (variables and lists)

local Core = require("tests.sb3_builder.core")

local Data = {}

-- ===== VARIABLE BLOCKS =====

---Create "variable" reporter block
---@param variableName string Variable name
---@param variableId string|nil Variable ID (auto-generated if nil)
---@return string id, SB3Builder.Block block, string variableId Variable ID used
function Data.variable(variableName, variableId)
    if not variableId then
        variableId = "var_" .. tostring(math.random(100000, 999999))
    end
    
    local id, block = Core.createBlock("data_variable", {}, {
        VARIABLE = Core.field(variableName, variableId)
    })
    
    return id, block, variableId
end

---Create "set variable to" block
---@param variableName string Variable name
---@param value any Value to set
---@param variableId string|nil Variable ID (auto-generated if nil)
---@return string id, SB3Builder.Block block, string variableId Variable ID used
function Data.setVariable(variableName, value, variableId)
    if not variableId then
        variableId = "var_" .. tostring(math.random(100000, 999999))
    end
    
    local id, block = Core.createBlock("data_setvariableto", {
        VALUE = value
    }, {
        VARIABLE = Core.field(variableName, variableId)
    })
    
    return id, block, variableId
end

---Create "change variable by" block
---@param variableName string Variable name
---@param delta any Change amount
---@param variableId string|nil Variable ID (auto-generated if nil)
---@return string id, SB3Builder.Block block, string variableId Variable ID used
function Data.changeVariable(variableName, delta, variableId)
    if not variableId then
        variableId = "var_" .. tostring(math.random(100000, 999999))
    end
    
    local id, block = Core.createBlock("data_changevariableby", {
        VALUE = delta
    }, {
        VARIABLE = Core.field(variableName, variableId)
    })
    
    return id, block, variableId
end

---Create "show variable" block
---@param variableName string Variable name
---@param variableId string|nil Variable ID (auto-generated if nil)
---@return string id, SB3Builder.Block block, string variableId Variable ID used
function Data.showVariable(variableName, variableId)
    if not variableId then
        variableId = "var_" .. tostring(math.random(100000, 999999))
    end
    
    local id, block = Core.createBlock("data_showvariable", {}, {
        VARIABLE = Core.field(variableName, variableId)
    })
    
    return id, block, variableId
end

---Create "hide variable" block
---@param variableName string Variable name
---@param variableId string|nil Variable ID (auto-generated if nil)
---@return string id, SB3Builder.Block block, string variableId Variable ID used
function Data.hideVariable(variableName, variableId)
    if not variableId then
        variableId = "var_" .. tostring(math.random(100000, 999999))
    end
    
    local id, block = Core.createBlock("data_hidevariable", {}, {
        VARIABLE = Core.field(variableName, variableId)
    })
    
    return id, block, variableId
end

-- ===== LIST BLOCKS =====

---Create "list contents" reporter block
---@param listName string List name
---@param listId string|nil List ID (auto-generated if nil)
---@return string id, SB3Builder.Block block, string listId List ID used
function Data.listContents(listName, listId)
    if not listId then
        listId = "list_" .. tostring(math.random(100000, 999999))
    end
    
    local id, block = Core.createBlock("data_listcontents", {}, {
        LIST = Core.field(listName, listId)
    })
    
    return id, block, listId
end

---Create "add to list" block
---@param item any Item to add
---@param listName string List name
---@param listId string|nil List ID (auto-generated if nil)
---@return string id, SB3Builder.Block block, string listId List ID used
function Data.addToList(item, listName, listId)
    if not listId then
        listId = "list_" .. tostring(math.random(100000, 999999))
    end
    
    local id, block = Core.createBlock("data_addtolist", {
        ITEM = item
    }, {
        LIST = Core.field(listName, listId)
    })
    
    return id, block, listId
end

---Create "delete from list" block
---@param index any Index to delete (number or "all", "last")
---@param listName string List name
---@param listId string|nil List ID (auto-generated if nil)
---@return string id, SB3Builder.Block block, string listId List ID used
function Data.deleteFromList(index, listName, listId)
    if not listId then
        listId = "list_" .. tostring(math.random(100000, 999999))
    end
    
    local id, block = Core.createBlock("data_deleteoflist", {
        INDEX = index
    }, {
        LIST = Core.field(listName, listId)
    })
    
    return id, block, listId
end

---Create "delete all of list" block
---@param listName string List name
---@param listId string|nil List ID (auto-generated if nil)
---@return string id, SB3Builder.Block block, string listId List ID used
function Data.deleteAllOfList(listName, listId)
    if not listId then
        listId = "list_" .. tostring(math.random(100000, 999999))
    end
    
    local id, block = Core.createBlock("data_deletealloflist", {}, {
        LIST = Core.field(listName, listId)
    })
    
    return id, block, listId
end

---Create "insert at list" block
---@param index any Index to insert at
---@param item any Item to insert
---@param listName string List name
---@param listId string|nil List ID (auto-generated if nil)
---@return string id, SB3Builder.Block block, string listId List ID used
function Data.insertAtList(index, item, listName, listId)
    if not listId then
        listId = "list_" .. tostring(math.random(100000, 999999))
    end
    
    local id, block = Core.createBlock("data_insertatlist", {
        INDEX = index,
        ITEM = item
    }, {
        LIST = Core.field(listName, listId)
    })
    
    return id, block, listId
end

---Create "replace item of list" block
---@param index any Index to replace
---@param item any New item value
---@param listName string List name
---@param listId string|nil List ID (auto-generated if nil)
---@return string id, SB3Builder.Block block, string listId List ID used
function Data.replaceItemOfList(index, item, listName, listId)
    if not listId then
        listId = "list_" .. tostring(math.random(100000, 999999))
    end
    
    local id, block = Core.createBlock("data_replaceitemoflist", {
        INDEX = index,
        ITEM = item
    }, {
        LIST = Core.field(listName, listId)
    })
    
    return id, block, listId
end

---Create "item of list" reporter block
---@param index any Index to get
---@param listName string List name
---@param listId string|nil List ID (auto-generated if nil)
---@return string id, SB3Builder.Block block, string listId List ID used
function Data.itemOfList(index, listName, listId)
    if not listId then
        listId = "list_" .. tostring(math.random(100000, 999999))
    end
    
    local id, block = Core.createBlock("data_itemoflist", {
        INDEX = index
    }, {
        LIST = Core.field(listName, listId)
    })
    
    return id, block, listId
end

---Create "item # of list" reporter block
---@param item any Item to find index of
---@param listName string List name
---@param listId string|nil List ID (auto-generated if nil)
---@return string id, SB3Builder.Block block, string listId List ID used
function Data.itemNumOfList(item, listName, listId)
    if not listId then
        listId = "list_" .. tostring(math.random(100000, 999999))
    end
    
    local id, block = Core.createBlock("data_itemnumoflist", {
        ITEM = item
    }, {
        LIST = Core.field(listName, listId)
    })
    
    return id, block, listId
end

---Create "length of list" reporter block
---@param listName string List name
---@param listId string|nil List ID (auto-generated if nil)
---@return string id, SB3Builder.Block block, string listId List ID used
function Data.lengthOfList(listName, listId)
    if not listId then
        listId = "list_" .. tostring(math.random(100000, 999999))
    end
    
    local id, block = Core.createBlock("data_lengthoflist", {}, {
        LIST = Core.field(listName, listId)
    })
    
    return id, block, listId
end

---Create "list contains item" block
---@param item any Item to check for
---@param listName string List name
---@param listId string|nil List ID (auto-generated if nil)
---@return string id, SB3Builder.Block block, string listId List ID used
function Data.listContainsItem(item, listName, listId)
    if not listId then
        listId = "list_" .. tostring(math.random(100000, 999999))
    end
    
    local id, block = Core.createBlock("data_listcontainsitem", {
        ITEM = item
    }, {
        LIST = Core.field(listName, listId)
    })
    
    return id, block, listId
end

---Create "show list" block
---@param listName string List name
---@param listId string|nil List ID (auto-generated if nil)
---@return string id, SB3Builder.Block block, string listId List ID used
function Data.showList(listName, listId)
    if not listId then
        listId = "list_" .. tostring(math.random(100000, 999999))
    end
    
    local id, block = Core.createBlock("data_showlist", {}, {
        LIST = Core.field(listName, listId)
    })
    
    return id, block, listId
end

---Create "hide list" block
---@param listName string List name
---@param listId string|nil List ID (auto-generated if nil)
---@return string id, SB3Builder.Block block, string listId List ID used
function Data.hideList(listName, listId)
    if not listId then
        listId = "list_" .. tostring(math.random(100000, 999999))
    end
    
    local id, block = Core.createBlock("data_hidelist", {}, {
        LIST = Core.field(listName, listId)
    })
    
    return id, block, listId
end

return Data