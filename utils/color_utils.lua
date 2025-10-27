---@class ColorUtils
---Color conversion utilities for HSV/RGB transformations
---Provides consistent color space conversions across the codebase
local ColorUtils = {}

---Convert HSV to RGB using standard algorithm
---@param h number Hue in degrees (0-360)
---@param s number Saturation (0-1)
---@param v number Value/Brightness (0-1)
---@return number r Red (0-1)
---@return number g Green (0-1)
---@return number b Blue (0-1)
function ColorUtils.hsvToRgb(h, s, v)
    -- Clamp values to valid ranges
    h = h % 360
    if h < 0 then h = h + 360 end
    s = math.max(0, math.min(1, s))
    v = math.max(0, math.min(1, v))

    local c = v * s
    local x = c * (1 - math.abs(((h / 60) % 2) - 1))
    local m = v - c

    local r, g, b = 0, 0, 0
    local sector = math.floor(h / 60) % 6

    if sector == 0 then
        r, g, b = c, x, 0
    elseif sector == 1 then
        r, g, b = x, c, 0
    elseif sector == 2 then
        r, g, b = 0, c, x
    elseif sector == 3 then
        r, g, b = 0, x, c
    elseif sector == 4 then
        r, g, b = x, 0, c
    else
        r, g, b = c, 0, x
    end

    return r + m, g + m, b + m
end

---Convert RGB to HSV
---@param r number Red (0-1)
---@param g number Green (0-1)
---@param b number Blue (0-1)
---@return number h Hue in degrees (0-360)
---@return number s Saturation (0-1)
---@return number v Value (0-1)
function ColorUtils.rgbToHsv(r, g, b)
    local max = math.max(r, g, b)
    local min = math.min(r, g, b)
    local delta = max - min

    local h, s, v = 0, 0, max

    if delta > 0 and max > 0 then
        s = delta / max

        if max == r then
            h = 60 * (((g - b) / delta) % 6)
        elseif max == g then
            h = 60 * ((b - r) / delta + 2)
        else
            h = 60 * ((r - g) / delta + 4)
        end
    end

    if h < 0 then h = h + 360 end

    return h, s, v
end

---Convert Scratch HSV values (0-100 range) to RGB (0-1 range)
---@param hue number Hue (0-100)
---@param saturation number Saturation (0-100)
---@param brightness number Brightness (0-100)
---@return number r Red (0-1)
---@return number g Green (0-1)
---@return number b Blue (0-1)
function ColorUtils.scratchHsvToRgb(hue, saturation, brightness)
    -- Normalize hue to 0-100 range
    hue = hue % 100
    if hue < 0 then
        hue = hue + 100
    end

    -- Convert Scratch values to standard HSV ranges
    local h = hue * 360 / 100        -- 0-100 -> 0-360
    local s = saturation / 100       -- 0-100 -> 0-1
    local v = brightness / 100       -- 0-100 -> 0-1

    return ColorUtils.hsvToRgb(h, s, v)
end

---Convert RGB (0-1 range) to Scratch HSV values (0-100 range)
---@param r number Red (0-1)
---@param g number Green (0-1)
---@param b number Blue (0-1)
---@return number hue Hue (0-100)
---@return number saturation Saturation (0-100)
---@return number brightness Brightness (0-100)
function ColorUtils.rgbToScratchHsv(r, g, b)
    local h, s, v = ColorUtils.rgbToHsv(r, g, b)

    -- Convert to Scratch ranges (0-100)
    local hue = (h * 100) / 360
    if hue < 0 then hue = hue + 100 end
    local saturation = s * 100
    local brightness = v * 100

    return hue, saturation, brightness
end

return ColorUtils
