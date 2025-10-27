-- Global Configuration for SB3 Love2D Runtime
-- Controls runtime settings and global configuration
---@class Global
---@field DEBUG_MODE boolean Debug mode toggle
---@field SHOW_PERFORMANCE_INFO boolean Performance info display toggle
---@field TARGET_FPS number Target logic frame rate (can be overridden by projects)
---@field RENDER_FPS number Target render frame rate (0 = unlimited, uses screen refresh rate)
---@field FRAME_TIME number Time per logic frame in seconds
---@field WORK_TIME_RATIO number Script execution time ratio (75% of frame time)
---@field FPS_LIMIT_ENABLED boolean FPS limiting toggle
---@field INTERPOLATION_ENABLED boolean Frame interpolation toggle
---@field STAGE_WIDTH number Stage width in pixels
---@field STAGE_HEIGHT number Stage height in pixels
---@field STAGE_HALF_WIDTH number Half of stage width
---@field STAGE_HALF_HEIGHT number Half of stage height
---@field SCRATCH_MIN_X number Minimum Scratch X coordinate
---@field SCRATCH_MAX_X number Maximum Scratch X coordinate
---@field SCRATCH_MIN_Y number Minimum Scratch Y coordinate
---@field SCRATCH_MAX_Y number Maximum Scratch Y coordinate
---@field SVG_RESOLUTION_SCALE number SVG rasterization scale factor
---@field FENCING_ENABLED boolean Sprite fencing toggle
---@field FENCE_WIDTH number Minimum pixels required to be onscreen
---@field GAMEPAD_SWAP_AB boolean Swap A and B button functions
---@field GAMEPAD_SWAP_XY boolean Swap X and Y button functions
---@field LETTERBOX_BLUR_ENABLED boolean Letterbox edge blur toggle
---@field COLLISION_SAMPLING_STEP number Collision detection sampling step
---@field COLLISION_CPU_THRESHOLD number Pixel threshold for GPU fallback
---@field COLLISION_ALPHA_THRESHOLD number Alpha threshold for collision
---@field COLLISION_LOW_PRECISION boolean Use low precision collision detection
---@field currentProject any Current project reference
---@field notoFont love.Font Noto Sans font
---@field cjkFont love.Font|nil CJK font
---@field resvgOptions Options|nil RESVG options
local Global = {}
local log = require("lib.log")

-- Debug and Performance Settings
Global.DEBUG_MODE = true
Global.SHOW_PERFORMANCE_INFO = false

-- Frame Rate and Timing (Scratch VM Compatibility)
Global.TARGET_FPS = 30                    -- Target logic frame rate (matches Scratch VM, can be overridden by projects)
Global.RENDER_FPS = 0                     -- Target render frame rate (0 = unlimited/screen refresh rate, typically 60 FPS)
Global.FRAME_TIME = 1 / Global.TARGET_FPS -- Time per logic frame in seconds
Global.WORK_TIME_RATIO = 0.75             -- 75% of frame time for script execution (matches Scratch VM)
Global.FPS_LIMIT_ENABLED = true           -- Enable FPS limiting to reduce CPU usage (only when interpolation disabled)

-- Interpolation (Frame Smoothing)
-- When enabled: Logic runs at TARGET_FPS, rendering runs at RENDER_FPS (or screen refresh rate if RENDER_FPS=0)
-- When disabled: Both logic and rendering run at TARGET_FPS (to save CPU)
Global.INTERPOLATION_ENABLED = false -- Enable frame interpolation for smoother rendering (2x perceived smoothness)

---Set target frame rate and recalculate frame time
---@param fps number Target frames per second (1-250)
function Global.setFramerate(fps)
    -- Clamp framerate to valid range (1-250 FPS)
    fps = math.max(1, math.min(250, fps))
    Global.TARGET_FPS = fps
    Global.FRAME_TIME = 1 / fps
    log.info("Global: Set framerate to %d FPS (frame time: %.4fs)", fps, Global.FRAME_TIME)
end

-- Stage Dimensions and Coordinate System (can be overridden by projects)
Global.STAGE_WIDTH = 480
Global.STAGE_HEIGHT = 360
Global.STAGE_HALF_WIDTH = Global.STAGE_WIDTH / 2
Global.STAGE_HALF_HEIGHT = Global.STAGE_HEIGHT / 2
Global.SCRATCH_MIN_X = -Global.STAGE_HALF_WIDTH
Global.SCRATCH_MAX_X = Global.STAGE_HALF_WIDTH
Global.SCRATCH_MIN_Y = -Global.STAGE_HALF_HEIGHT
Global.SCRATCH_MAX_Y = Global.STAGE_HALF_HEIGHT
Global.SVG_RESOLUTION_SCALE = 2 -- SVG rasterization scale factor, adjusted based on DPI in main.lua

---Set stage dimensions and recalculate coordinate bounds
---@param width number Stage width in pixels
---@param height number Stage height in pixels
function Global.setStageSize(width, height)
    Global.STAGE_WIDTH = width
    Global.STAGE_HEIGHT = height
    Global.STAGE_HALF_WIDTH = width / 2
    Global.STAGE_HALF_HEIGHT = height / 2
    Global.SCRATCH_MIN_X = -Global.STAGE_HALF_WIDTH
    Global.SCRATCH_MAX_X = Global.STAGE_HALF_WIDTH
    Global.SCRATCH_MIN_Y = -Global.STAGE_HALF_HEIGHT
    Global.SCRATCH_MAX_Y = Global.STAGE_HALF_HEIGHT
    log.info("Global: Set stage size to %dx%d (Scratch bounds: X[%.1f,%.1f] Y[%.1f,%.1f])",
        width, height,
        Global.SCRATCH_MIN_X, Global.SCRATCH_MAX_X,
        Global.SCRATCH_MIN_Y, Global.SCRATCH_MAX_Y)
end

-- Runtime Options
Global.FENCING_ENABLED = true -- Keep sprites within stage bounds (native Scratch behavior)
Global.FENCE_WIDTH = 15       -- Minimum pixels required to be onscreen (native Scratch value)

-- Gamepad Button Swapping (Linux handheld devices)
-- Some handheld devices have non-standard button layouts where A/B or X/Y are physically swapped
-- Enable these options to swap the button functions to match the physical layout
Global.GAMEPAD_SWAP_AB = false -- Swap A and B button functions (mainly for Switch-like layouts)
Global.GAMEPAD_SWAP_XY = false -- Swap X and Y button functions (mainly for Switch-like layouts)

-- Letterbox Rendering (Android/Linux scaling)
Global.LETTERBOX_BLUR_ENABLED = true -- Enable edge blur effect for letterbox areas (GPU-based)

-- Collision Detection Configuration
Global.COLLISION_SAMPLING_STEP = 2     -- 1=every pixel, 2=every 2nd pixel
Global.COLLISION_CPU_THRESHOLD = 40000 -- Pixel threshold for GPU fallback
Global.COLLISION_ALPHA_THRESHOLD = 25  -- 0-255 range
Global.COLLISION_LOW_PRECISION = false -- Use low precision collision detection (step=2 sampling), enabled by default on Linux

-- Runtime State
Global.currentProject = nil

---@type love.Font
Global.notoFont = nil
---@type love.Font|nil
Global.cjkFont = nil
---@type Options
Global.resvgOptions = nil

---Print current configuration
function Global.printConfig()
    log.info("=== Global Configuration ===")
    log.info("Debug Mode: " .. tostring(Global.DEBUG_MODE))
    log.info("Show Performance Info: " .. tostring(Global.SHOW_PERFORMANCE_INFO))
    log.info("Current Project: " .. tostring(Global.currentProject))
    log.info("=============================")
end

return Global
