-- Loading Screen UI for Project and Asset Loading
-- Displays progress during multi-threaded project loading

local Global = require("global")
local Runtime = require("vm.runtime")
local Renderer = require("renderer.renderer")
local ProjectLoader = require("loader.project_loader")
local ResourceLoader = require("loader.resource_loader")
local log = require("lib.log")

---@class LoadingScreen
---@field isVisible boolean Whether loading screen is currently shown
---@field currentTask string Current task being performed
---@field progress number Progress percentage (0-1)
---@field subProgress number Sub-task progress (0-1)
---@field totalAssets number Total number of assets to download
---@field completedAssets number Number of assets completed
---@field errorCount number Number of failed downloads
---@field startTime number Time when loading started
---@field projectLoader ProjectLoader Multi-threaded project loader
---@field resourceLoader ResourceLoader Main thread resource loader
---@field onLoadComplete function|nil Callback when loading is complete
---@field onLoadError function|nil Callback when loading fails
---@field currentStage string Current loading stage
---@field isProcessingResources boolean Whether currently processing resources on main thread
---@field loadedProject ProjectModel|nil Project waiting for ADPCM conversions to complete
---@field titleFont love.Font Font for title text
---@field taskFont love.Font Font for task text
---@field percentFont love.Font Font for percentage text
---@field infoFont love.Font Font for info text
---@field timeFont love.Font Font for time text
local LoadingScreen = {}
LoadingScreen.__index = LoadingScreen

---Create new loading screen
---@return LoadingScreen
function LoadingScreen:new()
    local self = setmetatable({}, LoadingScreen)
    self.isVisible = false
    self.currentTask = ""
    self.progress = 0
    self.subProgress = 0
    self.totalAssets = 0
    self.completedAssets = 0
    self.errorCount = 0
    self.startTime = 0
    self.projectLoader = ProjectLoader:new()
    self.resourceLoader = ResourceLoader:new()
    self.onLoadComplete = nil
    self.onLoadError = nil
    self.currentStage = ""
    self.isProcessingResources = false
    self.loadedProject = nil

    -- Create and cache fonts for crisp rendering
    self.titleFont = love.graphics.newFont(22)
    self.taskFont = love.graphics.newFont(14)
    self.percentFont = love.graphics.newFont(14)
    self.infoFont = love.graphics.newFont(13)
    self.timeFont = love.graphics.newFont(12)

    return self
end

---Show loading screen and start loading process
---@param taskName string Name of the loading task
function LoadingScreen:show(taskName)
    self.isVisible = true
    self.currentTask = taskName or "Loading..."
    self.progress = 0
    self.subProgress = 0
    self.totalAssets = 0
    self.completedAssets = 0
    self.errorCount = 0
    self.startTime = love.timer.getTime()
    log.info("Loading started: " .. self.currentTask)
end

---Hide loading screen
function LoadingScreen:hide()
    if self.isVisible then
        local elapsed = love.timer.getTime() - self.startTime

        -- Ensure minimum display time of 3 second for better UX
        local minDisplayTime = 2.5
        if elapsed < minDisplayTime then
            local sleepTime = minDisplayTime - elapsed
            log.info("Loading completed quickly, waiting %.2fs to meet minimum display time", sleepTime)
            love.timer.sleep(sleepTime)
            elapsed = minDisplayTime
        end

        log.info("Loading completed in %.2f seconds", elapsed)
        self.isVisible = false
    end
end

---Update current task being performed
---@param taskName string Name of the current task
---@param progress? number Overall progress (0-1)
function LoadingScreen:setTask(taskName, progress)
    self.currentTask = taskName
    if progress then
        self.progress = progress
    end
    self.subProgress = 0
    log.info("Loading: " .. taskName)
end

---Set sub-task progress
---@param progress number Progress (0-1)
function LoadingScreen:setSubProgress(progress)
    self.subProgress = progress
end

---Set asset loading information
---@param total number Total number of assets
---@param completed? number Number of completed assets
---@param errors? number Number of failed assets
function LoadingScreen:setAssetProgress(total, completed, errors)
    self.totalAssets = total
    self.completedAssets = completed or self.completedAssets
    self.errorCount = errors or self.errorCount

    if total > 0 then
        self.progress = self.completedAssets / total
    end
end

---Increment completed asset count
---@param wasError? boolean Whether this completion was due to an error
function LoadingScreen:incrementAsset(wasError)
    self.completedAssets = self.completedAssets + 1
    if wasError then
        self.errorCount = self.errorCount + 1
    end

    if self.totalAssets > 0 then
        self.progress = self.completedAssets / self.totalAssets
    end
end

---Draw the loading screen
function LoadingScreen:draw()
    if not self.isVisible then
        return
    end

    -- Calculate dimensions
    local screenWidth = Global.STAGE_WIDTH
    local screenHeight = Global.STAGE_HEIGHT
    local centerX = screenWidth / 2
    local centerY = screenHeight / 2
    local elapsed = love.timer.getTime() - self.startTime

    -- Modern medium blue gradient background (balanced contrast)
    for y = 0, screenHeight do
        local ratio = y / screenHeight
        -- Gradient from medium blue to deep blue (not too dark)
        local r = 0.25 - (ratio * 0.10) -- Slightly warmer
        local g = 0.35 - (ratio * 0.15) -- Medium tone
        local b = 0.50 - (ratio * 0.20) -- Medium blue dominant
        love.graphics.setColor(r, g, b, 1.0)
        love.graphics.rectangle("fill", 0, y, screenWidth, 1)
    end

    -- Decorative floating dots (Scratch-style)
    love.graphics.setColor(1, 1, 1, 0.15)
    for i = 1, 8 do
        local angle = (elapsed * 0.3 + i * 45) * math.pi / 180
        local radius = 150 + math.sin(elapsed * 0.5 + i) * 30
        local x = centerX + math.cos(angle) * radius
        local y = centerY + math.sin(angle) * radius
        local dotRadius = 8 + math.sin(elapsed * 2 + i) * 2
        love.graphics.circle("fill", x, y, dotRadius, 32) -- 32 segments for smooth circles
    end

    -- Main loading card
    local cardWidth = 420
    local cardHeight = 240
    local cardX = centerX - cardWidth / 2
    local cardY = centerY - cardHeight / 2
    local cornerRadius = 20

    -- Card shadow (softer)
    love.graphics.setColor(0, 0, 0, 0.2)
    love.graphics.rectangle("fill", cardX + 4, cardY + 4, cardWidth, cardHeight, cornerRadius, cornerRadius)

    -- Card background (soft light gray instead of pure white)
    love.graphics.setColor(0.95, 0.96, 0.97, 0.95)
    love.graphics.rectangle("fill", cardX, cardY, cardWidth, cardHeight, cornerRadius, cornerRadius)

    -- Fox spinning indicator (simulated with colored circles)
    local catSize = 50
    local catX = cardX + 40
    local catY = cardY + 40

    -- Outer spinning ring (deep orange - fox accent color)
    love.graphics.setColor(1, 0.5, 0.1, 0.8)
    love.graphics.setLineWidth(4)
    love.graphics.push()
    love.graphics.translate(catX, catY)
    love.graphics.rotate(elapsed * 2)
    love.graphics.arc("line", "open", 0, 0, catSize / 2, 0, math.pi * 1.5, 64) -- 64 segments for smooth arc
    love.graphics.pop()

    -- Inner spinning ring (blue - complementary color for contrast)
    love.graphics.setColor(0.3, 0.5, 0.9, 0.9)
    love.graphics.setLineWidth(3)
    love.graphics.push()
    love.graphics.translate(catX, catY)
    love.graphics.rotate(-elapsed * 3)
    love.graphics.arc("line", "open", 0, 0, catSize / 3, math.pi, math.pi * 2.5, 64) -- 64 segments for smooth arc
    love.graphics.pop()

    -- Center dot (dark orange)
    love.graphics.setColor(0.9, 0.4, 0.1, 1)
    love.graphics.circle("fill", catX, catY, 6, 32) -- 32 segments for smooth circle

    -- Title with Scratch colors
    love.graphics.setFont(self.titleFont)
    local titleText = "Loading Scratch Project"
    local titleX = catX + catSize + 15
    local titleY = cardY + 25

    -- Title shadow
    love.graphics.setColor(0, 0, 0, 0.15)
    love.graphics.print(titleText, titleX + 2, titleY + 2)
    -- Title text (Scratch purple)
    love.graphics.setColor(0.42, 0.37, 0.71, 1)
    love.graphics.print(titleText, titleX, titleY)

    -- Current task text
    love.graphics.setFont(self.taskFont)
    local taskY = cardY + 80
    local taskText = self.currentTask
    love.graphics.setColor(0.3, 0.3, 0.3, 1)
    love.graphics.print(taskText, cardX + 30, taskY)

    -- Progress bar container
    local barWidth = cardWidth - 60
    local barHeight = 28
    local barX = cardX + 30
    local barY = taskY + 35

    -- Progress bar background (light gray with rounded corners)
    love.graphics.setColor(0.9, 0.9, 0.92, 1)
    love.graphics.rectangle("fill", barX, barY, barWidth, barHeight, 14, 14)

    -- Progress bar fill with gradient (Scratch green to blue)
    if self.progress > 0 then
        local fillWidth = math.max(2, barWidth * self.progress)

        -- Draw gradient using stencil for rounded corners
        love.graphics.stencil(function()
            love.graphics.rectangle("fill", barX, barY, fillWidth, barHeight, 14, 14)
        end, "replace", 1)
        love.graphics.setStencilTest("greater", 0)

        -- Draw smooth gradient
        for i = 0, fillWidth do
            local ratio = i / barWidth
            -- Gradient from green (0.2, 0.73, 0.5) to blue (0.26, 0.67, 0.96)
            local r = 0.2 + ratio * 0.06
            local g = 0.73 - ratio * 0.06
            local b = 0.5 + ratio * 0.46
            love.graphics.setColor(r, g, b, 1)
            love.graphics.rectangle("fill", barX + i, barY, 1, barHeight)
        end

        love.graphics.setStencilTest()
    end

    -- Progress bar border
    love.graphics.setColor(0.8, 0.8, 0.82, 1)
    love.graphics.setLineWidth(2)
    love.graphics.rectangle("line", barX, barY, barWidth, barHeight, 14, 14)

    -- Progress percentage (centered on bar)
    love.graphics.setFont(self.percentFont)
    local percentText = string.format("%.0f%%", self.progress * 100)
    local percentWidth = self.percentFont:getWidth(percentText)
    love.graphics.setColor(1, 1, 1, 0.95)
    love.graphics.print(percentText, barX + (barWidth - percentWidth) / 2, barY + 6)

    -- Asset information with icon-style display
    if self.totalAssets > 0 then
        local infoY = barY + 40

        -- Asset count badge
        love.graphics.setColor(0.95, 0.95, 0.97, 1)
        love.graphics.rectangle("fill", barX, infoY, 150, 30, 15, 15)

        love.graphics.setFont(self.infoFont)
        local assetText = string.format("Assets: %d/%d", self.completedAssets, self.totalAssets)
        love.graphics.setColor(0.42, 0.37, 0.71, 1)
        love.graphics.print(assetText, barX + 15, infoY + 8)

        -- Error badge (if any)
        if self.errorCount > 0 then
            local errorX = barX + 165
            love.graphics.setColor(1, 0.4, 0.4, 1)
            love.graphics.rectangle("fill", errorX, infoY, 100, 30, 15, 15)

            local errorText = string.format("Failed: %d", self.errorCount)
            love.graphics.setColor(1, 1, 1, 1)
            love.graphics.print(errorText, errorX + 15, infoY + 8)
        end
    end

    -- Brand text (bottom center)
    love.graphics.setFont(self.timeFont)
    local brandPrefix = "Running on "
    local brandDomain = "fox2d.com"
    local brandText = brandPrefix .. brandDomain
    local brandWidth = self.timeFont:getWidth(brandText)
    local brandX = cardX + (cardWidth - brandWidth) / 2 -- Center horizontally
    local brandY = cardY + cardHeight - 25

    -- "Running on " in gray
    love.graphics.setColor(0.6, 0.6, 0.6, 1)
    love.graphics.print(brandPrefix, brandX, brandY)

    -- "fox2d.com" in blue
    local prefixWidth = self.timeFont:getWidth(brandPrefix)
    love.graphics.setColor(0.3, 0.5, 0.9, 1) -- Blue color
    love.graphics.print(brandDomain, brandX + prefixWidth, brandY)

    -- Elapsed time (bottom right, subtle)
    local timeText = string.format("%.1fs", elapsed)
    love.graphics.setFont(self.timeFont)
    local timeWidth = self.timeFont:getWidth(timeText)
    love.graphics.setColor(0.6, 0.6, 0.6, 1)
    love.graphics.print(timeText, cardX + cardWidth - timeWidth - 20, cardY + cardHeight - 25)
end

---Find project input (sb3 file or project ID) from arguments or default locations
---@param arg string[] Command line arguments
---@return string|nil input Path to sb3 file, project ID, or nil if not found
function LoadingScreen:findProjectInput(arg)
    -- Check command line argument
    if arg and arg[1] then
        local input = arg[1]

        -- Check if it's a numeric project ID
        local projectId = tonumber(input)
        if projectId then
            log.info("Using Scratch project ID: " .. projectId)
            return input -- Return as string for consistency
        end

        -- Otherwise treat as file path
        log.info("Using file path: " .. input)
        return input
    end

    -- Check default locations for local files
    -- On Android: APK assets are mounted and files appear at root level
    local defaultFiles = {
        "game.sb3",        -- For Android: APK assets at root (when mounted to apk_assets/)
        "assets/game.sb3", -- For desktop: assets in game.love or working directory
    }
    for _, filepath in ipairs(defaultFiles) do
        if love.filesystem.getInfo(filepath) then
            log.info("Auto-detected: " .. filepath)
            return filepath
        else
            log.warn("Not found: " .. filepath)
        end
    end

    return nil
end

---Start loading project from file path or project ID
---@param input string Path to sb3 file or project ID
---@param onComplete function Callback when loading is complete: function(runtime, renderer, project)
---@param onError function Callback when loading fails: function(errorMessage)
function LoadingScreen:loadProject(input, onComplete, onError)
    log.info("Starting multi-threaded project load: " .. input)

    -- Store callbacks
    self.onLoadComplete = onComplete
    self.onLoadError = onError

    -- Check if this is an online project (numeric ID)
    local isOnlineProject = tonumber(input) ~= nil
    local message = isOnlineProject and ("Loading Scratch Project #" .. input) or ("Loading " .. input)
    self:show(message)

    -- Start worker thread for I/O operations
    self.projectLoader:loadProject(
        input,
        function(stage, progress, message) -- onProgress
            self:handleWorkerProgress(stage, progress, message)
        end,
        function(projectPath) -- onComplete
            self:handleWorkerComplete(projectPath)
        end,
        function(errorMessage) -- onError
            self:handleWorkerError(errorMessage)
        end
    )
end

---Update loading process (should be called from love.update)
---@return boolean isActive Whether loading is still active
function LoadingScreen:update()
    -- Update project loader (handles worker thread communication)
    local isProjectLoading = self.projectLoader:update()

    -- Check for completed ADPCM conversions
    if self.resourceLoader then
        local hasCompletions = self.resourceLoader:checkAdpcmConversions()

        -- Check if we have a loaded project waiting for ADPCM conversions
        if self.loadedProject then
            local hasPending, count = self.resourceLoader:hasPendingAdpcm()

            if hasPending then
                -- Still waiting for conversions
                if hasCompletions then
                    local message = string.format("Converting audio formats... (%d remaining)", count)
                    self:setTask(message, 0.95 + (0.05 * (1 - count / 10))) -- Progress from 95% to 100%
                    log.debug("Waiting for " .. count .. " ADPCM conversions to complete")
                end
            else
                -- All conversions done, create runtime
                log.info("All ADPCM conversions completed, creating runtime...")
                local project = self.loadedProject
                self.loadedProject = nil
                self:createRuntimeAndComplete(project)
            end
        end
    end

    -- If not loading and not visible, nothing to do
    if not isProjectLoading and not self.isVisible and not self.loadedProject then
        return false
    end

    return isProjectLoading or self.isProcessingResources or (self.loadedProject ~= nil)
end

---Handle progress from worker thread
---@param stage string Current loading stage
---@param progress number Progress (0-1)
---@param message string Status message
function LoadingScreen:handleWorkerProgress(stage, progress, message)
    self.currentStage = stage
    self:setTask(message, progress * 0.7) -- Worker takes 70% of total progress
end

---Handle worker thread completion
---@param projectPath string Path to extracted project directory
function LoadingScreen:handleWorkerComplete(projectPath)
    log.info("Worker thread completed, starting main thread resource loading...")
    self.isProcessingResources = true
    self:setTask("Loading resources...", 0.7)

    -- Load resources on main thread
    local project, error = self.resourceLoader:loadProject(
        projectPath,
        function(stage, progress, message)                -- onProgress
            local totalProgress = 0.7 + (progress * 0.25) -- Resources take 25% of total
            self:setTask(message, totalProgress)
        end
    )

    if project then
        -- Store project but don't create runtime yet
        self.loadedProject = project
        self:setTask("Converting audio formats...", 0.95)
        -- Will continue in update() when ADPCM conversions are done
    else
        self:handleWorkerError(error or "Failed to load resources")
    end
end

---Handle worker thread error
---@param errorMessage string Error message
function LoadingScreen:handleWorkerError(errorMessage)
    log.error("Worker thread error: " .. errorMessage)

    self.isProcessingResources = false
    self:hide()

    -- Simply throw error - love.errorhandler will catch it
    error(errorMessage)
end

---Create runtime and complete loading process
---@param project ProjectModel Loaded project model
function LoadingScreen:createRuntimeAndComplete(project)
    self:setTask("Creating runtime...", 0.85)

    local options = project.projectOptions
    if options and type(options.width) == "number" and type(options.height) == "number" and
        options.width > 0 and options.height > 0 then
        -- update stage size before creating runtime
        Global.setStageSize(options.width, options.height)
        if love.system.mobile and love.system.mobile.setOrientation then
            love.system.mobile.setOrientation(options.width >= options.height and "landscape" or "portrait")
        end
    end

    local runtime = Runtime:new(project)

    -- Let errors propagate naturally - love.errorhandler will catch them
    runtime:initialize()

    self:setTask("Setting up renderer...", 0.92)
    local renderer = Renderer:new(runtime)
    runtime:setRenderer(renderer)

    self:setTask("Starting project...", 0.96)
    runtime:start()

    self:setTask("Complete!", 1.0)
    self:hide()
    self.isProcessingResources = false

    log.info("Multi-threaded project loading completed successfully!")

    if self.onLoadComplete then
        self.onLoadComplete(runtime, renderer, project)
    end
end

return LoadingScreen
