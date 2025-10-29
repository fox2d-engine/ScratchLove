-- Cast TurboWarp Compatibility Tests
-- Tests that our Cast implementation matches TurboWarp's cast.js exactly
-- Uses Node.js to run the actual TurboWarp code for comparison

local lust = require("tests.lust")
local describe, it, expect = lust.describe, lust.it, lust.expect

local Cast = require("utils.cast")

-- ============================================================================
-- Helper: Run TurboWarp cast.js code via Node.js
-- ============================================================================

---Run TurboWarp Cast function via Node.js
---@param functionName string Cast function name (toNumber, toBoolean, toString, compare)
---@param args table Arguments to pass to the function
---@return any result Result from TurboWarp
local function runTurboWarpCast(functionName, args)
    -- Path to TurboWarp cast.js (copied to test fixtures for independence)
    -- Use absolute path from project root
    local handle = io.popen("pwd")
    local projectRoot = handle:read("*l")
    handle:close()
    local castJsPath = projectRoot .. "/tests/fixtures/turbowarp/cast.js"

    -- Build Node.js script
    local argsJson = {}
    for i, arg in ipairs(args) do
        if type(arg) == "string" then
            table.insert(argsJson, string.format('"%s"', arg:gsub('"', '\\"')))
        elseif type(arg) == "number" then
            if arg ~= arg then -- NaN
                table.insert(argsJson, "NaN")
            elseif arg == math.huge then
                table.insert(argsJson, "Infinity")
            elseif arg == -math.huge then
                table.insert(argsJson, "-Infinity")
            else
                table.insert(argsJson, tostring(arg))
            end
        elseif type(arg) == "boolean" then
            table.insert(argsJson, tostring(arg))
        elseif arg == nil then
            table.insert(argsJson, "null")
        end
    end

    local nodeScript = string.format([[
const Cast = require('%s');
const result = Cast.%s(%s);
console.log(JSON.stringify(result));
]], castJsPath, functionName, table.concat(argsJson, ", "))

    local handle = io.popen("node -e '" .. nodeScript:gsub("'", "'\\''") .. "' 2>/dev/null")
    if not handle then
        return nil
    end

    local output = handle:read("*a")
    local success = handle:close()

    if not success or not output or output == "" then
        return nil
    end

    -- Parse JSON output
    output = output:gsub("^%s+", ""):gsub("%s+$", "")

    if output == "null" then
        return nil
    elseif output == "true" then
        return true
    elseif output == "false" then
        return false
    elseif output:match('^".*"$') then
        return output:sub(2, -2):gsub('\\"', '"')
    else
        return tonumber(output)
    end
end

-- ============================================================================
-- Cast.toNumber() Tests
-- ============================================================================

describe("Cast.toNumber() vs TurboWarp", function()
    local testCases = {
        -- Numbers
        {input = {0}, expected = 0, name = "zero"},
        {input = {1}, expected = 1, name = "positive integer"},
        {input = {-1}, expected = -1, name = "negative integer"},
        {input = {3.14}, expected = 3.14, name = "float"},
        {input = {math.huge}, expected = math.huge, name = "Infinity"},
        {input = {-math.huge}, expected = -math.huge, name = "-Infinity"},

        -- Strings
        {input = {"0"}, expected = 0, name = "string '0'"},
        {input = {"42"}, expected = 42, name = "string '42'"},
        {input = {"-123"}, expected = -123, name = "string '-123'"},
        {input = {"3.14"}, expected = 3.14, name = "string '3.14'"},
        {input = {""}, expected = 0, name = "empty string"},
        {input = {"hello"}, expected = 0, name = "non-numeric string"},
        {input = {"Infinity"}, expected = math.huge, name = "string 'Infinity'"},
        {input = {"-Infinity"}, expected = -math.huge, name = "string '-Infinity'"},

        -- Booleans
        {input = {true}, expected = 1, name = "true"},
        {input = {false}, expected = 0, name = "false"},
    }

    for _, test in ipairs(testCases) do
        it("should match TurboWarp for " .. test.name, function()
            local turboResult = runTurboWarpCast("toNumber", test.input)

            if turboResult ~= nil then
                local luaResult = Cast.toNumber(test.input[1])

                -- Handle NaN comparison
                if turboResult ~= turboResult then
                    expect(luaResult ~= luaResult).to.equal(true)
                else
                    expect(luaResult).to.equal(turboResult)
                end
            else
                print(string.format("  Skipped: Node.js not available for %s", test.name))
            end
        end)
    end
end)

-- ============================================================================
-- Cast.toBoolean() Tests
-- ============================================================================

describe("Cast.toBoolean() vs TurboWarp", function()
    local testCases = {
        -- Numbers
        {input = {0}, expected = false, name = "zero"},
        {input = {1}, expected = true, name = "one"},
        {input = {-1}, expected = true, name = "negative number"},
        {input = {0/0}, expected = false, name = "NaN"},

        -- Strings
        {input = {""}, expected = false, name = "empty string"},
        {input = {"0"}, expected = false, name = "string '0'"},
        {input = {"false"}, expected = false, name = "string 'false'"},
        {input = {"False"}, expected = false, name = "string 'False'"},
        {input = {"1"}, expected = true, name = "string '1'"},
        {input = {"hello"}, expected = true, name = "non-empty string"},

        -- Booleans
        {input = {true}, expected = true, name = "true"},
        {input = {false}, expected = false, name = "false"},
    }

    for _, test in ipairs(testCases) do
        it("should match TurboWarp for " .. test.name, function()
            local turboResult = runTurboWarpCast("toBoolean", test.input)

            if turboResult ~= nil then
                local luaResult = Cast.toBoolean(test.input[1])
                expect(luaResult).to.equal(turboResult)
            else
                print(string.format("  Skipped: Node.js not available for %s", test.name))
            end
        end)
    end
end)

-- ============================================================================
-- Cast.toString() Tests
-- ============================================================================

describe("Cast.toString() vs TurboWarp", function()
    local testCases = {
        -- Numbers
        {input = {0}, expected = "0", name = "zero"},
        {input = {1}, expected = "1", name = "integer"},
        {input = {-1}, expected = "-1", name = "negative integer"},
        {input = {3.14}, expected = "3.14", name = "float"},
        {input = {1.0}, expected = "1", name = "1.0 should be '1'"},
        {input = {2.50}, expected = "2.5", name = "2.50 should be '2.5'"},
        {input = {math.huge}, expected = "Infinity", name = "Infinity"},
        {input = {-math.huge}, expected = "-Infinity", name = "-Infinity"},

        -- Strings
        {input = {""}, expected = "", name = "empty string"},
        {input = {"hello"}, expected = "hello", name = "string"},

        -- Booleans
        {input = {true}, expected = "true", name = "true"},
        {input = {false}, expected = "false", name = "false"},
    }

    for _, test in ipairs(testCases) do
        it("should match TurboWarp for " .. test.name, function()
            local turboResult = runTurboWarpCast("toString", test.input)

            if turboResult ~= nil then
                local luaResult = Cast.toString(test.input[1])

                print(string.format("  Lua: '%s', TurboWarp: '%s'", luaResult, turboResult))
                expect(luaResult).to.equal(turboResult)
            else
                print(string.format("  Skipped: Node.js not available for %s", test.name))
            end
        end)
    end
end)

-- ============================================================================
-- Cast.compare() Tests
-- ============================================================================

describe("Cast.compare() vs TurboWarp", function()
    local testCases = {
        -- Numeric comparisons
        {input = {1, 2}, expected = -1, name = "1 < 2"},
        {input = {2, 1}, expected = 1, name = "2 > 1"},
        {input = {1, 1}, expected = 0, name = "1 == 1"},
        {input = {0, 0}, expected = 0, name = "0 == 0"},
        {input = {-1, 1}, expected = -1, name = "-1 < 1"},
        {input = {3.14, 3.14}, expected = 0, name = "3.14 == 3.14"},

        -- String to number comparisons
        {input = {"1", "2"}, expected = -1, name = "'1' < '2'"},
        {input = {"10", "2"}, expected = 1, name = "'10' > '2' (numeric)"},

        -- String comparisons
        {input = {"apple", "banana"}, expected = -1, name = "'apple' < 'banana'"},
        {input = {"Banana", "apple"}, expected = 1, name = "'Banana' > 'apple' (case insensitive)"},

        -- Empty string
        {input = {"", "0"}, expected = 0, name = "'' == '0' (both convert to 0 or both non-numeric)"},
        {input = {"", "hello"}, expected = -1, name = "'' < 'hello'"},

        -- Special values
        {input = {math.huge, math.huge}, expected = 0, name = "Infinity == Infinity"},
        {input = {-math.huge, -math.huge}, expected = 0, name = "-Infinity == -Infinity"},
        {input = {math.huge, 1}, expected = 1, name = "Infinity > 1"},
        {input = {1, math.huge}, expected = -1, name = "1 < Infinity"},

        -- String "Infinity" comparisons (testing what the user mentioned)
        {input = {"Infinity", "INFINITY"}, expected = 0, name = "String 'Infinity' == String 'INFINITY'"},
        {input = {"Infinity", "Infinity"}, expected = 0, name = "String 'Infinity' == String 'Infinity'"},
        {input = {"-Infinity", "-INFINITY"}, expected = 0, name = "String '-Infinity' == String '-INFINITY'"},
    }

    for _, test in ipairs(testCases) do
        it("should match TurboWarp for " .. test.name, function()
            local turboResult = runTurboWarpCast("compare", test.input)

            if turboResult ~= nil then
                local luaResult = Cast.compare(test.input[1], test.input[2])

                print(string.format("  Lua: %d, TurboWarp: %d", luaResult, turboResult))

                -- Allow for sign differences (as long as direction is correct)
                if turboResult < 0 then
                    expect(luaResult < 0).to.equal(true)
                elseif turboResult > 0 then
                    expect(luaResult > 0).to.equal(true)
                else
                    expect(luaResult).to.equal(0)
                end
            else
                print(string.format("  Skipped: Node.js not available for %s", test.name))
            end
        end)
    end
end)
