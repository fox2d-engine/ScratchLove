-- SpriteTemplate
-- Template for sprites that contains shared data (blocks, costumes, sounds)
-- Similar to Scratch's Sprite class - shared by all clones

local log = require("lib.log")

---@class SpriteTemplate
---@field runtime Runtime Runtime instance
---@field name string Sprite name
---@field blocks table<string, Block> Sprite blocks (shared by all clones)
---@field blockOrder string[] Ordered array of block IDs (preserves JSON order for stable compilation)
---@field hatBlockIndex table<string, table> Hat block index for fast lookups
---@field costumes Costume[] Available costumes (shared)
---@field sounds Sound[] Available sounds (shared)
---@field clones Sprite[] List of all clones (including original)
local SpriteTemplate = {}
SpriteTemplate.__index = SpriteTemplate

---Create a new sprite template
---@param data Target Target data from project
---@param runtime Runtime Runtime instance
---@return SpriteTemplate
function SpriteTemplate:new(data, runtime)
    local self = setmetatable({}, SpriteTemplate)

    self.runtime = runtime
    self.name = data.name
    self.blocks = data.blocks or {}
    self.blockOrder = data.blockOrder or {}
    self.costumes = data.costumes or {}
    self.sounds = data.sounds or {}
    self.clones = {} -- All clones of this sprite

    -- Hat block index for fast lookups
    self.hatBlockIndex = {
        event_whenflagclicked = {},
        event_whenkeypressed = {},
        event_whenthisspriteclicked = {},
        event_whenbackdropswitchesto = {},
        event_whengreaterthan = {},
        event_whenbroadcastreceived = {},
        control_start_as_clone = {}
    }

    self:buildHatBlockIndex()

    return self
end

---Create a clone (Sprite) of this sprite template
---@return Sprite clone The created clone
function SpriteTemplate:createClone()
    local Sprite = require("vm.sprite") -- Lazy load to avoid circular dependency
    local newClone = Sprite:newFromTemplate(self, self.runtime)

    -- Default to clone (will be overridden for original sprite in Runtime:initialize())
    newClone.isClone = true

    table.insert(self.clones, newClone)

    -- Fire target creation event (similar to original Scratch)
    log.debug("Clone created for sprite: %s (total clones: %d)",
        self.name, #self.clones)

    return newClone
end

---Remove a clone from this sprite
---@param clone Sprite Clone to remove
function SpriteTemplate:removeClone(clone)
    for i, c in ipairs(self.clones) do
        if c == clone then
            table.remove(self.clones, i)
            log.debug("Clone removed from sprite: %s (remaining: %d)",
                self.name, #self.clones)
            break
        end
    end
end

---Build hat block index for fast lookups
function SpriteTemplate:buildHatBlockIndex()
    -- Clear existing index
    for opcode in pairs(self.hatBlockIndex) do
        self.hatBlockIndex[opcode] = {}
    end

    -- Index all hat blocks using stable order from JSON
    if not self.blockOrder then
        error("SpriteTemplate:buildHatBlockIndex: blockOrder is required for stable compilation order")
    end

    for _, blockId in ipairs(self.blockOrder) do
        local block = self.blocks[blockId]
        if block and block.topLevel and self.hatBlockIndex[block.opcode] then
            table.insert(self.hatBlockIndex[block.opcode], blockId)
        end
    end
end

---Add a block and update hat block index
---@param blockId string Block ID
---@param block Block Block data
function SpriteTemplate:addBlock(blockId, block)
    self.blocks[blockId] = block

    -- Update hat block index if needed
    if block.topLevel and self.hatBlockIndex[block.opcode] then
        table.insert(self.hatBlockIndex[block.opcode], blockId)
    end
end

---Get total block count
---@return integer count Number of blocks
function SpriteTemplate:getBlockCount()
    -- Use blockOrder for stable count
    return #self.blockOrder
end

---Get all hat blocks of a specific type
---@param opcode string Hat block opcode
---@return string[] blockIds List of block IDs
function SpriteTemplate:getHatBlocks(opcode)
    return self.hatBlockIndex[opcode] or {}
end

return SpriteTemplate
