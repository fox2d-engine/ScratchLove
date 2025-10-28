-- Monitor Renderer
-- Renders variable/list monitors on the stage, matching native Scratch visual style
local log = require("lib.log")
local Global = require("global")

---@class MonitorRenderer
---@field monitorManager MonitorManager Monitor manager reference
---@field categoryColors table<string, table> Color mapping for monitor value backgrounds by category
---@field font love.Font Font for monitor text
---@field boldFont love.Font Bold font for monitor labels
local MonitorRenderer = {}
MonitorRenderer.__index = MonitorRenderer

-- Native Scratch monitor styling constants
local MONITOR_PADDING = 3        -- Internal padding (px)
local LABEL_MARGIN = 5           -- Horizontal margin for label (px)
local VALUE_PADDING = 2          -- Horizontal padding for value box (px)
local VALUE_MARGIN = 3           -- Margin between label and value box (px)
local BORDER_RADIUS = 4          -- Rounded corner radius (px)
local BORDER_WIDTH = 1           -- Border width (px)
local MIN_VALUE_WIDTH = 40       -- Minimum value box width (px)
local MONITOR_HEIGHT = 22        -- Total monitor height (px) for default mode

-- Category colors for value backgrounds (from native Scratch)
local CATEGORY_COLORS = {
    data = {1.0, 0.55, 0.1},      -- #FF8C1A (orange) - variables
    sensing = {0.36, 0.69, 0.84}, -- #5CB1D6 (light blue)
    sound = {0.81, 0.39, 0.81},   -- #CF63CF (magenta)
    looks = {0.6, 0.4, 1.0},      -- #9966FF (purple)
    motion = {0.3, 0.59, 1.0},    -- #4C97FF (blue)
    list = {0.99, 0.4, 0.17},     -- #FC662C (red-orange) - lists
    extension = {0.06, 0.74, 0.55} -- #0FBD8C (teal)
}

-- Background and border colors
local BG_COLOR = {1, 1, 1}           -- White background
local BORDER_COLOR = {0, 0, 0, 0.15} -- Semi-transparent black border
local TEXT_COLOR = {0, 0, 0}         -- Black text for labels
local VALUE_TEXT_COLOR = {1, 1, 1}   -- White text for values

---Create a new monitor renderer
---@param monitorManager MonitorManager Monitor manager instance
---@return MonitorRenderer
function MonitorRenderer:new(monitorManager)
    local self = setmetatable({}, MonitorRenderer)

    self.monitorManager = monitorManager
    self.categoryColors = CATEGORY_COLORS

    self.font = Global.cjkFont or love.graphics.getFont()
    -- For bold font, we'll use the same font but render with increased weight visually
    self.boldFont = self.font

    log.debug("MonitorRenderer: Initialized with native Scratch styling")
    return self
end

---Draw all visible monitors
---@param runtime Runtime Runtime reference for value evaluation
function MonitorRenderer:draw(runtime)
    if not self.monitorManager or not self.monitorManager.monitors or not next(self.monitorManager.monitors) then
        return
    end

    love.graphics.push("all")

    -- Draw each visible monitor
    for id, monitor in pairs(self.monitorManager.monitors) do
        if monitor.visible then
            self:drawMonitor(monitor, runtime)
        end
    end

    love.graphics.pop()
end

---Draw a single monitor in default mode
---@param monitor MonitorRecord Monitor to draw
---@param runtime Runtime Runtime reference for value evaluation
function MonitorRenderer:drawMonitor(monitor, runtime)
    -- Get current monitor value
    local value = monitor:getCurrentValue(runtime)
    if value == nil then
        value = ""
    end

    -- Format value for display
    local valueStr = self:formatValue(value, monitor)

    -- Build display label (sprite name prefix if applicable)
    local label = monitor.label
    if monitor.spriteName then
        label = monitor.spriteName .. ": " .. label
    end

    -- Calculate monitor dimensions (name and value on same row)
    local labelWidth = self.font:getWidth(label)
    local valueTextWidth = self.font:getWidth(valueStr)
    local valueBoxWidth = math.max(MIN_VALUE_WIDTH, valueTextWidth + VALUE_PADDING * 2)

    -- Total width: padding + label + margin + value box + padding
    local monitorWidth = MONITOR_PADDING + labelWidth + LABEL_MARGIN + valueBoxWidth + VALUE_MARGIN + MONITOR_PADDING
    local monitorHeight = MONITOR_HEIGHT

    -- Get monitor position (use auto-positioning if not set)
    local x, y = self:getMonitorPosition(monitor, monitorWidth, monitorHeight)

    -- Get category color for value background
    local categoryColor = self.categoryColors[monitor.category] or self.categoryColors.data

    -- Draw monitor background with border
    love.graphics.setColor(BG_COLOR)
    love.graphics.rectangle("fill", x, y, monitorWidth, monitorHeight, BORDER_RADIUS, BORDER_RADIUS)

    -- Draw border
    love.graphics.setColor(BORDER_COLOR)
    love.graphics.setLineWidth(BORDER_WIDTH)
    love.graphics.rectangle("line", x, y, monitorWidth, monitorHeight, BORDER_RADIUS, BORDER_RADIUS)

    -- Draw label (left-aligned, vertically centered)
    love.graphics.setColor(TEXT_COLOR)
    love.graphics.setFont(self.font)
    local labelX = x + MONITOR_PADDING
    local labelY = y + (monitorHeight - self.font:getHeight()) / 2
    love.graphics.print(label, labelX, labelY)

    -- Draw value box (colored background, right-aligned)
    local valueBoxX = x + MONITOR_PADDING + labelWidth + LABEL_MARGIN
    local valueBoxY = y + MONITOR_PADDING
    local valueBoxHeight = monitorHeight - MONITOR_PADDING * 2

    love.graphics.setColor(categoryColor)
    love.graphics.rectangle("fill", valueBoxX, valueBoxY, valueBoxWidth, valueBoxHeight, BORDER_RADIUS, BORDER_RADIUS)

    -- Draw value text (white, centered in value box)
    love.graphics.setColor(VALUE_TEXT_COLOR)
    love.graphics.setFont(self.font)
    local valueTextX = valueBoxX + (valueBoxWidth - valueTextWidth) / 2
    local valueTextY = valueBoxY + (valueBoxHeight - self.font:getHeight()) / 2
    love.graphics.print(valueStr, valueTextX, valueTextY)
end

---Format value for display
---@param value any Monitor value
---@param monitor MonitorRecord Monitor record
---@return string formatted Formatted value string
function MonitorRenderer:formatValue(value, monitor)
    -- Handle lists (show length instead of full content)
    if type(value) == "table" then
        return "length: " .. tostring(#value)
    end

    -- Handle numbers (round to 6 decimal places like native Scratch)
    if type(value) == "number" then
        -- Round to 6 decimal places and remove trailing zeros
        local rounded = math.floor(value * 1000000 + 0.5) / 1000000
        local str = string.format("%.6f", rounded)
        -- Remove trailing zeros and decimal point if not needed
        str = str:gsub("%.?0+$", "")
        return str
    end

    -- Convert to string
    return tostring(value)
end

---Get monitor position with auto-positioning fallback
---Native Scratch auto-positions monitors in a grid pattern starting at top-left
---@param monitor MonitorRecord Monitor record
---@param width number Monitor width
---@param height number Monitor height
---@return number x X position
---@return number y Y position
function MonitorRenderer:getMonitorPosition(monitor, width, height)
    -- Use explicit position from project data if available
    if monitor.x ~= nil and monitor.y ~= nil then
        return monitor.x, monitor.y
    end

    -- Auto-positioning fallback: stack monitors vertically on the left side
    local x = 10
    local y = 10

    -- Calculate Y offset based on monitor index (simple stacking)
    local index = 0
    for id, m in pairs(self.monitorManager.monitors) do
        if m.visible and m.id ~= monitor.id then
            if m.id < monitor.id then -- Simple ordering by ID
                index = index + 1
            end
        end
    end

    y = y + index * (height + 5) -- 5px gap between monitors

    return x, y
end

return MonitorRenderer
