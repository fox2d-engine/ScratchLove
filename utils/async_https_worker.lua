-- Async HTTPS Worker Thread
-- This code runs in a separate thread and processes HTTP requests without blocking the main thread
-- Communication with main thread happens through love.thread channels

require('love.timer')

-- Get channels for communication (passed as arguments)
local inputChannel, outputChannel, shutdownChannel = ...

-- Configure package.cpath to find lua-https module
-- The https.so is located in lib/lua-https/src/
package.cpath = package.cpath .. ";lib/lua-https/src/?.so"

-- Try to load HTTPS module (must be done in worker thread context)
-- lua-https is a Love2D native module, should be available in worker threads
local httpsSuccess, https = pcall(require, 'https')
if not httpsSuccess then
    -- If https module is not available in worker thread, we cannot proceed
    -- This is expected in test environments or when lua-https is not installed
    -- Send error and exit gracefully
    if outputChannel then
        outputChannel:push({
            error = true,
            errorType = 'module_load_failed',
            message = 'HTTPS module not available in worker thread: ' .. tostring(https)
        })
    end
    return
end

-- Worker main loop
while true do
    -- Check for shutdown signal
    local shouldShutdown = shutdownChannel:pop()
    if shouldShutdown then
        break
    end

    -- Wait for incoming request (non-blocking with timeout)
    local request = inputChannel:pop()

    if request then
        local startTime = love.timer.getTime()

        -- Prepare request options
        local options = request.options or {}

        -- Execute HTTP request (this blocks the worker thread, not the main thread)
        local status, body, headers = https.request(request.url, options)

        local elapsed = love.timer.getTime() - startTime

        -- Send response back to main thread
        outputChannel:push({
            id = request.id,
            url = request.url,
            status = status or 0,
            body = body,
            headers = headers,
            elapsed = elapsed,
            error = (status == nil or status == 0),
            timestamp = love.timer.getTime()
        })
    else
        -- No request available, sleep briefly to avoid busy-waiting
        love.timer.sleep(0.001)  -- 1ms
    end
end
