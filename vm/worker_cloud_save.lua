-- Cloud Variable Save Worker Thread
-- Runs in a separate thread to save cloud variables without blocking main thread
-- Matches native Scratch async cloud variable behavior

require("love.filesystem")

-- Load JSON library for encoding (threads have independent Lua state)
local json = require("lib.json")

-- Thread channels for communication
local requestChannel = ... -- Channel to receive save requests (passed on thread start)
local responseChannel = love.thread.getChannel("cloud_save_response")

---Helper: Count keys in a table
---@param t table
---@return integer
local function countKeys(t)
    local count = 0
    for _ in pairs(t) do
        count = count + 1
    end
    return count
end

---Save cloud variable data to file
---@param filePath string Full file path (Love filesystem relative)
---@param cloudData table<string, number> Cloud variable data
---@return boolean success
---@return string|nil error Error message if failed
local function saveToFile(filePath, cloudData)
    -- Encode to JSON
    local ok, jsonStr = pcall(json.encode, cloudData)
    if not ok then
        return false, "JSON encode failed: " .. tostring(jsonStr)
    end

    -- Write to file
    local writeOk, writeErr = love.filesystem.write(filePath, jsonStr)
    if not writeOk then
        return false, "File write failed: " .. tostring(writeErr)
    end

    return true
end

-- Main worker loop
while true do
    local request = requestChannel:demand() -- Block until request arrives

    if request.type == "save" then
        -- Execute save operation
        local success, err = saveToFile(request.filePath, request.cloudData)

        -- Send response back to main thread
        responseChannel:push({
            type = "save_complete",
            success = success,
            error = err,
            filePath = request.filePath,
            varCount = countKeys(request.cloudData)
        })

    elseif request.type == "quit" then
        -- Graceful shutdown
        break
    end
end
