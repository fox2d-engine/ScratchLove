-- Integration Test Helper
-- Shared utilities for all integration tests

local pl_path = require("pl.path")
local json = require("lib.json")

local IntegrationHelper = {}

---Synchronously load an sb3 project for testing
---Uses system unzip command to extract project files
---@param filename string The sb3 filename in tests/fixtures/integration/
---@return table projectData The parsed project.json data
---@return table assetMap Empty asset map (assets are extracted to temp directory)
function IntegrationHelper.loadSB3Project(filename)
    local filepath = pl_path.join("tests/fixtures/integration", filename)

    -- Check if file exists
    local file = io.open(filepath, "r")
    if not file then
        error("SB3 file not found: " .. filepath)
    end
    file:close()

    -- Create unique temp directory for extraction
    local tempDir = "/tmp/sb3_test_" .. filename:gsub("%W", "_")

    -- Clean up any existing temp directory
    os.execute("rm -rf " .. tempDir)
    os.execute("mkdir -p " .. tempDir)

    -- Extract sb3 file using unzip
    local unzipCmd = string.format("unzip -q -o '%s' -d '%s'", filepath, tempDir)
    local result = os.execute(unzipCmd)

    if result ~= 0 then
        error("Failed to extract SB3 file: " .. filepath)
    end

    -- Read project.json
    local jsonPath = tempDir .. "/project.json"
    local jsonFile = io.open(jsonPath, "r")
    if not jsonFile then
        error("project.json not found in SB3 file: " .. filepath)
    end

    local projectJsonData = jsonFile:read("*all")
    jsonFile:close()

    -- Parse JSON
    local projectData = json.decode(projectJsonData)

    -- Clean up temp directory
    os.execute("rm -rf " .. tempDir)

    -- Return project data and empty asset map
    -- Assets are handled by the project loader in actual runtime
    return projectData, {}
end

---Run a runtime until all threads complete or max iterations reached
---@param runtime Runtime The runtime instance
---@param maxIterations number Maximum iterations to prevent infinite loops (default: 100)
---@return number iterations Number of iterations executed
function IntegrationHelper.runUntilComplete(runtime, maxIterations)
    maxIterations = maxIterations or 100
    local iterations = 0

    while #runtime:getActiveThreads() > 0 and iterations < maxIterations do
        runtime:update(1/60)
        iterations = iterations + 1
    end

    return iterations
end

---Count elements in a table (works with both arrays and maps)
---@param tbl table The table to count
---@return number count The number of elements
function IntegrationHelper.tableCount(tbl)
    local count = 0
    for _ in pairs(tbl) do
        count = count + 1
    end
    return count
end

---Convert a table to an array (for iteration in specific order)
---@param tbl table The table to convert
---@return table array Array of values
function IntegrationHelper.tableToArray(tbl)
    local array = {}
    for _, value in pairs(tbl) do
        table.insert(array, value)
    end
    return array
end

---Filter array elements by predicate function
---@param array table Array to filter
---@param predicate function Function that returns true to keep element
---@return table filtered Filtered array
function IntegrationHelper.filter(array, predicate)
    local filtered = {}
    for _, item in ipairs(array) do
        if predicate(item) then
            table.insert(filtered, item)
        end
    end
    return filtered
end

---Sort array in place by comparator function
---@param array table Array to sort
---@param comparator function Comparison function (a, b) -> boolean
---@return table array The sorted array (same reference)
function IntegrationHelper.sort(array, comparator)
    table.sort(array, comparator)
    return array
end

return IntegrationHelper