-- Test: Async HTTPS Module
-- Verifies non-blocking HTTP requests using background threads

local lust = require("tests.lust")
local describe, it, expect = lust.describe, lust.it, lust.expect

-- Mock love.thread for testing
local mockChannels = {}
local mockThread = {
    isRunning = function() return true end,
    start = function() end  -- Add start method
}

love.thread = {
    getChannel = function(name)
        if not mockChannels[name] then
            mockChannels[name] = {
                _queue = {},
                push = function(self, value)
                    table.insert(self._queue, value)
                end,
                pop = function(self)
                    return table.remove(self._queue, 1)
                end,
                clear = function(self)
                    self._queue = {}
                end
            }
        end
        return mockChannels[name]
    end,
    newThread = function(code)
        return mockThread
    end
}

-- Mock love.filesystem for worker code loading
love.filesystem = {
    read = function(path)
        if path == "utils/async_https_worker.lua" then
            return "-- mock worker code"
        end
        return nil
    end
}

-- Mock love.timer
love.timer = {
    getTime = function()
        return os.clock()
    end,
    sleep = function(t) end
}

describe("AsyncHTTPS", function()
    local AsyncHTTPS
    local instance

    lust.before(function()
        -- Clear module cache
        package.loaded["utils.async_https"] = nil
        mockChannels = {}

        -- Load module and create instance
        AsyncHTTPS = require("utils.async_https")
        instance = AsyncHTTPS:new()
    end)

    lust.after(function()
        if instance then
            instance:shutdown()
        end
    end)

    describe("request", function()
        it("should queue request to worker thread", function()
            local callbackCalled = false
            local requestId = instance:request("https://example.com/test", nil, function(response)
                callbackCalled = true
            end)

            expect(requestId).to.be.a("number")
            expect(requestId).to.equal(1)

            -- Verify request was sent to input channel
            -- Note: Channel name is instance-specific, so we check the instance's channel
            expect(instance.inputChannel._queue[1]).to.exist()
            expect(instance.inputChannel._queue[1].id).to.equal(1)
            expect(instance.inputChannel._queue[1].url).to.equal("https://example.com/test")
        end)

        it("should increment request ID", function()
            local id1 = instance:request("https://example.com/1", nil, function() end)
            local id2 = instance:request("https://example.com/2", nil, function() end)
            local id3 = instance:request("https://example.com/3", nil, function() end)

            expect(id1).to.equal(1)
            expect(id2).to.equal(2)
            expect(id3).to.equal(3)
        end)

        it("should track pending requests", function()
            instance:request("https://example.com/1", nil, function() end)
            instance:request("https://example.com/2", nil, function() end)

            expect(instance:getPendingCount()).to.equal(2)
        end)

        it("should require valid URL", function()
            expect(function()
                instance:request("", nil, function() end)
            end).to.fail()

            expect(function()
                instance:request(nil, nil, function() end)
            end).to.fail()
        end)

        it("should require callback function", function()
            expect(function()
                instance:request("https://example.com/test", nil, nil)
            end).to.fail()

            expect(function()
                instance:request("https://example.com/test", nil, "not a function")
            end).to.fail()
        end)
    end)

    describe("update", function()
        it("should process completed requests", function()
            local callbackResponse = nil
            local requestId = instance:request("https://example.com/test", nil, function(response)
                callbackResponse = response
            end)

            -- Simulate worker thread response
            local outputChannel = instance.outputChannel
            outputChannel:push({
                id = requestId,
                url = "https://example.com/test",
                status = 200,
                body = "test response body",
                headers = { ["content-type"] = "text/plain" },
                error = false,
                elapsed = 0.5,
                timestamp = love.timer.getTime()
            })

            -- Process responses
            local processed = instance:update()

            expect(processed).to.equal(1)
            expect(callbackResponse).to.exist()
            expect(callbackResponse.id).to.equal(requestId)
            expect(callbackResponse.status).to.equal(200)
            expect(callbackResponse.body).to.equal("test response body")
            expect(callbackResponse.error).to.equal(false)
        end)

        it("should handle error responses", function()
            local callbackResponse = nil
            local requestId = instance:request("https://example.com/error", nil, function(response)
                callbackResponse = response
            end)

            -- Simulate error response
            local outputChannel = instance.outputChannel
            outputChannel:push({
                id = requestId,
                url = "https://example.com/error",
                status = 0,
                body = nil,
                error = true,
                elapsed = 0.1,
                timestamp = love.timer.getTime()
            })

            instance:update()

            expect(callbackResponse).to.exist()
            expect(callbackResponse.error).to.equal(true)
            expect(callbackResponse.status).to.equal(0)
        end)

        it("should remove pending request after processing", function()
            local requestId = instance:request("https://example.com/test", nil, function() end)

            expect(instance:getPendingCount()).to.equal(1)

            -- Simulate response
            local outputChannel = instance.outputChannel
            outputChannel:push({
                id = requestId,
                url = "https://example.com/test",
                status = 200,
                body = "ok",
                error = false
            })

            instance:update()

            expect(instance:getPendingCount()).to.equal(0)
        end)

        it("should process multiple responses in one update", function()
            local responses = {}

            local id1 = instance:request("https://example.com/1", nil, function(r)
                table.insert(responses, r)
            end)
            local id2 = instance:request("https://example.com/2", nil, function(r)
                table.insert(responses, r)
            end)
            local id3 = instance:request("https://example.com/3", nil, function(r)
                table.insert(responses, r)
            end)

            -- Simulate multiple responses
            local outputChannel = instance.outputChannel
            outputChannel:push({ id = id1, url = "https://example.com/1", status = 200, body = "1", error = false })
            outputChannel:push({ id = id2, url = "https://example.com/2", status = 200, body = "2", error = false })
            outputChannel:push({ id = id3, url = "https://example.com/3", status = 200, body = "3", error = false })

            local processed = instance:update()

            expect(processed).to.equal(3)
            expect(#responses).to.equal(3)
        end)
    end)

    describe("cancel", function()
        it("should cancel pending request", function()
            local callbackCalled = false
            local requestId = instance:request("https://example.com/test", nil, function()
                callbackCalled = true
            end)

            local cancelled = instance:cancel(requestId)

            expect(cancelled).to.equal(true)
            expect(instance:getPendingCount()).to.equal(0)

            -- Simulate response after cancellation
            local outputChannel = instance.outputChannel
            outputChannel:push({
                id = requestId,
                status = 200,
                body = "ok",
                error = false
            })

            instance:update()

            -- Callback should not be called
            expect(callbackCalled).to.equal(false)
        end)

        it("should return false for non-existent request", function()
            local cancelled = instance:cancel(999)
            expect(cancelled).to.equal(false)
        end)
    end)

    describe("getStats", function()
        it("should track request statistics", function()
            -- Make some requests
            instance:request("https://example.com/1", nil, function() end)
            instance:request("https://example.com/2", nil, function() end)

            local stats = instance:getStats()

            expect(stats.totalRequests).to.equal(2)
            expect(stats.pendingRequests).to.equal(2)
            expect(stats.completedRequests).to.equal(0)
            expect(stats.failedRequests).to.equal(0)
        end)

        it("should track completed and failed requests", function()
            local id1 = instance:request("https://example.com/ok", nil, function() end)
            local id2 = instance:request("https://example.com/fail", nil, function() end)

            local outputChannel = instance.outputChannel
            outputChannel:push({ id = id1, url = "https://example.com/ok", status = 200, body = "ok", error = false })
            outputChannel:push({ id = id2, url = "https://example.com/fail", status = 0, body = nil, error = true })

            instance:update()

            local stats = instance:getStats()
            expect(stats.completedRequests).to.equal(1)
            expect(stats.failedRequests).to.equal(1)
        end)
    end)

    describe("shutdown", function()
        it("should cancel all pending requests", function()
            instance:request("https://example.com/1", nil, function() end)
            instance:request("https://example.com/2", nil, function() end)

            expect(instance:getPendingCount()).to.equal(2)

            instance:shutdown()

            expect(instance:getPendingCount()).to.equal(0)
        end)

        it("should signal worker thread to shutdown", function()
            instance:request("https://example.com/test", nil, function() end)

            -- Get shutdown channel before shutdown clears it
            local shutdownChannel = instance.shutdownChannel
            instance:shutdown()

            -- Shutdown should have pushed to the channel
            expect(#shutdownChannel._queue > 0).to.equal(true)
        end)
    end)
end)
