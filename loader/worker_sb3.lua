-- Worker Thread for SB3 File Extraction
-- Runs in a separate thread to extract sb3 files without blocking main thread
-- Only performs I/O operations, no Love2D graphics API calls

local commandChannel, responseChannel = ...

-- Add error handling for the entire worker thread
local function safeExecute(func)
    local success, result = pcall(func)
    if not success then
        responseChannel:push({
            type = "error",
            message = "Worker thread error: " .. tostring(result)
        })
        return false
    end
    return true
end

-- Load required modules
local log = require("lib.log")
local json = require("lib.json")
local ProjectValidator = require("loader.project_validator")

-- Debug function
local function debug(message)
    log.debug("Worker SB3: " .. message)
end

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

-- Simple ZIP extraction function
---@param data string Raw ZIP data
---@param projectPath string Target directory path
---@return boolean success Whether extraction succeeded
local function extractZip(data, projectPath)
    -- Create a temporary file for the ZIP data
    local tempFile = "temp_extract.sb3"
    local success, writeErr = love.filesystem.write(tempFile, data)
    if not success then
        sendError("Failed to write temporary ZIP file: " .. (writeErr or "unknown error"))
        return false
    end

    -- Mount as ZIP archive
    local mountSuccess = love.filesystem.mount(tempFile, "zip_temp")
    if not mountSuccess then
        love.filesystem.remove(tempFile)
        sendError("Failed to mount sb3 file as ZIP archive")
        return false
    end

    sendProgress("extracting", 0.3, "Reading ZIP contents...")

    -- Get all files in the ZIP
    local files = love.filesystem.getDirectoryItems("zip_temp")
    if #files == 0 then
        love.filesystem.unmount("zip_temp")
        love.filesystem.remove(tempFile)
        sendError("No files found in sb3 archive")
        return false
    end

    -- Extract each file
    local extractedCount = 0
    for i, filename in ipairs(files) do
        local sourcePath = "zip_temp/" .. filename
        local fileInfo = love.filesystem.getInfo(sourcePath)

        if fileInfo and fileInfo.type == "file" then
            -- Read file from ZIP
            local fileData = love.filesystem.read(sourcePath)
            if fileData then
                -- Write to project directory
                local targetPath = projectPath .. "/" .. filename
                local writeSuccess, writeError = love.filesystem.write(targetPath, fileData)

                if writeSuccess then
                    extractedCount = extractedCount + 1
                    local progress = 0.3 + (i / #files) * 0.6
                    sendProgress("extracting", progress, "Extracted: " .. filename)
                else
                    log.warn("Failed to extract " .. filename .. ": " .. (writeError or "unknown error"))
                end
            else
                log.warn("Failed to read " .. filename .. " from ZIP")
            end
        end
    end

    -- Clean up
    love.filesystem.unmount("zip_temp")
    love.filesystem.remove(tempFile)

    if extractedCount == 0 then
        sendError("No files were successfully extracted from sb3 archive")
        return false
    end

    sendProgress("extracting", 1.0, string.format("Extracted %d files successfully", extractedCount))
    return true
end

-- Main worker function
local function processProject(command)
    debug("Starting processProject")
    local input = command.input
    local projectPath = command.projectPath

    debug("Input: " .. input .. ", ProjectPath: " .. projectPath)
    sendProgress("loading", 0.1, "Loading sb3 file...")

    -- Read the sb3 file
    local fileData = love.filesystem.read(input)

    -- If reading from Love2D filesystem fails, try external path
    if not fileData then
        debug("Love2D filesystem read failed, trying external path")
        sendProgress("loading", 0.15, "Trying external file path...")

        local file = io.open(input, "rb")
        if file then
            fileData = file:read("*a")
            file:close()
            debug("Successfully read from external path")
        else
            debug("External path also failed")
        end
    else
        debug("Successfully read from Love2D filesystem")
    end

    if not fileData then
        local errorMsg = "Failed to read sb3 file: " .. input
        debug("ERROR: " .. errorMsg)
        sendError(errorMsg)
        return
    end

    debug("File data size: " .. #fileData)
    sendProgress("loading", 0.2, "File loaded, starting extraction...")

    -- Extract the ZIP contents
    local success = extractZip(fileData, projectPath)
    if not success then
        debug("extractZip failed")
        return -- Error already sent by extractZip
    end

    debug("Extraction completed successfully")

    -- Validate project format (must be SB3)
    sendProgress("validating", 0.95, "Validating project format...")
    local projectJsonPath = projectPath .. "/project.json"
    local projectJsonData = love.filesystem.read(projectJsonPath)

    if not projectJsonData then
        sendError("Failed to read project.json after extraction")
        return
    end

    local parseSuccess, projectData = pcall(json.decode, projectJsonData)
    if not parseSuccess then
        sendError("Failed to parse project.json: " .. tostring(projectData))
        return
    end

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

    sendProgress("complete", 1.0, "Project extraction and validation completed successfully")
    sendComplete()
end

-- Main worker loop with error handling
debug("Worker thread started")
safeExecute(function()
    while true do
        debug("Waiting for command...")
        local command = commandChannel:demand() -- Block until command received
        debug("Received command: " .. tostring(command and command.type or "nil"))

        if command.type == "load" then
            processProject(command)
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
debug("Worker thread exiting")
