-- Pen Renderer
-- Implements optimized Scratch pen rendering with node-based path system and incremental rendering
local Global = require("global")
local log = require("lib.log")
local ColorUtils = require("utils.color_utils")
require("table.clear")
require("table.new")

---@class PathNode
---@field x number Path point X coordinate in Scratch coordinates
---@field y number Path point Y coordinate in Scratch coordinates
---@field size number Pen size
---@field rgba number[] Color [r,g,b,a]
---@field nodeType "line"|"point"|"stamp"|"clear" Node type
---@field endX number|nil End X coordinate (for line nodes)
---@field endY number|nil End Y coordinate (for line nodes)
---@field drawFunc function|nil Drawing function (for stamp)
---@field transform table|nil Transform data (for stamp)

---@class PenShaderState
---@field color number[] Last non-premultiplied RGBA color submitted to the shader
---@field size number Last pen size submitted to the shader
---@field shaderChanged boolean Forces next uniform submission to refresh cached values

---@class PenRenderer
---@field canvas love.Canvas The pen drawing canvas (480x360)
---@field pathNodes PathNode[] All path nodes in drawing order
---@field penShader love.Shader Pen line shader for GPU rendering (required)
---@field unitQuadMesh love.Mesh Unit quad mesh for shader-based line rendering
---@field _shaderActive boolean Tracks whether the GPU pen shader is currently bound
---@field _shaderState PenShaderState Cached shader uniform state for color/size reuse
---@field _premultColor number[] Reusable buffer for premultiplied RGBA uniforms
---@field _penPointsBuffer number[] Reusable buffer for pen point uniform submission
---@field renderQuality number Resolution multiplier for high-quality pen rendering (default 2)
---@field actualCanvasWidth number Actual canvas width with renderQuality applied
---@field actualCanvasHeight number Actual canvas height with renderQuality applied
---@field _isDirty boolean Dirty flag for cached ImageData
---@field _cachedImageData love.ImageData|nil Cached full canvas ImageData for fast color sampling
local PenRenderer = {}
PenRenderer.__index = PenRenderer

---Create a new pen renderer
---@return PenRenderer
function PenRenderer:new()
    local self = setmetatable({}, PenRenderer)

    -- High quality rendering multiplier
    self.renderQuality = Global.SVG_RESOLUTION_SCALE

    -- Actual canvas size with quality multiplier
    self.actualCanvasWidth = Global.STAGE_WIDTH * self.renderQuality
    self.actualCanvasHeight = Global.STAGE_HEIGHT * self.renderQuality

    -- Create pen canvas with higher resolution for quality
    -- using Love2D's automatic DPI scaling. This is because automatic DPI scaling can cause color
    -- interpolation issues with pen drawing, where colors blend incorrectly at boundaries
    -- (e.g., white pen strokes appearing gray due to unwanted interpolation).
    -- By manually controlling the canvas size and scaling during draw operations, we maintain
    -- precise control over pixel rendering and avoid these color artifacts.
    self.canvas = love.graphics.newCanvas(self.actualCanvasWidth, self.actualCanvasHeight, {
        format = "rgba8",
        dpiscale = 1,                         -- Disable automatic DPI scaling to avoid color interpolation issues
    })
    self.canvas:setFilter("linear", "linear") -- Use linear filtering for smooth downscaling when drawing to screen
    self.pathNodes = table.new(100, 0)        -- Preallocate for performance
    self._premultColor = { 0, 0, 0, 0 }
    self._penPointsBuffer = { 0, 0, 0, 0 }
    self._shaderActive = false
    self._shaderState = {
        color = { -1, -1, -1, -1 },
        size = -1,
        shaderChanged = false,
    }

    self._isDirty = true
    self._cachedImageData = nil

    -- Create reusable unit quad mesh for shader rendering (two triangles covering unit square)
    local vertices = {
        { 0, 0, 0, 0 }, -- Triangle 1
        { 1, 0, 1, 0 },
        { 1, 1, 1, 1 },
        { 0, 0, 0, 0 }, -- Triangle 2
        { 1, 1, 1, 1 },
        { 0, 1, 0, 1 },
    }
    self.unitQuadMesh = love.graphics.newMesh(vertices, "triangles", "static")

    -- Initialize canvas
    self.canvas:renderTo(function()
        love.graphics.clear(0, 0, 0, 0)
    end)

    -- Initialize shader (mandatory for GPU-only rendering)
    self:initializeShader()
    return self
end

---Initialize pen line shader for GPU rendering (mandatory)
function PenRenderer:initializeShader()
    local success, shader = pcall(love.graphics.newShader, "pen/pen_line_love2d.glsl")
    if not success then
        error("PenRenderer: Failed to load required pen shader: " .. tostring(shader))
    end

    self.penShader = shader

    self._shaderState.shaderChanged = true
    log.info("PenRenderer: Successfully loaded pen line shader (GPU-only pipeline)")
end

---Activate the GPU pen shader
---@return boolean shaderBound Whether the shader state was changed
function PenRenderer:_activatePenShader()
    if not self._shaderActive then
        love.graphics.setShader(self.penShader)
        self._shaderActive = true
        self._shaderState.shaderChanged = true
        return true
    end

    return false
end

---Deactivate the GPU pen shader if it is bound
function PenRenderer:_deactivatePenShader()
    if self._shaderActive then
        love.graphics.setShader()
        self._shaderActive = false
    end
end

---Update cached pen color uniform if needed
---@param r number
---@param g number
---@param b number
---@param a number
function PenRenderer:_updateShaderColor(r, g, b, a)
    local state = self._shaderState
    local color = state.color

    if state.shaderChanged or color[1] ~= r or color[2] ~= g or color[3] ~= b or color[4] ~= a then
        color[1], color[2], color[3], color[4] = r, g, b, a

        local premult = self._premultColor
        premult[1] = r * a
        premult[2] = g * a
        premult[3] = b * a
        premult[4] = a

        self.penShader:send("u_penColor", premult)
    end
end

---Update cached pen size uniform if needed
---@param size number
function PenRenderer:_updateShaderSize(size)
    local state = self._shaderState
    if state.shaderChanged or state.size ~= size then
        state.size = size
        self.penShader:send("u_penSize", size)
    end

    state.shaderChanged = false
end

---Convert Scratch coordinates to canvas coordinates
---@param scratchX number Scratch X coordinate
---@param scratchY number Scratch Y coordinate
---@return number canvasX Canvas X coordinate
---@return number canvasY Canvas Y coordinate
function PenRenderer:scratchToCanvas(scratchX, scratchY)
    -- Apply renderQuality scaling to coordinates
    local canvasX = (scratchX + Global.STAGE_HALF_WIDTH) * self.renderQuality
    local canvasY = (Global.STAGE_HALF_HEIGHT - scratchY) * self.renderQuality
    return canvasX, canvasY
end

---Convert Scratch HSV values to RGBA
---@param hue number Hue value (0-100, wraps around) - matches native Scratch range
---@param saturation number Saturation value (0-100) - maps to HSV S
---@param brightness number Brightness value (0-100) - maps to HSV V
---@param transparency number Transparency value (0-100, 0 is opaque)
---@return number r Red component (0-1)
---@return number g Green component (0-1)
---@return number b Blue component (0-1)
---@return number a Alpha component (0-1)
function PenRenderer:scratchColorToRGBA(hue, saturation, brightness, transparency)
    -- Convert Scratch HSV to RGB using shared utility
    local r, g, b = ColorUtils.scratchHsvToRgb(hue, saturation, brightness)

    -- Apply transparency (0-100, 0 is opaque)
    transparency = math.max(0, math.min(100, transparency))
    local alpha = 1 - (transparency / 100)

    return r, g, b, alpha
end

---Add a line drawing node to the path
---@param x0 number Starting X in Scratch coordinates
---@param y0 number Starting Y in Scratch coordinates
---@param x1 number Ending X in Scratch coordinates
---@param y1 number Ending Y in Scratch coordinates
---@param size number Pen size in stage pixels
---@param hue number Hue (0-100) - matches native Scratch range
---@param saturation number Saturation (0-100)
---@param brightness number Brightness (0-100)
---@param transparency number Transparency (0-100)
function PenRenderer:queueLine(x0, y0, x1, y1, size, hue, saturation, brightness, transparency)
    -- Skip zero-length lines
    if x0 == x1 and y0 == y1 then
        log.debug("PenRenderer: Skipping zero-length line at (%.2f,%.2f)", x0, y0)
        return
    end

    -- Apply Scratch 2.0 pixel alignment for pen sizes 1 and 3
    local offset = (size == 1 or size == 3) and 0.5 or 0
    x0 = x0 + offset
    y0 = y0 + offset
    x1 = x1 + offset
    y1 = y1 + offset

    local r, g, b, a = self:scratchColorToRGBA(hue, saturation, brightness, transparency)
    log.debug(
        "PenRenderer: queueLine HSV(%.1f,%.1f,%.1f) -> RGBA(%.3f,%.3f,%.3f,%.3f)",
        hue, saturation, brightness, r, g, b, a
    )

    -- Create path node
    local node = {
        x = x0,
        y = y0,
        endX = x1,
        endY = y1,
        size = size,
        rgba = { r, g, b, a },
        nodeType = "line",
    }

    table.insert(self.pathNodes, node)
end

---Add a point drawing node to the path (for pen down)
---@param x number X coordinate
---@param y number Y coordinate
---@param size number Pen size
---@param hue number Hue (0-100) - matches native Scratch range
---@param saturation number Saturation (0-100)
---@param brightness number Brightness (0-100)
---@param transparency number Transparency (0-100)
function PenRenderer:queuePoint(x, y, size, hue, saturation, brightness, transparency)
    -- Apply Scratch 2.0 pixel alignment for pen sizes 1 and 3
    local offset = (size == 1 or size == 3) and 0.5 or 0
    x = x + offset
    y = y + offset

    local r, g, b, a = self:scratchColorToRGBA(hue, saturation, brightness, transparency)
    log.debug(
        "PenRenderer: queuePoint HSV(%.1f,%.1f,%.1f) -> RGBA(%.3f,%.3f,%.3f,%.3f)",
        hue, saturation, brightness, r, g, b, a
    )

    -- Create point node
    local node = {
        x = x,
        y = y,
        size = size,
        rgba = { r, g, b, a },
        nodeType = "point",
    }

    table.insert(self.pathNodes, node)
end

---Add a stamp node to the path
---@param drawFunc function Function to draw the sprite
---@param transform table Transform snapshot
function PenRenderer:queueStamp(drawFunc, transform)
    local node = {
        drawFunc = drawFunc,
        transform = transform,
        nodeType = "stamp",
    }

    table.insert(self.pathNodes, node)
end

---Clear all drawing (add clear node to path)
function PenRenderer:queueClear()
    local node = {
        nodeType = "clear",
    }

    -- Clear all previous nodes and add clear node
    table.clear(self.pathNodes)
    table.insert(self.pathNodes, node)
end

---Draw a line segment using shader-based rendering (GPU accelerated with perfect anti-aliasing)
---@param x0 number Starting X in Scratch coordinates
---@param y0 number Starting Y in Scratch coordinates
---@param x1 number Ending X in Scratch coordinates
---@param y1 number Ending Y in Scratch coordinates
---@param size number Pen size
---@param r number Red component
---@param g number Green component
---@param b number Blue component
---@param a number Alpha component
function PenRenderer:drawShaderLine(x0, y0, x1, y1, size, r, g, b, a)
    self:_updateShaderColor(r, g, b, a)
    -- Apply renderQuality to shader size
    self:_updateShaderSize(size * self.renderQuality)

    local canvasX0, canvasY0 = self:scratchToCanvas(x0, y0)
    local canvasX1, canvasY1 = self:scratchToCanvas(x1, y1)

    local dx = canvasX1 - canvasX0
    local dy = canvasY1 - canvasY0
    local length = math.sqrt((dx * dx) + (dy * dy))

    local penPoints = self._penPointsBuffer
    penPoints[1] = canvasX0
    penPoints[2] = canvasY0
    penPoints[3] = dx
    penPoints[4] = dy
    self.penShader:send("u_penPoints", penPoints)
    self.penShader:send("u_lineLength", length)

    -- Draw unit quad - vertex shader will transform it to correct line geometry
    love.graphics.setColor(1, 1, 1, 1)
    love.graphics.draw(self.unitQuadMesh)
end

---Draw a point using shader-based rendering
---@param x number X coordinate in Scratch coordinates
---@param y number Y coordinate in Scratch coordinates
---@param size number Pen size
---@param r number Red component
---@param g number Green component
---@param b number Blue component
---@param a number Alpha component
function PenRenderer:drawShaderPoint(x, y, size, r, g, b, a)
    self:drawShaderLine(x, y, x, y, size, r, g, b, a)
end

---Execute path nodes and render to pen canvas
function PenRenderer:flush()
    -- Skip if no nodes to render
    if #self.pathNodes == 0 then
        return
    end

    self.canvas:renderTo(function()
        local prevBlendMode, prevAlphaMode = love.graphics.getBlendMode()

        -- Render nodes with premultiplied alpha blending to match Scratch GPU pipeline
        love.graphics.setBlendMode("alpha", "premultiplied")

        for _, node in ipairs(self.pathNodes) do
            self:renderNode(node)
        end

        self:_deactivatePenShader()
        love.graphics.setBlendMode(prevBlendMode, prevAlphaMode)
    end)

    -- Mark cache as dirty after rendering
    self._isDirty = true

    -- Clear all nodes after flush - they are now committed to canvas
    if #self.pathNodes < 100 then
        table.clear(self.pathNodes)
    else
        self.pathNodes = table.new(100, 0)
    end
end

---Render a single path node
---@param node PathNode The node to render
function PenRenderer:renderNode(node)
    if node.nodeType == "clear" then
        self:_deactivatePenShader()
        love.graphics.clear(0, 0, 0, 0)
    elseif node.nodeType == "line" then
        local r, g, b, a = unpack(node.rgba)
        self:_activatePenShader()
        self:drawShaderLine(node.x, node.y, node.endX, node.endY, node.size, r, g, b, a)
    elseif node.nodeType == "point" then
        local r, g, b, a = unpack(node.rgba)
        self:_activatePenShader()
        self:drawShaderPoint(node.x, node.y, node.size, r, g, b, a)
    elseif node.nodeType == "stamp" then
        -- Execute stamp drawing function with transform
        self:_deactivatePenShader()
        if node.drawFunc and node.transform then
            love.graphics.setBlendMode("alpha", "alphamultiply")
            node.drawFunc(node.transform)
            love.graphics.setBlendMode("alpha", "premultiplied")
        end
    end
end

---Get the pen canvas for rendering
---@return love.Canvas canvas The pen drawing canvas
function PenRenderer:getCanvas()
    return self.canvas
end

---Update cached ImageData if dirty (optimization pattern)
---This method implements the lazy caching system to minimize expensive GPU readbacks
function PenRenderer:_updateCachedImageData()
    if self._isDirty then
        -- Release old cached data if it exists
        if self._cachedImageData then
            self._cachedImageData:release()
        end

        -- Read entire canvas once into cache (updateSilhouette pattern)
        self._cachedImageData = self.canvas:newImageData()
        self._isDirty = false

        log.debug("PenRenderer: Updated cached ImageData (full canvas read)")
    end
end

---Sample pen layer color at Scratch coordinates (for CPU collision detection)
---Returns premultiplied RGBA in 0-255 range to match native Scratch behavior
---Uses dirty flag caching to minimize expensive GPU readbacks
---@param scratchX number X coordinate in Scratch space
---@param scratchY number Y coordinate in Scratch space
---@return number r Red component (0-255)
---@return number g Green component (0-255)
---@return number b Blue component (0-255)
---@return number a Alpha component (0-255)
function PenRenderer:sampleColor(scratchX, scratchY)
    -- Convert Scratch coordinates to pen canvas coordinates
    local canvasX, canvasY = self:scratchToCanvas(scratchX, scratchY)

    -- Clamp to canvas bounds
    if canvasX < 0 or canvasX >= self.actualCanvasWidth or
       canvasY < 0 or canvasY >= self.actualCanvasHeight then
        return 0, 0, 0, 0
    end

    -- Update cache if dirty (lazy read pattern)
    self:_updateCachedImageData()

    -- Fast pixel access from cached ImageData (no GPU readback!)
    local r, g, b, a = self._cachedImageData:getPixel(math.floor(canvasX), math.floor(canvasY))

    -- Convert from 0-1 range to 0-255 range
    -- Note: The canvas stores colors in premultiplied alpha format,
    -- matching native Scratch's pen layer behavior
    return math.floor(r * 255 + 0.5),
           math.floor(g * 255 + 0.5),
           math.floor(b * 255 + 0.5),
           math.floor(a * 255 + 0.5)
end

---Release cached ImageData to free memory (call when collision detection is done)
function PenRenderer:releaseCachedData()
    if self._cachedImageData then
        self._cachedImageData:release()
        self._cachedImageData = nil
        self._isDirty = true
        log.debug("PenRenderer: Released cached ImageData")
    end
end

return PenRenderer
