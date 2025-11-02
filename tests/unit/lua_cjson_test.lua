-- lua-cjson enhanced features test
-- This test validates that lua-cjson produces identical results to json.lua
-- for all existing functionality, plus adds new features
local lust = require("tests.lust")
local describe, it, expect = lust.describe, lust.it, lust.expect

describe("lua-cjson vs json.lua compatibility", function()
    local cjson, jsonlua

    lust.before(function()
        -- Load both implementations
        package.cpath = package.cpath .. ";lib/lua-cjson/?.so"
        cjson = require("cjson")
        jsonlua = require("lib.json_pure")  -- Use pure Lua implementation for comparison
    end)

    describe("standard JSON parsing - should be identical", function()
        local testCases = {
            {name = "simple object", json = '{"name": "test", "value": 123}'},
            {name = "nested object", json = '{"outer": {"inner": "value"}}'},
            {name = "array", json = '[1, 2, 3, 4, 5]'},
            {name = "mixed types without null", json = '{"str": "hello", "num": 42, "bool": true}'},
            {name = "empty object", json = '{}'},
            {name = "empty array", json = '[]'},
            {name = "string escapes", json = '{"escaped": "line1\\nline2\\ttab"}'},
            {name = "unicode", json = '{"emoji": "😀", "chinese": "中文"}'},
        }

        for _, tc in ipairs(testCases) do
            it("should parse " .. tc.name .. " identically", function()
                local result_cjson = cjson.decode(tc.json)
                local result_jsonlua = jsonlua.decode(tc.json)

                -- Deep compare (simplified for basic types)
                local function deepEqual(a, b)
                    if type(a) ~= type(b) then return false end
                    if type(a) ~= "table" then return a == b end

                    for k, v in pairs(a) do
                        if not deepEqual(v, b[k]) then return false end
                    end
                    for k in pairs(b) do
                        if a[k] == nil then return false end
                    end
                    return true
                end

                expect(deepEqual(result_cjson, result_jsonlua)).to.equal(true)
            end)
        end

        describe("null value handling with decode_null_as_nil option", function()
            it("should decode null as lightuserdata by default (cjson standard)", function()
                local cjson_default = cjson.new()
                local result = cjson_default.decode('{"value": null}')

                -- Default: null → lightuserdata(NULL)
                expect(type(result.value)).to.equal("userdata")
                expect(result.value).to.equal(cjson_default.null)
                expect(result.value == nil).to.equal(false)

                -- lightuserdata is truthy!
                expect(result.value and true or false).to.equal(true)
                if result.value then
                    -- This WILL execute - potential bug source
                else
                    error("lightuserdata should be truthy")
                end
            end)

            it("should decode null as nil when decode_null_as_nil enabled", function()
                local cjson_nil = cjson.new()
                cjson_nil.decode_null_as_nil(true)
                local result = cjson_nil.decode('{"value": null}')

                -- With decode_null_as_nil: null → nil
                expect(type(result.value)).to.equal("nil")
                expect(result.value).to.equal(nil)
                expect(result.value == nil).to.equal(true)

                -- nil is falsy!
                expect(result.value and true or false).to.equal(false)
                if result.value then
                    error("nil should be falsy")
                else
                    -- This will execute - correct behavior
                end
            end)

            it("should match json.lua behavior with decode_null_as_nil enabled", function()
                local cjson_nil = cjson.new()
                cjson_nil.decode_null_as_nil(true)

                local result_cjson = cjson_nil.decode('{"value": null}')
                local result_jsonlua = jsonlua.decode('{"value": null}')

                -- Both should return nil
                expect(result_cjson.value).to.equal(nil)
                expect(result_jsonlua.value).to.equal(nil)
                expect(result_cjson.value).to.equal(result_jsonlua.value)
            end)

            it("should handle null in arrays", function()
                local cjson_nil = cjson.new()
                cjson_nil.decode_null_as_nil(true)

                local result = cjson_nil.decode('[1, null, 3]')
                expect(result[1]).to.equal(1)
                expect(result[2]).to.equal(nil)  -- Array keeps nil values
                expect(result[3]).to.equal(3)
            end)

            it("should handle null in nested objects", function()
                local cjson_nil = cjson.new()
                cjson_nil.decode_null_as_nil(true)

                local result = cjson_nil.decode('{"outer": {"inner": null}}')
                expect(result.outer.inner).to.equal(nil)
                expect(type(result.outer.inner)).to.equal("nil")
            end)

            it("should handle mixed null and other falsy values", function()
                local cjson_nil = cjson.new()
                cjson_nil.decode_null_as_nil(true)

                local result = cjson_nil.decode('{"a": null, "b": 0, "c": false, "d": ""}')
                expect(result.a).to.equal(nil)
                expect(result.b).to.equal(0)
                expect(result.c).to.equal(false)
                expect(result.d).to.equal("")

                -- In Lua: only nil and false are falsy, everything else is truthy!
                expect(not result.a).to.equal(true)   -- nil is falsy
                expect(not result.b).to.equal(false)  -- 0 is truthy in Lua!
                expect(not result.c).to.equal(true)   -- false is falsy
                expect(not result.d).to.equal(false)  -- empty string is truthy in Lua!
            end)
        end)
    end)

    describe("TurboWarp JSON extensions - should match json.lua behavior", function()
        it("should parse Infinity identically to json.lua", function()
            local cjson_tw = cjson.new()
            cjson_tw.decode_turbowarp_extensions(true)

            local json_str = '{"value": Infinity}'
            local result_cjson = cjson_tw.decode(json_str)
            local result_jsonlua = jsonlua.decode(json_str)

            expect(result_cjson.value).to.equal(result_jsonlua.value)
            expect(result_cjson.value).to.equal(math.huge)
        end)

        it("should parse -Infinity identically to json.lua", function()
            local cjson_tw = cjson.new()
            cjson_tw.decode_turbowarp_extensions(true)

            local json_str = '{"value": -Infinity}'
            local result_cjson = cjson_tw.decode(json_str)
            local result_jsonlua = jsonlua.decode(json_str)

            expect(result_cjson.value).to.equal(result_jsonlua.value)
            expect(result_cjson.value).to.equal(-math.huge)
        end)

        it("should parse NaN identically to json.lua", function()
            local cjson_tw = cjson.new()
            cjson_tw.decode_turbowarp_extensions(true)

            local json_str = '{"value": NaN}'
            local result_cjson = cjson_tw.decode(json_str)
            local result_jsonlua = jsonlua.decode(json_str)

            -- NaN != NaN, so check both are NaN
            expect(tostring(result_cjson.value)).to.equal("nan")
            expect(tostring(result_jsonlua.value)).to.equal("nan")
        end)

        it("should handle Infinity when TurboWarp extensions disabled (via decode_invalid_numbers)", function()
            local cjson_default = cjson.new()
            -- cjson has decode_invalid_numbers=1 by default, which allows Infinity via fallback parsing
            -- This is different from TurboWarp extensions which parse "Infinity" literal
            -- Both should work when enabled

            -- With decode_invalid_numbers=1 (default), it parses via json_is_invalid_number path
            local success, result = pcall(function()
                return cjson_default.decode('{"value": Infinity}')
            end)

            -- cjson default behavior (decode_invalid_numbers=1) accepts Infinity
            expect(success).to.equal(true)
            if success then
                expect(result.value).to.equal(math.huge)
            end
        end)
    end)

    describe("keyOrder tracking - should match json.lua __keyOrder behavior", function()
        it("should track JSON object key order identically to json.lua", function()
            local cjson_order = cjson.new()
            cjson_order.decode_keep_key_order(true)

            local json_str = '{"z": 1, "a": 2, "m": 3}'
            local result_cjson = cjson_order.decode(json_str)
            local result_jsonlua = jsonlua.decode(json_str)

            local keyOrder_cjson = cjson_order.get_key_order(result_cjson)
            local keyOrder_jsonlua = jsonlua.getKeyOrder(result_jsonlua)

            expect(keyOrder_cjson).to_not.equal(nil)
            expect(keyOrder_jsonlua).to_not.equal(nil)
            expect(#keyOrder_cjson).to.equal(#keyOrder_jsonlua)

            for i = 1, #keyOrder_cjson do
                expect(keyOrder_cjson[i]).to.equal(keyOrder_jsonlua[i])
            end
        end)

        it("should handle empty objects identically to json.lua", function()
            local cjson_order = cjson.new()
            cjson_order.decode_keep_key_order(true)

            local result_cjson = cjson_order.decode('{}')
            local result_jsonlua = jsonlua.decode('{}')

            local keyOrder_cjson = cjson_order.get_key_order(result_cjson)
            local keyOrder_jsonlua = jsonlua.getKeyOrder(result_jsonlua)

            expect(keyOrder_cjson).to_not.equal(nil)
            expect(keyOrder_jsonlua).to_not.equal(nil)
            expect(#keyOrder_cjson).to.equal(0)
            expect(#keyOrder_jsonlua).to.equal(0)
        end)

        it("should handle nested objects identically to json.lua", function()
            local cjson_order = cjson.new()
            cjson_order.decode_keep_key_order(true)

            local json_str = '{"outer1": {"inner1": 1, "inner2": 2}, "outer2": 3}'
            local result_cjson = cjson_order.decode(json_str)
            local result_jsonlua = jsonlua.decode(json_str)

            local outerOrder_cjson = cjson_order.get_key_order(result_cjson)
            local outerOrder_jsonlua = jsonlua.getKeyOrder(result_jsonlua)

            for i = 1, #outerOrder_cjson do
                expect(outerOrder_cjson[i]).to.equal(outerOrder_jsonlua[i])
            end

            local innerOrder_cjson = cjson_order.get_key_order(result_cjson.outer1)
            local innerOrder_jsonlua = jsonlua.getKeyOrder(result_jsonlua.outer1)

            for i = 1, #innerOrder_cjson do
                expect(innerOrder_cjson[i]).to.equal(innerOrder_jsonlua[i])
            end
        end)

        it("should not track keyOrder when disabled (default)", function()
            local cjson_default = cjson.new()

            local result = cjson_default.decode('{"z": 1, "a": 2}')
            local keyOrder = cjson_default.get_key_order(result)

            expect(keyOrder).to.equal(nil)
        end)
    end)

    describe("combined features", function()
        it("should handle both TurboWarp extensions and keyOrder together", function()
            local cjson_combined = cjson.new()
            cjson_combined.decode_turbowarp_extensions(true)
            cjson_combined.decode_keep_key_order(true)

            local json_str = '{"infinity": Infinity, "nan": NaN, "normal": 42}'
            local result = cjson_combined.decode(json_str)

            expect(result.infinity).to.equal(math.huge)
            expect(tostring(result.nan)).to.equal("nan")
            expect(result.normal).to.equal(42)

            local keyOrder = cjson_combined.get_key_order(result)
            expect(keyOrder[1]).to.equal("infinity")
            expect(keyOrder[2]).to.equal("nan")
            expect(keyOrder[3]).to.equal("normal")
        end)
    end)

    describe("backward compatibility", function()
        it("should work with standard JSON by default", function()
            local cjson_default = cjson.new()

            local json_str = '{"name": "test", "value": 123, "nested": {"key": "value"}}'
            local result = cjson_default.decode(json_str)

            expect(result.name).to.equal("test")
            expect(result.value).to.equal(123)
            expect(result.nested.key).to.equal("value")
        end)
    end)
end)
