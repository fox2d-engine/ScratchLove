-- Monitor Record
-- Simplified monitor data structure for logging-based monitoring
local log = require("lib.log")
local json = require("lib.json")
local BlockHelpers = require("runtime.block_helpers")

---@class MonitorRecord
---@field id string Block ID or variable ID
---@field spriteName string|nil Sprite name (if sprite-specific)
---@field targetId string|nil Target ID
---@field targetRef Sprite|Stage Direct reference to target (Sprite or Stage) for evaluation
---@field opcode string Operation code (e.g., "data_variable", "motion_xposition")
---@field variableRef Variable|nil Direct reference to Variable object (for variable/list monitors)
---@field params table|nil Block parameters
---@field mode string Display mode: 'default'|'large'|'slider'|'list'
---@field visible boolean Whether monitor is active
---@field category string Block category (for identification)
---@field label string Display label
---@field x number|nil Monitor X position (nil for auto-positioning)
---@field y number|nil Monitor Y position (nil for auto-positioning)
---@field width number Monitor width (0 for auto-sizing)
---@field height number Monitor height (0 for auto-sizing)
local MonitorRecord = {}
MonitorRecord.__index = MonitorRecord

---Create a new monitor record
---@param id string Monitor ID
---@param opcode string Operation code
---@param category string Block category
---@param label string Display label
---@param spriteName string|nil Sprite name (optional)
---@return MonitorRecord
function MonitorRecord:new(id, opcode, category, label, spriteName)
    local self = setmetatable({}, MonitorRecord)

    self.id = id
    self.opcode = opcode
    self.category = category
    self.label = label
    self.spriteName = spriteName
    self.targetId = nil
    self.targetRef = nil
    self.variableRef = nil
    self.params = nil
    self.mode = "default"
    self.visible = false

    -- Position and size (nil/0 for auto-positioning/sizing)
    self.x = nil
    self.y = nil
    self.width = 0
    self.height = 0

    return self
end

---Set direct reference to Variable object (for variable/list monitors)
---@param variable Variable Variable object to reference
function MonitorRecord:setVariableReference(variable)
    self.variableRef = variable
end

---Set direct reference to target (Sprite or Stage) for evaluation
---@param target Sprite|Stage Target object (Sprite or Stage)
function MonitorRecord:setTargetReference(target)
    self.targetRef = target
end

---This is called every frame to get the current value, similar to native's monitor threads
---@param runtime Runtime Runtime reference (for sensing blocks)
---@return any value Evaluated monitor value
function MonitorRecord:evaluate(runtime)
    -- Variable/list monitors use direct reference (already real-time)
    if self.variableRef then
        -- Return the raw value (not JSON encoded) so renderer can format it properly
        return self.variableRef.value
    end

    -- For other monitors, evaluate based on opcode and target reference
    local target = self.targetRef
    if not target then
        log.warn("Monitor '%s' has no targetRef - cannot evaluate", self.id)
        return nil
    end

    if self.opcode == "motion_xposition" then
        return target.x
    elseif self.opcode == "motion_yposition" then
        return target.y
    elseif self.opcode == "motion_direction" then
        return target.direction
    elseif self.opcode == "looks_size" then
        return target.size
    elseif self.opcode == "looks_costumenumbername" then
        -- params.NUMBER_NAME should be "number" or "name"
        if self.params and self.params.NUMBER_NAME == "name" then
            local costume = target.costumes[target.currentCostume + 1]
            return costume and costume.name or ""
        else
            return target.currentCostume + 1 -- Scratch uses 1-based costume numbers
        end
    elseif self.opcode == "looks_backdropnumbername" then
        -- Stage backdrop monitor (params.NUMBER_NAME: "number" or "name")
        if not runtime or not runtime.stage then
            return ""
        end
        if self.params and self.params.NUMBER_NAME == "name" then
            local backdrop = runtime.stage.costumes[runtime.stage.currentCostume + 1]
            return backdrop and backdrop.name or ""
        else
            return runtime.stage.currentCostume + 1
        end
    elseif self.opcode == "sensing_answer" then
        -- User input answer (from ask/answer blocks)
        return runtime and runtime.askState and runtime.askState.answer or ""
    elseif self.opcode == "sensing_loudness" then
        -- Microphone loudness (0-100)
        return runtime and runtime:getLoudness() or 0
    elseif self.opcode == "sensing_timer" then
        return runtime and runtime:getTimer() or 0
    elseif self.opcode == "sensing_current" then
        -- Current date/time value (params.CURRENTMENU: "year", "month", "date", "dayofweek", "hour", "minute", "second")
        local currentMenu = self.params and self.params.CURRENTMENU or "YEAR"
        return BlockHelpers.Sensing.current(target, currentMenu, runtime, nil)
    elseif self.opcode == "sensing_mousex" then
        return runtime and runtime.mouseX or 0
    elseif self.opcode == "sensing_mousey" then
        return runtime and runtime.mouseY or 0
    elseif self.opcode == "sound_volume" then
        return target.volume or 100
    else
        -- Unknown opcode
        log.warn("Monitor '%s' has unknown opcode: %s", self.id, self.opcode)
        return nil
    end
end

---Get current monitor value (evaluates real-time value)
---@param runtime Runtime Runtime reference for evaluation
---@return any value Current monitor value
function MonitorRecord:getCurrentValue(runtime)
    return self:evaluate(runtime)
end

---Get formatted string representation for logging
---@param runtime Runtime Runtime reference for evaluation
---@return string formatted Formatted monitor info
function MonitorRecord:getLogString(runtime)
    local valueStr = tostring(self:getCurrentValue(runtime))
    local spritePrefix = self.spriteName and (self.spriteName .. ": ") or ""
    return string.format("[%s] %s%s = %s", self.category:upper(), spritePrefix, self.label, valueStr)
end

---Check if monitor should be logged this frame
---@param frameNumber number Current frame number
---@param logInterval number Frames between logs (default: 60 for 1 second)
---@return boolean shouldLog Whether to log this frame
function MonitorRecord:shouldLog(frameNumber, logInterval)
    logInterval = logInterval or 60 -- Default to 1 second intervals
    -- Native Scratch evaluates monitors every frame, so we log at intervals
    return (frameNumber % logInterval == 0)
end

return MonitorRecord
