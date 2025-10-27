-- LuaJIT Profiler Wrapper
-- Provides a clean interface for LuaJIT's built-in profiler
---@class JitProfiler
local JitProfiler = {}

-- Import LuaJIT profiler if available
local jit_profile = nil
if jit then
    jit_profile = require("jit.profile")
end

-- Profiler state
local profilerActive = false
local profilerResults = {}

---Check if LuaJIT profiler is available
---@return boolean available True if profiler is available
function JitProfiler.isAvailable()
    return jit_profile ~= nil
end

---Check if profiler is currently running
---@return boolean active True if profiler is active
function JitProfiler.isActive()
    return profilerActive
end

---Start profiling with line-level sampling
---@return boolean success True if profiler started successfully
function JitProfiler.start()
    if not jit_profile then
        return false
    end

    if profilerActive then
        return false -- Already running
    end

    -- Clear previous results
    profilerResults = {}

    -- Start profiler with line-level sampling
    jit_profile.start("li5", function(thread, samples, vmstate)
        local stack = jit_profile.dumpstack(thread, "pl\n", 20)
        for line in stack:gmatch("[^\n]+") do
            profilerResults[line] = (profilerResults[line] or 0) + samples
        end
    end)

    profilerActive = true
    return true
end

---Stop profiling and generate report
---@return table|nil report Profiling report table or nil if not running
function JitProfiler.stop()
    if not jit_profile or not profilerActive then
        return nil
    end

    -- Stop profiler
    jit_profile.stop()
    profilerActive = false

    -- Process and aggregate results
    local functionCounts = {}
    local totalSamples = 0

    for stackTrace, count in pairs(profilerResults) do
        totalSamples = totalSamples + count
        functionCounts[stackTrace] = (functionCounts[stackTrace] or 0) + count
    end

    -- Sort by sample count
    local sorted = {}
    for func, count in pairs(functionCounts) do
        table.insert(sorted, {
            func = func,
            count = count,
            percentage = totalSamples > 0 and (count / totalSamples * 100) or 0
        })
    end

    table.sort(sorted, function(a, b) return a.count > b.count end)

    -- Clear results
    profilerResults = {}

    return {
        totalSamples = totalSamples,
        functions = sorted
    }
end

---Generate a formatted text report
---@param report table Report data from stop()
---@param maxEntries number|nil Maximum number of entries to show (default: 20)
---@return string formatted Formatted report string
function JitProfiler.formatReport(report, maxEntries)
    if not report then
        return "No profiling data available"
    end

    maxEntries = maxEntries or 20
    local lines = {}

    table.insert(lines, "=== LUAJIT PROFILER REPORT ===")
    table.insert(lines, string.format("Total samples collected: %d", report.totalSamples))
    table.insert(lines, "")
    table.insert(lines, "Top functions by sample count:")
    table.insert(lines, string.format("%-50s %8s %8s", "Function", "Samples", "Percent"))
    table.insert(lines, string.rep("-", 68))

    local numEntries = math.min(maxEntries, #report.functions)
    for i = 1, numEntries do
        local entry = report.functions[i]
        table.insert(lines, string.format("%-50s %8d %7.1f%%",
            entry.func, entry.count, entry.percentage))
    end

    if #report.functions > maxEntries then
        local remaining = #report.functions - maxEntries
        table.insert(lines, "")
        table.insert(lines, string.format("... and %d more functions", remaining))
    end

    table.insert(lines, "")
    table.insert(lines, "=== END PROFILER REPORT ===")

    return table.concat(lines, "\n")
end

---Start profiling and print start message
---@return boolean success True if started successfully
function JitProfiler.startWithLog()
    local success = JitProfiler.start()
    if success then
        print("LuaJIT profiler started")
    else
        print("Failed to start LuaJIT profiler")
    end
    return success
end

---Stop profiling and print formatted report
---@param maxEntries number|nil Maximum number of entries to show (default: 20)
---@return table|nil report Report data or nil if failed
function JitProfiler.stopWithReport(maxEntries)
    local report = JitProfiler.stop()
    if report then
        print(JitProfiler.formatReport(report, maxEntries))
        print("LuaJIT profiler stopped and report generated")
    else
        print("No profiling data to report")
    end
    return report
end

---Toggle profiler on/off with logging
---@param maxEntries number|nil Maximum number of entries to show in report (default: 20)
---@return boolean newState True if profiler is now active
function JitProfiler.toggle(maxEntries)
    if not JitProfiler.isAvailable() then
        print("LuaJIT profiler not available (not running under LuaJIT)")
        return false
    end

    if profilerActive then
        JitProfiler.stopWithReport(maxEntries)
        return false
    else
        JitProfiler.startWithLog()
        return true
    end
end

return JitProfiler
