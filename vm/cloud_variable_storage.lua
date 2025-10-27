-- Cloud Variable Storage
-- Manages persistent storage of cloud variables using love.filesystem
-- Uses background thread to avoid blocking main execution

local json = require("lib.json")
local log = require("lib.log")
local Cast = require("utils.cast")

---@class CloudVariableStorage
---@field projectPath string|nil Project directory path for storage
---@field cloudData table<string, number> Cloud variable data cache (variableId -> value)
---@field saveThread love.Thread|nil Background save worker thread
---@field requestChannel love.Channel|nil Channel to send save requests to worker
---@field responseChannel love.Channel|nil Channel to receive save responses from worker
---@field pendingSave boolean True if there's data waiting to be saved
---@field lastSaveTime number Timestamp of last save request
---@field _variableIndex table<string, {target: table, variable: table}>|nil Variable ID index for O(1) lookups
local CloudVariableStorage = {}
CloudVariableStorage.__index = CloudVariableStorage

-- Storage filename (stored in project directory)
CloudVariableStorage.STORAGE_FILE = "cloud_variables.json"

-- Auto-save interval (seconds) - matches Scratch cloud variable update rate
CloudVariableStorage.AUTO_SAVE_INTERVAL = 2.0

---Create a new cloud variable storage manager
---@param projectPath string|nil Project directory path (Love filesystem relative)
---@return CloudVariableStorage
function CloudVariableStorage:new(projectPath)
    local self = setmetatable({}, CloudVariableStorage)

    self.projectPath = projectPath
    self.cloudData = {}
    self.saveThread = nil
    self.requestChannel = nil
    self.responseChannel = nil
    self.pendingSave = false
    self.lastSaveTime = 0
    self._variableIndex = nil -- Will be built on first use

    return self
end

---Load cloud variables from storage file
---@return boolean success True if loaded successfully
function CloudVariableStorage:load()
    if not self.projectPath then
        log.debug("CloudVariableStorage: No projectPath set, skipping load")
        return false
    end

    local filePath = self.projectPath .. "/" .. CloudVariableStorage.STORAGE_FILE

    -- Check if file exists
    local fileInfo = love.filesystem.getInfo(filePath)
    if not fileInfo then
        log.debug("CloudVariableStorage: No cloud variable file found at %s", filePath)
        return false
    end

    -- Read file contents
    local contents, readErr = love.filesystem.read(filePath)
    if not contents then
        log.warn("CloudVariableStorage: Failed to read cloud variables from %s: %s",
                 filePath, tostring(readErr))
        return false
    end

    -- Parse JSON
    local ok, data = pcall(json.decode, contents)
    if not ok then
        log.warn("CloudVariableStorage: Failed to parse cloud variables JSON from %s: %s",
                 filePath, tostring(data))
        return false
    end

    -- Validate and load data
    if type(data) ~= "table" then
        log.warn("CloudVariableStorage: Invalid cloud variables data format (expected table)")
        return false
    end

    self.cloudData = data
    log.info("CloudVariableStorage: Loaded %d cloud variable(s) from %s",
             self:_countKeys(data), filePath)

    return true
end

---Save cloud variables to storage file
---@return boolean success True if saved successfully
function CloudVariableStorage:save()
    if not self.projectPath then
        log.debug("CloudVariableStorage: No projectPath set, skipping save")
        return false
    end

    local filePath = self.projectPath .. "/" .. CloudVariableStorage.STORAGE_FILE

    -- Encode to JSON
    local ok, jsonStr = pcall(json.encode, self.cloudData)
    if not ok then
        log.error("CloudVariableStorage: Failed to encode cloud variables to JSON: %s",
                  tostring(jsonStr))
        return false
    end

    -- Write to file
    local writeOk, writeErr = love.filesystem.write(filePath, jsonStr)
    if not writeOk then
        log.error("CloudVariableStorage: Failed to write cloud variables to %s: %s",
                  filePath, tostring(writeErr))
        return false
    end

    log.debug("CloudVariableStorage: Saved %d cloud variable(s) to %s",
              self:_countKeys(self.cloudData), filePath)

    return true
end

---Get a cloud variable value from cache
---@param variableId string Variable ID
---@return number|nil value Cloud variable value or nil if not found
function CloudVariableStorage:get(variableId)
    return self.cloudData[variableId]
end

---Set a cloud variable value in cache (async save, matches Scratch behavior)
---@param variableId string Variable ID
---@param value any Variable value (will be coerced to number)
---@return boolean success True if value was set in cache
function CloudVariableStorage:set(variableId, value)
    -- Cloud variables are always coerced to numbers (matching native Scratch behavior)
    local numValue = Cast.toNumber(value)

    -- Update cache
    self.cloudData[variableId] = numValue

    -- Mark as pending save (will be saved asynchronously)
    self.pendingSave = true

    return true
end

---Build variable ID index for O(1) lookups
---@param runtime Runtime Runtime instance
function CloudVariableStorage:_buildVariableIndex(runtime)
    if not runtime or not runtime.stage then
        log.warn("CloudVariableStorage: Cannot build variable index - runtime unavailable")
        return
    end

    self._variableIndex = {}

    -- Index stage variables
    if runtime.stage.variables then
        for varId, variable in pairs(runtime.stage.variables) do
            if variable.isCloud then
                self._variableIndex[varId] = {
                    target = runtime.stage,
                    variable = variable
                }
            end
        end
    end

    -- Index sprite variables
    for _, target in ipairs(runtime.targets) do
        if target.variables then
            for varId, variable in pairs(target.variables) do
                if variable.isCloud then
                    -- Only index if not already present (stage variables take precedence)
                    if not self._variableIndex[varId] then
                        self._variableIndex[varId] = {
                            target = target,
                            variable = variable
                        }
                    end
                end
            end
        end
    end
end

---Apply loaded cloud variable values to runtime variables
---Optimized with O(1) variable lookups using pre-built index
---@param runtime Runtime Runtime instance
function CloudVariableStorage:applyToRuntime(runtime)
    if not runtime or not runtime.stage then
        log.warn("CloudVariableStorage: Cannot apply cloud variables - runtime or stage not available")
        return
    end

    -- Build index on first use
    if not self._variableIndex then
        self:_buildVariableIndex(runtime)
    end

    local appliedCount = 0

    -- O(cloudVars) lookup with indexed access
    for variableId, value in pairs(self.cloudData) do
        local entry = self._variableIndex[variableId]
        if entry then
            entry.variable.value = value
            appliedCount = appliedCount + 1
            log.debug("CloudVariableStorage: Applied cloud variable to %s: %s = %s",
                     entry.target.name or "stage", entry.variable.name, tostring(value))
        end
    end

    if appliedCount > 0 then
        log.info("CloudVariableStorage: Applied %d cloud variable value(s) to runtime", appliedCount)
    end
end

---Collect all cloud variables from runtime and save to storage
---@param runtime Runtime Runtime instance
---@return boolean success True if saved successfully
function CloudVariableStorage:collectFromRuntime(runtime)
    if not runtime or not runtime.stage then
        log.warn("CloudVariableStorage: Cannot collect cloud variables - runtime or stage not available")
        return false
    end

    local collectedCount = 0

    -- Collect from stage variables
    for variableId, variable in pairs(runtime.stage.variables) do
        if variable.isCloud then
            if type(variable.value) == "number" then
                self.cloudData[variableId] = variable.value
                collectedCount = collectedCount + 1
            else
                log.warn("CloudVariableStorage: Skipping non-numeric cloud variable: %s = %s",
                        variable.name, tostring(variable.value))
            end
        end
    end

    -- Collect from sprite variables
    for _, target in ipairs(runtime.targets) do
        if target.variables then
            for variableId, variable in pairs(target.variables) do
                if variable.isCloud then
                    if type(variable.value) == "number" then
                        self.cloudData[variableId] = variable.value
                        collectedCount = collectedCount + 1
                    else
                        log.warn("CloudVariableStorage: Skipping non-numeric cloud variable: %s = %s",
                                variable.name, tostring(variable.value))
                    end
                end
            end
        end
    end

    if collectedCount > 0 then
        log.debug("CloudVariableStorage: Collected %d cloud variable value(s) from runtime", collectedCount)
        return self:save()
    end

    return true
end

---Helper: Count keys in a table
---@param t table Table to count
---@return integer count Number of keys
function CloudVariableStorage:_countKeys(t)
    local count = 0
    for _ in pairs(t) do
        count = count + 1
    end
    return count
end

-- Thread Management

---Start the background save worker thread
---@return boolean success True if thread started successfully
function CloudVariableStorage:startThread()
    if self.saveThread then
        log.debug("CloudVariableStorage: Save thread already running")
        return true
    end

    -- Load worker thread code
    local threadCode = love.filesystem.read("vm/worker_cloud_save.lua")
    if not threadCode then
        -- This is expected in test environments - will fallback to flush()
        log.debug("CloudVariableStorage: Background thread not available (will use synchronous save)")
        return false
    end

    -- Create channels for communication
    self.requestChannel = love.thread.getChannel("cloud_save_request")
    self.responseChannel = love.thread.getChannel("cloud_save_response")

    -- Create and start thread
    self.saveThread = love.thread.newThread(threadCode)
    self.saveThread:start(self.requestChannel)

    log.info("CloudVariableStorage: Background save thread started")
    return true
end

---Stop the background save worker thread
function CloudVariableStorage:stopThread()
    if not self.saveThread then
        return
    end

    -- Send quit command to worker
    if self.requestChannel then
        self.requestChannel:push({ type = "quit" })
    end

    -- Wait for thread to finish (with timeout)
    local timeout = 1.0
    local startTime = love.timer.getTime()
    while self.saveThread:isRunning() and (love.timer.getTime() - startTime) < timeout do
        love.timer.sleep(0.01)
    end

    if self.saveThread:isRunning() then
        log.warn("CloudVariableStorage: Worker thread did not exit gracefully")
    end

    self.saveThread = nil
    self.requestChannel = nil
    self.responseChannel = nil

    log.info("CloudVariableStorage: Background save thread stopped")
end

-- Async Save Operations

---Send async save request to worker thread
---@return boolean success True if request was sent
function CloudVariableStorage:_requestAsyncSave()
    if not self.projectPath then
        return false
    end

    -- Check if thread is available
    if not self.saveThread or not self.saveThread:isRunning() then
        -- Try to start thread (first time or after failure)
        if not self:startThread() then
            -- Thread not available (e.g., test environment)
            -- Fallback to synchronous save
            log.debug("CloudVariableStorage: Using synchronous save (thread unavailable)")
            self.pendingSave = false
            return self:save()
        end
    end

    local filePath = self.projectPath .. "/" .. CloudVariableStorage.STORAGE_FILE

    -- Send save request to worker thread
    self.requestChannel:push({
        type = "save",
        filePath = filePath,
        cloudData = self.cloudData -- Thread will serialize this
    })

    self.pendingSave = false
    self.lastSaveTime = love.timer.getTime()

    log.debug("CloudVariableStorage: Async save request sent (%d variable(s))",
              self:_countKeys(self.cloudData))

    return true
end

---Update async save state and process responses (call from love.update)
---@param dt number Delta time
function CloudVariableStorage:update(dt)
    -- Process any responses from worker thread
    if self.responseChannel then
        local response = self.responseChannel:pop()
        if response and response.type == "save_complete" then
            if response.success then
                log.debug("CloudVariableStorage: Async save completed (%d variable(s) saved to %s)",
                         response.varCount, response.filePath)
            else
                log.error("CloudVariableStorage: Async save failed: %s", tostring(response.error))
            end
        end
    end

    -- Auto-save if pending and interval elapsed
    if self.pendingSave then
        local timeSinceLastSave = love.timer.getTime() - self.lastSaveTime
        if timeSinceLastSave >= CloudVariableStorage.AUTO_SAVE_INTERVAL then
            self:_requestAsyncSave()
        end
    end
end

---Flush all pending saves synchronously (use on quit/project close)
---@return boolean success True if saved successfully
function CloudVariableStorage:flush()
    if not self.projectPath then
        return false
    end

    -- Stop async thread if running
    self:stopThread()

    -- Perform synchronous save
    local success = self:save()

    if success then
        log.info("CloudVariableStorage: Flushed %d cloud variable(s) synchronously",
                self:_countKeys(self.cloudData))
    end

    return success
end

return CloudVariableStorage
