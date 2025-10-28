-- Virtual Gamepad Manager
-- Manages virtual gamepad button mapping and active key detection
-- Automatically maps detected keys to ABXY buttons with stable priority

local log = require("lib.log")
local Global = require("global")
require("table.clear")

---@class VirtualGamepadMapping
---@field keyToButton table<string, string> Scratch key → gamepad button mapping
---@field buttonToKey table<string, string> Gamepad button → Scratch key mapping

---@class VirtualGamepadManager
---@field runtime Runtime Reference to runtime instance
---@field staticActiveKeys table<string, boolean> Static keys from hat blocks (never changes after initialization)
---@field staticActiveKeysOrder string[] Ordered list of static keys (insertion order, for stable mapping)
---@field dynamicActiveKeys table<string, boolean> Dynamic keys from sensing_keypressed (cleared periodically)
---@field previousDynamicKeys table<string, boolean> Previous frame's dynamic keys (for change detection)
---@field allActiveKeysOrder string[] Combined static + dynamic keys in order (for mapping)
---@field mapping VirtualGamepadMapping|nil Current button mapping (bidirectional)
---@field dynamicKeysClearFrameCounter number Frame counter for periodic dynamic key clearing (clears every 60 frames)
local VirtualGamepadManager = {}
VirtualGamepadManager.__index = VirtualGamepadManager

---Create a new virtual gamepad manager
---@param runtime Runtime The runtime instance
---@return VirtualGamepadManager
function VirtualGamepadManager:new(runtime)
    local self = setmetatable({}, VirtualGamepadManager)
    self.runtime = runtime
    self.staticActiveKeys = {}
    self.staticActiveKeysOrder = {}       -- Array to preserve insertion order
    self.dynamicActiveKeys = {}
    self.previousDynamicKeys = {}         -- For change detection
    self.allActiveKeysOrder = {}          -- Combined keys for mapping
    self.mapping = nil
    self.dynamicKeysClearFrameCounter = 0 -- Clear every 60 frames (≈1 second)
    return self
end

---Initialize virtual gamepad mapping
---Collects active keys, generates mapping, and applies to virtual gamepad
function VirtualGamepadManager:initialize()
    -- Step 1: Collect active keys from project
    self:collectActiveKeys()

    -- Step 2: Initialize allActiveKeysOrder with static keys
    self.allActiveKeysOrder = {}
    for _, key in ipairs(self.staticActiveKeysOrder) do
        table.insert(self.allActiveKeysOrder, key)
    end

    -- Step 3: Setup mapping and apply to virtual gamepad
    self:setupMapping()
end

---Collect actively used keys from project hat blocks
---Scans all event_whenkeypressed blocks and populates staticActiveKeys
---Preserves insertion order in staticActiveKeysOrder array for stable mapping
function VirtualGamepadManager:collectActiveKeys()
    -- Helper function to normalize key to Scratch format (matching _keyArgToScratchKey)
    local function normalizeKey(key)
        -- Single character keys are converted to UPPERCASE (native Scratch behavior)
        if #key == 1 then
            return key:upper()
        end
        return key
    end

    -- Helper to register key (deduplicates while preserving order)
    local function registerKey(normalizedKey, source)
        if not self.staticActiveKeys[normalizedKey] then
            self.staticActiveKeys[normalizedKey] = true
            table.insert(self.staticActiveKeysOrder, normalizedKey)
            log.debug("Collected static key from " .. source .. ": " .. tostring(normalizedKey))
        end
    end

    -- Debug: Check stage structure
    log.debug("VirtualGamepad: Scanning stage...")
    log.debug("  stage exists: %s", tostring(self.runtime.stage ~= nil))
    if self.runtime.stage then
        log.debug("  stage.blocks exists: %s", tostring(self.runtime.stage.blocks ~= nil))
        log.debug("  stage.blockOrder exists: %s", tostring(self.runtime.stage.blockOrder ~= nil))
        if self.runtime.stage.blockOrder then
            log.debug("  stage.blockOrder length: %d", #self.runtime.stage.blockOrder)
        end
    end

    -- Scan stage blocks using stable order
    if self.runtime.stage and self.runtime.stage.blocks and self.runtime.stage.blockOrder then
        for _, blockId in ipairs(self.runtime.stage.blockOrder) do
            local block = self.runtime.stage.blocks[blockId]
            if block then
                log.debug("  Stage block %s: opcode=%s", blockId, tostring(block.opcode))
                if block.opcode == "event_whenkeypressed" then
                    log.debug("    Found whenkeypressed block!")
                    log.debug("    fields exists: %s", tostring(block.fields ~= nil))
                    if block.fields then
                        log.debug("    KEY_OPTION exists: %s", tostring(block.fields.KEY_OPTION ~= nil))
                        if block.fields.KEY_OPTION then
                            log.debug("    KEY_OPTION.value: %s", tostring(block.fields.KEY_OPTION.value))
                            local key = block.fields.KEY_OPTION.value
                            if key then
                                local normalizedKey = normalizeKey(key)
                                registerKey(normalizedKey, "stage")
                            end
                        end
                    end
                end
            end
        end
    end

    -- Debug: Check sprite templates
    log.debug("VirtualGamepad: Scanning sprite templates...")
    log.debug("  spriteTemplates count: %d", #self.runtime.spriteTemplates)

    -- Scan sprite templates blocks using stable order
    for i, template in ipairs(self.runtime.spriteTemplates) do
        log.debug("  Template %d (%s):", i, template.name or "unnamed")
        log.debug("    blocks exists: %s", tostring(template.blocks ~= nil))
        log.debug("    blockOrder exists: %s", tostring(template.blockOrder ~= nil))
        if template.blockOrder then
            log.debug("    blockOrder length: %d", #template.blockOrder)
        end

        if template.blocks and template.blockOrder then
            for _, blockId in ipairs(template.blockOrder) do
                local block = template.blocks[blockId]
                if block and block.opcode == "event_whenkeypressed" then
                    log.debug("    Found whenkeypressed in %s", template.name)
                    if block.fields and block.fields.KEY_OPTION then
                        local key = block.fields.KEY_OPTION.value
                        if key then
                            local normalizedKey = normalizeKey(key)
                            registerKey(normalizedKey, "sprite '" .. template.name .. "'")
                        end
                    end
                end
            end
        end
    end

    log.info("Virtual gamepad: Collected %d active keys from project", self:getActiveKeyCount())
end

---Get count of active keys
---@return integer count Number of active keys
function VirtualGamepadManager:getActiveKeyCount()
    local count = 0
    for _ in pairs(self.staticActiveKeys) do
        count = count + 1
    end
    return count
end

---Setup virtual gamepad button mapping
---Auto-detects keys, generates mapping, and applies to virtual gamepad
function VirtualGamepadManager:setupMapping()
    -- Generate mapping from active keys
    self:generateMapping()

    -- Apply mapping to virtual gamepad (only if API available)
    self:applyMappingToGamepad()
end

---Generate button mapping from active keys
---Uses insertion order from allActiveKeysOrder for stable, predictable mapping
---Includes both static keys (from hat blocks) and dynamic keys (from sensing_keypressed)
function VirtualGamepadManager:generateMapping()
    -- 1. Filter arrow direction keys from allActiveKeysOrder (preserves insertion order)
    -- Note: WASD are NOT excluded - they can be mapped to buttons like any other action key
    local excludedKeys = {
        ["up arrow"] = true,
        ["down arrow"] = true,
        ["left arrow"] = true,
        ["right arrow"] = true
    }

    local detectedKeys = {}
    for _, key in ipairs(self.allActiveKeysOrder) do
        if not excludedKeys[key] then
            table.insert(detectedKeys, key)
        end
    end

    -- Note: detectedKeys now preserves insertion order (static first, then dynamic)

    -- 2. Special handling for jump keys (ONLY arrow keys, not WASD)
    -- If non-directional keys < 4 and project uses arrow direction keys, add "up arrow" to buttons
    -- This separates jump from movement for better ergonomics in platform games
    if #detectedKeys < 4 and not Global.IS_HANDHELD_LINUX then
        -- Only consider "up arrow" for jump key mapping (not WASD)
        local hasUpArrow = self.staticActiveKeys["up arrow"] or self.dynamicActiveKeys["up arrow"]

        if hasUpArrow then
            table.insert(detectedKeys, 1, "up arrow") -- Insert at front for highest priority
            log.info(
            "Virtual gamepad: Added jump key 'up arrow' to buttons at highest priority (separating from D-pad for ergonomics)")
        end
    end

    -- 3. Apply priority mapping strategy based on ergonomic button layout
    -- Physical layout:  Y (top)
    --                 X   B  (left/right)
    --                   A (bottom)
    -- Priority: X (natural thumb position) → Y (easy reach) → A (downward) → B (rightward)
    local MAPPING_STRATEGIES = {
        [1] = { "x" },             -- 1 key  → X only (left, natural position)
        [2] = { "x", "y" },        -- 2 keys → X+Y (left + top, ergonomic pair)
        [3] = { "x", "y", "a" },   -- 3 keys → X+Y+A (left + top + bottom, triangle)
        [4] = { "x", "y", "a", "b" } -- 4 keys → all buttons (complete diamond)
    }

    -- Limit to maximum 4 keys
    local keyCount = math.min(#detectedKeys, 4)

    -- Handle zero-key case gracefully
    if keyCount == 0 then
        log.debug("Virtual gamepad: No action keys to map (only directional keys or no keys at all)")
        self.mapping = {
            keyToButton = {},
            buttonToKey = {}
        }
        return
    end

    local strategy = MAPPING_STRATEGIES[keyCount] or {}

    -- 5. Build bidirectional mapping
    self.mapping = {
        keyToButton = {}, -- Scratch key → gamepad button
        buttonToKey = {}  -- gamepad button → Scratch key
    }

    for i, button in ipairs(strategy) do
        local scratchKey = detectedKeys[i]
        self.mapping.keyToButton[scratchKey] = button
        self.mapping.buttonToKey[button] = scratchKey
    end

    -- Log mapping results with ergonomic button labels
    local buttonLabels = {
        x = "X (left)",
        y = "Y (top)",
        a = "A (bottom)",
        b = "B (right)"
    }

    if keyCount > 0 then
        log.info("Virtual gamepad: Generated mapping for %d keys", keyCount)
        -- Log in insertion order to match key priority
        for _, scratchKey in ipairs(detectedKeys) do
            local button = self.mapping.keyToButton[scratchKey]
            if button then
                local label = buttonLabels[button] or button:upper()
                log.info("  %s → %s", scratchKey, label)
            end
        end
    else
        log.info("Virtual gamepad: No action keys detected, all buttons hidden")
    end
end

---Apply current mapping to gamepad
---On Android: updates virtual gamepad UI (button labels and d-pad visibility)
---On Linux: mapping is ready for physical gamepad use (no UI updates needed)
---On all platforms: logs the active button mapping for debugging
function VirtualGamepadManager:applyMappingToGamepad()
    if not self.mapping then
        log.warn("Virtual gamepad: No mapping available to apply")
        return
    end

    -- Log the active mapping (useful for all platforms)
    local mappedButtons = {}
    for scratchKey, button in pairs(self.mapping.keyToButton) do
        table.insert(mappedButtons, string.format("%s→%s", button:upper(), scratchKey))
    end

    if #mappedButtons > 0 then
        log.info("Gamepad mapping active: %s", table.concat(mappedButtons, ", "))
    else
        log.info("Gamepad mapping: No action buttons mapped")
    end

    -- Android-specific: Update virtual gamepad UI
    local hasAndroidAPI = (love.system and love.system.mobile and love.system.mobile.setVirtualGamepadButtonLabel)

    if hasAndroidAPI then
        local BUTTON_PRIORITY = { "a", "b", "x", "y" }

        -- First hide all buttons
        for _, btn in ipairs(BUTTON_PRIORITY) do
            love.system.mobile.setVirtualGamepadButtonLabel(btn, nil)
        end

        -- Then show mapped buttons with appropriate labels
        for scratchKey, button in pairs(self.mapping.keyToButton) do
            local label = self:formatKeyLabel(scratchKey)
            love.system.mobile.setVirtualGamepadButtonLabel(button, label)
        end

        -- Control d-pad visibility based on directional key usage
        self:updateDpadVisibility()

        log.debug("Virtual gamepad UI updated (Android)")
    else
        log.debug("Virtual gamepad UI not available (physical gamepad mode)")
    end
end

---Format a Scratch key name into a short display label for virtual gamepad buttons
---@param scratchKey string Scratch key name (e.g., "space", "A", "enter")
---@return string label Short label for button display (1-2 characters preferred)
function VirtualGamepadManager:formatKeyLabel(scratchKey)
    -- Special keys get symbolic labels
    local specialLabels = {
        space = "␣", -- Space symbol
        enter = "↵", -- Return symbol
        ["up arrow"] = "↑",
        ["down arrow"] = "↓",
        ["left arrow"] = "←",
        ["right arrow"] = "→"
    }

    if specialLabels[scratchKey] then
        return specialLabels[scratchKey]
    end

    -- Single character keys: convert to uppercase
    if #scratchKey == 1 then
        return scratchKey:upper()
    end

    -- Multi-character keys: use first letter
    return scratchKey:sub(1, 1):upper()
end

---Apply button swap configuration to physical button input
---Swaps button mappings based on Global.GAMEPAD_SWAP_AB and Global.GAMEPAD_SWAP_XY
---@param button string Physical button pressed ("a", "b", "x", "y")
---@return string swappedButton The logical button after applying swap configuration
function VirtualGamepadManager:applyButtonSwap(button)
    -- Apply A/B swap if enabled
    if Global.GAMEPAD_SWAP_AB then
        if button == "a" then
            return "b"
        elseif button == "b" then
            return "a"
        end
    end

    -- Apply X/Y swap if enabled
    if Global.GAMEPAD_SWAP_XY then
        if button == "x" then
            return "y"
        elseif button == "y" then
            return "x"
        end
    end

    return button
end

---Get the Scratch key mapped to a gamepad button
---Applies button swap configuration before lookup (Linux handheld device support)
---@param button string Gamepad button name ("a", "b", "x", "y")
---@return string|nil scratchKey Scratch key name or nil if not mapped
function VirtualGamepadManager:getScratchKeyForButton(button)
    if not self.mapping then
        return nil
    end

    -- Apply button swap configuration (Linux handheld devices)
    local swappedButton = self:applyButtonSwap(button)

    return self.mapping.buttonToKey[swappedButton]
end

---Get formatted button mapping text for display (for Linux handheld physical gamepad UI hints)
---Shows physical button labels after applying swap configuration
---@return string|nil mappingText Formatted mapping text like "X->space  Y->W  A->enter" or nil if no mapping
function VirtualGamepadManager:getButtonMappingText()
    if not self.mapping or not self.mapping.buttonToKey then
        return nil
    end

    -- Button display order: X, Y, A, B (ergonomic priority)
    local buttonOrder = { "x", "y", "a", "b" }
    local mappingParts = {}

    for _, button in ipairs(buttonOrder) do
        local scratchKey = self.mapping.buttonToKey[button]
        if scratchKey then
            -- Format: "X->space" with uppercase button name
            table.insert(mappingParts, string.format("%s->%s", button:upper(), scratchKey))
        end
    end

    if #mappingParts > 0 then
        return table.concat(mappingParts, "  ") -- Two spaces between mappings
    end

    return nil
end

---Check if a key is actively monitored by the project (static keys only)
---@param scratchKey string Scratch key name
---@return boolean active Whether key is actively monitored
function VirtualGamepadManager:isKeyActive(scratchKey)
    return self.staticActiveKeys[scratchKey] == true
end

---Register a key as actively monitored during runtime (dynamic registration)
---Called when sensing_keypressed is executed with a dynamic key value
---These keys are cleared each frame and repopulated as needed
---@param scratchKey string The Scratch key name (e.g., "space", "a", "up arrow")
function VirtualGamepadManager:registerDynamicKey(scratchKey)
    if not self.dynamicActiveKeys[scratchKey] then
        self.dynamicActiveKeys[scratchKey] = true
        log.debug("Dynamically registered active key: " .. tostring(scratchKey))
    end
end

---Clear all dynamically registered keys (every 60 frames ≈ 1 second)
---Checks for changes before clearing and updates gamepad mapping if needed
---Should be called at the start of each frame
function VirtualGamepadManager:clearDynamicKeys()
    -- Increment frame counter
    self.dynamicKeysClearFrameCounter = self.dynamicKeysClearFrameCounter + 1

    -- Only clear every 60 frames (≈1 second at 60 FPS)
    if self.dynamicKeysClearFrameCounter < 60 then
        return
    end

    -- Reset counter for next interval
    self.dynamicKeysClearFrameCounter = 0

    -- Check if dynamic keys have changed and update mapping if needed
    self:updateMappingIfDynamicKeysChanged()

    -- Save current state for next interval comparison
    self.previousDynamicKeys = {}
    for key, _ in pairs(self.dynamicActiveKeys) do
        self.previousDynamicKeys[key] = true
    end

    -- Clear for new interval
    table.clear(self.dynamicActiveKeys)
end

---Check if dynamic keys have changed and update gamepad configuration if needed
---Detects any new keys (action or directional) and updates both buttons and D-pad
function VirtualGamepadManager:updateMappingIfDynamicKeysChanged()
    -- Check if there are any NEW keys in dynamicActiveKeys (regardless of type)
    local hasNewKeys = false
    local newKeysDetected = {}

    for key, _ in pairs(self.dynamicActiveKeys) do
        -- Check if key is new (not in previous dynamic keys and not in static keys)
        if not self.previousDynamicKeys[key] and not self.staticActiveKeys[key] then
            hasNewKeys = true
            table.insert(newKeysDetected, key)
            log.debug("Virtual gamepad: New dynamic key detected: %s", key)
        end
    end

    -- If any new keys detected, update entire virtual gamepad configuration
    if hasNewKeys then
        -- Log detected keys
        log.info("Virtual gamepad: Updating configuration for %d new dynamic keys: %s",
            #newKeysDetected, table.concat(newKeysDetected, ", "))

        -- Rebuild key list, regenerate mapping, and update both buttons and D-pad
        self:rebuildAllActiveKeys()
        self:generateMapping()
        self:applyMappingToGamepad() -- This includes D-pad visibility update
    end
end

---Rebuild allActiveKeysOrder by combining static and dynamic keys
---Static keys come first (preserve priority), then dynamic keys
function VirtualGamepadManager:rebuildAllActiveKeys()
    -- Only exclude arrow direction keys (WASD are treated as normal action keys)
    local excludedKeys = {
        ["up arrow"] = true,
        ["down arrow"] = true,
        ["left arrow"] = true,
        ["right arrow"] = true
    }

    -- Start with static keys
    self.allActiveKeysOrder = {}
    for _, key in ipairs(self.staticActiveKeysOrder) do
        table.insert(self.allActiveKeysOrder, key)
    end

    -- Add non-arrow-directional dynamic keys that aren't already in static keys
    for key, _ in pairs(self.dynamicActiveKeys) do
        if not excludedKeys[key] and not self.staticActiveKeys[key] then
            table.insert(self.allActiveKeysOrder, key)
        end
    end
end

---Update d-pad visibility based on whether project uses arrow direction keys
---Shows d-pad ONLY if arrow keys detected (not WASD), hides if not (default is hidden)
---WASD keys are treated as normal action keys and mapped to buttons
function VirtualGamepadManager:updateDpadVisibility()
    -- Check if d-pad visibility API is available
    if not (love.system and love.system.mobile and love.system.mobile.setVirtualGamepadDpadVisible) then
        return
    end

    -- Check if project uses arrow direction keys (NOT WASD)
    -- WASD are now treated as normal action keys and mapped to buttons
    local arrowDirectionalKeys = {
        ["up arrow"] = true,
        ["down arrow"] = true,
        ["left arrow"] = true,
        ["right arrow"] = true
    }

    local hasArrowKeys = false

    -- Check static keys (from hat blocks)
    for key, _ in pairs(self.staticActiveKeys) do
        if arrowDirectionalKeys[key] then
            hasArrowKeys = true
            break
        end
    end

    -- Check dynamic keys (from sensing_keypressed) if no static keys found
    if not hasArrowKeys then
        for key, _ in pairs(self.dynamicActiveKeys) do
            if arrowDirectionalKeys[key] then
                hasArrowKeys = true
                break
            end
        end
    end

    -- Explicitly show or hide d-pad (default is hidden, must call API to show)
    if hasArrowKeys then
        love.system.mobile.setVirtualGamepadDpadVisible(true)
        log.info("Virtual gamepad: D-pad shown (project uses arrow direction keys)")
    else
        love.system.mobile.setVirtualGamepadDpadVisible(false)
        log.info("Virtual gamepad: D-pad hidden (no arrow direction keys detected)")
    end
end

return VirtualGamepadManager
