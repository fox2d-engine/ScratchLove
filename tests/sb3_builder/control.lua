-- Control Blocks Module
-- Implements all control flow blocks (loops, conditionals, waits, etc.)

local Core = require("tests.sb3_builder.core")

local Control = {}

-- ===== WAIT BLOCKS =====

---Create "wait seconds" block
---@param duration number|string|nil Duration in seconds
---@return string id, SB3Builder.Block block
function Control.wait(duration)
    return Core.createBlock("control_wait", {
        DURATION = duration
    })
end

---Create "wait until" block
---@param conditionId string|nil Block ID for condition
---@return string id, SB3Builder.Block block
function Control.waitUntil(conditionId)
    return Core.createBlock("control_wait_until", {
        CONDITION = conditionId
    })
end

-- ===== LOOP BLOCKS =====

---Create "repeat" block
---@param times number|string|nil Number of times to repeat
---@param substackId string|nil First block ID in substack
---@return string id, SB3Builder.Block block
function Control.repeat_(times, substackId)
    return Core.createBlock("control_repeat", {
        TIMES = times,
        SUBSTACK = substackId and Core.substackInput(substackId) or nil
    })
end

---Create "forever" block
---@param substackId string|nil First block ID in substack
---@return string id, SB3Builder.Block block
function Control.forever(substackId)
    return Core.createBlock("control_forever", {
        SUBSTACK = substackId and Core.substackInput(substackId) or nil
    })
end

---Create "repeat until" block
---@param conditionId string|nil Block ID for condition
---@param substackId string|nil First block ID in substack
---@return string id, SB3Builder.Block block
function Control.repeatUntil(conditionId, substackId)
    return Core.createBlock("control_repeat_until", {
        CONDITION = conditionId,
        SUBSTACK = substackId and Core.substackInput(substackId) or nil
    })
end

---Create "while" block (unofficial, for testing)
---@param conditionId string|nil Block ID for condition
---@param substackId string|nil First block ID in substack
---@return string id, SB3Builder.Block block
function Control.repeatWhile(conditionId, substackId)
    return Core.createBlock("control_while", {
        CONDITION = conditionId,
        SUBSTACK = substackId and Core.substackInput(substackId) or nil
    })
end

-- ===== CONDITIONAL BLOCKS =====

---Create "if" block
---@param conditionId string|nil Block ID for condition
---@param substackId string|nil First block ID in substack
---@return string id, SB3Builder.Block block
function Control.if_(conditionId, substackId)
    return Core.createBlock("control_if", {
        CONDITION = conditionId,
        SUBSTACK = substackId and Core.substackInput(substackId) or nil
    })
end

---Create "if else" block
---@param conditionId string|nil Block ID for condition
---@param substackId string|nil First block ID in if substack
---@param substack2Id string|nil First block ID in else substack
---@return string id, SB3Builder.Block block
function Control.ifElse(conditionId, substackId, substack2Id)
    return Core.createBlock("control_if_else", {
        CONDITION = conditionId,
        SUBSTACK = substackId and Core.substackInput(substackId) or nil,
        SUBSTACK2 = substack2Id and Core.substackInput(substack2Id) or nil
    })
end

-- ===== STOP BLOCKS =====

---Create "stop" block
---@param stopOption string Stop option ("all", "this script", "other scripts in sprite")
---@return string id, SB3Builder.Block block
function Control.stop(stopOption)
    stopOption = stopOption or "all"
    return Core.createBlock("control_stop", {}, {
        STOP_OPTION = Core.field(stopOption)
    })
end

-- ===== CLONE BLOCKS =====

---Create "when I start as a clone" hat block
---@param x number|nil X position
---@param y number|nil Y position
---@return string id, SB3Builder.Block block
function Control.whenStartAsClone(x, y)
    return Core.createBlock("control_start_as_clone", {}, {}, {
        topLevel = true,
        x = x,
        y = y
    })
end

---Create "create clone of" block
---@param target string Target sprite ("_myself_" or sprite name)
---@return string cloneId, SB3Builder.Block cloneBlock, string menuId, SB3Builder.Block menuBlock
function Control.createCloneOf(target)
    -- Create the menu shadow block
    local menuId, menuBlock = Core.createBlock("control_create_clone_of_menu", {}, {
        CLONE_OPTION = Core.field(target)
    }, { shadow = true })

    -- Create the main block with menu as input
    local cloneId, cloneBlock = Core.createBlock("control_create_clone_of", {
        CLONE_OPTION = Core.blockInput(menuId)
    })

    return cloneId, cloneBlock, menuId, menuBlock
end

---Create "delete this clone" block
---@return string id, SB3Builder.Block block
function Control.deleteThisClone()
    return Core.createBlock("control_delete_this_clone")
end

-- ===== MISC BLOCKS =====

---Create "all at once" block (unofficial, for testing)
---@param substackId string|nil First block ID in substack
---@return string id, SB3Builder.Block block
function Control.allAtOnce(substackId)
    return Core.createBlock("control_all_at_once", {
        SUBSTACK = substackId and Core.substackInput(substackId) or nil
    })
end


-- ===== CONVENIENCE ALIASES =====

-- Alias for better readability
Control.repeatTimes = Control.repeat_
Control.ifCondition = Control.if_

-- Convenience functions for common stop options
---Create "stop all" block
---@return string id, SB3Builder.Block block
function Control.stopAll()
    return Control.stop("all")
end

---Create "stop this script" block
---@return string id, SB3Builder.Block block
function Control.stopThisScript()
    return Control.stop("this script")
end

---Create "stop other scripts in sprite" block
---@return string id, SB3Builder.Block block
function Control.stopOtherScriptsInSprite()
    return Control.stop("other scripts in sprite")
end

---Create "stop other scripts in stage" block
---@return string id, SB3Builder.Block block
function Control.stopOtherScriptsInStage()
    return Control.stop("other scripts in stage")
end


return Control
