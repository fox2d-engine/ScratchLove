-- Thread
-- Represents an execution thread for a script

local SimpleTimer = require("lib.SimpleTimer")
local log = require("lib.log")

---@class Thread
---@field target Sprite|Stage The target executing this thread
---@field runtime Runtime Runtime instance
---@field status number Thread execution status
---@field waitingTimer Timer|nil Timer being waited on
---@field topBlock string|nil Top-level hat block ID for this thread
---@field hatParam any|nil Parameter passed to hat block (e.g., key, broadcast ID)
---@field isHatBlockThread boolean Whether this thread was started by a hat block
---@field isCompiled boolean Whether this thread uses compiled execution
---@field compiledCoroutine thread|nil Lua coroutine for compiled execution
---@field compiledFunction function|nil Compiled Lua function
---@field compiledProcedures table<string, function>|nil Compiled procedure functions
local Thread = {}
Thread.__index = Thread

Thread.STATUS_RUNNING = 0
Thread.STATUS_PROMISE_WAIT = 1
Thread.STATUS_YIELD = 2
Thread.STATUS_YIELD_TICK = 3
Thread.STATUS_DONE = 4

---Get block container table for a target (handles clones via sprite templates)
---@param target Sprite|Stage
---@return table<string, Block>|nil
local function getBlockContainer(target)
    if not target then
        return nil
    end

    local blocks = target.blocks
    if blocks then
        return blocks
    end

    if target.spriteTemplate and target.spriteTemplate.blocks then
        return target.spriteTemplate.blocks
    end

    return nil
end

---Generate unique thread ID from target and top block
---@param target Sprite|Stage Target object
---@param topBlock string Top block ID
---@return string threadId Unique thread identifier
function Thread.getIdFromTargetAndBlock(target, topBlock)
    -- For clones, include a unique identifier to prevent thread conflicts
    if target.isClone then
        return target.name .. "&" .. topBlock .. "&clone_" .. tostring(target)
    else
        return target.name .. "&" .. topBlock
    end
end

---Create a new thread
---@param target Sprite|Stage Target executing the thread
---@param startBlockId string Starting block ID
---@param runtime Runtime Runtime instance
---@param stackClick boolean|nil Whether thread was started by clicking
---@param hatParam any|nil Parameter for hat block
---@return Thread
function Thread:new(target, startBlockId, runtime, stackClick, hatParam)
    local self = setmetatable({}, Thread)

    self.target = target
    self.runtime = runtime
    self.status = Thread.STATUS_RUNNING
    self.topBlock = startBlockId
    self.hatParam = hatParam

    -- Promise-based waiting
    self.waitingTimer = nil

    self.isCompiled = false
    self.compiledCoroutine = nil
    self.compiledFunction = nil
    self.compiledProcedures = nil

    self:loadFromGlobalCompilerCache()

    return self
end

---Request a time-based wait (Scratch "wait N seconds")
---@param seconds number Number of seconds to wait (will be clamped to >= 0)
function Thread:wait(seconds)
    local s = tonumber(seconds) or 0
    if s < 0 then s = 0 end

    -- Check for mock wait mode (used in tests)
    if self.runtime.mockWait then
        -- In mock wait mode, don't actually wait
        return
    end

    -- Native Scratch always yields on first call, then checks timer completion on subsequent calls
    self:waitForTimer(SimpleTimer.delay(s))
end

---Wait for a Timer to complete
---@param timer Timer Timer to wait for
function Thread:waitForTimer(timer)
    self.waitingTimer = timer
    self.status = Thread.STATUS_PROMISE_WAIT
end

---Check waiting status and return whether thread can continue execution
---@param dt number Delta time (unused in timer-based implementation)
---@return boolean canContinue Whether thread can continue execution
function Thread:checkWaitingStatus(dt)
    if self.status == Thread.STATUS_PROMISE_WAIT then
        -- Check if timer is completed
        if self.waitingTimer then
            if self.waitingTimer:isCompleted() then
                -- Timer completed, resume execution
                self.waitingTimer = nil
                log.debug("Thread: Resuming compiled thread after timer completion")
                self.status = Thread.STATUS_RUNNING
            else
                return false -- Still waiting
            end
        else
            -- No timer but in promise wait state, resume immediately
            self.status = Thread.STATUS_RUNNING
        end
    end

    -- YIELD state is handled by Sequencer
    return true -- Can continue execution
end

---Stop thread execution immediately
function Thread:stop()
    self.status = Thread.STATUS_DONE
end

---Restart thread from beginning
---@param newHatParam any|nil New hat parameter
function Thread:restart(newHatParam)
    -- Update hat parameter if provided
    if newHatParam ~= nil then
        self.hatParam = newHatParam
    end

    self.status = Thread.STATUS_RUNNING

    -- Clear wait state
    self.waitingTimer = nil

    -- Reset compiled execution state so coroutine restarts cleanly
    if self.isCompiled then
        self.compiledCoroutine = nil
    end
end

---Check if thread is currently waiting
---@return boolean isWaiting True if thread is in a waiting state
function Thread:isWaiting()
    return self.status == Thread.STATUS_PROMISE_WAIT
end

---@return boolean success True if loading from global cache succeeded
function Thread:loadFromGlobalCompilerCache()
    local compileCache = self.runtime.compilerCache
    if not compileCache then
        -- In test environment, allow graceful fallback
        if self.runtime.mockWait or string.match(self.topBlock or "", "^test") then
            log.debug("Test environment detected - skipping global compilation check for: " .. tostring(self.topBlock))
            self.isCompiled = false
            return false
        end
        error("Global compiler cache not available - global project compilation required for: " ..
            tostring(self.topBlock))
    end

    local blockContainer = getBlockContainer(self.target)
    if not blockContainer then
        error("Block container not available for thread: " .. tostring(self.topBlock))
    end

    local containerCache = compileCache[blockContainer]
    if not containerCache then
        -- In test environment, allow graceful fallback
        if self.runtime.mockWait or string.match(self.topBlock or "", "^test") then
            log.debug("Test environment detected - skipping compilation cache check for: " .. tostring(self.topBlock))
            self.isCompiled = false
            return false
        end
        error("Container cache not found in global compilation - thread not pre-compiled: " .. tostring(self.topBlock))
    end

    local cached = containerCache[self.topBlock]
    if not cached then
        -- In test environment, allow graceful fallback
        if self.runtime.mockWait or string.match(self.topBlock or "", "^test") then
            log.debug("Test environment detected - skipping block compilation check for: " .. tostring(self.topBlock))
            self.isCompiled = false
            return false
        end
        error("Thread not found in global compilation cache: " .. tostring(self.topBlock))
    end

    -- Load the pre-compiled function and procedures
    self.compiledFunction = cached.entryFunction
    self.compiledProcedures = cached.procedures or {}
    self.isCompiled = true

    return true
end

---Step compiled thread using coroutine
---@return string|nil status Thread status after step
function Thread:stepCompiled()
    if self.isKilled or (self.target and self.target.isDeleted) then
        log.debug("Thread: Target/thread was deleted, stopping execution")
        self.status = Thread.STATUS_DONE
        return "done"
    end

    -- Initialize coroutine if needed
    if not self.compiledCoroutine then
        -- Validate compiledFunction exists and is a function
        if not self.compiledFunction then
            log.error("Thread: compiledFunction is nil for block %s", tostring(self.topBlock))
            self.status = Thread.STATUS_DONE
            return "error"
        end

        if type(self.compiledFunction) ~= "function" then
            log.error("Thread: compiledFunction is not a function (type: %s) for block %s",
                type(self.compiledFunction), tostring(self.topBlock))
            self.status = Thread.STATUS_DONE
            return "error"
        end

        -- Register compiled procedures directly on thread
        if self.compiledProcedures and next(self.compiledProcedures) then
            if not self.procedures then
                self.procedures = {}
            end
            for variant, procedureFunc in pairs(self.compiledProcedures) do
                self.procedures[variant] = procedureFunc
            end
        end

        self.compiledCoroutine = coroutine.create(function()
            return self.compiledFunction(self.runtime, self.target, self)
        end)

        -- Validate coroutine was created successfully
        if type(self.compiledCoroutine) ~= "thread" then
            log.error("Thread: Failed to create coroutine (type: %s) for block %s",
                type(self.compiledCoroutine), tostring(self.topBlock))
            self.status = Thread.STATUS_DONE
            return "error"
        end
    end

    -- Validate coroutine before resuming
    if type(self.compiledCoroutine) ~= "thread" then
        log.error("Thread: compiledCoroutine is not a thread (type: %s) for block %s",
            type(self.compiledCoroutine), tostring(self.topBlock))
        self.status = Thread.STATUS_DONE
        return "error"
    end

    -- Save coroutine reference before resume (in case it gets modified)
    local coro = self.compiledCoroutine

    -- Resume coroutine
    local success, result = coroutine.resume(coro)

    if not success then
        -- Collect detailed debug information
        local targetName = self.target and (self.target.name or "Unknown") or "nil"
        local isClone = self.target and self.target.isClone or false
        local topBlockId = self.topBlock or "Unknown"

        -- Collect variable keys
        local varKeys = {}
        if self.target and self.target.variables then
            for k in pairs(self.target.variables) do
                table.insert(varKeys, k)
            end
        end
        table.sort(varKeys)

        -- Print complete error with stack trace
        log.error("=== Compiled thread execution error ===")
        log.error("Target: %s (isClone: %s)", targetName, tostring(isClone))
        log.error("Script: %s", topBlockId)
        log.error("Variables (%d): %s", #varKeys, table.concat(varKeys, ", "))
        log.error("Error message:")
        log.error("%s", tostring(result))
        log.error("Full stack trace:")
        -- Get complete stack trace from the coroutine (use saved reference)
        local trace = debug.traceback(coro)
        for line in trace:gmatch("[^\n]+") do
            log.error("%s", line)
        end
        log.error("=== End error ===")

        self.status = Thread.STATUS_DONE
        return "error"
    end

    -- Check coroutine status first to handle completion
    -- When coroutine finishes normally (e.g., thread:stop()), it returns nil
    -- Use saved reference in case self.compiledCoroutine was modified during resume
    local coStatus = coroutine.status(coro)
    if coStatus == "dead" then
        log.debug("Thread: Compiled thread coroutine is dead, marking as done")
        self.status = Thread.STATUS_DONE
        return "done"
    end

    -- Handle yield-like results (must happen after checking dead status)
    if result == "yield" or result == "yield_frame" then
        -- Thread yielded for the rest of the frame
        return "yield"
    elseif result == "yield_tick" then
        return "yield_tick"
    elseif result == "wait" then
        return "wait"
    end

    -- Continue running
    return "running"
end

return Thread
