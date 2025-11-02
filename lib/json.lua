--
-- json.lua - High-performance JSON library wrapper
--
-- This module provides a transparent wrapper around lua-cjson (C implementation)
-- with fallback to pure Lua implementation if cjson is not available.
--
-- Features:
-- - 4-9x faster than pure Lua implementation
-- - TurboWarp JSON extensions (Infinity, NaN, -Infinity)
-- - Preserves JSON object key order via metatable
-- - 100% compatible with existing json.lua API
--

local json = {}

-- Try to load cjson (C implementation) for better performance
local has_cjson, cjson = pcall(function()
    -- Prepend project local path (highest priority - searched first)
    package.cpath = "lib/lua-cjson/?.so;" .. package.cpath

    -- Add user luarocks path if not already configured
    -- (users can configure globally via: eval "$(luarocks --lua-version 5.1 path)")
    local home = os.getenv("HOME")
    if home and not package.cpath:find(home .. "/.luarocks/lib/lua/5.1/", 1, true) then
        package.cpath = package.cpath .. ";" .. home .. "/.luarocks/lib/lua/5.1/?.so"
    end

    return require("cjson")
end)

if has_cjson then
    -- Print the actual path where cjson was loaded from
    local cjson_path = package.searchpath("cjson", package.cpath)
    print("JSON library: Using lua-cjson (C implementation)")
    print("  Loaded from: " .. (cjson_path or "unknown path"))
    print("  Version: " .. (cjson._VERSION or "unknown"))
else
    print("JSON library: Falling back to pure Lua implementation")
end

if has_cjson then
    -- Configure cjson with enhanced features
    cjson.decode_keep_key_order(true)
    cjson.decode_turbowarp_extensions(true)
    cjson.decode_null_as_nil(true)  -- Decode null as nil (compatible with json.lua)

    -- Wrap cjson API to match json.lua interface
    json._version = "cjson-enhanced-" .. (cjson._VERSION or "2.1devel")
    json._implementation = "C (lua-cjson)"

    ---Decode JSON string to Lua table
    ---@param str string JSON string to decode
    ---@return table result Decoded Lua table with __keyOrder metadata
    function json.decode(str)
        return cjson.decode(str)
    end

    ---Encode Lua table to JSON string
    ---@param val table|string|number|boolean Lua value to encode
    ---@return string json JSON string
    function json.encode(val)
        return cjson.encode(val)
    end

    ---Extract key order from a table's metatable (if available)
    ---@param tbl table Table that may contain __keyOrder in metatable
    ---@return string[]|nil order Array of keys in original JSON order, or nil if not available
    function json.getKeyOrder(tbl)
        return cjson.get_key_order(tbl)
    end

else
    -- Fallback to pure Lua implementation
    local json_pure = require("lib.json_pure")

    json._version = json_pure._version .. "-pure"
    json._implementation = "Pure Lua"

    json.decode = json_pure.decode
    json.encode = json_pure.encode
    json.getKeyOrder = json_pure.getKeyOrder
end

return json
