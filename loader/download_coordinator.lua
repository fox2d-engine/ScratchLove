-- Multi-threaded Download Coordinator
-- Manages concurrent asset downloading using a thread pool for improved performance

---@class DownloadTask
---@field md5ext string Asset MD5 with extension
---@field name string Display name for the asset
---@field url string Download URL

---@class DownloadResult
---@field success boolean Whether download succeeded
---@field md5ext string Asset MD5 with extension
---@field error string|nil Error message if failed

---@class DownloadCoordinator
---@field maxConcurrentDownloads number Maximum number of concurrent download threads
---@field workerThreads love.Thread[] Pool of worker threads
---@field taskChannels love.Channel[] Input channels for each worker thread
---@field resultChannels love.Channel[] Output channels for each worker thread
---@field taskQueue DownloadTask[] Queue of pending download tasks
---@field totalTasks number Total number of tasks to process
---@field completedTasks number Number of completed tasks
---@field successTasks number Number of successfully completed tasks
---@field failedTasks number Number of failed tasks
---@field isRunning boolean Whether coordinator is currently running
---@field onProgress function|nil Progress callback function(completed, total, success, failed)
---@field projectPath string Project directory path for saving files
local DownloadCoordinator = {}
DownloadCoordinator.__index = DownloadCoordinator

---Create new download coordinator
---@param maxConcurrentDownloads number|nil Maximum concurrent downloads (default: 6)
---@return DownloadCoordinator
function DownloadCoordinator:new(maxConcurrentDownloads)
    local self = setmetatable({}, DownloadCoordinator)

    self.maxConcurrentDownloads = maxConcurrentDownloads or 6 -- Good balance for HTTP connections
    self.workerThreads = {}
    self.taskChannels = {}
    self.resultChannels = {}
    self.taskQueue = {}
    self.totalTasks = 0
    self.completedTasks = 0
    self.successTasks = 0
    self.failedTasks = 0
    self.isRunning = false
    self.onProgress = nil
    self.projectPath = ""

    return self
end

---Initialize worker thread pool
---@param projectPath string Project directory path
function DownloadCoordinator:initializeWorkers(projectPath)
    self.projectPath = projectPath

    for i = 1, self.maxConcurrentDownloads do
        -- Create communication channels
        local taskChannel = love.thread.newChannel()
        local resultChannel = love.thread.newChannel()

        -- Create and start worker thread
        local workerThread = love.thread.newThread("loader/download_worker.lua")
        workerThread:start(taskChannel, resultChannel, projectPath)

        table.insert(self.workerThreads, workerThread)
        table.insert(self.taskChannels, taskChannel)
        table.insert(self.resultChannels, resultChannel)
    end
end

---Start concurrent download of all tasks
---@param tasks DownloadTask[] List of download tasks
---@param onProgress function|nil Progress callback function(completed, total, success, failed)
function DownloadCoordinator:startDownload(tasks, onProgress)
    if self.isRunning then
        error("Download coordinator is already running")
    end

    self.isRunning = true
    self.onProgress = onProgress
    self.taskQueue = tasks
    self.totalTasks = #tasks
    self.completedTasks = 0
    self.successTasks = 0
    self.failedTasks = 0

    -- Initialize workers if not already done
    if #self.workerThreads == 0 then
        error("Workers not initialized. Call initializeWorkers() first.")
    end

    -- Distribute initial tasks to workers
    self:distributeInitialTasks()
end

---Distribute initial tasks to all available workers
function DownloadCoordinator:distributeInitialTasks()
    local tasksAssigned = 0

    for i = 1, math.min(self.maxConcurrentDownloads, #self.taskQueue) do
        if #self.taskQueue > tasksAssigned then
            local task = table.remove(self.taskQueue, 1)
            self.taskChannels[i]:push(task)
            tasksAssigned = tasksAssigned + 1
        end
    end
end

---Update download progress (call from main thread regularly)
---@return boolean isComplete Whether all downloads are complete
function DownloadCoordinator:update()
    if not self.isRunning then
        return true
    end

    local hasActivity = false

    -- Check results from all worker threads
    for i = 1, #self.resultChannels do
        local result = self.resultChannels[i]:pop()
        if result then
            hasActivity = true
            self:processResult(result, i)
        end
    end

    -- Check if all downloads are complete
    if self.completedTasks >= self.totalTasks then
        self:shutdown()
        return true
    end

    return false
end

---Process download result from worker thread
---@param result DownloadResult Download result
---@param workerIndex number Index of worker thread that produced result
function DownloadCoordinator:processResult(result, workerIndex)
    self.completedTasks = self.completedTasks + 1

    if result.success then
        self.successTasks = self.successTasks + 1
    else
        self.failedTasks = self.failedTasks + 1
        print("Download failed for " .. result.md5ext .. ": " .. (result.error or "Unknown error"))
    end

    -- Assign next task to this worker if available
    if #self.taskQueue > 0 then
        local nextTask = table.remove(self.taskQueue, 1)
        self.taskChannels[workerIndex]:push(nextTask)
    else
        -- No more tasks, send stop signal to worker
        self.taskChannels[workerIndex]:push({ type = "stop" })
    end

    -- Call progress callback
    if self.onProgress then
        self.onProgress(self.completedTasks, self.totalTasks, self.successTasks, self.failedTasks)
    end
end

---Shutdown all worker threads and clean up resources
function DownloadCoordinator:shutdown()
    self.isRunning = false

    -- Send stop signals to all remaining workers
    for i = 1, #self.taskChannels do
        self.taskChannels[i]:push({ type = "stop" })
    end

    -- Wait for threads to finish (with timeout)
    local socket = require("socket")
    local startTime = socket.gettime()
    for _, thread in ipairs(self.workerThreads) do
        while thread:isRunning() and (socket.gettime() - startTime) < 2.0 do
            socket.sleep(0.01)
        end
    end

    -- Clear thread pool
    self.workerThreads = {}
    self.taskChannels = {}
    self.resultChannels = {}
end

---Get current download statistics
---@return number completed Number of completed downloads
---@return number total Total number of downloads
---@return number success Number of successful downloads
---@return number failed Number of failed downloads
function DownloadCoordinator:getStats()
    return self.completedTasks, self.totalTasks, self.successTasks, self.failedTasks
end

---Force stop all downloads and clean up
function DownloadCoordinator:stop()
    if self.isRunning then
        self:shutdown()
    end
end

return DownloadCoordinator