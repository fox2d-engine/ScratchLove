-- Multi-threaded Download Worker Thread
-- Individual worker thread for downloading assets concurrently
-- Runs in separate thread context - no Love2D graphics API calls allowed

local taskChannel, resultChannel, projectPath = ...

-- Add lua-https submodule path to package.cpath for loading compiled library
-- Worker threads have independent package.cpath, so we need to add it here too
package.cpath = package.cpath .. ";lib/lua-https/src/?.so"

-- Load required modules (safe for worker thread)
local socket = require("socket") -- For socket.sleep
local log = require("lib.log")

-- Load lua-https module (REQUIRED for asset downloads)
-- This should never fail because project_loader.lua checks for https support before creating worker
local https = require("https")

-- Asset download base URL
local ASSET_BASE = "https://cdn.assets.scratch.mit.edu/internalapi/asset"

-- Debug function for worker
---@param message string Debug message
local function debug(message)
    log.debug("Download Worker: " .. message)
end

-- Send result back to coordinator
---@param success boolean Whether download succeeded
---@param md5ext string Asset MD5 with extension
---@param error string|nil Error message if failed
local function sendResult(success, md5ext, error)
    resultChannel:push({
        success = success,
        md5ext = md5ext,
        error = error
    })
end

-- Download single asset with retry logic
---@param md5ext string Asset MD5 with extension
---@param projectPath string Project directory path
---@param maxRetries number|nil Maximum retry attempts (default: 2)
---@return boolean success Whether download succeeded
---@return string|nil error Error message if failed
local function downloadAssetWithRetry(md5ext, projectPath, maxRetries)
    maxRetries = maxRetries or 2
    local finalPath = projectPath .. "/" .. md5ext
    local tempPath = projectPath .. "/.downloading_" .. md5ext
    local url = ASSET_BASE .. "/" .. md5ext .. "/get/"

    for attempt = 1, maxRetries + 1 do
        -- Check if file already exists (another thread may have downloaded it)
        if love.filesystem.getInfo(finalPath) then
            return true, nil
        end

        local status, body, headers = https.request(url)

        if body and status == 200 then
            -- Save to temporary file first
            local tempSaveSuccess = love.filesystem.write(tempPath, body)
            if not tempSaveSuccess then
                if attempt <= maxRetries then
                    debug("Temp save failed for " ..
                        md5ext .. ", retrying (attempt " .. attempt .. "/" .. maxRetries .. ")")
                    socket.sleep(0.1) -- Brief delay before retry
                else
                    return false, "Failed to save temporary file"
                end
            else
                -- Move from temp to final location atomically
                local finalSaveSuccess = love.filesystem.write(finalPath, body)
                if finalSaveSuccess then
                    -- Clean up temporary file
                    love.filesystem.remove(tempPath)
                    debug("Successfully downloaded " .. md5ext)
                    return true, nil
                else
                    -- Clean up temporary file on failure
                    love.filesystem.remove(tempPath)
                    if attempt <= maxRetries then
                        debug("Final save failed for " ..
                            md5ext .. ", retrying (attempt " .. attempt .. "/" .. maxRetries .. ")")
                        socket.sleep(0.1) -- Brief delay before retry
                    else
                        return false, "Failed to save final file"
                    end
                end
            end
        else
            local errorMsg = "HTTP request failed: status=" .. tostring(status)
            if attempt <= maxRetries then
                debug("Download failed for " ..
                    md5ext .. " (" .. errorMsg .. "), retrying (attempt " .. attempt .. "/" .. maxRetries .. ")")
                socket.sleep(0.2) -- Longer delay for network issues
            else
                return false, errorMsg
            end
        end
    end

    return false, "Max retries exceeded"
end

-- Main worker loop
debug("Download worker thread started for project: " .. projectPath)

local function safeExecute()
    while true do
        -- Wait for task from coordinator
        local task = taskChannel:demand() -- Block until task received

        -- Check for stop signal
        if task.type == "stop" then
            debug("Download worker received stop signal")
            break
        end

        -- Validate task structure
        if not task.md5ext or not task.url then
            sendResult(false, task.md5ext or "unknown", "Invalid task structure")
            goto continue
        end

        debug("Processing download: " .. task.md5ext)

        -- Attempt download with retry
        local success, error = downloadAssetWithRetry(task.md5ext, projectPath)

        -- Send result back to coordinator
        sendResult(success, task.md5ext, error)

        ::continue::
    end
end

-- Execute with error handling
local success, error = pcall(safeExecute)
if not success then
    debug("Worker thread error: " .. tostring(error))
    -- Send error result if possible
    pcall(function()
        resultChannel:push({
            success = false,
            md5ext = "worker_error",
            error = "Worker thread crashed: " .. tostring(error)
        })
    end)
end

debug("Download worker thread exiting")
