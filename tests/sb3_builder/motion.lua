-- Motion Blocks Module
-- Implements all motion-related Scratch blocks

local Core = require("tests.sb3_builder.core")

local Motion = {}

-- ===== BASIC MOVEMENT =====

---Create "move steps" block
---@param steps number|string|nil Number of steps to move
---@return string id, SB3Builder.Block block
function Motion.moveSteps(steps)
    return Core.createBlock("motion_movesteps", {
        STEPS = steps
    })
end

---Create "turn right" block  
---@param degrees number|string|nil Degrees to turn right
---@return string id, SB3Builder.Block block
function Motion.turnRight(degrees)
    return Core.createBlock("motion_turnright", {
        DEGREES = degrees
    })
end

---Create "turn left" block
---@param degrees number|string|nil Degrees to turn left
---@return string id, SB3Builder.Block block
function Motion.turnLeft(degrees)
    return Core.createBlock("motion_turnleft", {
        DEGREES = degrees
    })
end

-- ===== POSITIONING =====

---Create "go to x y" block
---@param x number|string|nil X coordinate
---@param y number|string|nil Y coordinate
---@return string id, SB3Builder.Block block
function Motion.goToXY(x, y)
    return Core.createBlock("motion_gotoxy", {
        X = x,
        Y = y
    })
end

---Create "go to target" block (sprite, mouse, random position)
---@param target string Target ("_mouse_", "_random_", or sprite name)
---@return string id, SB3Builder.Block block
function Motion.goTo(target)
    return Core.createBlock("motion_goto", {
        TO = target
    })
end

---Create "glide to x y" block
---@param secs number|string|nil Duration in seconds
---@param x number|string|nil Target X coordinate
---@param y number|string|nil Target Y coordinate
---@return string id, SB3Builder.Block block
function Motion.glideToXY(secs, x, y)
    return Core.createBlock("motion_glidesecstoxy", {
        SECS = secs,
        X = x,
        Y = y
    })
end

---Create "glide to target" block
---@param secs number|string|nil Duration in seconds
---@param target string Target ("_mouse_", "_random_", or sprite name)
---@return string id, SB3Builder.Block block
function Motion.glideTo(secs, target)
    return Core.createBlock("motion_glideto", {
        SECS = secs,
        TO = target
    })
end

-- ===== DIRECTION =====

---Create "point in direction" block
---@param direction number|string|nil Direction in degrees
---@return string id, SB3Builder.Block block
function Motion.pointInDirection(direction)
    return Core.createBlock("motion_pointindirection", {
        DIRECTION = direction
    })
end

---Create "point towards" block
---@param towards string Target ("_mouse_", "_random_", or sprite name)
---@return string id, SB3Builder.Block block
function Motion.pointTowards(towards)
    return Core.createBlock("motion_pointtowards", {
        TOWARDS = towards
    })
end

-- ===== COORDINATE CHANGES =====

---Create "change x by" block
---@param dx number|string|nil Change in X coordinate
---@return string id, SB3Builder.Block block
function Motion.changeXBy(dx)
    return Core.createBlock("motion_changexby", {
        DX = dx
    })
end

---Create "set x to" block
---@param x number|string|nil X coordinate
---@return string id, SB3Builder.Block block
function Motion.setX(x)
    return Core.createBlock("motion_setx", {
        X = x
    })
end

---Create "change y by" block
---@param dy number|string|nil Change in Y coordinate
---@return string id, SB3Builder.Block block
function Motion.changeYBy(dy)
    return Core.createBlock("motion_changeyby", {
        DY = dy
    })
end

---Create "set y to" block
---@param y number|string|nil Y coordinate
---@return string id, SB3Builder.Block block
function Motion.setY(y)
    return Core.createBlock("motion_sety", {
        Y = y
    })
end

-- ===== EDGE DETECTION =====

---Create "if on edge, bounce" block
---@return string id, SB3Builder.Block block
function Motion.ifOnEdgeBounce()
    return Core.createBlock("motion_ifonedgebounce")
end

-- ===== ROTATION STYLE =====

---Create "set rotation style" block
---@param style string Rotation style ("all around", "left-right", "don't rotate")
---@return string id, SB3Builder.Block block
function Motion.setRotationStyle(style)
    return Core.createBlock("motion_setrotationstyle", {}, {
        STYLE = Core.field(style)
    })
end

-- ===== REPORTER BLOCKS =====

---Create "x position" reporter block
---@return string id, SB3Builder.Block block
function Motion.xPosition()
    return Core.createBlock("motion_xposition")
end

---Create "y position" reporter block
---@return string id, SB3Builder.Block block
function Motion.yPosition()
    return Core.createBlock("motion_yposition")
end

---Create "direction" reporter block
---@return string id, SB3Builder.Block block
function Motion.direction()
    return Core.createBlock("motion_direction")
end

return Motion