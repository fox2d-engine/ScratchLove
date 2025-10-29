-- @fileoverview Looks block compilation for Scratch to Lua compiler

local enums = require("compiler.enums")
local intermediate = require("compiler.intermediate")

local InputType = enums.InputType
local StackOpcode = enums.StackOpcode
local InputOpcode = enums.InputOpcode
local IntermediateStackBlock = intermediate.IntermediateStackBlock
local IntermediateInput = intermediate.IntermediateInput

---@class LooksBlockCompiler
local LooksBlockCompiler = {}

---Compile looks blocks during IR generation
---@param generator ScriptTreeGenerator Generator instance
---@param block table Scratch block
---@param blockId string|nil Original Scratch block ID
---@return IntermediateStackBlock|IntermediateInput|nil result Compiled result
function LooksBlockCompiler.compile(generator, block, blockId)
    local opcode = block.opcode

    -- Stack blocks (statements)
    if opcode == "looks_show" then
        return IntermediateStackBlock:new(StackOpcode.LOOKS_SHOW)
    elseif opcode == "looks_hide" then
        return IntermediateStackBlock:new(StackOpcode.LOOKS_HIDE)
    elseif opcode == "looks_switchcostumeto" then
        local costume = generator:descendInputOfBlock(block, "COSTUME")
        return IntermediateStackBlock:new(StackOpcode.LOOKS_COSTUME_SET, {
            costume = costume
        })
    elseif opcode == "looks_nextcostume" then
        return IntermediateStackBlock:new(StackOpcode.LOOKS_COSTUME_NEXT)
    elseif opcode == "looks_switchbackdropto" then
        local backdrop = generator:descendInputOfBlock(block, "BACKDROP")
        return IntermediateStackBlock:new(StackOpcode.LOOKS_BACKDROP_SET, {
            backdrop = backdrop
        })
    elseif opcode == "looks_nextbackdrop" then
        return IntermediateStackBlock:new(StackOpcode.LOOKS_BACKDROP_NEXT)
    elseif opcode == "looks_changesizeby" then
        local change = generator:descendInputOfBlock(block, "CHANGE"):toType(InputType.NUMBER)
        return IntermediateStackBlock:new(StackOpcode.LOOKS_SIZE_CHANGE, {
            change = change
        })
    elseif opcode == "looks_setsizeto" then
        local size = generator:descendInputOfBlock(block, "SIZE"):toType(InputType.NUMBER)
        return IntermediateStackBlock:new(StackOpcode.LOOKS_SIZE_SET, {
            size = size
        })
    elseif opcode == "looks_changeeffectby" then
        local effect = generator:descendInputOfBlock(block, "EFFECT")
        local change = generator:descendInputOfBlock(block, "CHANGE"):toType(InputType.NUMBER)
        return IntermediateStackBlock:new(StackOpcode.LOOKS_EFFECT_CHANGE, {
            effect = effect,
            change = change
        })
    elseif opcode == "looks_seteffectto" then
        local effect = generator:descendInputOfBlock(block, "EFFECT")
        local value = generator:descendInputOfBlock(block, "VALUE"):toType(InputType.NUMBER)
        return IntermediateStackBlock:new(StackOpcode.LOOKS_EFFECT_SET, {
            effect = effect,
            value = value
        })
    elseif opcode == "looks_cleargraphiceffects" then
        return IntermediateStackBlock:new(StackOpcode.LOOKS_EFFECT_CLEAR)
    elseif opcode == "looks_gotofrontback" then
        local frontBack = generator:descendInputOfBlock(block, "FRONT_BACK")
        if frontBack and frontBack:isConstant("front") then
            return IntermediateStackBlock:new(StackOpcode.LOOKS_LAYER_FRONT)
        else
            return IntermediateStackBlock:new(StackOpcode.LOOKS_LAYER_BACK)
        end
    elseif opcode == "looks_goforwardbackwardlayers" then
        local forwardBackward = generator:descendInputOfBlock(block, "FORWARD_BACKWARD")
        local num = generator:descendInputOfBlock(block, "NUM"):toType(InputType.NUMBER)
        if forwardBackward and forwardBackward:isConstant("forward") then
            return IntermediateStackBlock:new(StackOpcode.LOOKS_LAYER_FORWARD, {
                num = num
            })
        else
            return IntermediateStackBlock:new(StackOpcode.LOOKS_LAYER_BACKWARD, {
                num = num
            })
        end
    elseif opcode == "looks_say" then
        local message = generator:descendInputOfBlock(block, "MESSAGE")
        return IntermediateStackBlock:new(StackOpcode.LOOKS_SAY, {
            message = message
        })
    elseif opcode == "looks_sayforsecs" then
        local message = generator:descendInputOfBlock(block, "MESSAGE")
        local secs = generator:descendInputOfBlock(block, "SECS"):toType(InputType.NUMBER)
        return IntermediateStackBlock:new(StackOpcode.LOOKS_SAY_FOR_SECS, {
            message = message,
            secs = secs
        }, true, blockId) -- Yields during timeout
    elseif opcode == "looks_think" then
        local message = generator:descendInputOfBlock(block, "MESSAGE")
        return IntermediateStackBlock:new(StackOpcode.LOOKS_THINK, {
            message = message
        })
    elseif opcode == "looks_thinkforsecs" then
        local message = generator:descendInputOfBlock(block, "MESSAGE")
        local secs = generator:descendInputOfBlock(block, "SECS"):toType(InputType.NUMBER)
        return IntermediateStackBlock:new(StackOpcode.LOOKS_THINK_FOR_SECS, {
            message = message,
            secs = secs
        }, true, blockId) -- Yields during timeout

        -- Reporter blocks (expressions)
    elseif opcode == "looks_costumenumbername" then
        local numberName = block.fields and block.fields.NUMBER_NAME and block.fields.NUMBER_NAME.value
        if numberName == "number" then
            return IntermediateInput:new(InputOpcode.LOOKS_COSTUME_NUMBER, InputType.NUMBER)
        else
            return IntermediateInput:new(InputOpcode.LOOKS_COSTUME_NAME, InputType.STRING)
        end
    elseif opcode == "looks_costume" then
        -- Costume menu reporter
        return generator:descendFieldOfBlock(block, "COSTUME")
    elseif opcode == "looks_backdropnumbername" then
        local numberName = block.fields and block.fields.NUMBER_NAME and block.fields.NUMBER_NAME.value
        if numberName == "number" then
            return IntermediateInput:new(InputOpcode.LOOKS_BACKDROP_NUMBER, InputType.NUMBER)
        else
            return IntermediateInput:new(InputOpcode.LOOKS_BACKDROP_NAME, InputType.STRING)
        end
    elseif opcode == "looks_backdrops" then
        -- Backdrop menu reporter
        return generator:descendFieldOfBlock(block, "BACKDROP")
    elseif opcode == "looks_size" then
        return IntermediateInput:new(InputOpcode.LOOKS_SIZE, InputType.NUMBER)
    elseif opcode == "looks_changestretchby" then
        local change = generator:descendInputOfBlock(block, "CHANGE"):toType(InputType.NUMBER)
        return IntermediateStackBlock:new(StackOpcode.LOOKS_STRETCH_CHANGE, {
            change = change
        })
    elseif opcode == "looks_setstretchto" then
        local stretch = generator:descendInputOfBlock(block, "STRETCH"):toType(InputType.NUMBER)
        return IntermediateStackBlock:new(StackOpcode.LOOKS_STRETCH_SET, {
            stretch = stretch
        })
    elseif opcode == "looks_hideallsprites" then
        return IntermediateStackBlock:new(StackOpcode.LOOKS_HIDE_ALL_SPRITES)
    elseif opcode == "looks_switchbackdroptoandwait" then
        local backdrop = generator:descendInputOfBlock(block, "BACKDROP")
        return IntermediateStackBlock:new(StackOpcode.LOOKS_SWITCH_BACKDROP_AND_WAIT, {
            backdrop = backdrop
        }, true) -- Yields until backdrop switch complete
    end

    return nil
end

---Generate Lua code for looks stack blocks
---@param generator LuaGenerator Generator instance
---@param opcode string Stack opcode
---@param inputs table Block inputs
---@param block table|nil Original block for blockId access
---@return boolean handled True if opcode was handled
function LooksBlockCompiler.generateStackBlock(generator, opcode, inputs, block)
    local StackOpcode = enums.StackOpcode

    if opcode == StackOpcode.LOOKS_SHOW then
        -- Show sprite
        generator:writeLine("target:show()")
        return true
    elseif opcode == StackOpcode.LOOKS_HIDE then
        -- Hide sprite
        generator:writeLine("target:hide()")
        return true
    elseif opcode == StackOpcode.LOOKS_COSTUME_SET then
        -- Switch costume
        local costume = inputs.costume
        if costume then
            local costumeCode = generator:generateInput(costume)
            generator:writeLine(string.format("target:switchCostume(%s)", costumeCode))
        end
        return true
    elseif opcode == StackOpcode.LOOKS_SIZE_SET then
        -- Set size
        local size = inputs.size
        if size then
            local sizeCode = generator:generateInput(size)
            generator:writeLine(string.format("target:setSize(%s)", sizeCode))
        end
        return true
    elseif opcode == StackOpcode.LOOKS_EFFECT_SET then
        -- Set effect (target method handles toLowerCase internally)
        local effect = inputs.effect
        local value = inputs.value
        if effect and value then
            local effectCode = generator:generateInput(effect)
            local valueCode = generator:generateInput(value)
            generator:writeLine(string.format("target:setEffect(%s, %s)", effectCode, valueCode))
        end
        return true
    elseif opcode == StackOpcode.LOOKS_SIZE_CHANGE then
        -- Change size
        local change = inputs.change
        if change then
            local changeCode = generator:generateInput(change)
            generator:writeLine(string.format("target:changeSize(%s)", changeCode))
        end
        return true
    elseif opcode == StackOpcode.LOOKS_EFFECT_CHANGE then
        -- Change effect (target method handles toLowerCase internally)
        local effect = inputs.effect
        local change = inputs.change
        if effect and change then
            local effectCode = generator:generateInput(effect)
            local changeCode = generator:generateInput(change)
            generator:writeLine(string.format("target:changeEffect(%s, %s)", effectCode, changeCode))
        end
        return true
    elseif opcode == StackOpcode.LOOKS_EFFECT_CLEAR then
        -- Clear all graphic effects
        generator:writeLine("target:clearEffects()")
        return true
    elseif opcode == StackOpcode.LOOKS_COSTUME_NEXT then
        -- Go to next costume
        generator:writeLine("target:nextCostume()")
        return true
    elseif opcode == StackOpcode.LOOKS_BACKDROP_SET then
        -- Switch backdrop
        local backdrop = inputs.backdrop
        if backdrop then
            local backdropCode = generator:generateInput(backdrop)
            generator:writeLine(string.format("runtime.stage:switchBackdrop(%s)", backdropCode))
        end
        return true
    elseif opcode == StackOpcode.LOOKS_BACKDROP_NEXT then
        -- Go to next backdrop
        generator:writeLine("runtime.stage:nextBackdrop()")
        return true
    elseif opcode == StackOpcode.LOOKS_LAYER_FRONT then
        -- Go to front layer
        generator:writeLine("target:goToFront()")
        return true
    elseif opcode == StackOpcode.LOOKS_LAYER_BACK then
        -- Go to back layer
        generator:writeLine("target:goToBack()")
        return true
    elseif opcode == StackOpcode.LOOKS_LAYER_FORWARD then
        -- Go forward layers
        local num = inputs.num
        if num then
            local numCode = generator:generateInput(num)
            generator:writeLine(string.format("target:goForwardLayers(%s)", numCode))
        end
        return true
    elseif opcode == StackOpcode.LOOKS_LAYER_BACKWARD then
        -- Go backward layers
        local num = inputs.num
        if num then
            local numCode = generator:generateInput(num)
            generator:writeLine(string.format("target:goBackwardLayers(%s)", numCode))
        end
        return true
    elseif opcode == StackOpcode.LOOKS_SAY then
        -- Say message - apply Scratch number formatting
        local message = inputs.message
        if message then
            local messageCode = generator:generateInput(message)
            generator:writeLine(string.format("target:say(toScratchDisplayString(%s))", messageCode))
        end
        return true
    elseif opcode == StackOpcode.LOOKS_SAY_FOR_SECS then
        -- Say message for seconds - use helper for cleaner code
        local message = inputs.message
        local secs = inputs.secs
        if message and secs then
            local messageCode = generator:generateInput(message)
            local secsCode = generator:generateInput(secs)
            generator:writeLine(string.format("BlockHelpers.Looks.sayForSecs(target, %s, %s, runtime, thread)", messageCode, secsCode))
        end
        return true
    elseif opcode == StackOpcode.LOOKS_THINK then
        -- Think message - apply Scratch number formatting
        local message = inputs.message
        if message then
            local messageCode = generator:generateInput(message)
            generator:writeLine(string.format("target:think(toScratchDisplayString(%s))", messageCode))
        end
        return true
    elseif opcode == StackOpcode.LOOKS_THINK_FOR_SECS then
        -- Think message for seconds - use helper for cleaner code
        local message = inputs.message
        local secs = inputs.secs
        if message and secs then
            local messageCode = generator:generateInput(message)
            local secsCode = generator:generateInput(secs)
            generator:writeLine(string.format("BlockHelpers.Looks.thinkForSecs(target, %s, %s, runtime, thread)", messageCode, secsCode))
        end
        return true
    elseif opcode == StackOpcode.LOOKS_STRETCH_CHANGE then
        -- Change stretch by amount
        local change = inputs.change
        if change then
            local changeCode = generator:generateInput(change)
            generator:writeLine(string.format("target:changeStretch(%s)", changeCode))
        end
        return true
    elseif opcode == StackOpcode.LOOKS_STRETCH_SET then
        -- Set stretch to amount
        local stretch = inputs.stretch
        if stretch then
            local stretchCode = generator:generateInput(stretch)
            generator:writeLine(string.format("target:setStretch(%s)", stretchCode))
        end
        return true
    elseif opcode == StackOpcode.LOOKS_HIDE_ALL_SPRITES then
        -- Hide all sprites
        generator:writeLine("runtime:hideAllSprites()")
        return true
    elseif opcode == StackOpcode.LOOKS_SWITCH_BACKDROP_AND_WAIT then
        -- Switch backdrop and wait for backdrop-switch scripts to complete - use helper for cleaner code
        local backdrop = inputs.backdrop
        if backdrop then
            local backdropCode = generator:generateInput(backdrop)
            generator:writeLine(string.format("BlockHelpers.Looks.switchBackdropAndWait(target, %s, runtime, thread)", backdropCode))
        end
        return true
    end

    return false
end

---Generate Lua code for looks input blocks
---@param generator LuaGenerator Generator instance
---@param opcode string Input opcode
---@param inputs table Block inputs
---@return string|nil code Generated Lua expression or nil if not handled
function LooksBlockCompiler.generateInput(generator, opcode, inputs)
    local InputOpcode = enums.InputOpcode

    if opcode == InputOpcode.LOOKS_COSTUME_NUMBER then
        -- Inline: Get 1-indexed costume number
        return "(target.currentCostume + 1)"
    elseif opcode == InputOpcode.LOOKS_COSTUME_NAME then
        -- Inline: Get costume name
        return "(target:getCurrentCostume().name or '')"
    elseif opcode == InputOpcode.LOOKS_BACKDROP_NUMBER then
        -- Inline: Get 1-indexed backdrop number
        return "(runtime.stage.currentCostume + 1)"
    elseif opcode == InputOpcode.LOOKS_BACKDROP_NAME then
        -- Inline: Get backdrop name
        return "(runtime.stage:getCurrentBackdrop().name or '')"
    elseif opcode == InputOpcode.LOOKS_SIZE then
        -- Get size - use original blocks implementation
        return "BlockHelpers.Looks.getSize(target, runtime, thread)"
    end

    return nil
end

return LooksBlockCompiler
