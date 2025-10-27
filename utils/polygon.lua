local ffi = require("ffi")
-- Initialize HC properly by requiring the main module first
local HC = require("lib.HC")
local Shapes = require("lib.HC.shapes")
local log = require("lib.log")

ffi.cdef [[
    typedef struct { uint8_t r, g, b, a; } Pixel;
]]

---@class PolygonManager
---@field cache table<love.ImageData, any> Cache mapping ImageData to PolygonShape
---@field points table<love.ImageData, table> Cache mapping ImageData to convex hull points
---@field hullDirty table<love.ImageData, boolean> Track which hulls need recalculation
---@field stats table Performance statistics
local PolygonManager = {}
PolygonManager.__index = PolygonManager

---Create a new PolygonManager instance
---@return PolygonManager manager New polygon manager
function PolygonManager:new()
    local manager = {
        cache = {},
        points = {},
        hullDirty = {},
        stats = {
            cacheHits = 0,
            cacheMisses = 0,
            hullCalculations = 0,
            totalCalculationTime = 0
        }
    }
    setmetatable(manager, self)
    return manager
end

---Check if convex hull needs recalculation (mimics needsConvexHullPoints)
---@param imagedata love.ImageData The image data to check
---@return boolean needsRecalc True if convex hull needs recalculation
function PolygonManager:needsConvexHullPoints(imagedata)
    return not self.points[imagedata] or
        self.hullDirty[imagedata] or
        (self.points[imagedata] and #self.points[imagedata] == 0)
end

---Mark convex hull as dirty for specific ImageData
---@param imagedata love.ImageData The image data to mark dirty
function PolygonManager:setConvexHullDirty(imagedata)
    self.hullDirty[imagedata] = true
end

---Check if three points are in counter-clockwise order
---@param a table Point with x, y fields
---@param b table Point with x, y fields
---@param c table Point with x, y fields
---@return boolean ccw True if counter-clockwise
local function ccw(a, b, c)
    return (b.x - a.x) * (c.y - a.y) > (b.y - a.y) * (c.x - a.x)
end

---Compute convex hull using Andrew's algorithm
---@param points table[] Array of points with x, y fields
---@return table[] hull Convex hull points
local function convexHull(points)
    if #points == 0 then
        return {}
    end

    -- Sort points by x-coordinate
    table.sort(points, function(left, right)
        return left.x < right.x
    end)

    local hull = {}

    -- Build lower hull
    for i, pt in ipairs(points) do
        while #hull >= 2 and not ccw(hull[#hull - 1], hull[#hull], pt) do
            table.remove(hull, #hull)
        end
        table.insert(hull, pt)
    end

    -- Build upper hull
    local t = #hull + 1
    for i = #points, 1, -1 do
        local pt = points[i]
        while #hull >= t and not ccw(hull[#hull - 1], hull[#hull], pt) do
            table.remove(hull, #hull)
        end
        table.insert(hull, pt)
    end

    -- Remove last point as it's same as first
    table.remove(hull, #hull)
    return hull
end

---Extract edge points from ImageData using efficient boundary scanning
---Similar to native Scratch convex hull algorithm
---@param imagedata love.ImageData The image data to analyze
---@return table[] points Array of edge points
local function extractEdgePoints(imagedata)
    local pixels = ffi.cast("Pixel*", imagedata:getFFIPointer())
    local width = imagedata:getWidth()
    local height = imagedata:getHeight()
    local points = {}

    -- Adaptive sampling based on image size (mimics native behavior)
    local maxSamples = 100 -- Limit total samples for performance
    local stepX = math.max(1, math.floor(width / math.sqrt(maxSamples)))
    local stepY = math.max(1, math.floor(height / math.sqrt(maxSamples)))

    -- Left and right boundary scan (similar to native Scratch algorithm)
    for y = 0, height - 1, stepY do
        -- Scan from left to find first opaque pixel
        for x = 0, width - 1 do
            local index = y * width + x
            local pixel = pixels[index]
            if pixel.a > 0 then
                table.insert(points, { x = x, y = y })
                break
            end
        end

        -- Scan from right to find first opaque pixel
        for x = width - 1, 0, -1 do
            local index = y * width + x
            local pixel = pixels[index]
            if pixel.a > 0 then
                -- Avoid duplicate points
                if #points == 0 or points[#points].x ~= x or points[#points].y ~= y then
                    table.insert(points, { x = x, y = y })
                end
                break
            end
        end
    end

    -- Top and bottom boundary scan for completeness
    for x = 0, width - 1, stepX do
        -- Scan from top
        for y = 0, height - 1 do
            local index = y * width + x
            local pixel = pixels[index]
            if pixel.a > 0 then
                table.insert(points, { x = x, y = y })
                break
            end
        end

        -- Scan from bottom
        for y = height - 1, 0, -1 do
            local index = y * width + x
            local pixel = pixels[index]
            if pixel.a > 0 then
                table.insert(points, { x = x, y = y })
                break
            end
        end
    end

    return points
end

---Get or create polygon shape for ImageData with performance tracking
---@param imagedata love.ImageData The image data to get polygon for
---@return any|nil polygon The polygon shape, or nil if failed
function PolygonManager:getPolygon(imagedata)
    -- Check cache first (mimics native fast path)
    if self.cache[imagedata] and not self.hullDirty[imagedata] then
        self.stats.cacheHits = self.stats.cacheHits + 1
        return self.cache[imagedata]
    end

    -- Cache miss - need to calculate
    self.stats.cacheMisses = self.stats.cacheMisses + 1
    local startTime = love.timer.getTime()

    -- Extract edge points using optimized boundary scanning
    local edgePoints = extractEdgePoints(imagedata)

    if #edgePoints < 3 then
        -- This typically happens when:
        -- 1. Image is completely transparent (all pixels alpha=0)
        -- 2. SVG rendering failed and fallback empty image was used
        -- 3. Image is too small (1x1 pixel)
        -- System will automatically fallback to AABB bounds - no user action needed
        log.debug("[PolygonManager] Not enough edge points (%d) - image may be transparent or failed to load. Using AABB fallback.", #edgePoints)
        return nil
    end

    -- Compute convex hull
    local hull = convexHull(edgePoints)

    if #hull < 3 then
        log.debug("[PolygonManager] Invalid convex hull (%d points) - using AABB fallback.", #hull)
        return nil
    end

    -- Convert to flat coordinates array for HC
    local vertices = {}
    for i, point in ipairs(hull) do
        table.insert(vertices, point.x)
        table.insert(vertices, point.y)
    end

    -- Create polygon shape using Shapes.newPolygonShape
    local success, polygon = pcall(Shapes.newPolygonShape, unpack(vertices))
    if not success then
        log.debug("[PolygonManager] Failed to create polygon shape: %s - using AABB fallback.", tostring(polygon))
        return nil
    end

    -- Cache results and mark as clean
    self.cache[imagedata] = polygon
    self.points[imagedata] = hull
    self.hullDirty[imagedata] = false

    -- Update performance statistics
    local calculationTime = love.timer.getTime() - startTime
    self.stats.hullCalculations = self.stats.hullCalculations + 1
    self.stats.totalCalculationTime = self.stats.totalCalculationTime + calculationTime

    return polygon
end

---Get cached convex hull points for ImageData
---@param imagedata love.ImageData The image data
---@return table[]|nil points Convex hull points, or nil if not cached
function PolygonManager:getPoints(imagedata)
    return self.points[imagedata]
end

---Create a transformed polygon using Love2D Transform API (optimized version)
---@param imagedata love.ImageData The image data
---@param spriteX number Sprite X position in Scratch coordinates
---@param spriteY number Sprite Y position in Scratch coordinates
---@param size number Sprite size percentage
---@param direction number Sprite direction in degrees
---@param rotationStyle string Rotation style ("all around", "left-right", "don't rotate")
---@param originX number Rotation center X in pixels
---@param originY number Rotation center Y in pixels
---@param bitmapResolution number Bitmap resolution factor
---@param runtime Runtime Runtime instance for coordinate conversion
---@return any|nil polygon Transformed polygon or nil if failed
function PolygonManager:getTransformedPolygon(imagedata, spriteX, spriteY, size, direction, rotationStyle, originX,
                                              originY, bitmapResolution, runtime)
    local basePolygon = self:getPolygon(imagedata)
    if not basePolygon then
        return nil
    end

    local baseVertices = basePolygon._polygon.vertices
    if not baseVertices or #baseVertices < 3 then
        return nil
    end

    -- Build transformation matrix using Love2D Transform API
    -- Transform chain: Image coords → Local (relative to rotation center) → Scale → Rotate → World
    local transform = love.math.newTransform()

    -- Step 1: Translate to sprite world position
    transform:translate(spriteX, spriteY)

    -- Step 2: Apply rotation (if applicable)
    local scaleX = size / 100 / bitmapResolution
    local scaleY = size / 100 / bitmapResolution

    if rotationStyle == "all around" then
        local rotation = math.rad(direction - 90)
        transform:rotate(rotation)
    elseif rotationStyle == "left-right" and direction < 0 then
        scaleX = -scaleX  -- Horizontal flip via negative scale
    end

    -- Step 3: Apply scale
    transform:scale(scaleX, scaleY)

    -- Step 4: Y-flip (image coords have Y-down, Scratch has Y-up)
    transform:scale(1, -1)

    -- Step 5: Translate by rotation center offset
    transform:translate(-originX, -originY)

    -- Extract transformation matrix once
    local e11, e12, _, e14,
          e21, e22, _, e24 = transform:getMatrix()

    -- Apply transformation to all vertices
    local verts = {}
    for i, vertex in ipairs(baseVertices) do
        -- Apply transformation matrix to vertex
        local worldX = e11 * vertex.x + e12 * vertex.y + e14
        local worldY = e21 * vertex.x + e22 * vertex.y + e24

        -- Convert from Scratch world coords to screen coords
        local screenX = runtime:scratchToScreenX(worldX)
        local screenY = runtime:scratchToScreenY(worldY)

        verts[i * 2 - 1] = screenX
        verts[i * 2] = screenY
    end

    return Shapes.newPolygonShape(unpack(verts))
end

---Clear cache for specific ImageData
---@param imagedata love.ImageData The image data to remove from cache
function PolygonManager:clearCache(imagedata)
    self.cache[imagedata] = nil
    self.points[imagedata] = nil
end

---Clear all cached data
function PolygonManager:clearAllCache()
    self.cache = {}
    self.points = {}
end

---Get cache statistics including performance metrics
---@return table stats Statistics about cached data and performance
function PolygonManager:getStats()
    local cacheCount = 0
    for _ in pairs(self.cache) do
        cacheCount = cacheCount + 1
    end

    local hitRate = 0
    local totalAccess = self.stats.cacheHits + self.stats.cacheMisses
    if totalAccess > 0 then
        hitRate = self.stats.cacheHits / totalAccess
    end

    local avgCalculationTime = 0
    if self.stats.hullCalculations > 0 then
        avgCalculationTime = self.stats.totalCalculationTime / self.stats.hullCalculations
    end

    return {
        cachedPolygons = cacheCount,
        cachedPoints = cacheCount,
        cacheHits = self.stats.cacheHits,
        cacheMisses = self.stats.cacheMisses,
        hitRate = hitRate,
        hullCalculations = self.stats.hullCalculations,
        totalCalculationTime = self.stats.totalCalculationTime,
        avgCalculationTime = avgCalculationTime
    }
end

return PolygonManager
