---Async HTTPS Module
---Provides non-blocking HTTP/HTTPS requests using background threads
---
---Usage:
---  local AsyncHTTPS = require("utils.async_https")
---
---  -- Create instance (typically in Runtime:initialize)
---  local asyncHTTPS = AsyncHTTPS:new()
---
---  -- Make async request
---  asyncHTTPS:request(url, options, function(response)
---      if response.error then
---          print("Error:", response.message)
---      else
---          print("Success:", response.status, #response.body)
---      end
---  end)
---
---  -- In your update loop
---  asyncHTTPS:update()
---
---  -- Cleanup (typically in Runtime shutdown)
---  asyncHTTPS:shutdown()

local log = require("lib.log")

---@class AsyncHTTPS
---@field nextRequestId number Request ID counter
---@field pendingRequests table Pending requests map
---@field workerThread love.Thread|nil Worker thread instance
---@field inputChannel love.Channel|nil Input channel to worker
---@field outputChannel love.Channel|nil Output channel from worker
---@field shutdownChannel love.Channel|nil Shutdown signal channel
---@field stats table Statistics
local AsyncHTTPS = {}
AsyncHTTPS.__index = AsyncHTTPS

---Create a new AsyncHTTPS instance
---@return AsyncHTTPS instance New AsyncHTTPS instance
function AsyncHTTPS:new()
    local instance = setmetatable({}, AsyncHTTPS)

    -- Request ID counter
    instance.nextRequestId = 1

    -- Pending requests map: { [id] = { callback = function, startTime = number, url = string } }
    instance.pendingRequests = {}

    -- Worker thread and channels (not initialized yet)
    instance.workerThread = nil
    instance.inputChannel = nil
    instance.outputChannel = nil
    instance.shutdownChannel = nil

    -- Statistics
    instance.stats = {
        totalRequests = 0,
        completedRequests = 0,
        failedRequests = 0,
        totalBytes = 0,
        totalTime = 0
    }

    -- Worker thread will be initialized on first request (lazy-loading)

    return instance
end

---Initialize the async HTTPS worker thread (lazy-loading)
---@private
function AsyncHTTPS:initialize()
    if self.workerThread then
        return -- Already initialized
    end

    -- Create channels with unique names per instance
    local channelPrefix = 'async_https_' .. tostring(self)
    self.inputChannel = love.thread.getChannel(channelPrefix .. '_input')
    self.outputChannel = love.thread.getChannel(channelPrefix .. '_output')
    self.shutdownChannel = love.thread.getChannel(channelPrefix .. '_shutdown')

    -- Clear channels
    self.inputChannel:clear()
    self.outputChannel:clear()
    self.shutdownChannel:clear()

    -- Create and start worker thread
    local workerCode = love.filesystem.read('utils/async_https_worker.lua')
    self.workerThread = love.thread.newThread(workerCode)
    self.workerThread:start(self.inputChannel, self.outputChannel, self.shutdownChannel)

    log.debug("AsyncHTTPS: Worker thread started (lazy-loaded)")
end

---Make an async HTTP/HTTPS request
---@param url string The URL to request
---@param options table|nil Optional request options (same as lua-https options table)
---@param callback function Callback function(response) where response contains: {id, url, status, body, headers, error, message, elapsed}
---@return number requestId Unique request ID that can be used to track or cancel the request
function AsyncHTTPS:request(url, options, callback)
    if type(url) ~= "string" or url == "" then
        error("AsyncHTTPS:request: url must be a non-empty string", 2)
    end

    if type(callback) ~= "function" then
        error("AsyncHTTPS:request: callback must be a function", 2)
    end

    -- Lazy-load: Initialize worker thread on first request
    if not self.workerThread then
        self:initialize()
    end

    -- Check if worker thread is available
    if not self.workerThread or not self.inputChannel then
        log.warn("AsyncHTTPS: Worker thread not available, cannot process request")
        -- Call callback immediately with error
        callback({
            id = 0,
            url = url,
            status = 0,
            body = nil,
            headers = nil,
            error = true,
            elapsed = 0,
            message = "AsyncHTTPS worker thread not available"
        })
        return 0
    end

    -- Generate request ID
    local requestId = self.nextRequestId
    self.nextRequestId = self.nextRequestId + 1

    -- Store pending request
    self.pendingRequests[requestId] = {
        callback = callback,
        startTime = love.timer.getTime(),
        url = url
    }

    -- Send request to worker thread
    local request = {
        id = requestId,
        url = url,
        options = options
    }
    self.inputChannel:push(request)

    self.stats.totalRequests = self.stats.totalRequests + 1

    log.debug("AsyncHTTPS: Queued request #%d to worker: %s", requestId, url)

    return requestId
end

---Cancel a pending request
---@param requestId number The request ID returned by AsyncHTTPS:request()
---@return boolean cancelled True if request was cancelled, false if not found or already completed
function AsyncHTTPS:cancel(requestId)
    if self.pendingRequests[requestId] then
        log.debug("AsyncHTTPS: Cancelled request #%d", requestId)
        self.pendingRequests[requestId] = nil
        return true
    end
    return false
end

---Get number of pending requests
---@return number count Number of requests waiting for response
function AsyncHTTPS:getPendingCount()
    local count = 0
    for _ in pairs(self.pendingRequests) do
        count = count + 1
    end
    return count
end

---Get statistics
---@return table stats Statistics table with totalRequests, completedRequests, failedRequests, totalBytes, totalTime
function AsyncHTTPS:getStats()
    return {
        totalRequests = self.stats.totalRequests,
        completedRequests = self.stats.completedRequests,
        failedRequests = self.stats.failedRequests,
        pendingRequests = self:getPendingCount(),
        totalBytes = self.stats.totalBytes,
        totalTime = self.stats.totalTime,
        avgTime = self.stats.completedRequests > 0 and (self.stats.totalTime / self.stats.completedRequests) or 0
    }
end

---Update function - processes completed requests
---MUST be called regularly (e.g., in love.update or Runtime:update)
---@return number processed Number of responses processed
function AsyncHTTPS:update()
    -- Early return if worker not initialized (lazy-loading)
    if not self.workerThread or not self.outputChannel then
        return 0
    end

    local processed = 0

    -- Process all available responses (non-blocking)
    while true do
        local response = self.outputChannel:pop()
        if not response then
            break
        end

        processed = processed + 1

        -- Handle worker thread initialization errors
        if response.error and response.errorType == 'module_load_failed' then
            log.error("AsyncHTTPS: Worker thread initialization failed: %s", response.message)
            -- Mark worker as unavailable but don't shutdown (allow graceful degradation)
            self.workerThread = nil
            break
        end

        -- Find pending request
        local pending = self.pendingRequests[response.id]
        if pending then
            -- Calculate total time (from initial request to now)
            local totalTime = love.timer.getTime() - pending.startTime

            -- Update statistics
            if response.error then
                self.stats.failedRequests = self.stats.failedRequests + 1
                log.warn("AsyncHTTPS: Request #%d failed (HTTP %d) in %.2fs: %s",
                    response.id, response.status, totalTime, response.url)
            else
                self.stats.completedRequests = self.stats.completedRequests + 1
                self.stats.totalBytes = self.stats.totalBytes + (response.body and #response.body or 0)
                self.stats.totalTime = self.stats.totalTime + totalTime

                log.debug("AsyncHTTPS: Request #%d completed (HTTP %d) in %.2fs: %s",
                    response.id, response.status, totalTime, response.url)
            end

            -- Prepare response for callback
            local callbackResponse = {
                id = response.id,
                url = response.url,
                status = response.status,
                body = response.body,
                headers = response.headers,
                error = response.error,
                elapsed = totalTime,
                message = response.error and (response.body or "Request failed") or nil
            }

            -- Call user callback
            local success, err = pcall(pending.callback, callbackResponse)
            if not success then
                log.error("AsyncHTTPS: Callback error for request #%d: %s", response.id, err)
            end

            -- Remove from pending
            self.pendingRequests[response.id] = nil
        else
            log.warn("AsyncHTTPS: Received response for unknown request #%d", response.id)
        end
    end

    return processed
end

---Shutdown the async HTTPS system
---Cancels all pending requests and stops the worker thread
function AsyncHTTPS:shutdown()
    if not self.workerThread then
        return
    end

    log.info("AsyncHTTPS: Shutting down...")

    -- Cancel all pending requests
    local cancelledCount = 0
    for id, pending in pairs(self.pendingRequests) do
        log.debug("AsyncHTTPS: Cancelled pending request #%d: %s", id, pending.url)
        cancelledCount = cancelledCount + 1
    end
    self.pendingRequests = {}

    -- Signal worker thread to shutdown
    self.shutdownChannel:push(true)

    -- Wait for thread to finish (with timeout)
    local timeout = 1.0  -- 1 second
    local startTime = love.timer.getTime()
    while self.workerThread:isRunning() do
        if love.timer.getTime() - startTime > timeout then
            log.warn("AsyncHTTPS: Worker thread shutdown timeout")
            break
        end
        love.timer.sleep(0.01)
    end

    self.workerThread = nil
    self.inputChannel = nil
    self.outputChannel = nil
    self.shutdownChannel = nil

    log.info("AsyncHTTPS: Shutdown complete (cancelled %d requests)", cancelledCount)
end

return AsyncHTTPS
