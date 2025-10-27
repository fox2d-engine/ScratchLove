-- Pen State
-- Manages pen state for sprites and clones with Scratch-compatible properties
local log = require("lib.log")
local ColorUtils = require("utils.color_utils")

---@class PenState
---@field down boolean Whether pen is currently down
---@field size number Pen size in stage pixels (1-1200)
---@field hue number Pen hue (0-100, wrapping) - maps to HSV H
---@field saturation number Pen saturation (0-100) - maps to HSV S  
---@field brightness number Pen brightness (0-100) - maps to HSV V
---@field transparency number Pen transparency (0-100, 0 is opaque)
---@field _shade number Legacy shade value for Scratch 2.0 compatibility
---@field shade number Getter for legacy shade value
---@field lastX number|nil Last X position when pen was down (Scratch coordinates)
---@field lastY number|nil Last Y position when pen was down (Scratch coordinates)
local PenState = {}
PenState.__index = function(t, k)
    if k == "shade" then
        return t._shade
    end
    return PenState[k]
end

---Create a new pen state with Scratch default values
---@return PenState
function PenState:new()
    local self = setmetatable({}, PenState)

    -- Scratch default pen properties (matching scratch3_pen/index.js)
    self.down = false
    self.size = 1.0           -- Default pen size
    self.hue = 66.66          -- Default hue (matches Scratch 3.0 native default: blue color)
    self.saturation = 100.0   -- Full saturation by default
    self.brightness = 100.0   -- Full brightness by default (NOT white!)
    self.transparency = 0.0   -- Fully opaque
    self._shade = 50.0        -- Legacy shade value for Scratch 2.0 blocks
    self.lastX = nil          -- No previous position
    self.lastY = nil          -- No previous position

    return self
end

---Create a copy of this pen state (for cloning)
---@return PenState copy A new pen state with the same values
function PenState:clone()
    local copy = PenState:new()
    copy.down = self.down
    copy.size = self.size
    copy.hue = self.hue
    copy.saturation = self.saturation
    copy.brightness = self.brightness
    copy.transparency = self.transparency
    copy._shade = self._shade
    copy.lastX = self.lastX
    copy.lastY = self.lastY
    return copy
end

---Set pen down state
---@param down boolean True to put pen down, false to lift pen up
---@param x number|nil Current X position (only set lastX/lastY if going down)
---@param y number|nil Current Y position
function PenState:setDown(down, x, y)
    if down and not self.down then
        -- Pen going down - record current position as last position
        -- Don't draw a point, wait for next movement
        self.lastX = x
        self.lastY = y
    elseif not down and self.down then
        -- Pen going up - don't update last position
        -- Next pen down will establish new starting point
    end
    self.down = down
end

---Set pen size without clamping
---NOTE: Clamping is now handled by BlockHelpers.Pen based on miscLimits
---@param size number Pen size
function PenState:setSize(size)
    self.size = size
end

---Change pen size by amount without clamping
---NOTE: Clamping is now handled by BlockHelpers.Pen based on miscLimits
---@param change number Amount to change size by
function PenState:changeSize(change)
    self.size = self.size + change
end

---Set pen hue with wrapping
---@param hue number Hue value (0-100, wraps around)
function PenState:setHue(hue)
    self.hue = hue % 100
    if self.hue < 0 then
        self.hue = self.hue + 100
    end
end

---Change pen hue by amount with wrapping
---@param change number Amount to change hue by
function PenState:changeHue(change)
    self:setHue(self.hue + change)
end

---Set pen saturation with clamping
---@param saturation number Saturation value (0-100)
function PenState:setSaturation(saturation)
    self.saturation = math.max(0, math.min(100, saturation))
end

---Change pen saturation by amount with clamping
---@param change number Amount to change saturation by
function PenState:changeSaturation(change)
    self:setSaturation(self.saturation + change)
end

---Set pen brightness with clamping
---@param brightness number Brightness value (0-100)
function PenState:setBrightness(brightness)
    self.brightness = math.max(0, math.min(100, brightness))
end

---Change pen brightness by amount with clamping
---@param change number Amount to change brightness by
function PenState:changeBrightness(change)
    self:setBrightness(self.brightness + change)
end

---Set pen shade (legacy Scratch 2.0 compatibility) with proper wrap clamping
---@param shade number Shade value (0-200, modulo wrapping like Scratch 2.0)
function PenState:setShade(shade)
    -- Wrap clamp the shade value the way Scratch 2 did (0-200 range)
    shade = shade % 200
    if shade < 0 then
        shade = shade + 200
    end

    self._shade = shade
    self:legacyUpdatePenColor()
end

---Change pen shade by amount (legacy Scratch 2.0 compatibility)
---@param change number Amount to change shade by
function PenState:changeShade(change)
    self:setShade(self._shade + change)
end

---Update pen color from hue and shade values using Scratch 2.0 legacy algorithm
---This matches the _legacyUpdatePenColor method in scratch3_pen/index.js
function PenState:legacyUpdatePenColor()
    -- Create the new color in RGB using the Scratch 2 "shade" model
    -- Convert hue (0-100) to degrees (0-360) for HSV calculation
    local h = (self.hue * 360) / 100
    local s = 1.0 -- Full saturation for legacy color calculation
    local v = 1.0 -- Full brightness for legacy color calculation

    -- Convert HSV to RGB using shared utility
    local r, g, b = ColorUtils.hsvToRgb(h, s, v)

    -- Apply shade mixing (shade > 100 means darker, shade < 100 means toward white/black)
    local shade = (self._shade > 100) and (200 - self._shade) or self._shade
    if shade < 50 then
        -- Mix with black
        local factor = (10 + shade) / 60
        r = 0 * (1 - factor) + r * factor
        g = 0 * (1 - factor) + g * factor
        b = 0 * (1 - factor) + b * factor
    else
        -- Mix with white
        local factor = (shade - 50) / 60
        r = r * (1 - factor) + 1 * factor
        g = g * (1 - factor) + 1 * factor
        b = b * (1 - factor) + 1 * factor
    end

    -- Convert back to HSV to update pen state using shared utility
    local newH, newS, newV = ColorUtils.rgbToHsv(r, g, b)

    -- Convert back to Scratch ranges (0-100)
    self.hue = (newH * 100) / 360
    if self.hue < 0 then self.hue = self.hue + 100 end
    self.saturation = newS * 100
    self.brightness = newV * 100
end

---Set pen transparency with clamping
---@param transparency number Transparency value (0-100, 0 is opaque)
function PenState:setTransparency(transparency)
    self.transparency = math.max(0, math.min(100, transparency))
end

---Change pen transparency by amount with clamping
---@param change number Amount to change transparency by
function PenState:changeTransparency(change)
    self:setTransparency(self.transparency + change)
end

---Update position and potentially queue a line draw command
---@param x number New X position (Scratch coordinates)
---@param y number New Y position (Scratch coordinates)
---@param penRenderer PenRenderer Pen renderer to queue commands to
---@return boolean drawn True if a line was drawn
function PenState:updatePosition(x, y, penRenderer)
    if not self.down or not penRenderer then
        -- Pen is up or no renderer - just update position silently
        if self.down then
            -- Keep track of position even when pen is down for potential future lines
            self.lastX = x
            self.lastY = y
        end
        return false
    end

    -- Pen is down and we have a renderer
    if self.lastX ~= nil and self.lastY ~= nil then
        -- We have a previous position - draw a line
        if self.lastX ~= x or self.lastY ~= y then
            penRenderer:queueLine(
                self.lastX, self.lastY,
                x, y,
                self.size, self.hue, self.saturation, self.brightness, self.transparency
            )
        end
    else
        log.debug("PenState: Pen down but no previous position, setting start point at (%.2f,%.2f)", x, y)
    end

    -- Update last position
    self.lastX = x
    self.lastY = y
    return true
end

---Set pen color from Scratch hue value (legacy compatibility)
---@param colorValue number Color value (treated as hue in 0-100 range, matches native Scratch)
function PenState:setColorFromHue(colorValue)
    self:setHue(colorValue)
end

---Set pen color from RGB hex value
---@param hexValue number RGB hex value (0x000000 to 0xFFFFFF)
function PenState:setColorFromRGB(hexValue)
    -- Convert RGB to HSV to get hue, saturation, brightness
    local r = (math.floor(hexValue / 65536) % 256) / 255
    local g = (math.floor(hexValue / 256) % 256) / 255
    local b = (hexValue % 256) / 255

    local max = math.max(r, g, b)
    local min = math.min(r, g, b)
    local delta = max - min

    local hue = 0
    local saturation = 0
    local brightness = max * 100 -- Convert to 0-100 range

    if delta > 0 and max > 0 then
        saturation = (delta / max) * 100 -- Convert to 0-100 range

        if max == r then
            hue = 60 * (((g - b) / delta) % 6)
        elseif max == g then
            hue = 60 * ((b - r) / delta + 2)
        else
            hue = 60 * ((r - g) / delta + 4)
        end
    end

    -- Convert hue from 0-360 to 0-100 range (native uses penState.color = (hsv.h / 360) * 100)
    hue = (hue * 100) / 360

    -- Set HSV values directly
    self:setHue(hue)
    self:setSaturation(saturation)
    self:setBrightness(brightness)
    self:setTransparency(0) -- Native resets transparency to 0

end

---Get current pen properties as a readable table
---@return table properties Current pen properties
function PenState:getProperties()
    return {
        down = self.down,
        size = self.size,
        hue = self.hue,
        saturation = self.saturation,
        brightness = self.brightness,
        transparency = self.transparency,
        _shade = self._shade,
        lastPosition = self.lastX and { self.lastX, self.lastY } or nil
    }
end

---Reset pen state to defaults (used by "erase all" - only clears canvas, not pen state)
function PenState:resetDefaults()
    -- Note: "erase all" in Scratch only clears the canvas, not pen properties
    -- This method is provided for completeness but shouldn't be called by "erase all"
    self.down = false
    self.size = 1.0
    self.hue = 66.66
    self.saturation = 100.0
    self.brightness = 100.0
    self.transparency = 0.0
    self._shade = 50.0
    self.lastX = nil
    self.lastY = nil
end

---Reset position tracking (used when sprite teleports or pen is lifted)
function PenState:resetPosition()
    self.lastX = nil
    self.lastY = nil
end

return PenState
