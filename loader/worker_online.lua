-- Worker Thread for Online Project Download
-- Runs in a separate thread to download Scratch projects without blocking main thread
-- Only performs network I/O, no Love2D graphics API calls

local commandChannel, responseChannel = ...

-- Add lua-https submodule path to package.cpath for loading compiled library
-- Worker threads have independent package.cpath, so we need to add it here too
package.cpath = package.cpath .. ";lib/lua-https/src/?.so"

-- Add error handling for the entire worker thread
local function safeExecute(func)
    local success, result = pcall(func)
    if not success then
        responseChannel:push({
            type = "error",
            message = "Online worker thread error: " .. tostring(result)
        })
        return false
    end
    return true
end

-- Load required modules (safe for worker thread)
local socket = require("socket") -- For socket.sleep
local json = require("lib.json")
local log = require("lib.log")
local DownloadCoordinator = require("loader.download_coordinator")
local ProjectValidator = require("loader.project_validator")

-- Load lua-https module (REQUIRED for online project loading)
-- This should never fail because project_loader.lua checks for https support before creating worker
-- Note: package.cpath is already configured in project_loader.lua before worker creation
local https = require("https")

-- Debug function
local function debug(message)
    log.debug("Worker Online: " .. message)
end

-- API endpoints
local API_BASE = "https://api.scratch.mit.edu"
local PROJECT_BASE = "https://projects.scratch.mit.edu"
local ASSET_BASE = "https://cdn.assets.scratch.mit.edu/internalapi/asset"

-- Helper function to send progress updates
---@param stage string Current stage name
---@param progress number Progress (0-1)
---@param message string Status message
local function sendProgress(stage, progress, message)
    responseChannel:push({
        type = "progress",
        stage = stage,
        progress = progress,
        message = message
    })
end

-- Helper function to send completion
local function sendComplete()
    responseChannel:push({ type = "complete" })
end

-- Helper function to send error
---@param message string Error message
local function sendError(message)
    responseChannel:push({
        type = "error",
        message = message
    })
end

-- Format filename for display with truncation if too long
---@param filename string Full filename to format
---@return string displayName Formatted filename for display
local function formatDisplayName(filename)
    if string.len(filename) <= 10 then
        return filename
    end

    -- Find the last dot to preserve extension
    local dotPos = string.find(filename, "%.[^%.]*$")
    if dotPos then
        local namepart = string.sub(filename, 1, dotPos - 1)
        local extension = string.sub(filename, dotPos)
        return string.sub(namepart, 1, 4) .. "..." .. string.sub(namepart, -4) .. extension
    else
        -- No extension found, use original logic
        return string.sub(filename, 1, 4) .. "..." .. string.sub(filename, -4)
    end
end

-- Get project token from Scratch API
---@param projectId number Project ID
---@return string|nil token Project token or nil on failure
local function getProjectToken(projectId)
    local url = API_BASE .. "/projects/" .. tostring(projectId) .. "/"
    log.info("Worker: Fetching project token from: " .. url)

    local status, body = https.request(url)
    if not body or status ~= 200 then
        log.error("Worker: Failed to fetch project token, status: " .. tostring(status))
        return nil
    end

    local success, data = pcall(json.decode, body)
    if not success or not data.project_token then
        return nil
    end

    return data.project_token
end

-- Fetch project data using token
---@param projectId number Project ID
---@param token string Project token
---@return table|nil,string|nil projectData Raw project JSON data or nil on failure
local function getProjectData(projectId, token)
    local url = PROJECT_BASE .. "/" .. tostring(projectId) .. "?token=" .. token
    log.info("Worker: Fetching project data from: " .. url)

    local status, body = https.request(url)
    if not body or status ~= 200 then
        return nil, nil
    end

    local success, data = pcall(json.decode, body)
    if not success then
        return nil, body
    end

    return data, body
end

-- Extract asset list from project data
---@param projectData table Raw project JSON
---@return table[] assets List of assets to download
local function extractAssetList(projectData)
    local assets = {}
    local seen = {}

    local function addAsset(md5ext, name)
        if md5ext and not seen[md5ext] then
            seen[md5ext] = true
            table.insert(assets, {
                md5ext = md5ext,
                name = name or md5ext
            })
        end
    end

    if projectData.targets then
        for _, target in ipairs(projectData.targets) do
            -- Extract costumes
            if target.costumes then
                for _, costume in ipairs(target.costumes) do
                    -- Handle missing md5ext (fallback to assetId.dataFormat)
                    local md5ext = costume.md5ext
                    if not md5ext and costume.assetId and costume.dataFormat then
                        md5ext = costume.assetId .. "." .. costume.dataFormat
                        log.debug("Worker: costume '" .. (costume.name or "unknown") ..
                            "' missing md5ext, using fallback: " .. md5ext)
                    end
                    addAsset(md5ext, costume.name)
                end
            end

            -- Extract sounds
            if target.sounds then
                for _, sound in ipairs(target.sounds) do
                    -- Handle missing md5ext (fallback to assetId.dataFormat)
                    local md5ext = sound.md5ext
                    if not md5ext and sound.assetId and sound.dataFormat then
                        md5ext = sound.assetId .. "." .. sound.dataFormat
                        log.debug("Worker: sound '" .. (sound.name or "unknown") ..
                            "' missing md5ext, using fallback: " .. md5ext)
                    end
                    addAsset(md5ext, sound.name)
                end
            end
        end
    end

    return assets
end

-- Main worker function
local function processOnlineProject(command)
    debug("Starting processOnlineProject")
    local projectId = tonumber(command.input)
    local projectPath = command.projectPath

    debug("Project ID: " .. tostring(projectId) .. ", ProjectPath: " .. projectPath)

    if not projectId then
        local errorMsg = "Invalid project ID: " .. tostring(command.input)
        debug("ERROR: " .. errorMsg)
        sendError(errorMsg)
        return
    end

    -- Step 1: Get project token
    sendProgress("token", 0.05, "Fetching project information...")
    local token = getProjectToken(projectId)
    if not token then
        sendError("Failed to get project token for project " .. projectId)
        return
    end

    -- Step 2: Get project data
    sendProgress("project", 0.1, "Downloading project data...")
    local projectData, rawBody = getProjectData(projectId, token)
    if not projectData or not rawBody then
        sendError("Failed to download project data for project " .. projectId)
        return
    end

    -- Step 3: Validate project format (must be SB3)
    sendProgress("validating", 0.15, "Validating project format...")
    local version, validationError = ProjectValidator.validate(projectData)
    if not version then
        sendError("Invalid project format: " .. tostring(validationError))
        return
    end

    if version ~= 3 then
        sendError(string.format("Unsupported project format: SB%d (only SB3 is supported)", version))
        return
    end

    -- Limit semver display length to prevent log overflow
    local semver = tostring(projectData.meta.semver)
    if #semver > 50 then
        semver = semver:sub(1, 47) .. "..."
    end
    log.info(string.format("Project format validated: SB%d (semver: %s)", version, semver))

    -- Step 4: Save project.json
    sendProgress("saving", 0.17, "Saving project data...")
    local saveSuccess = love.filesystem.write(projectPath .. "/project.json", rawBody)
    if not saveSuccess then
        sendError("Failed to save project.json")
        return
    end

    -- Step 5: Extract asset list
    sendProgress("assets", 0.2, "Analyzing project assets...")
    local assets = extractAssetList(projectData)

    if #assets == 0 then
        log.warn("Worker: No assets found in project")
        sendProgress("complete", 1.0, "Project has no assets, download complete")
        sendComplete()
        return
    end

    -- Step 5: Use multi-threaded download coordinator for assets
    local existingCount = 0
    local tasksToDownload = {}

    for _, asset in ipairs(assets) do
        local assetPath = projectPath .. "/" .. asset.md5ext
        if love.filesystem.getInfo(assetPath) then
            existingCount = existingCount + 1
        else
            -- Add to download queue
            table.insert(tasksToDownload, {
                md5ext = asset.md5ext,
                name = asset.name,
                url = ASSET_BASE .. "/" .. asset.md5ext .. "/get/"
            })
        end
    end

    local needsDownload = #tasksToDownload
    if needsDownload == 0 then
        sendProgress("complete", 1.0, string.format("All %d assets already exist, no download needed", #assets))
        sendComplete()
        return
    end

    sendProgress("downloading", 0.25,
        string.format("Starting concurrent download of %d assets (%d already exist)...", needsDownload, existingCount))

    -- Initialize download coordinator with moderate concurrency
    local coordinator = DownloadCoordinator:new(8)
    coordinator:initializeWorkers(projectPath)

    local successCount = existingCount -- Start with existing files
    local errorCount = 0

    -- Progress callback for coordinator
    local function onDownloadProgress(completed, total, success, failed)
        local progress = 0.25 + (completed / total) * 0.7
        local displayName = "..."
        -- Safe access to task name
        if completed > 0 and completed <= #tasksToDownload then
            displayName = formatDisplayName(tasksToDownload[completed].md5ext)
        end
        sendProgress("downloading", progress,
            string.format("Down %s (%d/%d, %d success, %d failed)", displayName, completed, total, success, failed))

        successCount = existingCount + success
        errorCount = failed
    end

    -- Start concurrent downloads
    coordinator:startDownload(tasksToDownload, onDownloadProgress)

    -- Wait for completion
    while not coordinator:update() do
        -- Use socket.sleep for worker thread compatibility
        socket.sleep(0.01)
    end

    -- Final statistics
    local finalCompleted, finalTotal, finalSuccess, finalFailed = coordinator:getStats()
    successCount = existingCount + finalSuccess
    errorCount = finalFailed

    -- Report results
    local finalMessage = string.format("Downloaded %d/%d assets successfully using %d threads", successCount, #assets,
        coordinator.maxConcurrentDownloads)
    if errorCount > 0 then
        finalMessage = finalMessage .. string.format(" (%d failed)", errorCount)
    end

    debug("Assets download completed: " .. finalMessage)
    sendProgress("complete", 1.0, finalMessage)
    debug("Sending completion message...")
    sendComplete()
    debug("Completion message sent")
end

-- Main worker loop with error handling
debug("Online worker thread started")
safeExecute(function()
    while true do
        debug("Waiting for command...")
        local command = commandChannel:demand() -- Block until command received
        debug("Received command: " .. tostring(command and command.type or "nil"))

        if command.type == "load" then
            processOnlineProject(command)
            break -- Exit after processing one project
        elseif command.type == "stop" then
            debug("Worker thread received stop command")
            break
        else
            local errorMsg = "Unknown command type: " .. tostring(command.type)
            debug("ERROR: " .. errorMsg)
            sendError(errorMsg)
            break
        end
    end
end)
debug("Online worker thread exiting")
