-- Runtime VM
-- Executes Scratch blocks in Love2D
local Global                = require("global")
local Thread                = require("vm.thread")
local SpriteTemplate        = require("vm.sprite_template")
local Stage                 = require("vm.stage")
local Sequencer             = require("vm.sequencer")
local log                   = require("lib.log")
local PenRenderer           = require("pen.pen_renderer")
local MonitorManager        = require("monitors.monitor_manager")
local AudioManager          = require("audio.audio_engine")
local VirtualGamepadManager = require("vm.virtual_gamepad_manager")
local CloudVariableStorage  = require("vm.cloud_variable_storage")
require("table.clear")

---@class AskState
---@field active boolean Whether an ask prompt is currently active
---@field question string The question being asked
---@field answer string The user's answer
---@field answered boolean Whether the user has answered

---@class Runtime
---@field project ProjectModel The project being executed
---@field stage Stage|nil The stage object
---@field spriteTemplates SpriteTemplate[] List of sprite templates (shared data)
---@field targets Sprite[] List of all targets (original sprites + clones)
---@field threads Thread[] List of active threads
---@field globalVariables table<string, Variable> Global variables from stage
---@field broadcasts table<string, string> Broadcast messages
---@field cloneCounter integer Total clone count
---@field sequencer Sequencer Thread scheduling system
---@field renderer Renderer|nil Renderer for drawing operations
---@field penRenderer PenRenderer Pen rendering system
---@field monitorManager MonitorManager|nil Monitor data logging system
---@field audioEngine AudioManager Audio system for sound playback and effects
---@field cloudStorage CloudVariableStorage Cloud variable storage manager
---@field runtimeOptions TurboWarpRuntimeOptions Runtime configuration options
---@field mouseX number Current mouse X position
---@field mouseY number Current mouse Y position
---@field mouseDown boolean Whether mouse is pressed
---@field dragTarget Sprite|nil Currently dragged sprite (for draggable sprites)
---@field wasDragged boolean Whether dragging occurred during mouse press
---@field dragStartX number Mouse X position when drag started (Scratch coordinates)
---@field dragStartY number Mouse Y position when drag started (Scratch coordinates)
---@field keysPressed table<string, boolean> Currently pressed keys
---@field pendingKeyReleases string[] Keys scheduled for release after dispatch
---@field joysticks love.Joystick[] List of connected joysticks
---@field gamepadManager VirtualGamepadManager Virtual gamepad and active key manager
---@field startTime number Runtime start timestamp
---@field frameCount integer Total frame count
---@field performance table Performance monitoring data
---@field threadMap table<string, Thread> Map of thread IDs to thread objects
---@field hatsConcurrency integer Maximum concurrent threads for non-event hats
---@field hatRunFrameMap table<string, integer> Tracks frame numbers when hats ran
---@field edgeActivatedValues table<string, table<string, {value:boolean, hasOldValue:boolean}>> Edge hat states
---@field redrawRequested boolean Whether a redraw has been requested this frame
---@field stuckCounter integer Counter for stuck detection (increments every isStuck call)
---@field tickStartTime number Start time of current tick for stuck detection
---@field compilerOptions table Compiler configuration options
---@field askState AskState|nil Ask and answer state for sensing blocks
---@field compilerCache table<string, table<string, CompileResult>> Cache of compiled scripts per block container
---@field interpolationEnabled boolean Master interpolation toggle
---@field _lastStepTime number Timestamp when last logic frame ended (milliseconds)
---@field currentStepTime number Duration of one logic frame (milliseconds)
---@field _deltaAccumulator number Accumulated time for fixed logic timestep (seconds)
local Runtime        = {}
Runtime.__index      = Runtime

-- Scratch clone limit
Runtime.MAX_CLONES   = 300

-- Hat block metadata - defines restart behavior
Runtime.HAT_METADATA = {
    -- These hat blocks restart existing threads
    event_whenflagclicked = { restartExistingThreads = true },
    event_whenthisspriteclicked = { restartExistingThreads = true },
    event_whenstageclicked = { restartExistingThreads = true },
    event_whenbackdropswitchesto = { restartExistingThreads = true },
    event_whenbroadcastreceived = { restartExistingThreads = true },
    event_whenkeypressed = { restartExistingThreads = false }, -- Block key press threads

    -- These hat blocks block new threads if existing ones are running
    event_whentouchingobject = { restartExistingThreads = false, edgeActivated = true },
    event_whengreaterthan = { restartExistingThreads = false, edgeActivated = true },

    -- Control hat blocks
    control_start_as_clone = { restartExistingThreads = true },
}

---Create a new runtime instance
---@param project ProjectModel The project to execute
---@return Runtime
function Runtime:new(project)
    local self = setmetatable({}, Runtime)

    self.project = project
    self.stage = nil

    -- New Scratch-style architecture
    self.spriteTemplates = {} -- Sprite templates (shared data)
    self.targets = {}         -- All targets (original sprites + clones)


    self.threads = {}
    self.globalVariables = {}
    self.broadcasts = {}
    self.cloneCounter = 0 -- Track total clone count
    self.sequencer = Sequencer:new(self)
    self.renderer = nil   -- Will be set by main.lua

    -- Initialize pen rendering system
    self.penRenderer = PenRenderer:new()

    -- Initialize monitor system
    self.monitorManager = MonitorManager:new()

    -- Initialize audio manager
    self.audioEngine = AudioManager:new()

    -- Initialize cloud variable storage
    self.cloudStorage = CloudVariableStorage:new(self.project.projectPath)

    self.runtimeOptions = {
        maxClones = Runtime.MAX_CLONES,  -- Maximum clones allowed (300 default, can be Infinity)
        miscLimits = true,               -- Enable miscellaneous limits (sound effects, etc.)
        fencing = Global.FENCING_ENABLED -- Keep sprites within stage bounds (native Scratch behavior)
    }

    -- Mouse state
    self.mouseX = 0
    self.mouseY = 0
    self.mouseDown = false

    self.dragTarget = nil   -- Currently dragged sprite
    self.wasDragged = false -- Whether dragging occurred
    self.dragStartX = 0     -- Mouse position when drag started (Scratch coordinates)
    self.dragStartY = 0

    -- Keyboard state
    self.keysPressed = {}
    self.pendingKeyReleases = {}

    -- Joystick state
    self.joysticks = {}

    -- Virtual gamepad and active key management
    self.gamepadManager = VirtualGamepadManager:new(self)

    -- Timing
    self.startTime = love.timer.getTime()
    self.frameCount = 0

    -- Thread management
    self.threadMap = {}      -- Maps thread IDs to thread objects
    self.hatsConcurrency = 1 -- Default concurrency limit for non-event hats
    -- Track hat executions per frame to block same-frame re-triggers for non-restarting hats
    self.hatRunFrameMap = {}

    -- Edge-activated hat blocks state tracking
    -- Format: edgeActivatedValues[targetId][blockId] = { value = boolean, hasOldValue = boolean }
    self.edgeActivatedValues = {}

    self.redrawRequested = false

    self.stuckCounter = 0
    self.tickStartTime = 0

    self.compilerOptions = {
        warpTimer = false -- Enable warp timer mode for stuck detection in warp loops
    }

    -- Performance monitoring
    self.performance = {
        frameTime = 0,
        threadTime = 0,
        activeThreads = 0,
        averageFrameTime = 0,
        averageThreadTime = 0,
        performanceHistory = {}
    }

    -- Compiler cache for compiled scripts (per block container)
    self.compilerCache = {}

    -- Interpolation state (frame smoothing)
    self.interpolationEnabled = Global.INTERPOLATION_ENABLED -- Master toggle for interpolation (from global config)
    self._lastStepTime = love.timer.getTime() * 1000         -- Timestamp when last logic frame ended (ms)
    self.currentStepTime = 1000 / Global.TARGET_FPS          -- Duration of one logic frame (ms)

    -- Logic frame rate control (time accumulation)
    self._deltaAccumulator = 0 -- Accumulated time for fixed logic timestep

    return self
end

---Set the renderer instance
---@param renderer table The renderer instance
function Runtime:setRenderer(renderer)
    self.renderer = renderer

    -- Add all existing targets to renderer (they were created before renderer was available)
    if renderer then
        for _, target in ipairs(self.targets) do
            renderer:addSprite(target)
        end
    end
end

---Update runtime options
---Set runtime options
---@param options TurboWarpRuntimeOptions New runtime options (partial update, merged with existing)
function Runtime:setRuntimeOptions(options)
    -- Merge new options with existing options
    for key, value in pairs(options) do
        -- Handle Infinity value from JSON (comes as string "Infinity", very large number, or math.huge)
        if key == "maxClones" then
            if value == "Infinity" or value == math.huge or (type(value) == "number" and value >= 999999999) then
                self.runtimeOptions[key] = math.huge
                log.info("Runtime: Set maxClones to Infinity (unlimited clones)")
            else
                self.runtimeOptions[key] = value
            end
        else
            self.runtimeOptions[key] = value
        end
    end

    -- Log runtime options changes
    if options.maxClones and options.maxClones ~= math.huge and options.maxClones ~= "Infinity" then
        log.info("Runtime: Set maxClones to %d", options.maxClones)
    end
    if options.miscLimits ~= nil then
        log.info("Runtime: miscLimits %s", options.miscLimits and "enabled" or "disabled")
    end
    if options.fencing ~= nil then
        log.info("Runtime: Fencing %s", options.fencing and "enabled" or "disabled")
    end

    -- Note: We don't have renderer.offscreenTouching optimization
    -- Fencing is handled directly in Sprite:setXY
end

---Initialize the runtime by creating sprites and stage
function Runtime:initialize()
    -- Apply project options (framerate, width, height, interpolation) before creating targets
    local options = self.project.projectOptions
    if options then
        if type(options.framerate) == "number" and options.framerate > 0 then
            Global.setFramerate(options.framerate)
        end

        if options.interpolation then
            self:setInterpolation(true)
        end

        -- Apply runtime options (fencing, etc.)
        if options.runtimeOptions then
            self:setRuntimeOptions(options.runtimeOptions)
        end
    end

    -- Create stage
    local stageData = self.project:getStage()
    if stageData then
        self.stage = Stage:new(stageData, self)
        self.stage:initialize()
        -- Set stage variables as global variables
        self.globalVariables = self.stage.variables

        -- Add stage to targets array (matching native Scratch behavior)
        -- Stage should be the first target (index 1)
        table.insert(self.targets, self.stage)

        -- Create audio bank for stage
        self:_initializeAudioForTarget(self.stage, "Stage")
    end

    -- Create sprite templates and original sprites
    -- layerOrder is ONLY for rendering/drawing order (Z-index), NOT execution order
    -- Execution order must preserve project file order (targets array order)
    --            (Sprite execution order is independent of layer/Z-index)
    local spritesData = self.project:getSprites()

    for _, spriteData in ipairs(spritesData) do
        -- Create sprite template (shared data)
        local spriteTemplate = SpriteTemplate:new(spriteData, self)
        table.insert(self.spriteTemplates, spriteTemplate)

        -- Create original sprite from template
        local originalSprite = spriteTemplate:createClone()

        originalSprite.layerOrder = spriteData.layerOrder

        -- Copy runtime state from project data
        originalSprite.currentCostume = spriteData.currentCostume or 0
        originalSprite.visible = spriteData.visible ~= false
        originalSprite.x = spriteData.x or 0
        originalSprite.y = spriteData.y or 0
        originalSprite.size = spriteData.size or 100
        originalSprite.direction = spriteData.direction or 90
        originalSprite.draggable = spriteData.draggable or false
        originalSprite.rotationStyle = spriteData.rotationStyle or "all around"
        originalSprite.volume = spriteData.volume or 100
        originalSprite.soundEffects = spriteData.soundEffects or { pitch = 0, pan = 0 }

        -- Copy variables from project data
        for id, varData in pairs(spriteData.variables or {}) do
            local Variable = require("vm.variable")
            local variable = Variable:new(id, varData.name, Variable.SCALAR_TYPE, varData.cloud or false)
            variable.value = varData.value
            originalSprite.variables[id] = variable
        end

        -- Copy lists from project data
        for id, listData in pairs(spriteData.lists or {}) do
            local Variable = require("vm.variable")
            local list = Variable:new(id, listData.name, Variable.LIST_TYPE, false)
            list.value = listData.value or {}
            originalSprite.variables[id] = list
        end

        -- Mark as original sprite (not a clone)
        originalSprite.isClone = false

        originalSprite:initialize()
        self:addTarget(originalSprite)


        -- Create audio bank for sprite and load sounds
        self:_initializeAudioForTarget(originalSprite, originalSprite.name)
    end

    -- Set runtime reference in monitor manager (needed for monitor evaluation)
    if self.monitorManager then
        self.monitorManager.runtime = self
    end

    -- Deserialize monitors from project data (creates monitors and initializes values)
    self:_autoCreateMonitors()

    -- Initialize joystick support
    self:_initializeJoysticks()

    -- Initialize virtual gamepad manager (collects active keys and sets up button mapping)
    self.gamepadManager:initialize()

    -- Load cloud variables from storage and apply to runtime variables
    if self.cloudStorage then
        self.cloudStorage:load()
        self.cloudStorage:applyToRuntime(self)
        -- Start async save thread for non-blocking cloud variable persistence
        self.cloudStorage:startThread()
    end

    -- Precompile all top-level scripts into a single aggregated bundle
    self:compileAllScripts()
end

---Start the runtime by broadcasting green flag
function Runtime:start()
    -- Start green flag scripts
    self:broadcastGreenFlag()
end

---Compile all project scripts eagerly into a single aggregated bundle
---@param options table|nil Optional configuration
---@field options.writeToProject boolean|nil When false, skips writing compiled Lua to project directory (auto-disabled on Android)
---@field options.useClosure boolean|nil When false, uses legacy compilation mode (default: true for closure mode)
---@return string compiledSource The generated aggregated Lua source
function Runtime:compileAllScripts(options)
    options = options or {}
    local ProjectCompiler = require("compiler.project_compiler")
    local useClosure = options.useClosure ~= false -- Default to closure mode

    local compiledSource = nil
    if useClosure then
        compiledSource = ProjectCompiler.compileRuntimeWithClosure(self)
    else
        compiledSource = ProjectCompiler.compileRuntime(self)
    end

    -- Check if we should write compiled source to disk
    -- Automatically skip on Android to avoid filesystem issues
    local shouldWrite = options.writeToProject ~= false
    if shouldWrite and love.system.getOS() == "Android" then
        shouldWrite = false
        log.debug("Runtime: Skipping compiled project write on Android")
    end

    if shouldWrite then
        local projectPath = self.project and self.project.projectPath
        if projectPath and love and love.filesystem and love.filesystem.write then
            local targetPath = projectPath .. "/project.lua"
            local ok, writeErr = love.filesystem.write(targetPath, compiledSource)
            if not ok then
                log.error("Runtime: Failed to write compiled project to " .. targetPath .. ": " .. tostring(writeErr))
            else
                local mode = useClosure and "closure" or "legacy"
                log.info("Runtime: Compiled project (" .. mode .. " mode) written to " .. targetPath)
            end
        else
            log.debug("Runtime: Skipping compiled project write (projectPath or filesystem unavailable)")
        end
    end

    return compiledSource
end

---Update the runtime for one frame
---@param dt number Delta time in seconds
function Runtime:update(dt)
    -- Logic runs at TARGET_FPS, rendering runs separately at screen refresh rate
    self._deltaAccumulator = self._deltaAccumulator + dt

    -- Reset stuck detection counter at the start of each update (even if no logic frame executes)
    -- This ensures tests that check stuckCounter behavior work correctly
    self:resetStuckCounter()

    -- Execute logic frames at fixed rate (TARGET_FPS)
    -- IMPORTANT: Only execute ONE logic frame per update to prevent spiral of death
    -- When a single logic frame takes longer than the target frame time (e.g., 200 threads @ 60ms > 33ms target),
    -- executing multiple catch-up frames causes exponential slowdown (5 frames × 60ms = 300ms).
    local logicFrameTime = Global.FRAME_TIME
    if self._deltaAccumulator >= logicFrameTime then
        -- Execute exactly ONE logic frame
        self:_executeLogicFrame(logicFrameTime)

        -- Consume time
        self._deltaAccumulator = self._deltaAccumulator - logicFrameTime

        -- If still behind after one frame, reset to prevent spiral of death
        -- This happens when logic processing (e.g., 60ms for 200 threads) exceeds target frame time (33ms)
        if self._deltaAccumulator >= logicFrameTime then
            log.debug("Runtime: Single logic frame took longer than target, resetting accumulator")
            self._deltaAccumulator = 0
        end
    end

    -- Audio and visual updates run every render frame (not tied to logic rate)
    -- Update audio engine
    if self.audioEngine then
        self.audioEngine:update(dt)
    end

    -- Update monitor system (visual updates)
    if self.monitorManager then
        self.monitorManager:update(dt)
    end

    -- Update cloud variable storage (I/O operations)
    if self.cloudStorage then
        self.cloudStorage:update(dt)
    end

    -- Global texture cleanup timer (only for hidden sprites as fallback)
    if Global.ENABLE_TEXTURE_CLEANUP then
        self._cleanupTimer = (self._cleanupTimer or 0) + dt
        if self._cleanupTimer >= Global.COSTUME_EXPIRE_SECONDS then
            self._cleanupTimer = 0
            self:cleanupHiddenSpritesTextures()
        end
    end
end

---Execute one logic frame at fixed timestep
---@param dt number Logic frame delta time
function Runtime:_executeLogicFrame(dt)
    local frameStartTime = love.timer.getTime()
    self.frameCount = self.frameCount + 1

    -- Setup interpolation initial state if enabled
    -- This must happen BEFORE block execution to capture frame-start state
    if self.interpolationEnabled then
        local Interpolate = require("vm.interpolate")
        Interpolate.setupInitialState(self)
    end

    -- Clear dynamic active keys at the start of each frame
    -- They will be repopulated during this frame if sensing_keypressed blocks are executed
    self.gamepadManager:clearDynamicKeys()

    -- Advance mock timer in test environment
    if love.timer.advance then
        love.timer.advance(dt)
    end

    local startTime = love.timer.getTime()

    self:resetRedrawRequest()

    -- Delegate thread scheduling to sequencer
    local activeThreads = self.sequencer:stepThreads(dt)
    local threadTime = love.timer.getTime() - startTime

    -- Release any queued key ups after threads have seen the press
    if self.pendingKeyReleases and #self.pendingKeyReleases > 0 then
        for i = 1, #self.pendingKeyReleases do
            local loveKey = self.pendingKeyReleases[i]
            self:onKeyReleased(loveKey)
        end
        self.pendingKeyReleases = {}
    end

    -- Update performance statistics
    self:updatePerformanceStats(dt, threadTime, activeThreads)

    -- Update all targets (sprites and clones)
    for i, target in ipairs(self.targets) do
        if target and target.update then
            target:update(dt)
        else
            log.warn("Runtime: Target missing update method: " .. tostring(target and target.name or "nil"))
        end
    end

    -- Update stage
    if self.stage then
        self.stage:update(dt)
    end

    -- Record frame end time for interpolation
    if self.interpolationEnabled then
        self._lastStepTime = love.timer.getTime() * 1000 -- Convert to milliseconds
    end

    -- Performance monitoring: Log extremely slow logic frames only
    local totalFrameTime = (love.timer.getTime() - frameStartTime) * 1000
    local threshold = Global.FRAME_TIME * self.sequencer.workTimeRatio * 1000
    if totalFrameTime > threshold and self.frameCount % 60 == 0 then
        local percentOver = ((totalFrameTime - threshold) / threshold) * 100
        log.warn("[LOGIC FRAME] Extremely slow: %.2fms (%.1f%% over threshold, Thread=%.2fms, Threads=%d)",
            totalFrameTime, percentOver, threadTime * 1000, activeThreads)
    end
end

---Get a snapshot of active threads (not DONE)
---@return Thread[] threads Active threads array copy
function Runtime:getActiveThreads()
    local threads = {}
    for i = 1, #self.threads do
        local t = self.threads[i]
        if t and t.status ~= Thread.STATUS_DONE then
            threads[#threads + 1] = t
        end
    end
    return threads
end

---Check if a thread is currently scheduled in the runtime thread list
---@param thread Thread|nil Thread to check
---@return boolean
function Runtime:isThreadScheduled(thread)
    if not thread then
        return false
    end

    for i = 1, #self.threads do
        if self.threads[i] == thread then
            return true
        end
    end

    return false
end

---Determine whether a thread is actively running
---@param thread Thread|nil Thread to inspect
---@return boolean
function Runtime:isActiveThread(thread)
    if not thread then
        return false
    end

    if thread.status == Thread.STATUS_DONE then
        return false
    end

    return self:isThreadScheduled(thread)
end

---Determine whether a thread is waiting for a promise/tick or is no longer active
---@param thread Thread|nil Thread to inspect
---@return boolean
function Runtime:isWaitingThread(thread)
    if not thread then
        return true
    end

    -- Match native Scratch: STATUS_YIELD is NOT considered waiting
    -- Only STATUS_PROMISE_WAIT and STATUS_YIELD_TICK are waiting states
    if thread.status == Thread.STATUS_PROMISE_WAIT or
        thread.status == Thread.STATUS_YIELD_TICK then
        return true
    end

    return not self:isActiveThread(thread)
end

---Get thread map (for tests/inspection)
---@return table<string, Thread> map Thread ID to Thread
function Runtime:getThreadMap()
    return self.threadMap
end

---Broadcast the green flag event to start scripts
function Runtime:broadcastGreenFlag()
    -- Process targets in forward order to match Scratch execution order
    -- Earlier sprites in the targets array should have their scripts start first
    -- Note: Native Scratch internally reverses iteration but threads are pushed to end,
    -- resulting in earlier sprites executing first when the thread list is processed sequentially
    for i = 1, #self.targets do
        local target = self.targets[i]
        self:startHatBlocks(target, "event_whenflagclicked")
    end
end

---Broadcast a message to all sprites
---@param message string Message to broadcast
---@param wait boolean|nil Whether to wait for completion
---@return Thread[]|nil threads List of started threads if wait=true
function Runtime:broadcast(message, wait)
    -- Broadcast a message to all sprites
    local threads = {}

    -- Convert message to string if needed
    local messageStr = tostring(message or "")

    -- Find broadcast ID
    local broadcastId = nil
    for id, name in pairs(self.broadcasts) do
        if name:lower() == messageStr:lower() then
            broadcastId = id
            break
        end
    end

    if not broadcastId then
        log.warn("Broadcast message not found: '%s'", messageStr)
        return
    end

    -- Process targets in forward order to match Scratch execution order
    for i = 1, #self.targets do
        local target = self.targets[i]
        local t = self:startHatBlocks(target, "event_whenbroadcastreceived", broadcastId)
        for _, thread in ipairs(t) do
            table.insert(threads, thread)
        end
    end

    -- If wait, return threads to wait for
    if wait then
        return threads
    end
end

---Start hat blocks matching the given criteria with proper restart/blocking logic
---@param target Sprite|Stage Target to search for hat blocks
---@param opcode string Hat block opcode to match
---@param param any Optional parameter for matching (e.g., broadcast ID)
---@param stackClick boolean|nil Whether triggered by clicking blocks
---@return Thread[] threads Started threads
function Runtime:startHatBlocks(target, opcode, param, stackClick)
    local threads = {}
    local blockIds = {}

    if target and target.getHatBlocks then
        blockIds = target:getHatBlocks(opcode, param)
    elseif target and target.spriteTemplate and target.spriteTemplate.getHatBlocks then
        -- Fallback: try using spriteTemplate method (for clones that lost their method)
        blockIds = target.spriteTemplate:getHatBlocks(opcode, param)
    else
        log.warn("Runtime: Target missing getHatBlocks method: " .. tostring(target and target.name or "nil"))
        return threads
    end

    local hatMeta = Runtime.HAT_METADATA[opcode] or { restartExistingThreads = true }
    local startingThreadListLength = #self.threads

    for _, blockId in ipairs(blockIds) do
        local newThreads = {}
        local threadId = Thread.getIdFromTargetAndBlock(target, blockId)

        if hatMeta.restartExistingThreads then
            -- If `restartExistingThreads` is true, restart existing threads
            local threadId = Thread.getIdFromTargetAndBlock(target, blockId)
            local existingThread = self.threadMap[threadId]

            if existingThread then
                -- Update hat parameter if provided
                if param then
                    existingThread.hatParam = param
                end
                -- Restart and ensure it is scheduled for execution
                existingThread:restart(param)
                existingThread.isHatBlockThread = true
                -- If the thread was previously cleaned up from the active list,
                -- reinsert it so the sequencer can run it again
                local inActiveList = false
                for i = 1, #self.threads do
                    if self.threads[i] == existingThread then
                        inActiveList = true
                        break
                    end
                end
                if not inActiveList then
                    table.insert(self.threads, existingThread)
                end
                table.insert(newThreads, existingThread)
            else
                -- Create new thread
                local thread = Thread:new(target, blockId, self, stackClick, param)
                thread.isHatBlockThread = true
                self.threadMap[threadId] = thread
                table.insert(self.threads, thread)
                table.insert(newThreads, thread)
            end
        else
            -- If `restartExistingThreads` is false, block if threads are running
            -- Also block same-frame re-triggers for this hat
            local threadId = Thread.getIdFromTargetAndBlock(target, blockId)
            if (not stackClick) and self.hatRunFrameMap[threadId] == self.frameCount then
                goto continue_next_block
            end
            -- For collision detection hats, block immediate next-frame retrigger
            -- But allow edge-activated hats to use their own edge logic
            if opcode == "event_whentouchingobject" and (not stackClick) and not self:getIsEdgeActivatedHat(opcode) then
                local last = self.hatRunFrameMap[threadId]
                if last ~= nil and (last == self.frameCount or last == (self.frameCount - 1)) then
                    goto continue_next_block
                end
            end
            local sameHatThreadCount = 0
            for j = 1, startingThreadListLength do
                local existingThread = self.threads[j]
                if existingThread and
                    existingThread.target == target and
                    existingThread.topBlock == blockId and
                    not existingThread.stackClick and
                    existingThread.status ~= Thread.STATUS_DONE then
                    sameHatThreadCount = sameHatThreadCount + 1
                    -- Allow stackClick (manual run) to coexist; otherwise apply block rules
                    if (not stackClick) and (opcode:find("^event_") or opcode:find("^control_") or
                            self.hatsConcurrency <= sameHatThreadCount) then
                        -- Block creation of new thread
                        goto continue_next_block
                    end
                end
            end

            -- No blocking conditions met, create new thread
            local thread = Thread:new(target, blockId, self, stackClick, param)
            thread.isHatBlockThread = true
            local threadId2 = Thread.getIdFromTargetAndBlock(target, blockId)
            self.threadMap[threadId2] = thread
            -- Remember this hat ran this frame to prevent duplicate triggers
            self.hatRunFrameMap[threadId2] = self.frameCount
            table.insert(self.threads, thread)
            table.insert(newThreads, thread)
        end

        ::continue_next_block::
        for _, thread in ipairs(newThreads) do
            if thread.isCompiled then
                -- Get executableHat flag from compiler cache
                local blockContainer = thread.target.blocks or
                    (thread.target.spriteTemplate and thread.target.spriteTemplate.blocks)
                local cached = blockContainer and self.compilerCache[blockContainer] and
                    self.compilerCache[blockContainer][thread.topBlock]
                local executableHat = cached and cached.executableHat or false

                if executableHat then
                    -- Execute the hat block immediately (yield once for proper event timing)
                    thread:stepCompiled()
                end
            end
            table.insert(threads, thread)
        end
    end

    -- print(string.format("[HAT] Returning %d threads", #threads))
    return threads
end

---Check if more clones can be created
---Uses runtimeOptions.maxClones for the limit
---@return boolean available Whether clones are available
function Runtime:clonesAvailable()
    return self.cloneCounter < self.runtimeOptions.maxClones
end

---Add a target to the runtime (Scratch-style)
---@param target Sprite Target to add
function Runtime:addTarget(target)
    if not target then
        log.warn("Runtime: Attempted to add nil target")
        return
    end

    table.insert(self.targets, target)

    -- Add to renderer draw order
    if self.renderer then
        self.renderer:addSprite(target)
    end

    log.debug("Target added: %s (isClone: %s, visible: %s, pos:(%.1f,%.1f), total targets: %d)",
        target.name or "nil", tostring(target.isClone), tostring(target.visible),
        target.x or 0, target.y or 0, #self.targets)
end

---Change clone counter
---@param delta integer Change amount (+1 for create, -1 for delete)
function Runtime:changeCloneCounter(delta)
    self.cloneCounter = self.cloneCounter + delta
end

---Get all clones from targets array (for testing compatibility)
---@return Sprite[] clones Array of clone sprites
function Runtime:getClones()
    local clones = {}
    for _, target in ipairs(self.targets) do
        if target.isClone then
            table.insert(clones, target)
        end
    end
    return clones
end

---Get sprite target by name (Scratch-style)
---@param spriteName string Name of sprite to find
---@return Sprite|nil target The target with the given name, or nil if not found
function Runtime:getSpriteTargetByName(spriteName)
    -- First check original sprites (non-clones) in targets
    for _, target in ipairs(self.targets) do
        if (not target.isClone) and target.name == spriteName then
            return target
        end
    end

    return nil
end

---Delete a clone sprite
---@param clone Sprite Clone to delete
function Runtime:deleteClone(clone)
    -- Only delete actual clones, not original sprites (silent handling like native Scratch)
    log.debug("Deleting clone of sprite: [%s]%s", clone.drawableId or "nil", clone.name)

    if not clone.isClone then
        return
    end

    -- Mark clone as deleted (prevents further execution)
    clone.isDeleted = true

    -- Stop all threads belonging to this clone (matching native Scratch stopForTarget)
    for i = #self.threads, 1, -1 do
        local thread = self.threads[i]
        if thread.target == clone then
            -- Mark thread as killed (matching native Scratch)
            thread.isKilled = true
            thread.status = Thread.STATUS_DONE
            -- Note: Don't remove here - let sequencer clean up in its loop
        end
    end

    -- Remove from sprite template clone list so sensing/touching checks stay in sync
    if clone.spriteTemplate and clone.spriteTemplate.removeClone then
        clone.spriteTemplate:removeClone(clone)
    end

    -- Remove from renderer draw order first
    if self.renderer then
        self.renderer:removeSprite(clone)
    end

    -- Threads may still be in execution and need access to variables
    -- Resources will be cleaned up when threads are retired by sequencer

    -- Remove from targets array (preserve order for rendering and sensing)
    local targets = self.targets
    for i = 1, #targets do
        if targets[i] == clone then
            table.remove(targets, i)
            break
        end
    end

    if Global.ENABLE_TEXTURE_CLEANUP and not clone.isStage then
        -- Cleanup unused costumes immediately
        clone:cleanupUnusedCostumes(0)
    end
    self.cloneCounter = self.cloneCounter - 1
end

---Convert Scratch X coordinate to screen coordinate
---@param x number Scratch X coordinate
---@return number screenX Screen X coordinate
function Runtime:scratchToScreenX(x)
    -- Convert Scratch X (-320 to 320) to screen X (0 to 640)
    return x + Global.STAGE_HALF_WIDTH
end

---Convert Scratch Y coordinate to screen coordinate
---@param y number Scratch Y coordinate
---@return number screenY Screen Y coordinate
function Runtime:scratchToScreenY(y)
    -- Convert Scratch Y (-240 to 240) to screen Y (0 to 480)
    return Global.STAGE_HALF_HEIGHT - y
end

---Convert screen X coordinate to Scratch coordinate
---@param x number Screen X coordinate
---@return number scratchX Scratch X coordinate
function Runtime:screenToScratchX(x)
    -- Convert screen X to Scratch X
    return x - Global.STAGE_HALF_WIDTH
end

---Convert screen Y coordinate to Scratch coordinate
---@param y number Screen Y coordinate
---@return number scratchY Scratch Y coordinate
function Runtime:screenToScratchY(y)
    -- Convert screen Y to Scratch Y
    return Global.STAGE_HALF_HEIGHT - y
end

---Get the runtime timer value
---@return number timer Timer value in seconds
function Runtime:getTimer()
    return love.timer.getTime() - self.startTime
end

---Get the current microphone loudness
---@return number loudness Loudness value from 0-100
function Runtime:getLoudness()
    if self.audioEngine and self.audioEngine.getLoudness then
        local loudness = self.audioEngine:getLoudness()
        return tonumber(loudness) or 0
    end
    return 0
end

---Reset the runtime timer
function Runtime:resetTimer()
    self.startTime = love.timer.getTime()
end

-- Edge-activated hat block management
---Check if a target has an old edge-activated value for the given block
---@param target Sprite|Stage The target sprite or stage
---@param blockId string The block ID
---@return boolean hasOldValue True if an old value exists
function Runtime:hasEdgeActivatedValue(target, blockId)
    local targetId = target.name or target.drawableId or "stage"
    return self.edgeActivatedValues[targetId] and
        self.edgeActivatedValues[targetId][blockId] and
        self.edgeActivatedValues[targetId][blockId].hasOldValue or false
end

---Update the edge-activated value for a hat block and return the old value
---@param target Sprite|Stage The target sprite or stage
---@param blockId string The block ID
---@param newValue boolean The new boolean value
---@return boolean oldValue The previous value (false if no old value existed)
function Runtime:updateEdgeActivatedValue(target, blockId, newValue)
    local targetId = target.name or target.drawableId or "stage"

    -- Initialize target storage if needed
    if not self.edgeActivatedValues[targetId] then
        self.edgeActivatedValues[targetId] = {}
    end

    -- Get old value
    local oldValue = false
    local hasOldValue = false
    if self.edgeActivatedValues[targetId][blockId] then
        oldValue = self.edgeActivatedValues[targetId][blockId].value
        hasOldValue = self.edgeActivatedValues[targetId][blockId].hasOldValue
    end

    -- Store new value
    self.edgeActivatedValues[targetId][blockId] = {
        value = newValue,
        hasOldValue = true
    }

    return oldValue
end

---Check if an opcode represents an edge-activated hat block
---@param opcode string The block opcode
---@return boolean isEdgeActivated True if the block is edge-activated
function Runtime:getIsEdgeActivatedHat(opcode)
    local hatMeta = Runtime.HAT_METADATA[opcode]
    return hatMeta and hatMeta.edgeActivated or false
end

---Evaluate the predicate condition for an edge-activated hat block
---@param target Sprite|Stage The target sprite or stage
---@param blockId string The block ID
---@param opcode string The block opcode
---@return boolean result The current predicate value
function Runtime:evaluateHatPredicate(target, blockId, opcode)
    local block = target.blocks[blockId]
    if not block then
        return false
    end

    if opcode == "event_whentouchingobject" then
        -- Get the touching object parameter
        local touchingObject = "_mouse_" -- default
        if block.fields and block.fields.TOUCHINGOBJECTMENU then
            touchingObject = block.fields.TOUCHINGOBJECTMENU.value
        elseif block.inputs and block.inputs.TOUCHINGOBJECTMENU then
            -- Handle input block case
            local input = block.inputs.TOUCHINGOBJECTMENU
            ---@type any input
            input = block.inputs.TOUCHINGOBJECTMENU
            if input and input.block then
                -- Input block evaluation not implemented, using default
                touchingObject = "_mouse_"
            end
        end

        -- Evaluate touching condition using sensing block logic
        if target.isStage then
            return false
        end

        if touchingObject == "_edge_" then
            return target:touchingEdge()
        elseif touchingObject == "_mouse_" then
            return target:containsPoint(self.mouseX, self.mouseY)
        else
            -- Check collision with another sprite or clone
            for _, sprite in ipairs(self.targets) do
                if sprite.name == touchingObject and sprite ~= target then
                    return target:touchingSprite(sprite)
                end
            end
        end
        return false
    elseif opcode == "event_whengreaterthan" then
        -- Get the sensor and value parameters
        local sensor = "TIMER" -- default
        local value = 10       -- default

        if block.fields and block.fields.WHENGREATERTHANMENU then
            sensor = block.fields.WHENGREATERTHANMENU.value
        end

        if block.fields and block.fields.VALUE then
            value = tonumber(block.fields.VALUE.value) or 10
        elseif block.inputs and block.inputs.VALUE then
            -- Input block evaluation not implemented, using default
            value = 10
        end

        -- Evaluate the greater than condition
        if sensor == "TIMER" then
            return self:getTimer() > value
        elseif sensor == "LOUDNESS" then
            return self:getLoudness() > value
        end
        return false
    end

    -- Unknown edge-activated hat, default to false
    return false
end

---Programmatically dispatch a key press hat (used by tests and tooling)
---@param scratchKey string Scratch key label to dispatch
function Runtime:broadcastKeyForTest(scratchKey)
    local loveKey = self:mapScratchToLoveKey(scratchKey)
    if not loveKey then
        log.warn('Runtime: Unknown scratch key broadcast: %s', tostring(scratchKey))
        return
    end

    self:onKeyPressed(loveKey)
    self.pendingKeyReleases[#self.pendingKeyReleases + 1] = loveKey
end

---Programmatically dispatch a sprite or stage click hat
---@param target Sprite|Stage Target that was clicked
function Runtime:broadcastSpriteClickForTest(target)
    if not target then
        log.warn('Runtime: broadcastSpriteClick called without a target')
        return
    end

    if target.isStage then
        self:startHatBlocks(target, 'event_whenstageclicked')
    else
        self:startHatBlocks(target, 'event_whenthisspriteclicked')
    end
end

-- Input handlers
---Handle key press event
---@param key string Love2D key name
function Runtime:onKeyPressed(key)
    self.keysPressed[key] = true

    -- Map Love2D keys to Scratch keys
    local scratchKey = self:mapKeyToScratch(key)
    if scratchKey then
        -- Only trigger hat blocks if this key is statically registered (from hat blocks)
        -- Dynamic keys (from sensing_keypressed) do not trigger hat blocks
        if not self.gamepadManager:isKeyActive(scratchKey) then
            return
        end

        -- Start key press scripts in reverse target order to match Scratch execution order
        for i = #self.targets, 1, -1 do
            local target = self.targets[i]
            self:startHatBlocks(target, "event_whenkeypressed", scratchKey)
        end
    end
end

---Handle key release event
---@param key string Love2D key name
function Runtime:onKeyReleased(key)
    self.keysPressed[key] = false
end

-- Joystick handlers
---Initialize joystick support - detect connected joysticks
function Runtime:_initializeJoysticks()
    local joysticks = love.joystick.getJoysticks()
    for _, joystick in ipairs(joysticks) do
        self:onJoystickAdded(joystick)
    end
end

---Handle joystick added event
---@param joystick love.Joystick The joystick that was added
function Runtime:onJoystickAdded(joystick)
    table.insert(self.joysticks, joystick)
    log.info("Joystick connected: " .. joystick:getName())
end

---Handle joystick removed event
---@param joystick love.Joystick The joystick that was removed
function Runtime:onJoystickRemoved(joystick)
    -- Remove from joysticks list
    for i, j in ipairs(self.joysticks) do
        if j == joystick then
            table.remove(self.joysticks, i)
            break
        end
    end
    log.info("Joystick disconnected: " .. joystick:getName())
end

---Handle gamepad button pressed event
---@param joystick love.Joystick The joystick that fired the event
---@param button love.GamepadButton The button that was pressed ("a", "b", "x", "y", "dpup", etc.)
function Runtime:onGamepadButtonPressed(joystick, button)
    -- Priority 1: Check virtual gamepad mapping for action buttons (ABXY)
    local scratchKey = self.gamepadManager:getScratchKeyForButton(button)
    if scratchKey then
        local loveKey = self:mapScratchToLoveKey(scratchKey)
        if loveKey then
            self:onKeyPressed(loveKey)
            log.debug("Virtual gamepad button pressed: %s → %s → %s", button, scratchKey, loveKey)
            return
        end
    end

    -- Priority 2: Fallback to directional pad (d-pad) mapping
    local dpadMap = {
        dpup = "up",
        dpdown = "down",
        dpleft = "left",
        dpright = "right"
    }

    local key = dpadMap[button]
    if key then
        self:onKeyPressed(key)
        log.debug("Gamepad dpad pressed: %s → %s", button, key)
    end
end

---Handle gamepad button released event
---@param joystick love.Joystick The joystick that fired the event
---@param button love.GamepadButton The button that was released ("a", "b", "x", "y", "dpup", etc.)
function Runtime:onGamepadButtonReleased(joystick, button)
    -- Priority 1: Check virtual gamepad mapping for action buttons (ABXY)
    local scratchKey = self.gamepadManager:getScratchKeyForButton(button)
    if scratchKey then
        local loveKey = self:mapScratchToLoveKey(scratchKey)
        if loveKey then
            self:onKeyReleased(loveKey)
            log.debug("Virtual gamepad button released: %s → %s → %s", button, scratchKey, loveKey)
            return
        end
    end

    -- Priority 2: Fallback to directional pad (d-pad) mapping
    local dpadMap = {
        dpup = "up",
        dpdown = "down",
        dpleft = "left",
        dpright = "right"
    }

    local key = dpadMap[button]
    if key then
        self:onKeyReleased(key)
        log.debug("Gamepad dpad released: %s → %s", button, key)
    end
end

---Handle mouse press event
---Reference: Native Scratch io/mouse.js:59-102 (postData with isDown transition)
---@param x number Window X position
---@param y number Window Y position
---@param button number Mouse button
function Runtime:onMousePressed(x, y, button)
    if button == 1 then
        self.mouseDown = true

        -- Convert window coordinates to stage coordinates
        local stageX = (x - (love.graphics.autoOffsetX or 0)) / (love.graphics.autoScale or 1)
        local stageY = (y - (love.graphics.autoOffsetY or 0)) / (love.graphics.autoScale or 1)

        -- Convert stage coordinates to Scratch coordinates
        local scratchX = self:screenToScratchX(stageX)
        local scratchY = self:screenToScratchY(stageY)

        -- Store drag start position
        self.dragStartX = scratchX
        self.dragStartY = scratchY
        self.wasDragged = false

        -- Find clicked target (topmost sprite at click position)
        -- Process targets in reverse order (top to bottom in Z-order)
        local clickedTarget = nil
        for i = #self.targets, 1, -1 do
            local target = self.targets[i]
            -- Skip stage and invisible sprites
            if not target.isStage and target.visible and target.containsPoint and target:containsPoint(scratchX, scratchY) then
                clickedTarget = target
                break -- Found topmost sprite
            end
        end

        if clickedTarget then
            -- Draggable sprites: delay click event until mouse up
            -- Non-draggable sprites: trigger click event immediately
            if clickedTarget.draggable then
                -- Draggable targets start click hats on mouse up
                self.dragTarget = clickedTarget
                log.debug("Mouse down on draggable sprite: %s", clickedTarget.name)
            else
                -- Non-draggable targets start click hats on mouse down
                log.debug("Mouse down on non-draggable sprite: %s", clickedTarget.name)
                self:startHatBlocks(clickedTarget, "event_whenthisspriteclicked")
            end
        end
    end
end

---Handle mouse release event
---Reference: Native Scratch io/mouse.js:59-102 (postData with isDown transition)
---@param x number Window X position
---@param y number Window Y position
---@param button number Mouse button
function Runtime:onMouseReleased(x, y, button)
    if button == 1 then
        self.mouseDown = false

        -- Handle draggable sprite click event
        if self.dragTarget then
            -- Only trigger click event if:
            -- 1. Target is draggable (already checked when dragTarget was set)
            -- 2. No dragging occurred (wasDragged is false)
            if not self.wasDragged then
                log.debug("Mouse up on draggable sprite without drag, triggering click: %s", self.dragTarget.name)
                self:startHatBlocks(self.dragTarget, "event_whenthisspriteclicked")
            else
                log.debug("Mouse up on draggable sprite after drag, NOT triggering click: %s", self.dragTarget.name)
            end

            -- Clear drag state
            self.dragTarget = nil
            self.wasDragged = false
        end
    end
end

---Handle mouse move event
---@param x number Window X position
---@param y number Window Y position
function Runtime:onMouseMoved(x, y)
    -- Convert window coordinates to stage coordinates
    local stageX = (x - (love.graphics.autoOffsetX or 0)) / (love.graphics.autoScale or 1)
    local stageY = (y - (love.graphics.autoOffsetY or 0)) / (love.graphics.autoScale or 1)

    -- Convert stage coordinates to Scratch coordinates
    self.mouseX = self:screenToScratchX(stageX)
    self.mouseY = self:screenToScratchY(stageY)

    -- Handle sprite dragging
    if self.mouseDown and self.dragTarget then
        -- Calculate drag delta from start position
        local dx = self.mouseX - self.dragStartX
        local dy = self.mouseY - self.dragStartY

        -- Mark as dragged if moved more than threshold (1 pixel in Scratch coordinates)
        if math.abs(dx) > 1 or math.abs(dy) > 1 then
            self.wasDragged = true
        end

        -- Update sprite position to follow mouse
        -- Use setXY to apply fencing if enabled
        self.dragTarget:setXY(self.mouseX, self.mouseY)
    end
end

---Map Scratch key name to Love2D key name
---@param scratchKey string Scratch key label from blocks (letters are UPPERCASE in native Scratch)
---@return string|nil loveKey Corresponding Love2D key name
function Runtime:mapScratchToLoveKey(scratchKey)
    if scratchKey == "space" then
        return "space"
    elseif scratchKey == "up arrow" then
        return "up"
    elseif scratchKey == "down arrow" then
        return "down"
    elseif scratchKey == "left arrow" then
        return "left"
    elseif scratchKey == "right arrow" then
        return "right"
    elseif scratchKey == "enter" then
        return "return"
    elseif scratchKey == "any" then
        return nil
    elseif #scratchKey == 1 then
        -- Single character keys: convert to lowercase for Love2D (native Scratch stores as uppercase)
        return scratchKey:lower()
    end
    return scratchKey
end

---Map Love2D key to Scratch key name
---@param key string Love2D key name
---@return string scratchKey Scratch key name
function Runtime:mapKeyToScratch(key)
    -- Map Love2D key names to Scratch key names
    -- Letters are stored as UPPERCASE in native Scratch (matching _keyStringToScratchKey behavior)
    local keyMap = {
        space = "space",
        up = "up arrow",
        down = "down arrow",
        left = "left arrow",
        right = "right arrow",
        ["return"] = "enter",
        enter = "enter",
        -- Letters (UPPERCASE to match native Scratch)
        a = "A",
        b = "B",
        c = "C",
        d = "D",
        e = "E",
        f = "F",
        g = "G",
        h = "H",
        i = "I",
        j = "J",
        k = "K",
        l = "L",
        m = "M",
        n = "N",
        o = "O",
        p = "P",
        q = "Q",
        r = "R",
        s = "S",
        t = "T",
        u = "U",
        v = "V",
        w = "W",
        x = "X",
        y = "Y",
        z = "Z",
        -- Numbers
        ["0"] = "0",
        ["1"] = "1",
        ["2"] = "2",
        ["3"] = "3",
        ["4"] = "4",
        ["5"] = "5",
        ["6"] = "6",
        ["7"] = "7",
        ["8"] = "8",
        ["9"] = "9",
        -- Keypad numbers
        kp0 = "0",
        kp1 = "1",
        kp2 = "2",
        kp3 = "3",
        kp4 = "4",
        kp5 = "5",
        kp6 = "6",
        kp7 = "7",
        kp8 = "8",
        kp9 = "9"
    }

    return keyMap[key] or key
end

---Check if a key is currently pressed
---@param key string Scratch key name
---@return boolean pressed Whether key is pressed
function Runtime:isKeyPressed(key)
    -- Special case: "any" key - check if any key is pressed
    if key == "any" then
        for _, pressed in pairs(self.keysPressed) do
            if pressed then
                return true
            end
        end
        return false
    end

    local loveKey = self:mapScratchToLoveKey(key)
    if not loveKey then
        return false
    end

    return self.keysPressed[loveKey] or false
end

-- Performance monitoring methods
---Update performance statistics
---@param frameTime number Frame delta time
---@param threadTime number Thread execution time
---@param activeThreads integer Number of active threads
function Runtime:updatePerformanceStats(frameTime, threadTime, activeThreads)
    local perf = self.performance

    perf.frameTime = frameTime
    perf.threadTime = threadTime
    perf.activeThreads = activeThreads

    -- Calculate moving averages (exponential smoothing)
    local smoothingFactor = 0.1
    perf.averageFrameTime = perf.averageFrameTime * (1 - smoothingFactor) + frameTime * smoothingFactor
    perf.averageThreadTime = perf.averageThreadTime * (1 - smoothingFactor) + threadTime * smoothingFactor

    -- Store history (keep last 60 frames for 1 second at 60fps)
    table.insert(perf.performanceHistory, {
        frame = self.frameCount,
        frameTime = frameTime,
        threadTime = threadTime,
        activeThreads = activeThreads
    })

    if #perf.performanceHistory > 60 then
        table.remove(perf.performanceHistory, 1)
    end
end

---Get performance information
---@return table performance Performance data
function Runtime:getPerformanceInfo()
    local perf = self.performance
    local avgFrameTime = math.max(perf.averageFrameTime, 0.001)

    return {
        fps = 1 / avgFrameTime,
        frameTime = avgFrameTime * 1000, -- Convert to milliseconds
        threadTime = perf.averageThreadTime * 1000,
        threadTimeRatio = perf.averageThreadTime / avgFrameTime,
        activeThreads = perf.activeThreads,
        workTimeRatio = self.sequencer:getWorkTimeRatio()
    }
end

-- Monitor system methods

---Enable or disable monitor logging
---@param enabled boolean Whether to enable monitor logging
function Runtime:setMonitorLogging(enabled)
    if self.monitorManager then
        self.monitorManager:setLogging(enabled)
    end
end

---Deserialize monitors from project data, matching native Scratch behavior
---Only creates monitors that were explicitly saved in the project file
---Values are evaluated in real-time from target/variable references
function Runtime:_autoCreateMonitors()
    if not self.monitorManager then return end

    -- Only create monitors from project data, not auto-create for all variables
    for _, monitorData in ipairs(self.project.monitors or {}) do
        -- Create monitor based on opcode type
        if monitorData.opcode == "data_variable" then
            -- Variable monitor
            local spriteName = monitorData.spriteName
            local label = monitorData.params and monitorData.params.VARIABLE or "unknown variable"
            self.monitorManager:addMonitor(monitorData.id, monitorData.opcode, "data", label, spriteName)

            -- Find the variable and set direct reference (no need to copy value)
            local variableId = monitorData.id
            local variable = nil
            if self.stage and self.stage.variables[variableId] then
                variable = self.stage.variables[variableId]
            else
                for _, sprite in ipairs(self.targets) do
                    if sprite.variables and sprite.variables[variableId] then
                        variable = sprite.variables[variableId]
                        break
                    end
                end
            end

            if variable then
                self.monitorManager:setVariableReference(monitorData.id, variable)
            end
        elseif monitorData.opcode == "data_listcontents" then
            -- List monitor
            local spriteName = monitorData.spriteName
            local label = monitorData.params and monitorData.params.LIST or "unknown list"
            self.monitorManager:addMonitor(monitorData.id, monitorData.opcode, "data", label, spriteName)

            -- Find the list and set direct reference
            local listId = monitorData.id
            local listVariable = nil
            if self.stage and self.stage.variables[listId] then
                listVariable = self.stage.variables[listId]
            else
                for _, sprite in ipairs(self.targets) do
                    if sprite.variables and sprite.variables[listId] then
                        listVariable = sprite.variables[listId]
                        break
                    end
                end
            end

            if listVariable then
                self.monitorManager:setVariableReference(monitorData.id, listVariable)
            end
        elseif monitorData.opcode == "motion_xposition" then
            -- X position monitor
            local spriteName = monitorData.spriteName
            self.monitorManager:addMonitor(monitorData.id, monitorData.opcode, "motion", "x position", spriteName)
            local sprite = self:getSpriteTargetByName(spriteName)
            if sprite then
                self.monitorManager:setTargetReference(monitorData.id, sprite)
            end
        elseif monitorData.opcode == "motion_yposition" then
            -- Y position monitor
            local spriteName = monitorData.spriteName
            self.monitorManager:addMonitor(monitorData.id, monitorData.opcode, "motion", "y position", spriteName)
            local sprite = self:getSpriteTargetByName(spriteName)
            if sprite then
                self.monitorManager:setTargetReference(monitorData.id, sprite)
            end
        elseif monitorData.opcode == "motion_direction" then
            -- Direction monitor
            local spriteName = monitorData.spriteName
            self.monitorManager:addMonitor(monitorData.id, monitorData.opcode, "motion", "direction", spriteName)
            local sprite = self:getSpriteTargetByName(spriteName)
            if sprite then
                self.monitorManager:setTargetReference(monitorData.id, sprite)
            end
        else
            -- Other monitor types (sensing, operators, looks, sound, etc.)
            local label = monitorData.opcode:gsub("_", " ") -- Simple label generation
            local category = monitorData.opcode:match("^([^_]+)") or "unknown"
            local spriteName = monitorData.spriteName
            self.monitorManager:addMonitor(monitorData.id, monitorData.opcode, category, label, spriteName)

            -- Set target reference for sprite-specific monitors
            if spriteName then
                local sprite = self:getSpriteTargetByName(spriteName)
                if sprite then
                    self.monitorManager:setTargetReference(monitorData.id, sprite)
                end
            else
                -- Stage monitors (timer, mouse position, etc.)
                if self.stage then
                    self.monitorManager:setTargetReference(monitorData.id, self.stage)
                end
            end
        end

        -- Set monitor visibility (values are evaluated in real-time, no need to set initial values)
        if self.monitorManager.monitors[monitorData.id] then
            self.monitorManager.monitors[monitorData.id].visible = monitorData.visible ~= false

            -- Set monitor position and size from project data
            self.monitorManager:setPosition(
                monitorData.id,
                monitorData.x,
                monitorData.y,
                monitorData.width,
                monitorData.height
            )
        end
    end

    if #(self.project.monitors or {}) > 0 then
        log.info("MonitorManager: Deserialized " .. #self.project.monitors .. " monitors from project data")
    end
end

---Clean up unused costume textures for all hidden sprites (fallback mechanism)
---This catches sprites that were hidden and never shown again
---Active sprites clean themselves up on costume switch
---@return number totalCleaned Total number of costumes cleaned up
function Runtime:cleanupHiddenSpritesTextures()
    local totalCleaned = 0

    -- Only clean up hidden sprites (active sprites clean themselves)
    for _, target in ipairs(self.targets) do
        if not target.isStage and not target.visible then
            local cleaned = target:cleanupUnusedCostumes()
            totalCleaned = totalCleaned + cleaned
        end
    end

    return totalCleaned
end

---Request a redraw on the next frame
---Use after a sprite has completed some visible operation on the stage
function Runtime:requestRedraw()
    self.redrawRequested = true
end

---Check if a redraw has been requested this frame
---@return boolean redrawRequested Whether redraw was requested
function Runtime:isRedrawRequested()
    return self.redrawRequested
end

---Reset redraw request flag at the start of each frame
---Should be called before thread execution in main update loop
function Runtime:resetRedrawRequest()
    self.redrawRequested = false
end

---Stop all threads)
function Runtime:stopAll()
    self.threads = {}
end

---Stop threads for a specific target, optionally excluding one thread)
---Each clone is an independent target - use strict reference equality (===) like native Scratch
---@param target Sprite|Stage Target to stop threads for
---@param excludeThread Thread|nil Thread to exclude from stopping
function Runtime:stopForTarget(target, excludeThread)
    local i = 1
    while i <= #self.threads do
        local thread = self.threads[i]
        -- Native Scratch: if (this.threads[i].target === target)
        -- Each clone is a separate target instance and should not be affected
        if thread.target == target and thread ~= excludeThread then
            table.remove(self.threads, i)
        else
            i = i + 1
        end
    end
end

-- Audio system integration

---Initialize audio system for a target (stage or sprite)
---Reference: Native Scratch uses global soundId registry (SoundBank.addSoundPlayer)
---@param target Sprite|Stage The target to initialize audio for
---@param targetName string Name of the target
function Runtime:_initializeAudioForTarget(target, targetName)
    if not self.audioEngine then
        return
    end

    -- Add sounds to the audio manager (global soundId registry)
    if target.sounds then
        for _, soundData in ipairs(target.sounds) do
            -- Get duration from Love2D source if not already set
            if soundData.source and not soundData.duration then
                local ok, duration = pcall(function() return soundData.source:getDuration() end)
                if ok and duration then
                    soundData.duration = duration
                else
                    soundData.duration = 0
                    log.warn("Failed to get duration for sound '%s', using 0", soundData.name or "unknown")
                end
            end

            self.audioEngine:addSoundPlayer(soundData)
        end
    end

    if not target.volume then
        target.volume = 100
    end
    if not target.soundEffects then
        target.soundEffects = { pitch = 0, pan = 0 }
    end
end

---Get target by name (including clones)
---@param targetName string Name of target
---@return Sprite|Stage|nil target The target or nil if not found
function Runtime:getTargetByName(targetName)
    if targetName == "Stage" then
        return self.stage
    end

    for _, target in ipairs(self.targets) do
        if target.name == targetName or (target.cloneName and target.cloneName == targetName) then
            return target
        end
    end

    return nil
end

---Register a key as actively monitored during runtime (dynamic registration)
---Called when sensing_keypressed is executed with a dynamic key value
---Delegates to gamepadManager for centralized key management
---@param scratchKey string The Scratch key name (e.g., "space", "a", "up arrow")
function Runtime:registerActiveKey(scratchKey)
    self.gamepadManager:registerDynamicKey(scratchKey)
end

---Should be called at the beginning of Runtime:update()
function Runtime:resetStuckCounter()
    self.stuckCounter = 0
    self.tickStartTime = love.timer.getTime()
end

---Check if the current tick is stuck (taking too long)
---Check if thread execution appears stuck
---Checks every 100 calls and returns true if tick has exceeded 500ms
---@return boolean isStuck True if the tick appears to be stuck
function Runtime:isStuck()
    self.stuckCounter = self.stuckCounter + 1

    if self.stuckCounter >= 100 then
        self.stuckCounter = 0
        local elapsed = love.timer.getTime() - self.tickStartTime
        return elapsed > 0.5 -- 500ms threshold
    end

    return false
end

-- Cloud variable storage methods

---Save a cloud variable value to persistent storage
---Called automatically when a cloud variable is modified
---@param variableId string Variable ID
---@param value number Variable value (cloud variables are always numbers)
---@return boolean success True if saved successfully
function Runtime:saveCloudVariable(variableId, value)
    if not self.cloudStorage then
        return false
    end

    return self.cloudStorage:set(variableId, value)
end

---Save all cloud variables to persistent storage
---@return boolean success True if saved successfully
function Runtime:saveAllCloudVariables()
    if not self.cloudStorage then
        return false
    end

    return self.cloudStorage:collectFromRuntime(self)
end

-- Interpolation system methods

---Enable or disable frame interpolation
---Set interpolation enabled state
---@param enabled boolean Whether to enable interpolation
function Runtime:setInterpolation(enabled)
    self.interpolationEnabled = enabled
    log.info("Runtime: Interpolation %s", enabled and "enabled" or "disabled")
end

return Runtime
