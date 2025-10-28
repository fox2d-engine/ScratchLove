--[[
    ScratchLove - A high-performance Scratch 3.0 runtime for LÖVE (Love2D)
    Copyright (C) 2024 Fox2D.com. All rights reserved.

    This program is free software: you can redistribute it and/or modify
    it under the terms of the GNU Affero General Public License as published
    by the Free Software Foundation, either version 3 of the License, or
    (at your option) any later version.

    This program is distributed in the hope that it will be useful,
    but WITHOUT ANY WARRANTY; without even the implied warranty of
    MERCHANTABILITY or FITNESS FOR A PARTICULAR PURPOSE.  See the
    GNU Affero General Public License for more details.

    You should have received a copy of the GNU Affero General Public License
    along with this program.  If not, see <https://www.gnu.org/licenses/>.
--]]

local Global                     = require("global")
local LoadingScreen              = require("ui.loading_screen")
local ErrorDialog                = require("ui.error_dialog")
local log                        = require("lib.log")
local resvg                      = require("resvg")
local JitProfiler                = require("lib.jit_profiler")

-- Runtime variables
---@type Runtime|nil
local runtime                    = nil
---@type Renderer|nil
local renderer                   = nil
---@type ProjectModel|nil
local project                    = nil
---@type LoadingScreen|nil
local loadingScreen              = nil
---@type ErrorDialog|nil
local globalErrorDialog          = nil

-- Gamepad Back button long press exit state (Handheld Linux only)
local gamepadBackButtonPressTime = nil -- Timestamp when Back button was pressed (nil if not pressed)
local GAMEPAD_BACK_EXIT_DURATION = 1.0 -- Duration to hold Back button for exit (seconds)

-- Help text displayed when no project is loaded
local HELP_TEXT                  = "ScratchLove\n\n" ..
    "Controls:\n" ..
    "Ctrl+R: Reload\n" ..
    "Ctrl+D: Toggle debug\n" ..
    "Ctrl+P: Toggle performance\n" ..
    "Ctrl+M: Toggle monitor logging\n" ..
    "Ctrl+F: Toggle profiler\n\n" ..
    "Drag and drop an .sb3 file to load it\n" ..
    "Or use: love . <project-id>"

-- Letterbox rendering (for Android/Handheld Linux scaling)
---@type love.Canvas|nil
local stageCanvas                = nil
---@type love.Shader|nil
local letterboxShader            = nil

-- Window configuration (saved from love.load to preserve conf.lua settings)
local windowConfig               = nil

-- Current state
local currentFilePath            = nil


-- Performance monitoring variables
-- IMPORTANT: Don't cache Global.FRAME_TIME here as it can be changed by projects
local performanceData = {
    lastFrameDuration = 0,
    maxFrameDuration = 0,
    longFrameCount = 0,
    lastFrameStart = 0
}

-- Tick-style frame control variables (based on tick.lua design)
-- IMPORTANT: Don't cache Global.TARGET_FPS here as it can be changed by projects
local frameControl    = {
    lastFrameTime = 0,
    sleepPrecision = 0.0005 -- 0.5ms sleep precision like tick.lua
}

-- Override Love2D's error handler to use our error dialog system
-- This catches ALL uncaught errors in the entire application
-- IMPORTANT: Must be defined at module level, not inside love.load
function love.errorhandler(msg)
    msg = tostring(msg)

    -- Get stack trace
    local errorDetails = debug.traceback("", 2)

    -- Try to log the error with full stack trace (may fail if log module has issues)
    pcall(function()
        log.error("Uncaught error: %s\n%s", msg, errorDetails)
    end)

    -- Parse error message to extract file:line information
    local errorTitle = "Runtime Error"
    local errorMessage = msg

    -- Check if this is a compilation error
    if msg:match("compilation") or msg:match("Compilation") or msg:match("compiler") then
        errorTitle = "Compilation Error"
        -- errorMessage = "Failed to compile the project"
    end

    -- Show error dialog (globalErrorDialog is initialized in love.load)
    if globalErrorDialog then
        globalErrorDialog:show(errorTitle, errorMessage, errorDetails)
    end

    -- Return a minimal event loop to keep the window open
    -- This allows the error dialog to be visible and interactive
    return function()
        love.event.pump()

        for name, a in love.event.poll() do
            if name == "quit" then
                return 1
            elseif name == "keypressed" then
                -- Let error dialog handle keypresses
                if globalErrorDialog and globalErrorDialog:keypressed(a) then
                    -- If error dialog dismissed (ESC key), quit
                    if not globalErrorDialog.isVisible then
                        return 1
                    end
                end
            end
        end

        -- Draw the error dialog
        if love.graphics and love.graphics.isActive() then
            love.graphics.origin()
            love.graphics.clear(0.3, 0.3, 0.35)

            -- Apply transform if needed (for Android/Handheld Linux scaling)
            local needsTransform = (love.graphics.autoScale or 1) ~= 1 or
                (love.graphics.autoOffsetX or 0) ~= 0 or
                (love.graphics.autoOffsetY or 0) ~= 0

            if needsTransform then
                love.graphics.push()
                love.graphics.translate(love.graphics.autoOffsetX or 0, love.graphics.autoOffsetY or 0)
                love.graphics.scale(love.graphics.autoScale or 1, love.graphics.autoScale or 1)
            end

            if globalErrorDialog then
                globalErrorDialog:draw()
            end

            if needsTransform then
                love.graphics.pop()
            end

            love.graphics.present()
        end

        love.timer.sleep(0.01)
    end
end

---Clean up current runtime
local function cleanup()
    runtime = nil
    renderer = nil
    project = nil
    -- Also clean up loading state
    if loadingScreen and loadingScreen.isVisible then
        loadingScreen:hide()
    end
end

---Update rendering parameters after stage size changes
---This is needed when projects override Global.STAGE_WIDTH/HEIGHT
local function updateLetterboxParameters()
    if not windowConfig then
        log.warn("Window configuration not saved, cannot update letterbox parameters")
        return
    end
    if windowConfig.width == Global.STAGE_WIDTH and windowConfig.height == Global.STAGE_HEIGHT then
        -- No change in stage size, no need to update
        return
    end

    local os = love.system.getOS()
    if os == "Android" or Global.IS_HANDHELD_LINUX then
        -- Mobile/handheld: Update letterbox parameters for fullscreen scaling
        local screenWidth, screenHeight = love.graphics.getDimensions()

        -- Recalculate scaling using updated Global.STAGE_WIDTH/HEIGHT
        local scaleX = screenWidth / Global.STAGE_WIDTH
        local scaleY = screenHeight / Global.STAGE_HEIGHT
        local scale = math.min(scaleX, scaleY)

        -- Calculate offset to center the scaled content
        local scaledWidth = Global.STAGE_WIDTH * scale
        local scaledHeight = Global.STAGE_HEIGHT * scale
        local offsetX = (screenWidth - scaledWidth) / 2
        local offsetY = (screenHeight - scaledHeight) / 2

        -- Update global scaling parameters
        love.graphics.autoScale = scale
        love.graphics.autoOffsetX = offsetX
        love.graphics.autoOffsetY = offsetY
        love.graphics.autoScratchWidth = Global.STAGE_WIDTH
        love.graphics.autoScratchHeight = Global.STAGE_HEIGHT

        log.info("Updated letterbox: Stage=%dx%d, Screen=%dx%d, Scale=%.2f, Offset=(%.1f,%.1f)",
            Global.STAGE_WIDTH, Global.STAGE_HEIGHT, screenWidth, screenHeight, scale, offsetX, offsetY)

        -- Recreate stage canvas with new dimensions if letterbox is enabled
        if Global.LETTERBOX_BLUR_ENABLED and stageCanvas then
            local canvasSuccess, canvasErr = pcall(function()
                stageCanvas = love.graphics.newCanvas(Global.STAGE_WIDTH, Global.STAGE_HEIGHT, {
                    format = "normal",
                    readable = true,
                    msaa = 0,
                    dpiscale = 1
                })
                stageCanvas:setFilter("linear", "linear")
            end)

            if canvasSuccess then
                log.info("Stage canvas recreated with new dimensions: %dx%d", Global.STAGE_WIDTH, Global.STAGE_HEIGHT)
            else
                log.warn("Failed to recreate stage canvas: " .. tostring(canvasErr))
            end
        end
    else
        -- Desktop (Windows/macOS): Check if stage fits on screen, scale if needed
        local screenWidth, screenHeight = love.window.getDesktopDimensions()
        local targetStageWidth = Global.STAGE_WIDTH
        local targetStageHeight = Global.STAGE_HEIGHT

        -- Check if stage size exceeds screen size (with padding for window chrome and system UI)
        local paddingRatio = 0.8 -- Use 80% of screen to leave space for window decorations and menu bars
        local maxWindowWidth = screenWidth * paddingRatio
        local maxWindowHeight = screenHeight * paddingRatio

        if targetStageWidth > maxWindowWidth or targetStageHeight > maxWindowHeight then
            -- Stage exceeds screen, need to scale down
            local scaleX = maxWindowWidth / targetStageWidth
            local scaleY = maxWindowHeight / targetStageHeight
            local scale = math.min(scaleX, scaleY)

            -- Calculate scaled window size
            local windowWidth = math.floor(targetStageWidth * scale)
            local windowHeight = math.floor(targetStageHeight * scale)

            -- Center window on screen
            local windowX = math.floor((screenWidth - windowWidth) / 2)
            local windowY = math.floor((screenHeight - windowHeight) / 2)

            -- Create new flags with scaled size and center position
            local newFlags = {}
            for k, v in pairs(windowConfig.flags) do
                newFlags[k] = v
            end
            newFlags.x = windowX
            newFlags.y = windowY

            love.window.setMode(windowWidth, windowHeight, newFlags)

            -- Update saved config
            windowConfig.width = windowWidth
            windowConfig.height = windowHeight

            -- Set scaling parameters to render stage content at scaled size
            love.graphics.autoScale = scale
            love.graphics.autoOffsetX = 0
            love.graphics.autoOffsetY = 0
            love.graphics.autoScratchWidth = targetStageWidth
            love.graphics.autoScratchHeight = targetStageHeight

            log.info(
                "Desktop: Stage size (%dx%d) exceeds screen, scaled window to %dx%d (scale=%.2f) at position (%d,%d)",
                targetStageWidth, targetStageHeight, windowWidth, windowHeight, scale, windowX, windowY)
        else
            -- Stage fits on screen, use 1:1 window size
            local oldWidth = windowConfig.width
            local oldHeight = windowConfig.height

            -- Get current window position
            local x, y = love.window.getPosition()

            -- Calculate center-based position adjustment to keep window center in same location
            local newX = x + (oldWidth - targetStageWidth) / 2
            local newY = y + (oldHeight - targetStageHeight) / 2

            -- Create new flags table with updated position
            local newFlags = {}
            for k, v in pairs(windowConfig.flags) do
                newFlags[k] = v
            end
            newFlags.x = newX
            newFlags.y = newY

            love.window.setMode(targetStageWidth, targetStageHeight, newFlags)

            -- Update saved config
            windowConfig.width = targetStageWidth
            windowConfig.height = targetStageHeight

            log.info("Desktop: Resized window to match stage 1:1: %dx%d at position (%.0f,%.0f)",
                targetStageWidth, targetStageHeight, newX, newY)

            -- No scaling needed
            love.graphics.autoScale = 1
            love.graphics.autoOffsetX = 0
            love.graphics.autoOffsetY = 0
            love.graphics.autoScratchWidth = targetStageWidth
            love.graphics.autoScratchHeight = targetStageHeight
        end
    end
end

---Load project using the loading screen
---@param input string Path to sb3 file or project ID
local function loadProject(input)
    currentFilePath = input
    runtime = nil
    renderer = nil
    project = nil

    loadingScreen:loadProject(input, function(runtimeObj, rendererObj, projectObj)
        -- On successful load
        runtime = runtimeObj
        renderer = rendererObj
        project = projectObj

        -- Update letterbox parameters if stage size was changed by project
        updateLetterboxParameters()
    end, function(errorMessage)
        -- On error
        log.error("Failed to load project: " .. errorMessage)
        cleanup()
    end)
end

---Draw debug overlay (performance info and gamepad hints) in stage coordinate space
---This function should be called INSIDE the transform (push/pop/scale) block
local function drawDebugOverlay()
    -- Draw performance info (top-right corner)
    if Global.SHOW_PERFORMANCE_INFO then
        -- Use different color when profiler is active
        if JitProfiler.isActive() then
            love.graphics.setColor(1, 0.5, 0, 1) -- Orange color for profiler active
        else
            love.graphics.setColor(1, 0, 0, 1)   -- Red color for normal performance display
        end
        -- Use Love2D's built-in FPS calculation
        local fps = love.timer.getFPS()

        local info = {}
        if runtime then
            info = runtime:getPerformanceInfo()
        end
        -- Basic metrics for UI display
        local logicFps = math.floor((info.fps or 0) + 0.5)
        local logicMs = info.threadTime or 0 -- Thread processing time in milliseconds
        local profilerIndicator = JitProfiler.isActive() and " [PROF]" or ""
        local performanceText = string.format("D:%d L:%d LT:%.1fms T:%d%s", fps, logicFps, logicMs,
            info.activeThreads or 0,
            profilerIndicator)

        -- Detailed logging every 10 frames (faster for debugging) - ALWAYS log for debugging
        if runtime and runtime.frameCount > 0 and runtime.frameCount % Global.TARGET_FPS == 0 then
            local frameMs = performanceData.lastFrameDuration * 1000
            local maxFrameMs = performanceData.maxFrameDuration * 1000
            local longFrames = performanceData.longFrameCount
            local detail = string.format(
                "[PERF] DrawFPS=%d LogicFPS=%d Frame=%.2fms Max=%.2fms LongFrames=%d Threads=%d ThreadTime=%.2fms WorkRatio=%.0f%%",
                fps, logicFps, frameMs, maxFrameMs, longFrames, info.activeThreads or 0,
                (info.threadTime or 0), (info.threadTime or 0) / 1000 / Global.FRAME_TIME * 100)
            log.info(detail)
        end

        -- Draw in stage coordinate space (top-right corner)
        local textWidth = Global.cjkFont:getWidth(performanceText)
        love.graphics.print(performanceText, Global.cjkFont, Global.STAGE_WIDTH - textWidth - 10, 10)
    end

    -- Draw gamepad button mapping hint (bottom-center) for handheld Linux
    if Global.IS_HANDHELD_LINUX and runtime and runtime.gamepadManager then
        local mappingText = runtime.gamepadManager:getButtonMappingText()
        if mappingText then
            local textWidth = Global.cjkFont:getWidth(mappingText)
            local textHeight = Global.cjkFont:getHeight()
            local x = (Global.STAGE_WIDTH - textWidth) / 2  -- Center horizontally in stage space
            local y = Global.STAGE_HEIGHT - textHeight - 10 -- Bottom with 10px padding in stage space

            -- Draw blue text without background
            love.graphics.setColor(0.2, 0.6, 1, 1) -- Bright blue
            love.graphics.print(mappingText, Global.cjkFont, x, y)
        end
    end
end


---Create resvg options with preloaded Scratch fonts
---@return Options Configured options with Scratch fonts loaded
local function createResvgOptionsWithFonts()
    local options = resvg.Options.new()

    -- Scratch font mapping table
    local scratchFonts = {
        ["Sans Serif"] = "NotoSans-Medium.ttf",   -- fontName: Noto Sans
        ["Serif"] = "SourceSerifPro-Regular.otf", -- fontName: Source Serif Pro
        ["Handwriting"] = "handlee-regular.ttf",  -- fontName: Handlee
        ["Marker"] = "Knewave.ttf",               -- fontName: Knewave
        ["Curly"] = "Griffy-Regular.ttf",         -- fontName: Griffy
        ["Pixel"] = "Grand9K-Pixel.ttf",          -- fontName: Grand9K Pixel
        ["Scratch"] = "Scratch.ttf"               -- fontName: ScratchFont
    }

    -- Load all Scratch fonts to resvg
    for fontFamily, fontFile in pairs(scratchFonts) do
        local fontPath = "assets/fonts/" .. fontFile
        local fontData = love.filesystem.read(fontPath)

        if fontData then
            options:load_font_data(fontData)
            log.info("Loaded Scratch font: " .. fontFamily .. " (" .. fontFile .. ")")
        else
            log.warn("Failed to load Scratch font: " .. fontPath)
        end
    end


    -- Load system fonts first
    local os = love.system.getOS()

    -- Platform-specific CJK font loading
    -- On Android, fontdb's load_system_fonts() doesn't scan /system/fonts directory
    -- On other platforms, we manually load CJK fonts for accurate text width measurement
    local cjkSystemFonts = {}

    if os == "Android" then
        log.info("Loading Android system fonts from /system/fonts...")
        cjkSystemFonts = {
            { path = "/system/fonts/NotoSansCJK-Regular.ttc",  size = 14 }, -- CJK (Chinese, Japanese, Korean)
            { path = "/system/fonts/NotoSerifCJK-Regular.ttc", size = 14 }, -- CJK Serif
            { path = "/system/fonts/DroidSansFallback.ttf",    size = 14 }, -- Legacy CJK fallback (older Android)
        }
    elseif os == "Windows" then
        log.info("Loading Windows CJK fonts...")
        options:load_system_fonts()                                -- Load system fonts first
        cjkSystemFonts = {
            { path = "C:/Windows/Fonts/msyh.ttc",     size = 14 }, -- Microsoft YaHei (Simplified Chinese)
            { path = "C:/Windows/Fonts/msjh.ttc",     size = 14 }, -- Microsoft JhengHei (Traditional Chinese)
            { path = "C:/Windows/Fonts/msgothic.ttc", size = 14 }, -- MS Gothic (Japanese)
            { path = "C:/Windows/Fonts/malgun.ttf",   size = 14 }, -- Malgun Gothic (Korean)
            { path = "C:/Windows/Fonts/simsun.ttc",   size = 14 }, -- SimSun (Simplified Chinese, legacy)
        }
    elseif os == "OS X" then
        log.info("Loading macOS CJK fonts...")
        options:load_system_fonts()                                             -- Load system fonts first
        cjkSystemFonts = {
            { path = "/System/Library/Fonts/PingFang.ttc",         size = 14 }, -- PingFang (Modern macOS CJK, replaces STHeiti)
            { path = "/System/Library/Fonts/STHeiti Medium.ttc",   size = 14 }, -- STHeiti (Legacy Chinese)
            { path = "/System/Library/Fonts/Hiragino Sans GB.ttc", size = 14 }, -- Hiragino Sans GB (Chinese)
            { path = "/System/Library/Fonts/AppleSDGothicNeo.ttc", size = 14 }, -- Apple SD Gothic Neo (Korean)
        }
    elseif os == "Linux" then
        log.info("Loading Linux CJK fonts...")
        options:load_system_fonts()                                                            -- Load system fonts first
        cjkSystemFonts = {
            { path = "/usr/share/fonts/noto-cjk/NotoSansCJK-Regular.ttc",         size = 14 }, -- Arch Linux
            { path = "/usr/share/fonts/opentype/noto/NotoSansCJK-Regular.ttc",    size = 14 }, -- Debian/Ubuntu (opentype)
            { path = "/usr/share/fonts/truetype/noto/NotoSansCJK-Regular.ttc",    size = 14 }, -- Debian/Ubuntu (truetype)
            { path = "/usr/share/fonts/truetype/droid/DroidSansFallbackFull.ttf", size = 14 }, -- Legacy Droid Sans
            { path = "/usr/share/fonts/wenquanyi/wqy-microhei/wqy-microhei.ttc",  size = 14 }, -- WenQuanYi
            { path = "/usr/trimui/res/full.ttf",                                  size = 14 }, -- Trimui (Linux handheld devices)
        }
    else
        -- Unknown platform, just load system fonts
        options:load_system_fonts()
    end

    -- Try to load CJK fonts for text measurement
    if #cjkSystemFonts > 0 then
        for _, fontInfo in ipairs(cjkSystemFonts) do
            -- Try to load font for resvg
            local success, err = options:load_font_file(fontInfo.path)
            if success then
                log.info("Loaded CJK font for resvg: " .. fontInfo.path)

                -- Load this font for Love2D CJK text measurement
                -- Love2D cannot load from absolute paths directly, use Lua io to read file
                local fontSuccess, fontErr = pcall(function()
                    local file = io.open(fontInfo.path, "rb")
                    if file then
                        local data = file:read("*all")
                        file:close()
                        local fontData = love.filesystem.newFileData(data, "cjk_font.ttc")
                        Global.cjkFont = love.graphics.newFont(fontData, fontInfo.size)
                        Global.cjkFont:setFilter("linear", "linear")
                        Global.cjkFontPath = fontInfo.path

                        options:load_font_data(data) -- Also load into resvg options
                    else
                        error("Could not open font file: " .. fontInfo.path)
                    end
                end)

                if fontSuccess then
                    log.info("Set Global.cjkFont for CJK text measurement")
                else
                    log.debug("Could not load CJK font for Love2D: " .. tostring(fontErr))
                end

                -- Only load the first successful CJK font
                break
            else
                -- Don't warn if file doesn't exist (different OS versions have different fonts)
                log.debug("Could not load " .. fontInfo.path .. ": " .. tostring(err))
            end
        end

        if not Global.cjkFont then
            log.warn("No CJK font loaded, CJK text width measurement may be inaccurate")
        end
    end

    return options
end

---Love2D load callback
---@param arg string[] Command line arguments
function love.load(arg)
    -- Initialize random seed for proper randomization
    math.randomseed(os.time())

    -- Initialize frame control timing
    frameControl.lastFrameTime = love.timer.getTime()

    local os = love.system.getOS()

    if os == "Android" then
        -- Register SDL gamepad mapping for LÖVE Virtual Gamepad (Android)
        -- GUID format: vendor(4c56) + product(5647) + zeros
        -- This makes the virtual gamepad recognized as a standard gamepad
        local virtualGamepadMapping =
            "4c5600005647000000000000000000000," .. -- GUID
            "LÖVE Virtual Gamepad," ..              -- Name
            "a:b0," ..                              -- A button
            "b:b1," ..                              -- B button
            "x:b2," ..                              -- X button
            "y:b3," ..                              -- Y button
            "dpup:b11," ..                          -- D-pad up
            "dpdown:b12," ..                        -- D-pad down
            "dpleft:b13," ..                        -- D-pad left
            "dpright:b14," ..                       -- D-pad right
            "platform:Android"                      -- Platform

        love.joystick.loadGamepadMappings(virtualGamepadMapping)
        log.info("Registered LÖVE Virtual Gamepad mapping for Android")
    elseif Global.IS_HANDHELD_LINUX then
        -- Load SDL Game Controller Database for physical gamepads (Linux handheld devices)
        -- This database contains mappings for thousands of physical controllers
        -- Source: https://github.com/gabomdq/SDL_GameControllerDB
        local controllerDbPath = "assets/gamecontrollerdb.txt"
        local success, err = pcall(function()
            love.joystick.loadGamepadMappings(controllerDbPath)
        end)

        if success then
            log.info("Loaded physical gamepad mappings from %s", controllerDbPath)
        else
            log.warn("Failed to load gamepad mappings: %s", tostring(err))
        end
    end

    local scratchWidth = Global.STAGE_WIDTH
    local scratchHeight = Global.STAGE_HEIGHT
    if os == "Android" or Global.IS_HANDHELD_LINUX then
        -- On Android, force landscape orientation and scale to fit screen
        local screenWidth, screenHeight = love.graphics.getDimensions()

        -- Calculate scaling to fit Scratch content with maximum proportional scaling
        local scaleX = screenWidth / scratchWidth
        local scaleY = screenHeight / scratchHeight
        local scale = math.min(scaleX, scaleY)

        -- Calculate offset to center the scaled content
        local scaledWidth = scratchWidth * scale
        local scaledHeight = scratchHeight * scale
        local offsetX = (screenWidth - scaledWidth) / 2
        local offsetY = (screenHeight - scaledHeight) / 2

        -- Store scaling parameters globally
        love.graphics.autoScale = scale
        love.graphics.autoOffsetX = offsetX
        love.graphics.autoOffsetY = offsetY
        love.graphics.autoScratchWidth = scratchWidth
        love.graphics.autoScratchHeight = scratchHeight

        log.info("Landscape: Screen=%dx%d, Scratch=%dx%d, Scale=%.2f, Offset=(%.1f,%.1f)",
            screenWidth, screenHeight, scratchWidth, scratchHeight, scale, offsetX, offsetY)
    else
        -- On Windows and macOS, use the window size directly
        love.graphics.autoScale = 1
        love.graphics.autoOffsetX = 0
        love.graphics.autoOffsetY = 0
        love.graphics.autoScratchWidth = scratchWidth
        love.graphics.autoScratchHeight = scratchHeight
    end

    love.graphics.setDefaultFilter("linear", "linear")

    -- Calculate debug font size based on stage height (not screen height)
    -- This ensures debug text scales consistently with stage content
    -- Font will be rendered in stage coordinate space and scaled with autoScale
    local fontSize = math.max(12, math.floor(Global.STAGE_HEIGHT / 25 + 0.5))
    Global.cjkFont = love.graphics.newFont("assets/fonts/NotoSans-Medium.ttf", fontSize)
    Global.cjkFont:setFilter("linear", "linear")

    -- Calculate SVG resolution scale based on both DPI and window scaling
    -- This ensures SVG assets are rendered at sufficient resolution to avoid blur when scaled
    local dpiScale = love.graphics.getDPIScale()
    local autoScale = love.graphics.autoScale or 1
    local effectiveScale = dpiScale
    if not Global.IS_HANDHELD_LINUX then
        -- Limit scale to DPI only on Linux to prevent excessive VRAM usage from large scaling factors
        effectiveScale = math.max(dpiScale, autoScale)
    end
    Global.SVG_RESOLUTION_SCALE = math.max(1, math.floor(effectiveScale + 0.5)) -- Round to nearest integer
    log.info("Display DPI scale: %.2f, Auto scale: %.2f, SVG resolution scale: %d", dpiScale, autoScale,
        Global.SVG_RESOLUTION_SCALE)

    -- Load resvg options with fonts after UI font is created
    Global.resvgOptions = createResvgOptionsWithFonts()

    -- Create stage canvas for letterbox rendering (only on platforms with scaling and if enabled)
    if Global.LETTERBOX_BLUR_ENABLED and (os == "Android" or Global.IS_HANDHELD_LINUX) then
        log.info("Platform requires letterbox rendering: " .. os)

        local canvasSuccess, canvasErr = pcall(function()
            -- CRITICAL: Enable stencil support for UI elements (loading screen uses stencil)
            stageCanvas = love.graphics.newCanvas(Global.STAGE_WIDTH, Global.STAGE_HEIGHT, {
                format = "normal",
                readable = true,
                msaa = 0,
                dpiscale = 1 -- Use 1x scale, we handle DPI manually in shader
            })
            -- Use linear filtering for smooth texture sampling (required for blur optimization)
            stageCanvas:setFilter("linear", "linear")
        end)

        if canvasSuccess then
            log.info("Stage canvas created successfully (with stencil support)")
        else
            log.warn("Failed to create stage canvas: " .. tostring(canvasErr))
        end

        -- Load letterbox shader
        local success, shader = pcall(love.graphics.newShader, "renderer/shaders/letterbox.glsl")
        if success then
            letterboxShader = shader
            log.info("Letterbox shader loaded successfully")
        else
            log.warn("Could not load letterbox shader: " .. tostring(shader))
        end
    elseif not Global.LETTERBOX_BLUR_ENABLED then
        log.info("Letterbox blur disabled via Global.LETTERBOX_BLUR_ENABLED")
    end

    -- Initialize UI components
    loadingScreen = LoadingScreen:new()

    -- Initialize global error dialog (used by love.errorhandler)
    globalErrorDialog = ErrorDialog:new()

    -- Save window configuration
    local width, height, flags = love.window.getMode()
    windowConfig = {
        width = width,
        height = height,
        flags = flags
    }
    log.info("Saved window configuration: %dx%d", width, height)

    -- Print startup info
    log.info("=== ScratchLove ===")

    -- Check for compiler test mode
    if arg and arg[1] == "--test-compiler" then
        log.info("Running compiler integration test...")
        local testCompilerIntegration = require('test.test_compiler_integration')
        local success = testCompilerIntegration()
        love.event.quit(success and 0 or 1)
        return
    end

    -- Find sb3 file or project ID to load
    local input = loadingScreen:findProjectInput(arg)
    if input then
        loadProject(input)
    else
        log.info("No project loaded. Available options:")
        log.info("1. Place your .sb3 file in assets/ directory")
        log.info("2. Drag and drop an .sb3 file")
        log.info("3. Use: love . <path-to-sb3-file>")
        log.info("4. Use: love . <scratch-project-id>")
        log.info("")
        log.info("Examples:")
        log.info("  love . assets/project.sb3")
        log.info("  love . 1213794058")
        log.info("")
        log.info("Controls:")
        log.info("  Ctrl+R: Reload project")
        log.info("  Ctrl+D: Toggle debug mode")
        log.info("  Ctrl+P: Toggle performance info")
        log.info("  Ctrl+F: Toggle profiler")
    end
end

---Love2D update callback
---@param dt number Delta time in seconds
function love.update(dt)
    local updateStart = love.timer.getTime()

    -- Handle async loading
    if loadingScreen then
        loadingScreen:update()
    end

    -- Update runtime if it exists
    if runtime then
        runtime:update(dt)
    end

    -- Performance monitoring: Log extremely slow updates only
    local updateTime = (love.timer.getTime() - updateStart) * 1000
    if runtime and updateTime > 200 and runtime.frameCount % Global.TARGET_FPS == 0 then
        log.warn("[UPDATE] Extremely slow: %.2fms (dt=%.2fms)", updateTime, dt * 1000)
    end
end

---Love2D draw callback
function love.draw()
    -- Record frame start time for performance monitoring and FPS limiting
    local frameStart = love.timer.getTime()

    -- Calculate interpolation progress if enabled
    if runtime and runtime.interpolationEnabled then
        local Interpolate = require("vm.interpolate")
        local currentTime = love.timer.getTime() * 1000 -- Convert to milliseconds
        local elapsed = currentTime - runtime._lastStepTime
        local progress = math.min(1, elapsed / runtime.currentStepTime)
        Interpolate.interpolate(runtime, progress)
    end

    -- Update frame timing data (measure time BETWEEN draw calls, not draw duration)
    -- Use frameControl.lastFrameTime for consistency with frame rate limiting
    if frameControl.lastFrameTime > 0 then
        performanceData.lastFrameDuration = frameStart - frameControl.lastFrameTime
    end

    -- Clear with white (Scratch stage default color)
    -- Letterbox shader will handle fade to black for edge areas
    love.graphics.clear(1, 1, 1, 1)

    -- Apply scaling and offset transformation
    local needsTransform = love.graphics.autoScale ~= 1 or love.graphics.autoOffsetX ~= 0 or
        love.graphics.autoOffsetY ~= 0

    -- OPTIMIZED LETTERBOX RENDERING: Direct stage rendering + letterbox shader for edges only
    if needsTransform and letterboxShader and stageCanvas then
        -- CRITICAL: Clear any scissor test from previous frames
        love.graphics.setScissor()

        -- Step 1: Render stage content to small canvas (ONLY for edge sampling by shader)
        -- This canvas is ONLY used by letterbox shader to sample edge colors
        love.graphics.setCanvas({ stageCanvas, stencil = true })
        love.graphics.clear(1, 1, 1, 1)

        if renderer then
            renderer:draw()
        elseif loadingScreen and loadingScreen.isVisible then
            loadingScreen:draw()
        else
            -- Display help message
            love.graphics.setColor(0, 0, 0)
            love.graphics.printf(HELP_TEXT, Global.cjkFont, 0, Global.STAGE_HEIGHT / 2 - 80,
                Global.STAGE_WIDTH, "center")
        end

        love.graphics.setCanvas()

        -- Step 2: Draw stage content directly (no quality loss)
        love.graphics.push()
        love.graphics.translate(love.graphics.autoOffsetX, love.graphics.autoOffsetY)
        love.graphics.scale(love.graphics.autoScale, love.graphics.autoScale)

        if renderer then
            renderer:draw()
        elseif loadingScreen and loadingScreen.isVisible then
            loadingScreen:draw()
        else
            -- Display help message
            love.graphics.setColor(0, 0, 0)
            love.graphics.printf(HELP_TEXT, Global.cjkFont, 0, Global.STAGE_HEIGHT / 2 - 80,
                Global.STAGE_WIDTH, "center")
        end

        -- Draw debug overlay (performance info, gamepad hints) in stage space
        drawDebugOverlay()

        love.graphics.pop()

        -- Step 3: Draw letterbox areas ONLY (shader discards stage region)
        local screenW, screenH = love.graphics.getDimensions()
        local dpiScale = love.graphics.getDPIScale()
        local offsetX = love.graphics.autoOffsetX * dpiScale
        local offsetY = love.graphics.autoOffsetY * dpiScale
        local boundsW = Global.STAGE_WIDTH * love.graphics.autoScale * dpiScale
        local boundsH = Global.STAGE_HEIGHT * love.graphics.autoScale * dpiScale

        -- Physical screen pixel dimensions
        local screenPhysicalW = screenW * dpiScale
        local screenPhysicalH = screenH * dpiScale

        love.graphics.setShader(letterboxShader)
        letterboxShader:send("stageOffset", { offsetX, offsetY })
        letterboxShader:send("stageBounds", { boundsW, boundsH })
        letterboxShader:send("screenSize", { screenPhysicalW, screenPhysicalH })
        letterboxShader:send("stageSize", { Global.STAGE_WIDTH, Global.STAGE_HEIGHT })
        letterboxShader:send("stageTexture", stageCanvas)

        love.graphics.setColor(1, 1, 1, 1)
        love.graphics.rectangle("fill", 0, 0, screenW, screenH)
        love.graphics.setShader()
    elseif needsTransform then
        love.graphics.push()
        love.graphics.translate(love.graphics.autoOffsetX, love.graphics.autoOffsetY)
        love.graphics.scale(love.graphics.autoScale, love.graphics.autoScale)

        -- Set scissor to clip rendering to the scaled Scratch stage bounds
        local scissorX = love.graphics.autoOffsetX
        local scissorY = love.graphics.autoOffsetY
        local scissorW = Global.STAGE_WIDTH * love.graphics.autoScale
        local scissorH = Global.STAGE_HEIGHT * love.graphics.autoScale
        love.graphics.setScissor(scissorX, scissorY, scissorW, scissorH)

        -- Draw runtime or help message
        if renderer then
            renderer:draw()
        elseif loadingScreen and loadingScreen.isVisible then
            loadingScreen:draw()
        else
            -- Display help message
            love.graphics.setColor(0, 0, 0)
            love.graphics.printf(HELP_TEXT, Global.cjkFont, 0, love.graphics.autoScratchHeight / 2 - 80,
                love.graphics.autoScratchWidth,
                "center")
        end

        -- Draw debug overlay (performance info, gamepad hints) in stage space
        drawDebugOverlay()

        -- Clear scissor and pop transform
        love.graphics.setScissor()
        love.graphics.pop()
    else
        if renderer then
            renderer:draw()
        elseif loadingScreen and loadingScreen.isVisible then
            loadingScreen:draw()
        else
            -- Display help message
            love.graphics.setColor(0, 0, 0)
            love.graphics.printf(HELP_TEXT, Global.cjkFont, 0, Global.STAGE_HEIGHT / 2 - 80,
                Global.STAGE_WIDTH,
                "center")
        end

        -- Draw debug overlay (performance info, gamepad hints) in stage space
        drawDebugOverlay()
    end

    -- Update draw time monitoring data
    if performanceData.lastFrameDuration > performanceData.maxFrameDuration then
        performanceData.maxFrameDuration = performanceData.lastFrameDuration
    end
    if performanceData.lastFrameDuration > Global.FRAME_TIME then
        performanceData.longFrameCount = performanceData.longFrameCount + 1
    end

    -- Frame rate limiting logic
    -- INTERPOLATION ENABLED: Use RENDER_FPS for draw loop (0 = unlimited/screen refresh)
    -- INTERPOLATION DISABLED: Use TARGET_FPS for both logic and draw (to save CPU)
    local shouldLimitDrawFPS = Global.FPS_LIMIT_ENABLED
    local targetDrawFPS = Global.TARGET_FPS -- Default: same as logic FPS

    if runtime and runtime.interpolationEnabled then
        -- Interpolation mode: Use RENDER_FPS (0 = unlimited)
        if Global.RENDER_FPS > 0 then
            targetDrawFPS = Global.RENDER_FPS
        else
            shouldLimitDrawFPS = false -- Unlimited render FPS
        end
    end

    if shouldLimitDrawFPS and targetDrawFPS > 0 then
        local targetFrameTime = 1 / targetDrawFPS
        local currentTime = love.timer.getTime()
        local timeSinceLastFrame = currentTime - frameControl.lastFrameTime

        -- Safety check: reset if time difference is too large (>1 second)
        if timeSinceLastFrame > 1.0 then
            frameControl.lastFrameTime = currentTime - targetFrameTime
            timeSinceLastFrame = targetFrameTime
        end

        -- Busy-wait with micro sleeps for precision (like tick.lua line 64-66)
        while currentTime - frameControl.lastFrameTime < targetFrameTime do
            love.timer.sleep(frameControl.sleepPrecision)
            currentTime = love.timer.getTime()
        end

        -- Update lastFrameTime AFTER the wait completes (like tick.lua line 68)
        frameControl.lastFrameTime = currentTime
    else
        -- No frame limiting: update lastFrameTime to current frame start
        frameControl.lastFrameTime = frameStart
    end
end

---Love2D key press callback
---@param key string Key name
---@param scancode love.Scancode Scancode
---@param isrepeat boolean Whether key is repeating
function love.keypressed(key, scancode, isrepeat)
    -- Let global error dialog handle input first (highest priority)
    if globalErrorDialog and globalErrorDialog:keypressed(key) then
        return
    end

    -- Handle system keys
    if key == "escape" then
        love.event.quit()
        return
    end

    -- Handle control key combinations
    if love.keyboard.isDown("lctrl") then
        if key == "r" then
            -- Reload project
            if currentFilePath then
                log.info("Reloading project...")
                loadProject(currentFilePath)
            else
                log.warn("No current file path to reload")
            end
            return
        elseif key == "d" then
            -- Toggle debug mode
            Global.DEBUG_MODE = not Global.DEBUG_MODE
            log.info("Debug mode: " .. (Global.DEBUG_MODE and "ON" or "OFF"))
            return
        elseif key == "p" then
            -- Toggle performance info
            Global.SHOW_PERFORMANCE_INFO = not Global.SHOW_PERFORMANCE_INFO
            log.info("Performance info: " .. (Global.SHOW_PERFORMANCE_INFO and "ON" or "OFF"))
            return
        elseif key == "m" then
            -- Toggle monitor logging
            if runtime and runtime.monitorManager then
                local currentState = runtime.monitorManager.enableLogging
                runtime:setMonitorLogging(not currentState)
                log.info("Monitor logging: " .. (not currentState and "ON" or "OFF"))
            else
                log.warn("Monitor system not available")
            end
            return
        elseif key == "f" then
            -- Toggle LuaJIT profiler
            local newState = JitProfiler.toggle(30)
            if JitProfiler.isAvailable() then
                log.info("LuaJIT profiler " .. (newState and "started" or "stopped"))
            else
                log.warn("LuaJIT profiler not available")
            end
            return
        end
    end

    -- Only process initial key press, ignore key repeats (Scratch behavior)
    -- Forward to runtime
    if runtime and not isrepeat then
        runtime:onKeyPressed(key)
    end
end

---Love2D key release callback
---@param key string Key name
function love.keyreleased(key)
    if runtime then
        runtime:onKeyReleased(key)
    end
end

---Love2D mouse press callback
---@param x number Mouse X position
---@param y number Mouse Y position
---@param button number Mouse button
function love.mousepressed(x, y, button)
    if runtime then
        runtime:onMousePressed(x, y, button)
    end
end

---Love2D mouse release callback
---@param x number Mouse X position
---@param y number Mouse Y position
---@param button number Mouse button
function love.mousereleased(x, y, button)
    if runtime then
        runtime:onMouseReleased(x, y, button)
    end
end

---Love2D mouse move callback
---@param x number Mouse X position
---@param y number Mouse Y position
---@param dx number X movement delta
---@param dy number Y movement delta
function love.mousemoved(x, y, dx, dy)
    if runtime then
        runtime:onMouseMoved(x, y)
    end
end

-- Handle file drops
---Love2D joystick added callback
---@param joystick love.Joystick The joystick that was added
function love.joystickadded(joystick)
    if runtime then
        runtime:onJoystickAdded(joystick)
    end
end

---Love2D joystick removed callback
---@param joystick love.Joystick The joystick that was removed
function love.joystickremoved(joystick)
    if runtime then
        runtime:onJoystickRemoved(joystick)
    end
end

---Love2D gamepad button pressed callback
---@param joystick love.Joystick The joystick that fired the event
---@param button love.GamepadButton The button that was pressed ("a", "b", etc.)
function love.gamepadpressed(joystick, button)
    log.info("Gamepad button pressed: " .. tostring(button))
    if Global.IS_HANDHELD_LINUX and button == "back" then
        gamepadBackButtonPressTime = love.timer.getTime()
        log.info("Gamepad Back button pressed at %.3f, tracking hold time...", gamepadBackButtonPressTime)
    end

    if runtime then
        runtime:onGamepadButtonPressed(joystick, button)
    end
end

---Love2D gamepad button released callback
---@param joystick love.Joystick The joystick that fired the event
---@param button love.GamepadButton The button that was released ("a", "b", etc.)
function love.gamepadreleased(joystick, button)
    if Global.IS_HANDHELD_LINUX and button == "back" then
        if gamepadBackButtonPressTime then
            local holdDuration = love.timer.getTime() - gamepadBackButtonPressTime
            if holdDuration >= GAMEPAD_BACK_EXIT_DURATION then
                log.info("Gamepad Back button held for %.1f seconds, exiting...", holdDuration)
                love.event.quit()
            end
        end
        gamepadBackButtonPressTime = nil
    end

    if runtime then
        runtime:onGamepadButtonReleased(joystick, button)
    end
end

---Love2D file drop callback
---@param file love.DroppedFile Dropped file
function love.filedropped(file)
    local filename = file:getFilename()
    if filename:match("%.sb3$") then
        loadProject(filename)
    else
        log.warn("Please drop a .sb3 file (received: " .. filename .. ")")
    end
end

---Love2D quit callback - save cloud variables before exit
---@return boolean shouldQuit Always returns false to allow quit
function love.quit()
    -- Flush all cloud variables to persistent storage
    if runtime and runtime.cloudStorage then
        local success = runtime.cloudStorage:flush()
        if success then
            log.info("Cloud variables saved on quit")
        else
            log.warn("Failed to save cloud variables on quit")
        end
    end

    -- Allow quit to proceed
    return false
end

function love.resize(w, h)
    log.info("Window resized to: " .. w .. "x" .. h)
    updateLetterboxParameters()
end
