-- Cast utility functions
-- Similar to Scratch Foundation's Cast tool class
-- Handles type conversion and precision limiting
---@class Cast
local Cast = {}

-- Import stringx for efficient string operations
local stringx = require("pl.stringx")


-- Constants for list operations
Cast.LIST_INVALID = "INVALID"
Cast.LIST_ALL = "ALL"
Cast.LIST_ITEM_LIMIT = 200000

local function isINF(value)
    return value == math.huge or value == -math.huge
end

---Parse string to number with infinity handling (shared utility)
---@param value string String to parse
---@param returnNaNOnInvalid boolean Return NaN instead of 0 for invalid inputs
---@return number result Parsed number
local function parseStringToNumber(value, returnNaNOnInvalid)
    -- Try direct numeric conversion first
    local num = tonumber(value)
    if num ~= nil and not isINF(num) then
        return num
    end

    -- Handle whitespace
    local trimmed = stringx.strip(value)
    if trimmed == "" then
        return 0
    end

    -- Handle exact infinity cases (case-sensitive, matching JavaScript behavior)
    -- JavaScript's Number() only recognizes "Infinity" and "-Infinity" (exact case)
    if trimmed == "Infinity" then
        return math.huge
    end
    if trimmed == "-Infinity" then
        return -math.huge
    end

    -- Any other variation (e.g., "INFINITY", "infinity") should be treated as NaN
    return returnNaNOnInvalid and (0 / 0) or 0
end

---Convert value to number following Scratch conversion rules
---@param value any Input value
---@return number result Converted number or 0 if invalid
function Cast.toNumber(value)
    if type(value) == "number" then
        return value
    end

    if type(value) == "string" then
        return parseStringToNumber(value, false)
    end

    if type(value) == "boolean" then
        return value and 1 or 0
    end

    return 0
end

---Convert value to number following Scratch conversion rules, preserving NaN
---Similar to toNumber but allows NaN to pass through (like JavaScript's +x)
---@param value any Input value
---@return number result Converted number (may be NaN)
function Cast.toNumberOrNaN(value)
    if type(value) == "number" then
        -- Return as-is, including NaN and Infinity
        return value
    end

    if type(value) == "string" then
        return parseStringToNumber(value, true)
    end

    if type(value) == "boolean" then
        return value and 1 or 0
    end

    -- For nil and other types, return NaN
    return 0 / 0
end

---Convert value to string following Scratch conversion rules
---@param value any Input value
---@return string result Converted string
function Cast.toString(value)
    if type(value) == "string" then
        return value
    end

    if type(value) == "number" then
        -- Handle special cases
        if value == math.huge then
            return "Infinity"
        end
        if value == -math.huge then
            return "-Infinity"
        end
        if value ~= value then -- NaN
            return "NaN"
        end

        -- Convert to string
        local str = tostring(value)

        -- Remove trailing zeros and decimal point if not needed (Lua-specific: tostring(1.0) = "1.0")
        if str:find("%.") then
            str = str:gsub("%.?0+$", "")
        end

        return str
    end

    if type(value) == "boolean" then
        return value and "true" or "false"
    end

    if value == nil then
        return "undefined" -- Match original Scratch behavior
    end

    if type(value) == "table" then
        return "[object Object]" -- Match original Scratch behavior
    end

    return tostring(value)
end

---Convert value to boolean following Scratch conversion rules
---@param value any Input value
---@return boolean result Converted boolean
function Cast.toBoolean(value)
    if type(value) == "boolean" then
        return value
    end

    if type(value) == "string" then
        -- Empty string, "0", and "false" are falsy (case-insensitive for "false")
        if value == "" or value == "0" or value:lower() == "false" then
            return false
        end
        -- All other strings are truthy
        return true
    end

    -- Coerce other values
    -- In Lua: nil and false are falsy, everything else is truthy
    return value ~= nil and value ~= false and value ~= 0 and value == value -- 0 and NaN are falsy
end

---Used internally by compare() - checks if a string that converts to 0 is actually zero
---@param val any Value that evaluates to 0 in string-to-number conversion
---@return boolean result True if the value should not be treated as the number zero
local function isNotActuallyZero(val)
    if type(val) ~= "string" then
        return false
    end
    -- Empty string should be treated as NaN
    if #val == 0 then
        return true
    end
    -- Check each character - if any is not '0' or tab, it's not actually zero
    for i = 1, #val do
        local code = string.byte(val, i)
        -- '0'.byte() = 48, '\t'.byte() = 9
        if code ~= 48 and code ~= 9 then
            return true
        end
    end
    return false
end

-- Convert to numbers like JavaScript Number() - this is different from Cast.toNumber!
-- JavaScript Number() returns NaN for unrecognized strings, which we need for proper comparison
local function jsNumber(value)
    if type(value) == "number" then
        return value
    end
    if type(value) == "string" then
        return parseStringToNumber(value, true)
    end
    if type(value) == "boolean" then
        return value and 1 or 0
    end
    return 0 / 0 -- NaN
end

---Compare two values following Scratch comparison rules
---@param a any First value
---@param b any Second value
---@return number result -1 if a < b, 0 if equal, 1 if a > b
function Cast.compare(a, b)
    -- Convert values using jsNumber for numeric comparison
    local numA = jsNumber(a)
    local numB = jsNumber(b)

    -- Handle strings that convert to 0 but aren't actually zero
    if numA == 0 and isNotActuallyZero(a) then
        numA = 0 / 0 -- NaN
    end
    if numB == 0 and isNotActuallyZero(b) then
        numB = 0 / 0 -- NaN
    end

    -- If both can be converted to numbers (not NaN), compare numerically
    if numA == numA and numB == numB then -- NaN check (NaN ~= NaN)
        -- Handle special case of Infinity (like native Scratch)
        if (numA == math.huge and numB == math.huge) or
            (numA == -math.huge and numB == -math.huge) then
            return 0
        end

        -- Compare as numbers directly
        return numA - numB
    end

    -- Otherwise compare as case-insensitive strings
    -- Convert to string (handle Lua's math.huge -> "inf" vs JS's Infinity -> "Infinity")
    local strA = a == math.huge and "Infinity" or (a == -math.huge and "-Infinity" or tostring(a))
    local strB = b == math.huge and "Infinity" or (b == -math.huge and "-Infinity" or tostring(b))
    strA = strA:lower()
    strB = strB:lower()

    if strA < strB then
        return -1
    elseif strA > strB then
        return 1
    else
        return 0
    end
end

---Check if a value is a valid number
---@param value any Input value
---@return boolean result True if value is or can be converted to a valid number
function Cast.isNumber(value)
    if type(value) == "number" then
        return value == value -- Check for NaN
    end

    if type(value) == "string" then
        local num = tonumber(value)
        if num ~= nil then
            return true
        end
        local trimmed = stringx.strip(value)
        if trimmed == "" then
            return true -- Empty string converts to 0
        end
        return trimmed == "Infinity" or trimmed == "-Infinity"
    end

    return type(value) == "boolean"
end

---Convert hex color string to RGB values (0-1 range)
---@param hexColor string Hex color string (e.g., "#FF0000" or "FF0000")
---@return table|nil result RGB table {r, g, b} with values 0-1, or nil if invalid
function Cast.hexToRGB(hexColor)
    if not hexColor or type(hexColor) ~= "string" then
        return nil
    end

    -- Remove # prefix if present
    local hex = hexColor:gsub("#", "")

    -- Validate hex string length
    if #hex ~= 6 then
        return nil
    end

    -- Convert hex to RGB (0-1 range for Love2D compatibility)
    local r = tonumber(hex:sub(1, 2), 16)
    local g = tonumber(hex:sub(3, 4), 16)
    local b = tonumber(hex:sub(5, 6), 16)

    -- Validate conversion
    if not r or not g or not b then
        return nil
    end

    -- Normalize to 0-1 range
    return {
        r = r / 255,
        g = g / 255,
        b = b / 255
    }
end

---Convert RGB values (0-1 range) to hex color string
---@param r number Red component (0-1)
---@param g number Green component (0-1)
---@param b number Blue component (0-1)
---@return string result Hex color string with # prefix (e.g., "#FF0000")
function Cast.rgbToHex(r, g, b)
    -- Clamp values to 0-1 range
    r = math.max(0, math.min(1, r or 0))
    g = math.max(0, math.min(1, g or 0))
    b = math.max(0, math.min(1, b or 0))

    -- Convert to 0-255 range and format as hex
    local hexR = string.format("%02X", math.floor(r * 255 + 0.5))
    local hexG = string.format("%02X", math.floor(g * 255 + 0.5))
    local hexB = string.format("%02X", math.floor(b * 255 + 0.5))

    return "#" .. hexR .. hexG .. hexB
end

---Convert hex color string to RGB values (0-255 range)
---@param hexColor string Hex color string (e.g., "#FF0000" or "FF0000")
---@return table|nil result RGB table {r, g, b} with values 0-255, or nil if invalid
function Cast.hexToRGB255(hexColor)
    local rgb = Cast.hexToRGB(hexColor)
    if not rgb then
        return nil
    end

    return {
        r = math.floor(rgb.r * 255 + 0.5),
        g = math.floor(rgb.g * 255 + 0.5),
        b = math.floor(rgb.b * 255 + 0.5)
    }
end

---Convert Scratch list index to 1-based Lua index
---Handles special values like "all", "last", "random", "any"
---OPTIMIZATION: Scratch and Lua both use 1-based indexing - no conversion needed!
---This is a major advantage over JavaScript which requires complex offset calculations
---@param index any Scratch index value
---@param length number Current length of the list
---@param acceptAll boolean Whether to accept "all" as valid
---@return string|number result LIST_INVALID, LIST_ALL, or 1-based index
function Cast.toListIndex(index, length, acceptAll)
    if type(index) ~= "number" then
        if index == "all" then
            return acceptAll and Cast.LIST_ALL or Cast.LIST_INVALID
        end
        if index == "last" then
            if length > 0 then
                return length
            end
            return Cast.LIST_INVALID
        elseif index == "random" or index == "any" then
            if length > 0 then
                return math.random(1, length)
            end
            return Cast.LIST_INVALID
        end
    end

    -- Convert to number and floor it
    local numIndex = math.floor(Cast.toNumber(index))
    if numIndex < 1 or numIndex > length then
        return Cast.LIST_INVALID
    end

    return numIndex
end

---Math utility function equivalent to native Scratch's wrapClamp
---@param n number Value to clamp
---@param min number Minimum value
---@param max number Maximum value
---@return number result Wrapped value within range [min, max]
function Cast.wrapClamp(n, min, max)
    local range = (max - min) + 1
    return n - (math.floor((n - min) / range) * range)
end

---Convert list contents to string using Scratch's data_listcontents logic
---This matches the exact behavior of the native Scratch data_listcontents block
---@param listValue table Array of list items
---@return string result String representation of list contents
function Cast.listContentsToString(listValue)
    if #listValue == 0 then
        return ""
    end

    -- Convert all items to strings first (most efficient approach)
    local stringItems = {}
    local allSingleLetters = true

    for i, item in ipairs(listValue) do
        local str = Cast.toString(item)
        stringItems[i] = str
        if allSingleLetters and #str ~= 1 then
            allSingleLetters = false
        end
    end

    -- Use table.concat for efficient string joining
    -- No separator if all single characters, space otherwise
    local separator = allSingleLetters and "" or " "
    return table.concat(stringItems, separator)
end

---Generate random number using Scratch's random logic
---@param from any From value (will be converted to number)
---@param to any To value (will be converted to number)
---@return number result Random number within range
function Cast.random(from, to)
    -- Check if inputs are string integers (native Scratch behavior)
    local fromStr = Cast.toString(from)
    local toStr = Cast.toString(to)
    local fromNum = Cast.toNumber(from)
    local toNum = Cast.toNumber(to)

    if fromNum > toNum then
        fromNum, toNum = toNum, fromNum
    end

    -- Check if both original inputs are integers (including string integers)
    local fromIsInt = (fromStr and fromStr:match("^%-?%d+$")) or (math.floor(fromNum) == fromNum)
    local toIsInt = (toStr and toStr:match("^%-?%d+$")) or (math.floor(toNum) == toNum)

    if fromIsInt and toIsInt then
        return math.random(fromNum, toNum)
    else
        return fromNum + math.random() * (toNum - fromNum)
    end
end

---Join two strings following Scratch join logic
---@param string1 any First string (will be converted to string)
---@param string2 any Second string (will be converted to string)
---@return string result Concatenated string
function Cast.join(string1, string2)
    local str1 = Cast.toString(string1)
    local str2 = Cast.toString(string2)
    return str1 .. str2
end

---Get a letter from a string at specified position (1-indexed, like Scratch)
---@param position any Position in string (will be converted to number)
---@param str any String to extract from (will be converted to string)
---@return string result Single character at position, or empty string if out of bounds
function Cast.letterOf(position, str)
    local string = Cast.toString(str)
    local pos = math.floor(Cast.toNumber(position))

    -- Scratch uses 1-based indexing
    if pos < 1 or pos > #string then
        return ""
    end

    return string:sub(pos, pos)
end

---Get the length of a string
---@param str any String to measure (will be converted to string)
---@return number result Length of the string
function Cast.length(str)
    local string = Cast.toString(str)
    return #string
end

---Check if a string contains another string (case-insensitive like Scratch)
---@param haystack any String to search in (will be converted to string)
---@param needle any String to search for (will be converted to string)
---@return boolean result True if haystack contains needle (case-insensitive)
function Cast.contains(haystack, needle)
    local haystackStr = Cast.toString(haystack):lower()
    local needleStr = Cast.toString(needle):lower()

    return haystackStr:find(needleStr, 1, true) ~= nil
end

---Converts coordinate to Scratch precision (rounds to nearest integer for values close to integers)
---@param value number Coordinate value
---@return number rounded Rounded coordinate
function Cast.toScratchCoordinate(value)
    local num = Cast.toNumber(value)
    -- Scratch rounds coordinates that are very close to integers to integers
    -- Native uses 1e-9 threshold (see scratch3_motion.js limitPrecision)
    local rounded = math.floor(num + 0.5)
    if math.abs(num - rounded) < 1e-9 then
        return rounded
    end
    return num
end

---Converts value to string with Scratch display formatting (for say/think blocks)
---@param value any Value to format
---@return string formatted Formatted string
function Cast.toScratchDisplayString(value)
    if type(value) == "number" then
        if value == math.floor(value) then
            -- Integer - display without decimal places
            return tostring(math.floor(value))
        else
            -- Float - Scratch rounds to 2 decimal places, but preserves small numbers
            local rounded = math.floor(value * 100 + 0.5) / 100
            if rounded == 0 and value ~= 0 then
                -- Small number that would round to 0 - keep original precision
                return tostring(value)
            else
                -- Normal case - format with 2 decimal places
                return string.format("%.2f", rounded)
            end
        end
    else
        return Cast.toString(value)
    end
end

---@param n any Dividend
---@param modulus any Divisor
---@return number result Modulo result
function Cast.mod(n, modulus)
    local num = Cast.toNumber(n)
    local mod = Cast.toNumber(modulus)

    -- Handle division by zero
    if mod == 0 then
        return 0 / 0 -- NaN
    end

    -- Lua's % operator behavior differs from Scratch/JavaScript
    -- Scratch uses floored division modulo (like Python)
    local result = num % mod

    -- Adjust result to match Scratch behavior
    if (result < 0 and mod > 0) or (result > 0 and mod < 0) then
        result = result + mod
    end

    return result
end

---Check if a list contains an item (case-insensitive like Scratch)
---@param listValue table Array of list items
---@param item any Item to search for
---@return boolean result True if list contains item
function Cast.listContains(listValue, item)
    local searchStr = Cast.toString(item):lower()

    for _, listItem in ipairs(listValue) do
        local listItemStr = Cast.toString(listItem):lower()
        if listItemStr == searchStr then
            return true
        end
    end

    return false
end

---Find the index of an item in a list (case-insensitive like Scratch)
---@param listValue table Array of list items
---@param item any Item to search for
---@return number result 1-based index of item, or 0 if not found
function Cast.listIndexOf(listValue, item)
    local searchStr = Cast.toString(item):lower()

    for i, listItem in ipairs(listValue) do
        local listItemStr = Cast.toString(listItem):lower()
        if listItemStr == searchStr then
            return i
        end
    end

    return 0
end

---Get the contents of a list as a string
---@param listValue table Array of list items
---@return string result String representation of list contents
function Cast.listContents(listValue)
    return Cast.listContentsToString(listValue)
end

---Get item from list with proper index handling (for compiler use)
---Matches the exact behavior of data_itemoflist block
---@param listValue table Array of list items
---@param index any Index value (number, "last", etc.)
---@return any result Item value (preserving original type) or empty string if invalid
function Cast.listGet(listValue, index)
    local idx = Cast.toListIndex(index, #listValue, false)
    if idx == Cast.LIST_INVALID then
        return ""
    end
    local item = listValue[idx]
    -- Return original value if exists, empty string if slot is nil/empty
    return item ~= nil and item or ""
end

return Cast
