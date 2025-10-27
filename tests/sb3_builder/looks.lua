-- Looks Blocks Module
-- Implements all appearance-related Scratch blocks

local Core = require("tests.sb3_builder.core")

local Looks = {}

-- ===== SPEECH BUBBLES =====

---Create "say" block
---@param message any Message to display
---@return string id, SB3Builder.Block block
function Looks.say(message)
    return Core.createBlock("looks_say", {
        MESSAGE = message
    })
end

---Create "say for seconds" block
---@param message any Message to display
---@param seconds any Duration in seconds
---@return string id, SB3Builder.Block block
function Looks.sayForSecs(message, seconds)
    return Core.createBlock("looks_sayforsecs", {
        MESSAGE = message,
        SECS = seconds
    })
end

---Create "think" block
---@param message any Message to display in thought bubble
---@return string id, SB3Builder.Block block
function Looks.think(message)
    return Core.createBlock("looks_think", {
        MESSAGE = message
    })
end

---Create "think for seconds" block
---@param message any Message to display in thought bubble
---@param seconds any Duration in seconds
---@return string id, SB3Builder.Block block
function Looks.thinkForSecs(message, seconds)
    return Core.createBlock("looks_thinkforsecs", {
        MESSAGE = message,
        SECS = seconds
    })
end

-- ===== COSTUMES =====

---Create "switch costume to" block
---@param costume string Costume name
---@return string id, SB3Builder.Block block
function Looks.switchCostumeTo(costume)
    return Core.createBlock("looks_switchcostumeto", {
        COSTUME = costume
    })
end

---Create "next costume" block
---@return string id, SB3Builder.Block block
function Looks.nextCostume()
    return Core.createBlock("looks_nextcostume")
end

---Create "switch backdrop to" block
---@param backdrop string Backdrop name
---@return string id, SB3Builder.Block block
function Looks.switchBackdropTo(backdrop)
    return Core.createBlock("looks_switchbackdropto", {
        BACKDROP = backdrop
    })
end

---Create "next backdrop" block
---@return string id, SB3Builder.Block block
function Looks.nextBackdrop()
    return Core.createBlock("looks_nextbackdrop")
end

-- ===== SIZE AND EFFECTS =====

---Create "change size by" block
---@param change any Size change amount
---@return string id, SB3Builder.Block block
function Looks.changeSizeBy(change)
    return Core.createBlock("looks_changesizeby", {
        CHANGE = change
    })
end

---Create "set size to" block
---@param size any Size percentage
---@return string id, SB3Builder.Block block
function Looks.setSizeTo(size)
    return Core.createBlock("looks_setsizeto", {
        SIZE = size
    })
end

---Create "change graphic effect by" block
---@param effect string Effect name ("COLOR", "FISHEYE", "WHIRL", "PIXELATE", "MOSAIC", "BRIGHTNESS", "GHOST")
---@param change any Effect change amount
---@return string id, SB3Builder.Block block
function Looks.changeEffectBy(effect, change)
    return Core.createBlock("looks_changeeffectby", {
        CHANGE = change
    }, {
        EFFECT = Core.field(effect)
    })
end

---Create "set graphic effect to" block
---@param effect string Effect name ("COLOR", "FISHEYE", "WHIRL", "PIXELATE", "MOSAIC", "BRIGHTNESS", "GHOST")
---@param value any Effect value
---@return string id, SB3Builder.Block block
function Looks.setEffectTo(effect, value)
    return Core.createBlock("looks_seteffectto", {
        VALUE = value
    }, {
        EFFECT = Core.field(effect)
    })
end

---Create "clear graphic effects" block
---@return string id, SB3Builder.Block block
function Looks.clearGraphicEffects()
    return Core.createBlock("looks_cleargraphiceffects")
end

-- ===== VISIBILITY =====

---Create "show" block
---@return string id, SB3Builder.Block block
function Looks.show()
    return Core.createBlock("looks_show")
end

---Create "hide" block
---@return string id, SB3Builder.Block block
function Looks.hide()
    return Core.createBlock("looks_hide")
end

-- ===== LAYERING =====

---Create "go to front/back" block
---@param frontBack string "front" or "back"
---@return string id, SB3Builder.Block block
function Looks.goToFrontBack(frontBack)
    return Core.createBlock("looks_gotofrontback", {}, {
        FRONT_BACK = Core.field(frontBack)
    })
end

---Create "go forward/backward layers" block
---@param forwardBackward string "forward" or "backward"
---@param num any Number of layers
---@return string id, SB3Builder.Block block
function Looks.goForwardBackwardLayers(forwardBackward, num)
    return Core.createBlock("looks_goforwardbackwardlayers", {
        NUM = num
    }, {
        FORWARD_BACKWARD = Core.field(forwardBackward)
    })
end

-- ===== REPORTER BLOCKS =====

---Create "costume number/name" reporter block
---@param numberName string "number" or "name"
---@return string id, SB3Builder.Block block
function Looks.costumeNumberName(numberName)
    return Core.createBlock("looks_costumenumbername", {}, {
        NUMBER_NAME = Core.field(numberName)
    })
end

---Create "backdrop number/name" reporter block
---@param numberName string "number" or "name"
---@return string id, SB3Builder.Block block
function Looks.backdropNumberName(numberName)
    return Core.createBlock("looks_backdropnumbername", {}, {
        NUMBER_NAME = Core.field(numberName)
    })
end

---Create "size" reporter block
---@return string id, SB3Builder.Block block
function Looks.size()
    return Core.createBlock("looks_size")
end

-- ===== CONVENIENCE FUNCTIONS =====

-- Common effect shortcuts
---Create color effect block
---@param change any Effect change amount
---@return string id, SB3Builder.Block block
function Looks.changeColorEffectBy(change)
    return Looks.changeEffectBy("COLOR", change)
end

---Create brightness effect block
---@param change any Effect change amount
---@return string id, SB3Builder.Block block
function Looks.changeBrightnessBy(change)
    return Looks.changeEffectBy("BRIGHTNESS", change)
end

---Create ghost effect block
---@param change any Effect change amount
---@return string id, SB3Builder.Block block
function Looks.changeGhostEffectBy(change)
    return Looks.changeEffectBy("GHOST", change)
end

return Looks