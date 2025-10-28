-- Memory Profiler for LuaJIT
-- Provides detailed memory usage tracking and analysis

local log = require("lib.log")
local ffi = require("ffi")

-- Platform-specific system memory detection
local systemMemoryAvailable = false
local getSystemMemory

if ffi.os == "OSX" then
    -- macOS: Use ps command to get process memory
    systemMemoryAvailable = true
    getSystemMemory = function()
        local handle = io.popen("ps -o rss= -p " .. ffi.C.getpid())
        if handle then
            local result = handle:read("*a")
            handle:close()
            local rss = tonumber(result)
            if rss then
                return rss * 1024 -- Convert KB to bytes
            end
        end
        return nil
    end
elseif ffi.os == "Linux" then
    -- Linux: Read from /proc/self/status
    systemMemoryAvailable = true
    getSystemMemory = function()
        local file = io.open("/proc/self/status", "r")
        if file then
            for line in file:lines() do
                local key, value = line:match("^VmRSS:%s*(%d+)%s*kB")
                if key then
                    file:close()
                    return tonumber(value) * 1024 -- Convert KB to bytes
                end
            end
            file:close()
        end
        return nil
    end
elseif ffi.os == "Windows" then
    -- Windows: Would need Windows API, skip for now
    systemMemoryAvailable = false
    getSystemMemory = function() return nil end
else
    systemMemoryAvailable = false
    getSystemMemory = function() return nil end
end

-- FFI declaration for getpid (macOS/Linux)
if ffi.os == "OSX" or ffi.os == "Linux" then
    ffi.cdef[[
        int getpid(void);
    ]]
end

---@class MemoryProfiler
local MemoryProfiler = {}

---Format bytes to human-readable string
---@param bytes number Bytes to format
---@return string formatted Formatted string (e.g., "1.5 MB")
local function formatBytes(bytes)
    if bytes < 1024 then
        return string.format("%.0f B", bytes)
    elseif bytes < 1024 * 1024 then
        return string.format("%.2f KB", bytes / 1024)
    elseif bytes < 1024 * 1024 * 1024 then
        return string.format("%.2f MB", bytes / (1024 * 1024))
    else
        return string.format("%.2f GB", bytes / (1024 * 1024 * 1024))
    end
end

---Get current Lua memory usage in KB
---@return number memory Lua memory usage in KB
function MemoryProfiler.getCurrentMemory()
    collectgarbage("collect")
    collectgarbage("collect") -- Call twice for thorough collection
    return collectgarbage("count")
end

---Get current Lua memory usage in bytes
---@return number memory Lua memory usage in bytes
function MemoryProfiler.getCurrentMemoryBytes()
    return MemoryProfiler.getCurrentMemory() * 1024
end

---Get system memory usage (RSS - Resident Set Size)
---@return number|nil memory System memory usage in bytes, or nil if unavailable
function MemoryProfiler.getSystemMemory()
    if not systemMemoryAvailable then
        return nil
    end
    return getSystemMemory()
end

---Get comprehensive memory info (both Lua and system)
---@return table memory Memory info with lua_bytes, system_bytes, and formatted strings
function MemoryProfiler.getMemoryInfo()
    local luaBytes = MemoryProfiler.getCurrentMemoryBytes()
    local systemBytes = MemoryProfiler.getSystemMemory()

    local info = {
        lua_bytes = luaBytes,
        lua_formatted = formatBytes(luaBytes),
        system_bytes = systemBytes,
        system_formatted = systemBytes and formatBytes(systemBytes) or "N/A",
        native_bytes = systemBytes and (systemBytes - luaBytes) or nil,
        native_formatted = systemBytes and formatBytes(systemBytes - luaBytes) or "N/A"
    }

    return info
end

---Create a memory checkpoint (with both Lua and system memory)
---@param name string Checkpoint name
---@return table checkpoint Checkpoint data with name and memory
function MemoryProfiler.checkpoint(name)
    local info = MemoryProfiler.getMemoryInfo()
    local checkpoint = {
        name = name,
        lua_memory = info.lua_bytes,
        system_memory = info.system_bytes,
        native_memory = info.native_bytes,
        lua_formatted = info.lua_formatted,
        system_formatted = info.system_formatted,
        native_formatted = info.native_formatted,
        timestamp = os.time()
    }

    if info.system_bytes then
        log.info(string.format("[MemProfile] %s: Lua=%s, System=%s, Native=%s",
            name,
            checkpoint.lua_formatted,
            checkpoint.system_formatted,
            checkpoint.native_formatted))
    else
        log.info(string.format("[MemProfile] %s: Lua=%s (System memory unavailable)",
            name,
            checkpoint.lua_formatted))
    end

    return checkpoint
end

---Calculate memory difference between two checkpoints
---@param start table Start checkpoint
---@param finish table End checkpoint
---@return number luaDiff Lua memory difference in bytes
---@return number|nil systemDiff System memory difference in bytes
---@return string formatted Formatted difference string
function MemoryProfiler.diff(start, finish)
    local luaDiff = finish.lua_memory - start.lua_memory
    local luaFormatted = formatBytes(math.abs(luaDiff))
    local luaSign = luaDiff >= 0 and "+" or "-"

    if start.system_memory and finish.system_memory then
        local systemDiff = finish.system_memory - start.system_memory
        local systemFormatted = formatBytes(math.abs(systemDiff))
        local systemSign = systemDiff >= 0 and "+" or "-"

        local nativeDiff = finish.native_memory - start.native_memory
        local nativeFormatted = formatBytes(math.abs(nativeDiff))
        local nativeSign = nativeDiff >= 0 and "+" or "-"

        log.info(string.format("[MemProfile] %s → %s: Lua=%s%s (%.1f%%), System=%s%s (%.1f%%), Native=%s%s",
            start.name,
            finish.name,
            luaSign,
            luaFormatted,
            start.lua_memory > 0 and (luaDiff / start.lua_memory) * 100 or 0,
            systemSign,
            systemFormatted,
            start.system_memory > 0 and (systemDiff / start.system_memory) * 100 or 0,
            nativeSign,
            nativeFormatted
        ))

        return luaDiff, systemDiff, luaSign .. luaFormatted
    else
        log.info(string.format("[MemProfile] %s → %s: Lua=%s%s (%.1f%%)",
            start.name,
            finish.name,
            luaSign,
            luaFormatted,
            start.lua_memory > 0 and (luaDiff / start.lua_memory) * 100 or 0
        ))

        return luaDiff, nil, luaSign .. luaFormatted
    end
end

---Profile a function execution
---@param name string Profile name
---@param func function Function to profile
---@return any result Function result
---@return number memoryUsed Memory used in bytes
function MemoryProfiler.profile(name, func)
    local start = MemoryProfiler.checkpoint(name .. " (start)")

    local result = func()

    local finish = MemoryProfiler.checkpoint(name .. " (end)")
    local diff = MemoryProfiler.diff(start, finish)

    return result, diff
end

---Get detailed memory statistics
---@return table stats Memory statistics
function MemoryProfiler.getDetailedStats()
    -- Force full GC to get accurate stats
    collectgarbage("collect")
    collectgarbage("collect")

    local info = MemoryProfiler.getMemoryInfo()

    local stats = {
        lua_memory_kb = collectgarbage("count"),
        lua_memory_bytes = info.lua_bytes,
        lua_memory_formatted = info.lua_formatted,
        system_memory_bytes = info.system_bytes,
        system_memory_formatted = info.system_formatted,
        native_memory_bytes = info.native_bytes,
        native_memory_formatted = info.native_formatted
    }

    -- Try to get LuaJIT-specific stats if available
    if jit then
        stats.jit_version = jit.version
        stats.jit_arch = jit.arch
        stats.jit_os = jit.os

        -- Get JIT status
        local jit_status = { jit.status() }
        stats.jit_enabled = jit_status[1]
        stats.jit_flags = table.concat(jit_status, " ", 2)
    end

    return stats
end

---Print detailed memory report
function MemoryProfiler.printReport()
    local stats = MemoryProfiler.getDetailedStats()

    log.info("========== Memory Profile Report ==========")
    log.info(string.format("Lua Memory:    %s (%.2f KB)",
        stats.lua_memory_formatted,
        stats.lua_memory_kb))

    if stats.system_memory_bytes then
        log.info(string.format("System Memory: %s (RSS)", stats.system_memory_formatted))
        log.info(string.format("Native Memory: %s (Love2D/C/FFI/GPU)", stats.native_memory_formatted))

        if stats.native_memory_bytes and stats.system_memory_bytes > 0 then
            local nativePercent = (stats.native_memory_bytes / stats.system_memory_bytes) * 100
            log.info(string.format("  └─ Native is %.1f%% of total system memory", nativePercent))
        end
    else
        log.info("System Memory: Not available on this platform")
    end

    if stats.jit_version then
        log.info(string.format("JIT: %s (%s, %s)",
            stats.jit_version,
            stats.jit_arch,
            stats.jit_os))
        log.info(string.format("JIT Status: %s (%s)",
            stats.jit_enabled and "ENABLED" or "DISABLED",
            stats.jit_flags or ""))
    end

    log.info("==========================================")
end

---Track memory allocations during a scope
---@param name string Scope name
---@return table tracker Tracker object with stop() method
function MemoryProfiler.startTracking(name)
    local start = MemoryProfiler.checkpoint(name .. " tracking started")

    return {
        start = start,
        stop = function()
            local finish = MemoryProfiler.checkpoint(name .. " tracking stopped")
            return MemoryProfiler.diff(start, finish)
        end
    }
end

---Get GC statistics
---@return table gcStats GC statistics
function MemoryProfiler.getGCStats()
    local stats = {}

    -- Lua 5.1 / LuaJIT collectgarbage options
    stats.count_kb = collectgarbage("count")
    stats.count_bytes = stats.count_kb * 1024
    stats.count_formatted = formatBytes(stats.count_bytes)

    return stats
end

---Force garbage collection and measure time taken
---@return number time_ms Time taken for GC in milliseconds
---@return number memory_freed Memory freed in bytes
function MemoryProfiler.forceGC()
    local before = MemoryProfiler.getCurrentMemoryBytes()
    local start_time = os.clock()

    collectgarbage("collect")
    collectgarbage("collect")

    local end_time = os.clock()
    local after = MemoryProfiler.getCurrentMemoryBytes()

    local time_ms = (end_time - start_time) * 1000
    local freed = before - after

    log.info(string.format("[MemProfile] GC completed in %.2fms, freed %s",
        time_ms,
        formatBytes(freed)))

    return time_ms, freed
end

return MemoryProfiler
