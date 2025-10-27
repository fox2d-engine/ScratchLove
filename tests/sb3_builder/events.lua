-- Event Blocks Module
-- Implements all event-related Scratch blocks (hat blocks and broadcast blocks)

local Core = require("tests.sb3_builder.core")

local Events = {}

-- ===== HAT BLOCKS =====

---Create "when flag clicked" hat block
---@param x number|nil X position
---@param y number|nil Y position
---@return string id, SB3Builder.Block block
function Events.whenFlagClicked(x, y)
    return Core.createBlock("event_whenflagclicked", {}, {}, {
        topLevel = true,
        x = x,
        y = y
    })
end

---Create "when key pressed" hat block
---@param key string Key name ("space", "a", "any", etc.)
---@param x number|nil X position
---@param y number|nil Y position
---@return string id, SB3Builder.Block block
function Events.whenKeyPressed(key, x, y)
    return Core.createBlock("event_whenkeypressed", {}, {
        KEY_OPTION = Core.field(key)
    }, {
        topLevel = true,
        x = x,
        y = y
    })
end

---Create "when this sprite clicked" hat block
---@param x number|nil X position
---@param y number|nil Y position
---@return string id, SB3Builder.Block block
function Events.whenThisSpriteClicked(x, y)
    return Core.createBlock("event_whenthisspriteclicked", {}, {}, {
        topLevel = true,
        x = x,
        y = y
    })
end

---Create "when stage clicked" hat block
---@param x number|nil X position
---@param y number|nil Y position
---@return string id, SB3Builder.Block block
function Events.whenStageClicked(x, y)
    return Core.createBlock("event_whenstageclicked", {}, {}, {
        topLevel = true,
        x = x,
        y = y
    })
end

---Create "when backdrop switches to" hat block
---@param backdrop string Backdrop name
---@param x number|nil X position
---@param y number|nil Y position
---@return string id, SB3Builder.Block block
function Events.whenBackdropSwitchesTo(backdrop, x, y)
    return Core.createBlock("event_whenbackdropswitchesto", {}, {
        BACKDROP = Core.field(backdrop)
    }, {
        topLevel = true,
        x = x,
        y = y
    })
end

---Create "when greater than" hat block
---@param option string Option ("LOUDNESS", "TIMER")
---@param value number|string|nil Threshold value
---@param x number|nil X position
---@param y number|nil Y position
---@return string id, SB3Builder.Block block
function Events.whenGreaterThan(option, value, x, y)
    return Core.createBlock("event_whengreaterthan", {
        VALUE = value
    }, {
        WHENGREATERTHANMENU = Core.field(option)
    }, {
        topLevel = true,
        x = x,
        y = y
    })
end

---Create "when I receive" hat block
---@param broadcastName string Broadcast message name
---@param broadcastId string|nil Broadcast ID (auto-generated if nil)
---@param x number|nil X position
---@param y number|nil Y position
---@return string id, SB3Builder.Block block, string broadcastId Broadcast ID used
function Events.whenIReceive(broadcastName, broadcastId, x, y)
    if not broadcastId then
        broadcastId = "broadcast_" .. tostring(math.random(100000, 999999))
    end
    
    local id, block = Core.createBlock("event_whenbroadcastreceived", {}, {
        BROADCAST_OPTION = Core.field(broadcastName, broadcastId)
    }, {
        topLevel = true,
        x = x,
        y = y
    })
    
    return id, block, broadcastId
end

-- ===== BROADCAST BLOCKS =====

---Create "broadcast" block
---@param broadcastName string Broadcast message name
---@param broadcastId string|nil Broadcast ID (auto-generated if nil)
---@return string id, SB3Builder.Block block, string broadcastId Broadcast ID used
function Events.broadcast(broadcastName, broadcastId)
    if not broadcastId then
        broadcastId = "broadcast_" .. tostring(math.random(100000, 999999))
    end
    
    local id, block = Core.createBlock("event_broadcast", {
        BROADCAST_INPUT = { Core.INPUT_SAME_BLOCK_SHADOW, { Core.BROADCAST_PRIMITIVE, broadcastName, broadcastId } }
    })
    
    return id, block, broadcastId
end

---Create "broadcast and wait" block
---@param broadcastName string Broadcast message name
---@param broadcastId string|nil Broadcast ID (auto-generated if nil)
---@return string id, SB3Builder.Block block, string broadcastId Broadcast ID used
function Events.broadcastAndWait(broadcastName, broadcastId)
    if not broadcastId then
        broadcastId = "broadcast_" .. tostring(math.random(100000, 999999))
    end
    
    local id, block = Core.createBlock("event_broadcastandwait", {
        BROADCAST_INPUT = { Core.INPUT_SAME_BLOCK_SHADOW, { Core.BROADCAST_PRIMITIVE, broadcastName, broadcastId } }
    })
    
    return id, block, broadcastId
end

return Events