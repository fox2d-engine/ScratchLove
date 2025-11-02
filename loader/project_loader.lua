-- Multi-threaded Project Loader
-- Manages project loading using separate worker threads for I/O operations
-- and main thread for Love2D resource creation

-- Add lua-https submodule path to package.cpath for loading compiled library
-- This allows loading from lib/lua-https/src/https.so without system installation
package.cpath = package.cpath .. ";lib/lua-https/src/?.so"

local log = require("lib.log")

---@class ProjectLoader
---@field projectsDir string Base directory for storing extracted projects
---@field currentProjectId string|nil Currently loading project identifier
---@field workerThread love.Thread|nil Active worker thread
---@field commandChannel love.Channel Channel for sending commands to worker
---@field responseChannel love.Channel Channel for receiving responses from worker
---@field isLoading boolean Whether currently loading a project
---@field onProgress function|nil Progress callback function
---@field onComplete function|nil Completion callback function
---@field onError function|nil Error callback function
local ProjectLoader = {}
ProjectLoader.__index = ProjectLoader

---Create new project loader
---@return ProjectLoader
function ProjectLoader:new()
    local self = setmetatable({}, ProjectLoader)

    -- Setup appdata directory structure
    self.projectsDir = "projects"
    self.currentProjectId = nil
    self.workerThread = nil
    self.commandChannel = nil
    self.responseChannel = nil
    self.isLoading = false
    self.onProgress = nil
    self.onComplete = nil
    self.onError = nil

    -- Ensure projects directory exists
    self:ensureProjectsDirectory()

    return self
end

---Ensure projects directory exists in appdata
function ProjectLoader:ensureProjectsDirectory()
    local info = love.filesystem.getInfo(self.projectsDir)
    if not info then
        local success = love.filesystem.createDirectory(self.projectsDir)
        if not success then
            log.error("Failed to create projects directory in appdata")
            error("Failed to create projects directory in appdata")
        end
        log.info("Created projects directory: " .. love.filesystem.getSaveDirectory() .. "/" .. self.projectsDir)
    elseif info.type ~= "directory" then
        log.error("Projects path exists but is not a directory")
        error("Projects path exists but is not a directory")
    end
end

---Clean up project directory if it exists
---@param projectId string Project identifier
function ProjectLoader:cleanupProject(projectId)
    local projectPath = self.projectsDir .. "/" .. projectId
    local info = love.filesystem.getInfo(projectPath)

    if info and info.type == "directory" then
        log.info("Cleaning up existing project files (keeping assets): " .. projectPath)

        -- Only remove project.json and any temporary files, keep asset files
        local items = love.filesystem.getDirectoryItems(projectPath)
        for _, item in ipairs(items) do
            local itemPath = projectPath .. "/" .. item
            local itemInfo = love.filesystem.getInfo(itemPath)

            if itemInfo and itemInfo.type == "file" then
                -- Remove project.json and any temporary downloading files
                if item == "project.json" or item:match("^%.downloading_") then
                    love.filesystem.remove(itemPath)
                    log.debug("Removed: " .. item)
                end
                -- Keep all other files (asset files)
            end
        end
        log.info("Project directory cleaned up successfully (assets preserved)")
    end
end

---Get project directory path
---@param projectId string Project identifier
---@return string path Full path to project directory
function ProjectLoader:getProjectPath(projectId)
    return self.projectsDir .. "/" .. projectId
end

---Load project from sb3 file or online project ID
---@param input string Path to sb3 file or project ID
---@param onProgress function|nil Progress callback: function(stage, progress, message)
---@param onComplete function|nil Completion callback: function(projectPath)
---@param onError function|nil Error callback: function(errorMessage)
function ProjectLoader:loadProject(input, onProgress, onComplete, onError)
    if self.isLoading then
        if onError then
            onError("Another project is already loading")
        end
        return
    end

    -- Generate project ID
    local isOnlineProject = tonumber(input) ~= nil

    -- Check HTTPS support for online projects
    if isOnlineProject then
        local hasHttpsSupport = pcall(function() require("https") end)
        if not hasHttpsSupport then
            local errorMsg = "CRITICAL ERROR: Online project loading requires lua-https module!\n\n" ..
                "The lua-https module is not compiled or not found.\n" ..
                "Online projects cannot be loaded without HTTPS support.\n\n" ..
                "To fix this issue:\n" ..
                "1. Compile the lua-https module (see README for instructions)\n" ..
                "2. Place the compiled library in your LÖVE path\n" ..
                "3. Restart the application\n\n" ..
                "Alternatively, use a local .sb3 file instead of a project ID."
            if onError then
                onError(errorMsg)
            end
            return
        end
    end

    self.isLoading = true
    self.onProgress = onProgress
    self.onComplete = onComplete
    self.onError = onError
    self.currentProjectId = isOnlineProject and input or self:generateProjectIdFromPath(input)

    log.info("Starting project load: " .. input .. " (ID: " .. self.currentProjectId .. ")")

    -- Clean up existing project directory
    self:cleanupProject(self.currentProjectId)

    -- Create new project directory
    local projectPath = self:getProjectPath(self.currentProjectId)
    local success = love.filesystem.createDirectory(projectPath)
    if not success then
        self:handleError("Failed to create project directory: " .. projectPath)
        return
    end

    -- Create communication channels
    self.commandChannel = love.thread.newChannel()
    self.responseChannel = love.thread.newChannel()

    -- Start worker thread
    if isOnlineProject then
        self.workerThread = love.thread.newThread("loader/worker_online.lua")
    else
        self.workerThread = love.thread.newThread("loader/worker_sb3.lua")
    end

    -- Send load command to worker
    local command = {
        type = "load",
        input = input,
        projectId = self.currentProjectId,
        projectPath = projectPath
    }

    self.commandChannel:push(command)
    self.workerThread:start(self.commandChannel, self.responseChannel)

    if self.onProgress then
        self.onProgress("initializing", 0, "Starting worker thread...")
    end
end

---Update loader state (call from love.update)
---@return boolean isActive Whether loader is still active
function ProjectLoader:update()
    if not self.isLoading or not self.workerThread then
        return false
    end

    -- Process all pending worker messages first
    local processedMessages = false
    while true do
        local message = self.responseChannel:pop()
        if not message then
            break
        end
        processedMessages = true
        self:handleWorkerMessage(message)

        -- If we received a completion or error message, loading should be finished
        if not self.isLoading then
            break
        end
    end

    -- Only check thread status after processing all messages
    if self.isLoading and not self.workerThread:isRunning() then
        local error = self.workerThread:getError()
        if error then
            self:handleError("Worker thread crashed: " .. error)
        else
            -- Give one more chance to process any final messages
            if not processedMessages then
                -- Wait a bit and try again
                local finalMessage = self.responseChannel:pop()
                if finalMessage then
                    self:handleWorkerMessage(finalMessage)
                end
            end

            -- If still loading after processing messages, then it's an error
            if self.isLoading then
                self:handleError("Worker thread finished without completion message")
            end
        end
    end

    return self.isLoading
end

---Handle message from worker thread
---@param message table Message from worker thread
function ProjectLoader:handleWorkerMessage(message)
    if message.type == "progress" then
        if self.onProgress then
            self.onProgress(message.stage, message.progress, message.message)
        end
    elseif message.type == "complete" then
        log.info("Multi-threaded loading: Worker completed successfully")

        -- Save project path before cleanup clears currentProjectId
        local projectPath = nil
        if self.currentProjectId then
            projectPath = self:getProjectPath(self.currentProjectId)
        end

        self:cleanup()

        if self.onComplete and projectPath then
            self.onComplete(projectPath)
        end

        self.isLoading = false
    elseif message.type == "error" then
        log.error("Multi-threaded loading error: " .. tostring(message.message))
        self:handleError(message.message)
    else
        log.warn("Multi-threaded loading: Unknown worker message type: " .. tostring(message.type))
    end
end

---Handle error during loading
---@param errorMessage string Error message
function ProjectLoader:handleError(errorMessage)
    log.error("Project loading error: " .. errorMessage)
    self:cleanup()

    if self.onError then
        self.onError(errorMessage)
    end

    self.isLoading = false
end

---Clean up worker thread and channels
function ProjectLoader:cleanup()
    if self.workerThread then
        -- Send stop command if thread is still running
        if self.workerThread:isRunning() and self.commandChannel then
            self.commandChannel:push({ type = "stop" })
        end

        -- Don't wait too long for thread to finish
        local startTime = love.timer.getTime()
        while self.workerThread:isRunning() and (love.timer.getTime() - startTime) < 1.0 do
            love.timer.sleep(0.01)
        end

        self.workerThread = nil
    end

    self.commandChannel = nil
    self.responseChannel = nil
    self.currentProjectId = nil
end

---Generate project ID from file path with UTF-8 support
---@param filepath string Path to sb3 file
---@return string projectId Generated project ID
function ProjectLoader:generateProjectIdFromPath(filepath)
    -- Extract filename from path (handle both forward and backslashes)
    local filename = filepath:match("([^/\\]+)$") or filepath

    -- Remove file extension if present
    local filenameWithoutExt = filename:match("^(.+)%..+$") or filename

    -- Replace problematic characters while preserving UTF-8
    -- Only replace ASCII punctuation and spaces, keep UTF-8 multi-byte sequences
    local safeId = ""
    local i = 1
    while i <= #filenameWithoutExt do
        local byte = string.byte(filenameWithoutExt, i)
        local char = string.char(byte)

        if byte >= 128 then
            -- UTF-8 multi-byte sequence, keep as-is
            safeId = safeId .. char
            i = i + 1
        elseif (byte >= 48 and byte <= 57) or -- 0-9
            (byte >= 65 and byte <= 90) or    -- A-Z
            (byte >= 97 and byte <= 122) or   -- a-z
            (byte == 45) or (byte == 95) then -- - and _
            safeId = safeId .. char
            i = i + 1
        else
            -- Replace other ASCII chars with underscore
            safeId = safeId .. "_"
            i = i + 1
        end
    end

    -- Clean up underscores
    safeId = safeId:gsub("_+", "_"):gsub("^_+", ""):gsub("_+$", "")

    -- Ensure we have something if the filename was all special characters
    if safeId == "" then
        safeId = "project"
    end

    -- Truncate to reasonable length (byte-based to be safe)
    local maxLen = 80
    if #safeId > maxLen then
        safeId = safeId:sub(1, maxLen)
        -- Make sure we didn't cut in the middle of a UTF-8 sequence
        while #safeId > 0 and string.byte(safeId, -1) >= 128 and string.byte(safeId, -1) < 192 do
            safeId = safeId:sub(1, -2)
        end
    end

    -- Add stable hash based on original filepath for uniqueness and cache reuse
    -- Use simple string hash that's deterministic across runs
    local hash = 0
    for i = 1, #filepath do
        hash = (hash * 31 + string.byte(filepath, i)) % 0xFFFFFFFF
    end
    local hashStr = string.format("_%08X", hash)

    return safeId .. hashStr
end

---Stop current loading operation
function ProjectLoader:stop()
    if self.isLoading then
        log.info("Stopping project load...")
        self:cleanup()
        self.isLoading = false
    end
end

return ProjectLoader
