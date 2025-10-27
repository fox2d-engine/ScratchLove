-- Variable
-- Represents a Scratch variable (scalar, list, or broadcast message)

---@class Variable
---@field id string Variable ID
---@field name string Variable name
---@field type string Variable type ("", "list", or "broadcast_msg")
---@field isCloud boolean Whether the variable is stored in the cloud
---@field value any Variable value (number for scalar, array for list, string for broadcast)
local Variable = {}
Variable.__index = Variable

-- Type constants matching original Scratch
Variable.SCALAR_TYPE = ""
Variable.LIST_TYPE = "list"
Variable.BROADCAST_MESSAGE_TYPE = "broadcast_msg"

---Create a new variable
---@param id string|nil Variable ID (will generate one if nil)
---@param name string Variable name
---@param type string Variable type (SCALAR_TYPE, LIST_TYPE, or BROADCAST_MESSAGE_TYPE)
---@param isCloud boolean|nil Whether the variable is stored in the cloud (default: false)
---@return Variable
function Variable:new(id, name, type, isCloud)
    local self = setmetatable({}, Variable)

    self.id = id or self:generateUID()
    self.name = name
    self.type = type or Variable.SCALAR_TYPE
    self.isCloud = isCloud or false

    -- Set default value based on type
    if self.type == Variable.SCALAR_TYPE then
        self.value = 0
    elseif self.type == Variable.LIST_TYPE then
        self.value = {}
    elseif self.type == Variable.BROADCAST_MESSAGE_TYPE then
        self.value = self.name
    else
        error("Invalid variable type: " .. tostring(self.type))
    end

    return self
end

---Generate a unique ID for this variable
---@return string
function Variable:generateUID()
    -- Simple UID generation - could be made more sophisticated if needed
    return "var_" .. tostring(os.time()) .. "_" .. tostring(math.random(1000, 9999))
end

---Check if this is a scalar variable
---@return boolean
function Variable:isScalar()
    return self.type == Variable.SCALAR_TYPE
end

---Check if this is a list variable
---@return boolean
function Variable:isList()
    return self.type == Variable.LIST_TYPE
end

---Check if this is a broadcast message variable
---@return boolean
function Variable:isBroadcast()
    return self.type == Variable.BROADCAST_MESSAGE_TYPE
end

---Convert variable to string representation (for debugging)
---@return string
function Variable:toString()
    return string.format("Variable{id=%s, name=%s, type=%s, value=%s}",
                        self.id, self.name, self.type, tostring(self.value))
end

return Variable