#!/usr/bin/env luajit

-- Test Runner
-- Usage: luajit tests/run.lua [pattern] [--only test_case_pattern]
-- pattern: optional wildcard pattern to match test files (e.g., "data" matches "*data*")
-- --only: run only test cases matching the given pattern

-- Set up package path to find project modules
local testPath = debug.getinfo(1, "S").source:match("@(.*/)")
local projectRoot = testPath:gsub("tests/$", "")
package.path = projectRoot .. "?.lua;" .. projectRoot .. "?/init.lua;" .. package.path

-- Set up mock environment for Love2D (only mock the external dependencies)
local MockLove = require("tests.mocks.love_mock")
MockLove.install()

-- Import testing framework
local lust = require("tests.lust")

-- CRITICAL: Reset mock state before each test to prevent state pollution
-- This ensures consistent behavior between single test runs and full test suite
lust.before(function()
    MockLove.reset()
end)

-- CRITICAL: Warmup - create a dummy Runtime to initialize all modules
-- Some modules have initialization side effects on first use
-- This ensures consistent behavior between single test runs and full test suite
local function warmupModules()
    local ProjectModel = require("parser.project_model")
    local Runtime = require("vm.runtime")
    local SB3Builder = require("tests.sb3_builder")

    SB3Builder.resetCounter()
    local stage = SB3Builder.createStage()
    local sprite = SB3Builder.createSprite("_WarmupSprite")
    local projectJson = SB3Builder.createProject({stage, sprite})
    local warmupProject = ProjectModel:new(projectJson, {})
    local warmupRuntime = Runtime:new(warmupProject)
    -- Don't need to initialize, just creating the instance is enough
end

warmupModules()


-- Color definitions (similar to lib/log.lua)
local colors = {
    reset = "\27[0m",
    bright = "\27[1m",
    green = "\27[32m",
    cyan = "\27[36m",
    yellow = "\27[33m",
    red = "\27[31m",
    blue = "\27[34m",
    magenta = "\27[35m"
}

-- Check if colors should be used (similar to log.lua's approach)
local usecolor = true
if os.getenv("NO_COLOR") or not io.type(io.stdout) then
    usecolor = false
end

-- Helper function to colorize text
local function colorize(text, color)
    if not usecolor then return text end
    return (colors[color] or "") .. text .. colors.reset
end

-- Parse command line arguments
local pattern = nil
local onlyPattern = nil

if arg then
    for i, argument in ipairs(arg) do
        if argument == "--only" then
            onlyPattern = arg[i + 1]
        elseif not argument:match("^%-%-") and not (i > 1 and arg[i-1] == "--only") then
            pattern = argument
        end
    end
end

-- Set up test case filter if --only is specified
if onlyPattern then
    lust.only(onlyPattern)
end

print(colorize("Running Tests", "cyan"))
if pattern then
    print(colorize("File Pattern: ", "blue") .. colorize("*" .. pattern .. "*", "yellow"))
end
if onlyPattern then
    print(colorize("Test Case Filter: ", "blue") .. colorize("*" .. onlyPattern .. "*", "yellow"))
end
print(colorize("=========================", "cyan"))

-- Define available test suites
local testSuites = {
    "tests.blocks.data_blocks_test",
    "tests.blocks.control_blocks_test",
    "tests.blocks.event_blocks_test",
    "tests.blocks.operators_blocks_test",
    "tests.blocks.motion_blocks_test",
    "tests.blocks.looks_blocks_test",
    "tests.blocks.sensing_blocks_test",
    "tests.blocks.sound_blocks_test",
    "tests.blocks.sound_playuntildone_loop_test",
    "tests.blocks.procedures_blocks_test",
    "tests.blocks.loop_efficiency_test",
    "tests.blocks.compiler_optimization_test",
    "tests.blocks.active_keys_test",
    "tests.blocks.cast_turbowarp_test",
    "tests.unit.cast_test",
    "tests.unit.monitor_realtime_test",
    "tests.unit.compiler_migration_test",  -- Compiler migration phases 1-3 tests
    "tests.unit.stable_compilation_order_test",  -- Stable compilation order tests
    "tests.unit.transform_aabb_test",  -- Transform AABB calculation tests
    "tests.unit.rotation_center_aabb_test",  -- Rotation center AABB calculation tests
    "tests.unit.world_to_local_test",  -- worldToLocal optimization tests
    "tests.unit.draw_order_manager_test",  -- DrawOrderManager tests
    "tests.unit.project_validator_test",  -- Project format validation tests
    "tests.unit.draggable_test",  -- Draggable sprite and set drag mode tests
    "tests.unit.lua_cjson_test",  -- lua-cjson enhanced features vs json.lua compatibility tests
    -- "tests.unit.compiler_code_quality_test",  -- TODO: Fix environment setup for code quality tests
    "tests.vm.cloud_variable_storage_test",  -- Cloud variable storage tests
    "tests.audio.audio_manager_test",
    "tests.audio.ima_adpcm_test",
    "tests.audio.sound_effects_test",
    "tests.unit.pen_renderer_test",
    "tests.yield.yield_stuck_test",  -- P0 yield and stuck detection tests
    "tests.yield.yield_p1_features_test",  -- P1 yield features (warpTimer, Hat yield, recursion)
    "tests.yield.yield_p2_features_test",  -- P2 yield optimizations (broadcast wait, unified yield methods)
    "tests.yield.debug_yield_test",  -- Debug yield behavior
    -- Compiler tests
    "tests.compiler.warp_inheritance_real_test",  -- Warp mode inheritance behavior test
    -- Interpolation tests
    "tests.interpolation_test",  --  frame interpolation with edge case handling
    "tests.interpolation_config_test",  -- project options interpolation configuration
    "tests.runtime_options_test",  -- runtimeOptions configuration (maxClones, miscLimits, fencing)
    -- Integration tests (one file per native test)
    "tests.integration.default_test",
    "tests.integration.broadcast_special_chars_sb3_test",
    "tests.integration.variable_special_chars_sb3_test",
    "tests.integration.comments_sb3_test",
    "tests.integration.list_monitor_rename_test",
    "tests.integration.execute_order_library_test",
    "tests.integration.clone_sound_test",
}

-- Helper function to check if a string matches pattern with wildcards
local function matchesPattern(str, pattern)
    if not pattern then return true end
    -- Convert pattern to lowercase for case-insensitive matching
    local lowerStr = str:lower()
    local lowerPattern = pattern:lower()
    -- Simple wildcard matching: check if pattern is contained in the string
    return lowerStr:find(lowerPattern, 1, true) ~= nil
end

-- Import and run test suites
if pattern then
    local matchedTests = {}
    for _, testFile in ipairs(testSuites) do
        if matchesPattern(testFile, pattern) then
            table.insert(matchedTests, testFile)
        end
    end

    if #matchedTests > 0 then
        print(colorize("Running " .. #matchedTests .. " matched test(s):", "green"))
        for _, testFile in ipairs(matchedTests) do
            print(colorize("  - ", "blue") .. colorize(testFile, "bright"))
            require(testFile)
        end
    else
        print(colorize("Error: ", "red") .. "No tests match pattern " .. colorize("*" .. pattern .. "*", "yellow"))
        print(colorize("Available test files:", "blue"))
        for _, testFile in ipairs(testSuites) do
            print(colorize("  - ", "blue") .. testFile)
        end
        print()
        print(colorize("Usage: ", "blue") .. "luajit tests/run.lua [file_pattern] [--only test_case_pattern]")
        print(colorize("Examples:", "blue"))
        print(colorize("  luajit tests/run.lua", "cyan") .. "                     # Run all tests")
        print(colorize("  luajit tests/run.lua data", "cyan") .. "               # Run all data tests")
        print(colorize("  luajit tests/run.lua --only variable", "cyan") .. "    # Run only tests containing 'variable'")
        print(colorize("  luajit tests/run.lua data --only set", "cyan") .. "    # Run data tests containing 'set'")
        os.exit(1)
    end
else
    -- Run all tests
    for _, testFile in ipairs(testSuites) do
        require(testFile)
    end
end

-- Print test results
print()
print(colorize("Test Results:", "cyan"))
print(colorize("=============", "cyan"))

local passColor = lust.errors > 0 and "yellow" or "green"
local errorColor = lust.errors > 0 and "red" or "green"

print(colorize("Passes: ", "blue") .. colorize(tostring(lust.passes), passColor))
print(colorize("Errors: ", "blue") .. colorize(tostring(lust.errors), errorColor))

-- Show skip count if any tests were skipped
if lust.skips and lust.skips > 0 then
    print(colorize("Skipped: ", "blue") .. colorize(tostring(lust.skips), "yellow"))
end

-- Show filtering info if applicable
if onlyPattern then
    print(colorize("Filter: ", "blue") .. colorize("Only tests matching '*" .. onlyPattern .. "*'", "yellow"))
end

-- Print overall result summary
if lust.errors > 0 then
    print()
    print(colorize("❌ FAILED", "red") .. colorize(" - " .. lust.errors .. " test(s) failed", "red"))
else
    print()
    print(colorize("✅ SUCCESS", "green") .. colorize(" - All tests passed!", "green"))
end

-- Clean up mock environment
MockLove.uninstall()

-- Exit with appropriate code
if lust.errors > 0 then
    os.exit(1)
else
    os.exit(0)
end
