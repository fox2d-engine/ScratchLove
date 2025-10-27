local IS_DEBUG = arg[3] == "--debug"
if IS_DEBUG then
    print("Debug mode enabled...")
    require("lldebugger").start()

    function love.errorhandler(msg)
        error(msg, 2)
    end
end

-- Love2D configuration file
local Global = require("global")

---Love2D configuration callback
---@param t table Configuration table
function love.conf(t)
    t.identity           = "scratchlove"
    t.version            = "11.4"
    t.console            = true

    t.window.title       = "ScratchLove"
    t.window.width       = Global.STAGE_WIDTH
    t.window.height      = Global.STAGE_HEIGHT
    t.window.highdpi     = true
    t.window.usedpiscale = true
    t.window.vsync       = 1

    t.modules.audio      = true
    t.modules.data       = true
    t.modules.event      = true
    t.modules.font       = true
    t.modules.graphics   = true
    t.modules.image      = true
    t.modules.joystick   = true
    t.modules.keyboard   = true
    t.modules.math       = true
    t.modules.mouse      = true
    t.modules.physics    = true
    t.modules.sound      = true
    t.modules.system     = true
    t.modules.thread     = true
    t.modules.timer      = true
    t.modules.touch      = true
    t.modules.video      = true
    t.modules.window     = true
end
