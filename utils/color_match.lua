-- Fast Color Matching Utilities
-- Replicates native Scratch color matching logic using bitwise operations
-- Optimized for array-based color access [1][2][3] instead of .r .g .b

local bit = require("bit")

---@class ColorMatch
local ColorMatch = {}

local bit_band = bit.band
local math_floor = math.floor

---Native Scratch color matching with array inputs
---Equivalent to: (a[0] & 0b11111000) === (b[0] & 0b11111000) && ...
---@param color1 number[] RGB color array [r, g, b] (0-255)
---@param color2 number[] RGB color array [r, g, b] (0-255)
---@return boolean matches True if colors match within Scratch tolerance
local function colorMatchesArray(color1, color2)
    -- Use bitwise AND to mask out lower bits for approximate matching
    -- R and G: mask 0b11111000 (keep upper 5 bits, tolerance ~8)
    -- B: mask 0b11110000 (keep upper 4 bits, tolerance ~16)
    return bit_band(color1[1], 0xF8) == bit_band(color2[1], 0xF8) and
        bit_band(color1[2], 0xF8) == bit_band(color2[2], 0xF8) and
        bit_band(color1[3], 0xF0) == bit_band(color2[3], 0xF0)
end

---Native Scratch color matching function (individual values)
---@param r1 number Red component 1 (0-255)
---@param g1 number Green component 1 (0-255)
---@param b1 number Blue component 1 (0-255)
---@param r2 number Red component 2 (0-255)
---@param g2 number Green component 2 (0-255)
---@param b2 number Blue component 2 (0-255)
---@return boolean matches True if colors match within Scratch tolerance
local function colorMatches(r1, g1, b1, r2, g2, b2)
    return bit_band(r1, 0xF8) == bit_band(r2, 0xF8) and
        bit_band(g1, 0xF8) == bit_band(g2, 0xF8) and
        bit_band(b1, 0xF0) == bit_band(b2, 0xF0)
end

---Optimized version using precomputed masks for arrays
---@param color number[] RGB color array [r, g, b] (0-255)
---@return number[] masked Masked color [r_masked, g_masked, b_masked]
local function applyColorMaskArray(color)
    return {
        bit_band(color[1], 0xF8),
        bit_band(color[2], 0xF8),
        bit_band(color[3], 0xF0)
    }
end

---Single-pass mask application for individual values
---@param r number Red component (0-255)
---@param g number Green component (0-255)
---@param b number Blue component (0-255)
---@return number r_masked Masked red component
---@return number g_masked Masked green component
---@return number b_masked Masked blue component
local function applyColorMask(r, g, b)
    return bit_band(r, 0xF8), bit_band(g, 0xF8), bit_band(b, 0xF0)
end

---Compare pre-masked arrays
---@param mask1 number[] Masked color array [r, g, b]
---@param mask2 number[] Masked color array [r, g, b]
---@return boolean matches True if masked colors match exactly
local function maskedColorsMatchArray(mask1, mask2)
    return mask1[1] == mask2[1] and mask1[2] == mask2[2] and mask1[3] == mask2[3]
end

---Compare pre-masked individual values
---@param mask_r1 number Masked red component 1
---@param mask_g1 number Masked green component 1
---@param mask_b1 number Masked blue component 1
---@param mask_r2 number Masked red component 2
---@param mask_g2 number Masked green component 2
---@param mask_b2 number Masked blue component 2
---@return boolean matches True if masked colors match exactly
local function maskedColorsMatch(mask_r1, mask_g1, mask_b1, mask_r2, mask_g2, mask_b2)
    return mask_r1 == mask_r2 and mask_g1 == mask_g2 and mask_b1 == mask_b2
end

---Convert 0-1 range color array to 0-255 range
---@param r number Red component (0-1)
---@param g number Green component (0-1)
---@param b number Blue component (0-1)
---@return number r_byte Red component (0-255)
---@return number g_byte Green component (0-255)
---@return number b_byte Blue component (0-255)
local function normalizedToBytes(r, g, b)
    return math_floor(r * 255 + 0.5), math_floor(g * 255 + 0.5), math_floor(b * 255 + 0.5)
end

-- Export functions
ColorMatch.colorMatches = colorMatches
ColorMatch.colorMatchesArray = colorMatchesArray
ColorMatch.applyColorMask = applyColorMask
ColorMatch.applyColorMaskArray = applyColorMaskArray
ColorMatch.maskedColorsMatch = maskedColorsMatch
ColorMatch.maskedColorsMatchArray = maskedColorsMatchArray
ColorMatch.normalizedToBytes = normalizedToBytes

return ColorMatch
