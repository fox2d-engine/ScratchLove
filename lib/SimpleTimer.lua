-- SimpleTimer: A lightweight timer system for Scratch thread waiting

local SimpleTimer = {}

-- Timer states
local TIMER_PENDING = 0
local TIMER_COMPLETED = 1

-- Active timers list
local activeTimers = {}

---@class Timer
---@field id string Unique timer ID
---@field duration number Duration in seconds
---@field elapsed number Elapsed time
---@field status number Timer status
---@field callback function|nil Optional callback when completed
local Timer = {}
Timer.__index = Timer

---Create a new timer
---@param duration number Duration in seconds
---@param callback function|nil Optional callback
---@return Timer timer New timer instance
function Timer:new(duration, callback)
    local self = setmetatable({}, Timer)
    self.id = tostring({}):sub(8) -- Use table address as unique ID
    self.duration = duration
    self.elapsed = 0
    self.status = TIMER_PENDING
    self.callback = callback

    -- Add to active timers
    activeTimers[self.id] = self

    return self
end

---Get timer status
---@return number status TIMER_PENDING or TIMER_COMPLETED
function Timer:getStatus()
    return self.status
end

---Check if timer is completed
---@return boolean completed True if timer has finished
function Timer:isCompleted()
    return self.status == TIMER_COMPLETED
end

---Update all active timers
---@param dt number Delta time in seconds
function SimpleTimer.update(dt)
    for id, timer in pairs(activeTimers) do
        if timer.status == TIMER_PENDING then
            timer.elapsed = timer.elapsed + dt

            if timer.elapsed >= timer.duration then
                -- Timer completed
                timer.status = TIMER_COMPLETED

                -- Call callback if provided
                if timer.callback then
                    timer.callback()
                end

                -- Remove from active timers
                activeTimers[id] = nil
            end
        end
    end
end

---Create a delay timer (main API)
---@param duration number Duration in seconds
---@return Timer timer Timer instance
function SimpleTimer.delay(duration)
    return Timer:new(duration)
end

---Get count of active timers (for debugging)
---@return number count Number of active timers
function SimpleTimer.getActiveCount()
    local count = 0
    for _ in pairs(activeTimers) do
        count = count + 1
    end
    return count
end

-- Export timer states for compatibility
SimpleTimer.Status = {
    Pending = TIMER_PENDING,
    Completed = TIMER_COMPLETED
}

return SimpleTimer