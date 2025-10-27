--
-- log.lua
--
-- Copyright (c) 2016 rxi
--
-- This library is free software; you can redistribute it and/or modify it
-- under the terms of the MIT license. See LICENSE for details.
--

---@class LogMode
---@field name string The name of the log level
---@field color string ANSI color code for terminal output

---@class Log
---@field _version string Library version
---@field usecolor boolean Whether to use colors in console output
---@field level string Current log level threshold
---@field trace fun(...: any): nil Log trace level message
---@field debug fun(...: any): nil Log debug level message
---@field info fun(...: any): nil Log info level message
---@field warn fun(...: any): nil Log warn level message
---@field error fun(...: any): nil Log error level message
---@field fatal fun(...: any): nil Log fatal level message
local log = { _version = "0.1.0" }

log.usecolor = true
log.level = os.getenv("LOG_LEVEL") or "info"
log.flushEachLine = os.getenv("LOG_FLUSH") == "1"

---@type LogMode[]
local modes = {
    { name = "trace", color = "\27[34m", },
    { name = "debug", color = "\27[36m", },
    { name = "info",  color = "\27[32m", },
    { name = "warn",  color = "\27[33m", },
    { name = "error", color = "\27[31m", },
    { name = "fatal", color = "\27[35m", },
}

---@type table<string, integer>
local levels = {}
for i, v in ipairs(modes) do
    levels[v.name] = i
end

---Round a number to the specified increment
---@param x number The number to round
---@param increment? number The increment to round to (default: 1)
---@return number rounded The rounded number
local round = function(x, increment)
    increment = increment or 1
    x = x / increment
    return (x > 0 and math.floor(x + .5) or math.ceil(x - .5)) * increment
end


local _tostring = tostring

---Convert arguments to string with number rounding and format support
---@param format string|any First argument - if string with % patterns, treat as format string
---@param ... any Additional arguments for formatting or concatenation
---@return string result Formatted or concatenated string representation
local tostring = function(format, ...)
    local numArgs = select('#', ...)

    -- If first argument is a string containing % and we have additional arguments,
    -- treat it as a format string
    if type(format) == "string" and numArgs > 0 and format:find("%%") then
        local args = {}
        for i = 1, numArgs do
            local x = select(i, ...)
            if type(x) == "number" then
                x = round(x, .01)
            end
            args[i] = x
        end
        return string.format(format, unpack(args))
    else
        -- Original behavior: concatenate all arguments with spaces
        local t = {}
        local x = format
        if type(x) == "number" then
            x = round(x, .01)
        end
        t[1] = _tostring(x)

        for i = 1, numArgs do
            local x = select(i, ...)
            if type(x) == "number" then
                x = round(x, .01)
            end
            t[#t + 1] = _tostring(x)
        end
        return table.concat(t, " ")
    end
end


for i, x in ipairs(modes) do
    local nameupper = x.name:upper()
    ---@type function
    local logFunction = function(...)
        -- Return early if we're below the log level
        if i < levels[log.level] then
            return
        end

        local msg = tostring(...)
        local info = debug.getinfo(2, "Sl")
        local lineinfo = info and (info.short_src .. ":" .. info.currentline) or "unknown"

        -- Output to console
        print(string.format("%s[%-6s%s]%s %s: %s",
            log.usecolor and x.color or "",
            nameupper,
            os.date("%H:%M:%S"),
            log.usecolor and "\27[0m" or "",
            lineinfo,
            msg))
        if log.flushEachLine then
            io.stdout:flush()
        end
    end

    -- Assign the function to the log table
    rawset(log, x.name, logFunction)
end

---@type Log
return log
