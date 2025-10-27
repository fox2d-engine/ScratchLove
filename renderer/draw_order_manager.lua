-- Draw Order Manager
-- Manages Scratch-style drawable ordering and layer groups

local StageLayering = require("renderer.stage_layering")
local log = require("lib.log")

---@class DrawOrderManager
---@field _drawList string[] Ordered list of drawable IDs
---@field _layerGroups table<number, table> Layer group metadata
---@field _drawableToIndex table<string, number> Mapping from drawable ID to index
---@field _drawableToLayer table<string, number> Mapping from drawable ID to layer
---@field _drawableToLayerOrder table<string, number> Mapping from drawable ID to layerOrder
---@field _indicesValid boolean Whether the index mappings are up to date
local DrawOrderManager = {}
DrawOrderManager.__index = DrawOrderManager

---Create a new draw order manager
---@return DrawOrderManager
function DrawOrderManager:new()
    local self = setmetatable({}, DrawOrderManager)

    self._drawList = {}
    self._layerGroups = {}
    self._drawableToIndex = {}
    self._drawableToLayer = {}
    self._drawableToLayerOrder = {}
    self._indicesValid = true -- Initially valid (empty)

    -- Initialize layer groups
    for _, layer in pairs({
        StageLayering.BACKGROUND_LAYER,
        StageLayering.VIDEO_LAYER,
        StageLayering.PEN_LAYER,
        StageLayering.SPRITE_LAYER
    }) do
        self._layerGroups[layer] = {
            startIndex = 1,
            count = 0
        }
    end

    return self
end

---Add a drawable to the draw order
---@param drawableId string Unique drawable ID
---@param layer number Layer to add to
---@param layerOrder number|nil Specific position within layer (optional)
function DrawOrderManager:addDrawable(drawableId, layer, layerOrder)
    -- Remove if already exists
    self:removeDrawable(drawableId)

    local layerGroup = self._layerGroups[layer]
    if not layerGroup then
        log.warn("DrawOrderManager: Unknown layer %d for drawable %s", layer, drawableId)
        return
    end

    -- Determine insertion position
    local insertIndex
    if layerOrder then
        -- Find position based on layer order within the layer
        insertIndex = self:_findInsertionIndex(layer, layerOrder)
    else
        -- Add to end of layer
        insertIndex = layerGroup.startIndex + layerGroup.count
    end

    -- Insert into draw list
    table.insert(self._drawList, insertIndex, drawableId)

    -- Update indices and layer groups
    self:_updateIndicesAfterInsertion(insertIndex, layer)

    -- Store layer mapping and layerOrder (index mapping is handled by _updateIndicesAfterInsertion)
    self._drawableToLayer[drawableId] = layer
    if layerOrder then
        self._drawableToLayerOrder[drawableId] = layerOrder
    end
end

---Remove a drawable from the draw order
---@param drawableId string Drawable ID to remove
function DrawOrderManager:removeDrawable(drawableId)
    local index = self:_getIndex(drawableId)
    if not index then
        return
    end

    local layer = self._drawableToLayer[drawableId]

    -- Remove from draw list
    table.remove(self._drawList, index)

    -- Update indices and layer groups
    self:_updateIndicesAfterRemoval(index, layer)

    -- Clear mappings
    self._drawableToIndex[drawableId] = nil
    self._drawableToLayer[drawableId] = nil
    self._drawableToLayerOrder[drawableId] = nil
end

---Move a drawable to a specific position within its layer
---@param drawableId string Drawable ID to move
---@param newLayerOrder number New layer order within the same layer
function DrawOrderManager:setDrawableLayerOrder(drawableId, newLayerOrder)
    local currentIndex = self:_getIndex(drawableId)
    local layer = self._drawableToLayer[drawableId]

    if not currentIndex or not layer then
        log.warn("DrawOrderManager: Cannot move unknown drawable %s", drawableId)
        return
    end

    -- Remove and re-add with new layer order
    self:removeDrawable(drawableId)
    self:addDrawable(drawableId, layer, newLayerOrder)
end

---Move a drawable behind another drawable
---@param drawableId string Drawable ID to move
---@param targetId string Target drawable ID to move behind
---@return number|nil position New position, or nil if target not found
function DrawOrderManager:moveDrawableBehind(drawableId, targetId)
    local targetIndex = self:_getIndex(targetId)
    local targetLayer = self._drawableToLayer[targetId]

    -- Native behavior: return null if target drawable not found
    if not targetIndex or not targetLayer then
        return nil
    end

    local currentLayer = self._drawableToLayer[drawableId]
    -- Return nil if drawables are in different layers
    if currentLayer ~= targetLayer then
        return nil
    end

    -- Remove drawable first
    self:removeDrawable(drawableId)

    -- Get updated target index (may have changed after removal)
    targetIndex = self:_getIndex(targetId)
    -- Return nil if target disappeared during move
    if not targetIndex then
        return nil
    end

    -- Insert at target position (behind means same index)
    table.insert(self._drawList, targetIndex, drawableId)

    -- Update indices and layer groups
    self:_updateIndicesAfterInsertion(targetIndex, targetLayer)

    -- Store layer mapping (index mapping is handled by _updateIndicesAfterInsertion)
    self._drawableToLayer[drawableId] = targetLayer

    return targetIndex
end

---Move a drawable forward by a number of positions
---@param drawableId string Drawable ID to move
---@param positions number Number of positions to move forward
function DrawOrderManager:moveDrawableForward(drawableId, positions)
    local currentIndex = self:_getIndex(drawableId)
    local layer = self._drawableToLayer[drawableId]

    if not currentIndex or not layer then
        return
    end

    local layerGroup = self._layerGroups[layer]
    local layerEndIndex = layerGroup.startIndex + layerGroup.count - 1

    -- Calculate new position (clamped to layer bounds)
    local newIndex = math.min(currentIndex + positions, layerEndIndex)

    if newIndex ~= currentIndex then
        -- Move within the draw list
        local drawable = self._drawList[currentIndex]
        table.remove(self._drawList, currentIndex)
        table.insert(self._drawList, newIndex, drawable)

        -- Invalidate indices for lazy rebuild
        self:_invalidateIndices()
    end
end

---Move a drawable backward by a number of positions
---@param drawableId string Drawable ID to move
---@param positions number Number of positions to move backward
function DrawOrderManager:moveDrawableBackward(drawableId, positions)
    local currentIndex = self:_getIndex(drawableId)
    local layer = self._drawableToLayer[drawableId]

    if not currentIndex or not layer then
        return
    end

    local layerGroup = self._layerGroups[layer]
    local layerStartIndex = layerGroup.startIndex

    -- Calculate new position (clamped to layer bounds)
    local newIndex = math.max(currentIndex - positions, layerStartIndex)

    if newIndex ~= currentIndex then
        -- Move within the draw list
        local drawable = self._drawList[currentIndex]
        table.remove(self._drawList, currentIndex)
        table.insert(self._drawList, newIndex, drawable)

        -- Invalidate indices for lazy rebuild
        self:_invalidateIndices()
    end
end

---Get the ordered list of drawables for rendering
---@return string[] drawables Ordered list of drawable IDs
function DrawOrderManager:getDrawOrder()
    return { unpack(self._drawList) } -- Return a copy
end

---Get drawables in a specific layer
---@param layer number Layer to get drawables from
---@return string[] drawables Drawables in the specified layer
function DrawOrderManager:getDrawablesInLayer(layer)
    local layerGroup = self._layerGroups[layer]
    if not layerGroup or layerGroup.count == 0 then
        return {}
    end

    local drawables = {}
    for i = layerGroup.startIndex, layerGroup.startIndex + layerGroup.count - 1 do
        if self._drawList[i] then
            table.insert(drawables, self._drawList[i])
        end
    end

    return drawables
end

---Get the layer of a drawable
---@param drawableId string Drawable ID
---@return number|nil layer Layer number or nil if not found
function DrawOrderManager:getDrawableLayer(drawableId)
    return self._drawableToLayer[drawableId]
end

---Find the insertion index for a drawable with a specific layer order
---@param layer number Layer to insert into
---@param layerOrder number Layer order within the layer
---@return number index Insertion index
function DrawOrderManager:_findInsertionIndex(layer, layerOrder)
    local layerGroup = self._layerGroups[layer]
    local startIndex = layerGroup.startIndex
    local endIndex = startIndex + layerGroup.count

    -- Find correct position by comparing layerOrder values
    -- Lower layerOrder values should be drawn first (appear behind)
    for i = startIndex, endIndex - 1 do
        local existingDrawableId = self._drawList[i]
        local existingLayerOrder = self._drawableToLayerOrder[existingDrawableId]

        -- If existing drawable has no layerOrder, treat it as highest priority (drawn last)
        if not existingLayerOrder or layerOrder < existingLayerOrder then
            return i
        end
    end

    -- If not inserted yet, add to end of layer
    return endIndex
end

---Update indices and layer group metadata after insertion
---@param insertIndex number Index where item was inserted
---@param insertLayer number Layer of inserted item
function DrawOrderManager:_updateIndicesAfterInsertion(insertIndex, insertLayer)
    -- Update layer group counts and start indices
    for layer, group in pairs(self._layerGroups) do
        if layer == insertLayer then
            group.count = group.count + 1
        elseif group.startIndex >= insertIndex and layer ~= insertLayer then
            group.startIndex = group.startIndex + 1
        end
    end

    -- Invalidate indices for lazy rebuild
    self:_invalidateIndices()
end

---Update indices and layer group metadata after removal
---@param removedIndex number Index where item was removed
---@param removedLayer number Layer of removed item
function DrawOrderManager:_updateIndicesAfterRemoval(removedIndex, removedLayer)
    -- Update layer group counts and start indices
    for layer, group in pairs(self._layerGroups) do
        if layer == removedLayer then
            group.count = group.count - 1
        elseif group.startIndex > removedIndex then
            group.startIndex = group.startIndex - 1
        end
    end

    -- Invalidate indices for lazy rebuild
    self:_invalidateIndices()
end

---Invalidate indices (call when draw list changes)
function DrawOrderManager:_invalidateIndices()
    self._indicesValid = false
end

---Rebuild index mappings from the current draw list (lazy rebuild)
function DrawOrderManager:_rebuildIndices()
    -- Clear current mappings
    self._drawableToIndex = {}

    -- Rebuild from draw list
    for i, drawableId in ipairs(self._drawList) do
        self._drawableToIndex[drawableId] = i
    end

    self._indicesValid = true
end

---Get index with lazy rebuild if needed
---@param drawableId string The drawable ID to look up
---@return number|nil index Index in draw list, or nil if not found
function DrawOrderManager:_getIndex(drawableId)
    if not self._indicesValid then
        self:_rebuildIndices()
    end
    return self._drawableToIndex[drawableId]
end

---Debug: Print current draw order state
function DrawOrderManager:debugPrint()
    log.debug("=== Draw Order Manager State ===")
    log.debug("Total drawables: %d", #self._drawList)

    for layer, group in pairs(self._layerGroups) do
        local layerName = StageLayering:getLayerName(layer)
        log.debug("Layer %s: start=%d, count=%d",
            layerName, group.startIndex, group.count)
    end

    log.debug("Draw order:")
    for i, drawableId in ipairs(self._drawList) do
        local layer = self._drawableToLayer[drawableId]
        local layerName = layer and StageLayering:getLayerName(layer) or "UNKNOWN"
        log.debug("  [%d] %s (%s)", i, drawableId, layerName)
    end
    log.debug("=== End Draw Order State ===")
end

---Move a drawable to the front of its layer
---@param drawableId string The drawable to move
function DrawOrderManager:moveDrawableToFront(drawableId)
    local layer = self._drawableToLayer[drawableId]
    if not layer then
        log.warn("Cannot move to front - drawable not found: " .. tostring(drawableId))
        return
    end

    local group = self._layerGroups[layer]
    if not group then
        log.warn("Cannot move to front - layer group not found: " .. tostring(layer))
        return
    end

    -- Get current position using optimized index lookup
    local currentIndex = self:_getIndex(drawableId)
    if not currentIndex then
        log.warn("Cannot move to front - drawable not found in index: " ..
            tostring(drawableId) .. " (" .. type(drawableId) .. ")")
        log.warn("Current draw list: " .. table.concat(self._drawList, ", "))
        return
    end

    -- Target position is at the end of the layer group
    local targetIndex = group.startIndex + group.count - 1

    if currentIndex == targetIndex then
        -- Already at front
        return
    end

    -- Remove from current position and insert at target
    table.remove(self._drawList, currentIndex)
    table.insert(self._drawList, targetIndex, drawableId)

    -- Invalidate indices for lazy rebuild
    self:_invalidateIndices()
end

---Move a drawable to the back of its layer
---@param drawableId string The drawable to move
function DrawOrderManager:moveDrawableToBack(drawableId)
    local layer = self._drawableToLayer[drawableId]
    if not layer then
        log.warn("Cannot move to back - drawable not found: " .. tostring(drawableId))
        return
    end

    local group = self._layerGroups[layer]
    if not group then
        log.warn("Cannot move to back - layer group not found: " .. tostring(layer))
        return
    end

    -- Get current position using optimized index lookup
    local currentIndex = self:_getIndex(drawableId)
    if not currentIndex then
        log.warn("Cannot move to back - drawable not found in index: " .. tostring(drawableId))
        return
    end

    -- Target position is at the start of the layer group
    local targetIndex = group.startIndex

    if currentIndex == targetIndex then
        -- Already at back
        return
    end

    -- Remove from current position and insert at target
    table.remove(self._drawList, currentIndex)
    table.insert(self._drawList, targetIndex, drawableId)

    -- Invalidate indices for lazy rebuild
    self:_invalidateIndices()
end

return DrawOrderManager
