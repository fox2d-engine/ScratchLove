-- Sensing Blocks Module
-- Implements all sensing-related Scratch blocks

local Core = require("tests.sb3_builder.core")

local Sensing = {}

-- ===== COLLISION DETECTION =====

---Create "touching object" block
---@param object string Object name ("_mouse_", "_edge_", or sprite name)
---@return string id, SB3Builder.Block block
function Sensing.touchingObject(object)
    return Core.createBlock("sensing_touchingobject", {
        TOUCHINGOBJECTMENU = object
    })
end

---Create "touching color" block
---@param color string Color in hex format (#RRGGBB)
---@return string id, SB3Builder.Block block
function Sensing.touchingColor(color)
    return Core.createBlock("sensing_touchingcolor", {
        COLOR = Core.primitiveInput(color, Core.COLOR_PICKER_PRIMITIVE)
    })
end

---Create "color is touching color" block
---@param color1 string First color in hex format
---@param color2 string Second color in hex format
---@return string id, SB3Builder.Block block
function Sensing.colorIsTouchingColor(color1, color2)
    return Core.createBlock("sensing_coloristouchingcolor", {
        COLOR = Core.primitiveInput(color1, Core.COLOR_PICKER_PRIMITIVE),
        COLOR2 = Core.primitiveInput(color2, Core.COLOR_PICKER_PRIMITIVE)
    })
end

---Create "distance to" block
---@param target string Target ("_mouse_" or sprite name)
---@return string id, SB3Builder.Block block
function Sensing.distanceTo(target)
    return Core.createBlock("sensing_distanceto", {
        DISTANCETOMENU = target
    })
end

-- ===== USER INPUT =====

---Create "ask and wait" block
---@param question any Question to ask
---@return string id, SB3Builder.Block block
function Sensing.askAndWait(question)
    return Core.createBlock("sensing_askandwait", {
        QUESTION = question
    })
end

---Create "answer" reporter block
---@return string id, SB3Builder.Block block
function Sensing.answer()
    return Core.createBlock("sensing_answer")
end

-- ===== MOUSE AND KEYBOARD =====

---Create "key pressed" block
---@param key string Key name ("space", "a", "any", etc.)
---@return string id, SB3Builder.Block block
function Sensing.keyPressed(key)
    return Core.createBlock("sensing_keypressed", {
        KEY_OPTION = key
    })
end

---Create "mouse down" reporter block
---@return string id, SB3Builder.Block block
function Sensing.mouseDown()
    return Core.createBlock("sensing_mousedown")
end

---Create "mouse x" reporter block
---@return string id, SB3Builder.Block block
function Sensing.mouseX()
    return Core.createBlock("sensing_mousex")
end

---Create "mouse y" reporter block
---@return string id, SB3Builder.Block block
function Sensing.mouseY()
    return Core.createBlock("sensing_mousey")
end

---Create "set drag mode" block
---@param dragMode string "draggable" or "not draggable"
---@return string id, SB3Builder.Block block
function Sensing.setDragMode(dragMode)
    return Core.createBlock("sensing_setdragmode", {}, {
        DRAG_MODE = Core.field(dragMode)
    })
end

-- ===== AUDIO =====

---Create "loudness" reporter block
---@return string id, SB3Builder.Block block
function Sensing.loudness()
    return Core.createBlock("sensing_loudness")
end

-- ===== TIME =====

---Create "timer" reporter block
---@return string id, SB3Builder.Block block
function Sensing.timer()
    return Core.createBlock("sensing_timer")
end

---Create "reset timer" block
---@return string id, SB3Builder.Block block
function Sensing.resetTimer()
    return Core.createBlock("sensing_resettimer")
end

-- ===== SPRITE PROPERTIES =====

---Create "of" block (get property of sprite)
---@param property string Property to get ("x position", "y position", "direction", "costume #", "costume name", "size", "volume", "backdrop #", "backdrop name")
---@param object string Object to get property from
---@return string id, SB3Builder.Block block
function Sensing.of(property, object)
    return Core.createBlock("sensing_of", {
        OBJECT = object
    }, {
        PROPERTY = Core.field(property)
    })
end

-- ===== DATE AND TIME =====

---Create "current" block (date/time info)
---@param currentMenu string What to get ("YEAR", "MONTH", "DATE", "DAYOFWEEK", "HOUR", "MINUTE", "SECOND")
---@return string id, SB3Builder.Block block
function Sensing.current(currentMenu)
    return Core.createBlock("sensing_current", {}, {
        CURRENTMENU = Core.field(currentMenu)
    })
end

---Create "days since 2000" reporter block
---@return string id, SB3Builder.Block block
function Sensing.daysSince2000()
    return Core.createBlock("sensing_dayssince2000")
end

-- ===== USER INFO =====

---Create "username" reporter block
---@return string id, SB3Builder.Block block
function Sensing.username()
    return Core.createBlock("sensing_username")
end

-- ===== CONVENIENCE FUNCTIONS =====

-- Common property getters
---Get x position of sprite
---@param sprite string Sprite name
---@return string id, SB3Builder.Block block
function Sensing.xPositionOf(sprite)
    return Sensing.of("x position", sprite)
end

---Get y position of sprite
---@param sprite string Sprite name
---@return string id, SB3Builder.Block block
function Sensing.yPositionOf(sprite)
    return Sensing.of("y position", sprite)
end

---Get direction of sprite
---@param sprite string Sprite name
---@return string id, SB3Builder.Block block
function Sensing.directionOf(sprite)
    return Sensing.of("direction", sprite)
end

---Get size of sprite
---@param sprite string Sprite name
---@return string id, SB3Builder.Block block
function Sensing.sizeOf(sprite)
    return Sensing.of("size", sprite)
end

-- Common time getters
---Get current year
---@return string id, SB3Builder.Block block
function Sensing.currentYear()
    return Sensing.current("YEAR")
end

---Get current month
---@return string id, SB3Builder.Block block
function Sensing.currentMonth()
    return Sensing.current("MONTH")
end

---Get current day
---@return string id, SB3Builder.Block block
function Sensing.currentDate()
    return Sensing.current("DATE")
end

---Get current hour
---@return string id, SB3Builder.Block block
function Sensing.currentHour()
    return Sensing.current("HOUR")
end

---Get current minute
---@return string id, SB3Builder.Block block
function Sensing.currentMinute()
    return Sensing.current("MINUTE")
end

---Get current second
---@return string id, SB3Builder.Block block
function Sensing.currentSecond()
    return Sensing.current("SECOND")
end

return Sensing