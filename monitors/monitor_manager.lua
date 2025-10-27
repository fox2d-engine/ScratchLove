-- Monitor Manager
-- Simplified monitor system for logging-based data monitoring
local log = require("lib.log")
local MonitorRecord = require("monitors.monitor_record")

---@class MonitorManager
---@field monitors table<string, MonitorRecord> Active monitors by ID
---@field frameNumber number Current frame counter
---@field logInterval number Frames between monitor logs (60 = 1 second)
---@field enableLogging boolean Whether to output monitor logs
---@field runtime Runtime|nil Runtime reference for monitor evaluation
local MonitorManager = {}
MonitorManager.__index = MonitorManager

---Create a new monitor manager
---@param runtime Runtime|nil Runtime reference (optional, can be set later)
---@return MonitorManager
function MonitorManager:new(runtime)
    local self = setmetatable({}, MonitorManager)

    self.monitors = {}
    self.frameNumber = 0
    self.logInterval = 60     -- Log every 60 frames (1 second at 60fps)
    self.enableLogging = true -- Default: monitoring enabled
    self.runtime = runtime    -- Reference to runtime for evaluation

    log.debug("MonitorManager: Initialized with real-time evaluation (matches native Scratch)")
    return self
end

---Add a new monitor
---@param id string Monitor ID (block ID or variable ID)
---@param opcode string Operation code
---@param category string Block category
---@param label string Display label
---@param spriteName string|nil Sprite name (optional)
function MonitorManager:addMonitor(id, opcode, category, label, spriteName)
    if self.monitors[id] then
        -- Monitor already exists, just ensure it's visible
        self.monitors[id].visible = true
        return
    end

    self.monitors[id] = MonitorRecord:new(id, opcode, category, label, spriteName)

    log.info("MonitorManager: Added monitor '%s' (%s) for %s", label, category, spriteName or "stage")
end

---Remove a monitor
---@param id string Monitor ID
function MonitorManager:removeMonitor(id)
    if self.monitors[id] then
        self.monitors[id].visible = false
        log.info("MonitorManager: Removed monitor '%s'", id)
    end
end

---Set monitor visibility (for show/hide variable/list blocks)
---@param id string Monitor ID (variable or list ID)
---@param visible boolean Whether monitor should be visible
function MonitorManager:setVisible(id, visible)
    local monitor = self.monitors[id]
    if monitor then
        monitor.visible = visible
    end
end

---Set Variable reference for a monitor (for variable/list monitors)
---@param id string Monitor ID
---@param variable Variable Variable object to reference
function MonitorManager:setVariableReference(id, variable)
    local monitor = self.monitors[id]
    if monitor then
        monitor:setVariableReference(variable)
    end
end

---Set target reference for a monitor (for reporter monitors that need evaluation)
---@param id string Monitor ID
---@param target Sprite|Stage Target object (Sprite or Stage)
function MonitorManager:setTargetReference(id, target)
    local monitor = self.monitors[id]
    if monitor then
        monitor:setTargetReference(target)
        log.debug("MonitorManager: Set target reference for monitor '%s'", id)
    end
end

---Set monitor position and size from project data
---@param id string Monitor ID
---@param x number|nil X position (nil for auto-positioning)
---@param y number|nil Y position (nil for auto-positioning)
---@param width number|nil Width (0 or nil for auto-sizing)
---@param height number|nil Height (0 or nil for auto-sizing)
function MonitorManager:setPosition(id, x, y, width, height)
    local monitor = self.monitors[id]
    if monitor then
        monitor.x = x
        monitor.y = y
        monitor.width = width or 0
        monitor.height = height or 0
        log.debug("MonitorManager: Set position for monitor '%s': x=%s, y=%s", id, tostring(x), tostring(y))
    end
end

---Update frame counter and evaluate/log monitor values
---Native Scratch creates monitor threads every frame; we evaluate monitors directly for efficiency
---@param dt number Delta time
function MonitorManager:update(dt)
    self.frameNumber = self.frameNumber + 1

    if not self.enableLogging then
        return
    end

    -- Evaluate and log monitors at intervals (native evaluates every frame via monitor threads)
    -- We evaluate on-demand during logging for efficiency while maintaining real-time accuracy
    local hasLogged = false
    for id, monitor in pairs(self.monitors) do
        if monitor.visible and monitor:shouldLog(self.frameNumber, self.logInterval) then
            if not hasLogged then
                print("=== MONITORS (Frame " .. self.frameNumber .. ") ===")
                hasLogged = true
            end
            -- Evaluate monitor using current runtime state
            print("  " .. monitor:getLogString(self.runtime))
        end
    end
end

---Enable or disable monitor logging
---@param enabled boolean Whether to enable logging
function MonitorManager:setLogging(enabled)
    self.enableLogging = enabled
    log.info("MonitorManager: Logging " .. (enabled and "enabled" or "disabled"))
end

---Set logging interval
---@param frames number Frames between monitor logs
function MonitorManager:setLogInterval(frames)
    self.logInterval = frames
    log.info("MonitorManager: Log interval set to " .. frames .. " frames")
end

return MonitorManager
