-- Simple bubble renderer using SVG and resvg
-- Text width measurement uses Global.cjkFont (if available) for accurate CJK character width
-- Falls back to estimation-based calculation when CJK font is not loaded
local Global = require "global"
local resvg = require("lib.resvg")
local log = require("lib.log")
local utf8 = require("utf8")

---@class BubbleRenderer
---@field font love.Font Font used for non-CJK text measurement (Noto Sans)
---@field cjkCharWidth number Cached CJK character width for fallback estimation
local BubbleRenderer = {}
BubbleRenderer.__index = BubbleRenderer

-- Match Scratch bubble style constants
local MAX_LINE_WIDTH = 170                 -- Single line max width (Scratch pixels)
local MIN_WIDTH = 50                       -- Bubble minimum width (Scratch pixels)
local STROKE_WIDTH = 4                     -- Border width (only half visible)
local PADDING = 10                         -- Text area padding
local CORNER_RADIUS = 16                   -- Rounded corner radius
local TAIL_HEIGHT = 12                     -- Bubble tail height

local FONT_SIZE = 14                       -- Font size (Scratch pixels)
local FONT_HEIGHT_RATIO = 0.9              -- Text height to font size ratio
local LINE_HEIGHT = 16                     -- Line height

local TEXT_COLOR = { 0.34, 0.37, 0.46, 1 } -- #575E75
local STROKE_COLOR = { 0, 0, 0, 0.15 }
local FILL_COLOR = { 1, 1, 1, 1 }

-- Font to load for resvg and to measure wraps with Love2D
local FONT_PATH = "assets/fonts/NotoSans-Medium.ttf"
local FONT_FAMILY = "Noto Sans"

---Create a new bubble renderer
---@return BubbleRenderer
function BubbleRenderer:new()
    local self = setmetatable({}, BubbleRenderer)
    self.font = love.graphics.newFont(FONT_PATH, FONT_SIZE)
    self.font:setFilter("linear", "linear")

    -- Cache CJK character width for correction calculation
    -- Use U+4E2D (CJK Unified Ideograph) as representative character
    self.cjkCharWidth = self.font:getWidth("\u{4E2D}")

    return self
end

---Check if a codepoint is CJK character
---@param codepoint number Unicode codepoint
---@return boolean
local function isCJK(codepoint)
    return (codepoint >= 0x4E00 and codepoint <= 0x9FFF) or -- CJK Ideographs
        (codepoint >= 0x3040 and codepoint <= 0x309F) or    -- Hiragana
        (codepoint >= 0x30A0 and codepoint <= 0x30FF) or    -- Katakana
        (codepoint >= 0xAC00 and codepoint <= 0xD7AF) or    -- Hangul
        (codepoint >= 0xFF00 and codepoint <= 0xFFEF)       -- Full-width
end

---Calculate corrected width for text line with CJK character consideration
---@param line string Text line to measure
---@return number width Corrected width in pixels
function BubbleRenderer:calculateLineWidth(line)
    -- If Global.cjkFont is available (all platforms attempt to load it),
    -- use it directly for text with CJK characters for accurate measurement
    if Global.cjkFont then
        local hasCJK = false
        for pos, codepoint in utf8.codes(line) do
            if isCJK(codepoint) then
                hasCJK = true
                break
            end
        end

        if hasCJK then
            -- Use CJK font to measure the entire line for accurate width
            return Global.cjkFont:getWidth(line)
        else
            -- Pure non-CJK text, use default font
            return self.font:getWidth(line)
        end
    end

    -- Fallback: estimation-based calculation when CJK font is not available
    -- Single pass: count CJK and collect non-CJK characters
    local cjkCount = 0
    local nonCJKChars = {}

    for pos, codepoint in utf8.codes(line) do
        if isCJK(codepoint) then
            cjkCount = cjkCount + 1
        else
            local charEnd = utf8.offset(line, 2, pos) or (#line + 1)
            table.insert(nonCJKChars, line:sub(pos, charEnd - 1))
        end
    end

    -- Fast path: pure non-CJK text
    if cjkCount == 0 then
        return self.font:getWidth(line)
    end

    -- Calculate width for mixed or pure CJK text
    local nonCJKWidth = #nonCJKChars > 0 and self.font:getWidth(table.concat(nonCJKChars)) or 0
    local cjkTotalWidth = self.cjkCharWidth * cjkCount * 1.5

    return nonCJKWidth + cjkTotalWidth
end

---Draw complete bubble (format text, calculate position, render and draw)
---@param sprite table The sprite showing the bubble
---@param text any The bubble text (will be formatted)
---@param bubbleType "say"|"think"
---@param runtime Runtime Runtime instance for coordinate conversion
function BubbleRenderer:drawBubble(sprite, text, bubbleType, runtime)
    love.graphics.push()

    if text == "" then
        love.graphics.pop()
        return
    end

    -- Use bubble font
    -- Render bubble with integrated positioning
    local success, imageData, _, _, drawX, drawY = pcall(
        self.renderBubble, self, text, bubbleType, sprite, runtime)

    if not success then
        log.warn("Failed to render bubble: " .. tostring(imageData))
        love.graphics.pop()
        return
    end

    -- Convert ImageData to Image for drawing and immediately use it
    local success, bubbleImage = pcall(love.graphics.newImage, imageData)
    if success then
        love.graphics.setColor(1, 1, 1, 1) -- Reset color to white for image drawing
        -- Scale down the high-resolution bubble to logical size
        local scale = 1 / Global.SVG_RESOLUTION_SCALE
        love.graphics.draw(bubbleImage, drawX, drawY, 0, scale, scale)
        -- Clean up the image immediately after drawing
        bubbleImage:release()
    else
        log.warn("Failed to create bubble image: " .. tostring(bubbleImage))
    end

    love.graphics.pop()
end

---Calculate bubble position and side
---@param sprite Sprite The sprite showing the bubble
---@param runtime Runtime Runtime instance for coordinate conversion
---@param text string The bubble text
---@param bubbleType string "say" or "think"
---@return number drawX Final draw X position (screen coords)
---@return number drawY Final draw Y position (screen coords)
---@return boolean pointsLeft Whether bubble tail points left
function BubbleRenderer:calculatePosition(sprite, runtime, text, bubbleType)
    -- Pre-calculate bubble dimensions for positioning (in logical pixels)
    local _, textLines = self.font:getWrap(text, MAX_LINE_WIDTH)

    local longest = 0
    for i = 1, #textLines do
        local w = self:calculateLineWidth(textLines[i])
        if w > longest then longest = w end
    end

    local paddedWidth = math.max(longest, MIN_WIDTH) + (PADDING * 2)
    local paddedHeight = (LINE_HEIGHT * #textLines) + (PADDING * 2)
    -- These are logical bubble dimensions (what Scratch sees)
    local logicalBubbleWidth = paddedWidth + STROKE_WIDTH
    local logicalBubbleHeight = paddedHeight + STROKE_WIDTH + TAIL_HEIGHT

    -- Calculate sprite bounds for bubble positioning, considering rotation
    local function getSpriteBoundsForBubble()
        local costume = sprite:getCurrentCostume()
        local bounds = {
            left = sprite.x,
            right = sprite.x,
            top = sprite.y,
            bottom = sprite.y
        }

        if costume and costume.image then
            local bitmapResolution = costume.bitmapResolution or 1
            local imageWidth = costume.image:getWidth()
            local imageHeight = costume.image:getHeight()
            local rotationCenterX = costume.rotationCenterX or (imageWidth / 2)
            local rotationCenterY = costume.rotationCenterY or (imageHeight / 2)
            local scale = sprite.size / 100

            -- Convert costume dimensions to Scratch coordinate space
            local costumeWidth = (imageWidth / bitmapResolution) * scale
            local costumeHeight = (imageHeight / bitmapResolution) * scale

            -- Calculate offset from rotation center to image center
            local offsetX = (rotationCenterX - imageWidth / 2) / bitmapResolution * scale
            local offsetY = (rotationCenterY - imageHeight / 2) / bitmapResolution * scale

            -- Get rotation angle in radians (Scratch uses degrees, clockwise)
            local rotationDegrees = sprite.direction - 90 -- Convert to standard math coordinates
            local rotationRadians = math.rad(rotationDegrees)
            local cosR = math.cos(rotationRadians)
            local sinR = math.sin(rotationRadians)

            -- Calculate the four corners of the costume in local coordinates
            -- (relative to the sprite position, before rotation)
            local halfWidth = costumeWidth / 2
            local halfHeight = costumeHeight / 2
            local corners = {
                { x = -halfWidth - offsetX, y = halfHeight + offsetY },  -- top-left
                { x = halfWidth - offsetX,  y = halfHeight + offsetY },  -- top-right
                { x = halfWidth - offsetX,  y = -halfHeight + offsetY }, -- bottom-right
                { x = -halfWidth - offsetX, y = -halfHeight + offsetY }  -- bottom-left
            }

            -- Apply rotation and translation to each corner
            local transformedCorners = {}
            for i, corner in ipairs(corners) do
                local rotatedX = corner.x * cosR - corner.y * sinR
                local rotatedY = corner.x * sinR + corner.y * cosR
                transformedCorners[i] = {
                    x = sprite.x + rotatedX,
                    y = sprite.y + rotatedY
                }
            end

            -- Find the bounding box of the rotated sprite
            local minX, maxX = transformedCorners[1].x, transformedCorners[1].x
            local minY, maxY = transformedCorners[1].y, transformedCorners[1].y

            for i = 2, #transformedCorners do
                local corner = transformedCorners[i]
                minX = math.min(minX, corner.x)
                maxX = math.max(maxX, corner.x)
                minY = math.min(minY, corner.y)
                maxY = math.max(maxY, corner.y)
            end

            -- Following original Scratch logic: only consider top slice for bubble positioning
            -- Original uses top 8px slice, we'll use a proportional slice
            local BUBBLE_SLICE_HEIGHT = 8 * scale -- Scale the slice height with sprite
            local topSliceMinY = maxY - BUBBLE_SLICE_HEIGHT

            -- Filter corners that are in the top slice
            local topSliceCorners = {}
            for i, corner in ipairs(transformedCorners) do
                if corner.y >= topSliceMinY then
                    table.insert(topSliceCorners, corner)
                end
            end

            -- If no corners in top slice, use the highest point
            if #topSliceCorners == 0 then
                -- Find the corner with highest Y
                local highestCorner = transformedCorners[1]
                for i = 2, #transformedCorners do
                    if transformedCorners[i].y > highestCorner.y then
                        highestCorner = transformedCorners[i]
                    end
                end
                topSliceCorners = { highestCorner }
            end

            -- Calculate bounds from top slice corners only
            local sliceMinX, sliceMaxX = topSliceCorners[1].x, topSliceCorners[1].x
            for i = 2, #topSliceCorners do
                local corner = topSliceCorners[i]
                sliceMinX = math.min(sliceMinX, corner.x)
                sliceMaxX = math.max(sliceMaxX, corner.x)
            end

            bounds.left = sliceMinX
            bounds.right = sliceMaxX
            bounds.bottom = minY -- Still use full sprite bottom for reference
            bounds.top = maxY    -- Top is still the sprite's highest point
        else
            -- Fallback for sprites without costumes
            local defaultSize = 20 * (sprite.size / 100)
            bounds.left = sprite.x - defaultSize
            bounds.right = sprite.x + defaultSize
            bounds.top = sprite.y + defaultSize
            bounds.bottom = sprite.y - defaultSize
        end

        return bounds
    end

    local targetBounds = getSpriteBoundsForBubble()
    local stageBounds = {
        left = Global.SCRATCH_MIN_X,
        right = Global.SCRATCH_MAX_X,
        top = Global.SCRATCH_MAX_Y,
        bottom = Global.SCRATCH_MIN_Y
    }

    -- Determine bubble side - whether bubble should appear on sprite's right or left
    local onSpriteRight = true
    if targetBounds.right + logicalBubbleWidth > stageBounds.right and
        (targetBounds.left - logicalBubbleWidth > stageBounds.left) then
        onSpriteRight = false
    end

    -- Calculate bubble X position in Scratch coordinates
    -- Following original Scratch positioning logic exactly
    local bubbleX
    if onSpriteRight then
        -- Bubble on sprite's right side
        -- Try to position bubble starting from sprite's right edge
        bubbleX = math.max(
            stageBounds.left, -- Don't go past left stage edge
            math.min(stageBounds.right - logicalBubbleWidth, targetBounds.right)
        )
    else
        -- Bubble on sprite's left side
        bubbleX = math.min(
            stageBounds.right - logicalBubbleWidth, -- Don't go past right stage edge
            math.max(stageBounds.left, targetBounds.left - logicalBubbleWidth)
        )
    end

    -- Y position: Follow original Scratch logic exactly
    -- Original: Math.min(stageBounds.top, targetBounds.bottom + bubbleHeight)
    -- This positions the bubble's TOP edge, not bottom
    local bubbleTopScratchY = math.min(stageBounds.top, targetBounds.top + logicalBubbleHeight)

    -- bubbleTopScratchY is where the bubble's top should be in Scratch coordinates
    -- For drawing, we need this exact position since Love2D draws from top-left

    local screenX = runtime:scratchToScreenX(bubbleX)
    local screenY = runtime:scratchToScreenY(bubbleTopScratchY)

    local drawX = screenX
    local drawY = screenY

    return drawX, drawY, onSpriteRight
end

---Create and render a bubble with positioning
---@param text string The text to display
---@param bubbleType string "say" or "think"
---@param sprite Sprite The sprite showing the bubble (for positioning)
---@param runtime Runtime Runtime instance (for coordinate conversion)
---@return love.ImageData imageData Rendered bubble ImageData
---@return number width Actual width
---@return number height Actual height
---@return number drawX Final X position for drawing (screen coords)
---@return number drawY Final Y position for drawing (screen coords)
function BubbleRenderer:renderBubble(text, bubbleType, sprite, runtime)
    -- If sprite and runtime are provided, calculate positioning
    local drawX, drawY, pointsLeft = self:calculatePosition(sprite, runtime, text, bubbleType)

    -- 1) Wrap text using Love's font measurement with the same font used by resvg
    local _, textLines = self.font:getWrap(text, MAX_LINE_WIDTH)

    local longest = 0
    for i = 1, #textLines do
        local w = self:calculateLineWidth(textLines[i])
        if w > longest then longest = w end
    end

    local paddedWidth = math.max(longest, MIN_WIDTH) + (PADDING * 2)
    local paddedHeight = (LINE_HEIGHT * #textLines) + (PADDING * 2)

    local bubbleWidth = paddedWidth + STROKE_WIDTH
    local bubbleHeight = paddedHeight + STROKE_WIDTH + TAIL_HEIGHT

    -- 2) Build SVG according to Scratch Canvas path logic
    local function rgbaToCss(c)
        return string.format("rgba(%d,%d,%d,%.3f)", math.floor(c[1] * 255), math.floor(c[2] * 255),
            math.floor(c[3] * 255),
            c[4])
    end

    local strokeCss = rgbaToCss(STROKE_COLOR)
    local fillCss = rgbaToCss(FILL_COLOR)
    local textCss = string.format("#%02x%02x%02x", math.floor(TEXT_COLOR[1] * 255), math.floor(TEXT_COLOR[2] * 255),
        math.floor(TEXT_COLOR[3] * 255))

    -- Build complete bubble path following Canvas API logic from original implementation
    local function buildBubblePath()
        local path = {}

        -- Following Canvas ctx.beginPath() logic exactly:
        -- Start at bottom left corner (after the corner radius)
        table.insert(path, string.format("M %f %f", CORNER_RADIUS, paddedHeight))

        -- Draw bottom left corner arc (counterclockwise for outward rounding)
        table.insert(path,
            string.format("A %f %f 0 0 1 0 %f", CORNER_RADIUS, CORNER_RADIUS, paddedHeight - CORNER_RADIUS))

        -- Left side
        table.insert(path, string.format("L 0 %f", CORNER_RADIUS))

        -- Draw top left corner arc (counterclockwise for outward rounding)
        table.insert(path, string.format("A %f %f 0 0 1 %f 0", CORNER_RADIUS, CORNER_RADIUS, CORNER_RADIUS))

        -- Top side
        table.insert(path, string.format("L %f 0", paddedWidth - CORNER_RADIUS))

        -- Draw top right corner arc (counterclockwise for outward rounding)
        table.insert(path, string.format("A %f %f 0 0 1 %f %f", CORNER_RADIUS, CORNER_RADIUS, paddedWidth, CORNER_RADIUS))

        -- Right side
        table.insert(path, string.format("L %f %f", paddedWidth, paddedHeight - CORNER_RADIUS))

        -- Draw bottom right corner arc (counterclockwise for outward rounding)
        table.insert(path,
            string.format("A %f %f 0 0 1 %f %f", CORNER_RADIUS, CORNER_RADIUS, paddedWidth - CORNER_RADIUS, paddedHeight))

        -- Now we're at the bottom right corner, ready for the tail
        local tailStartX = paddedWidth - CORNER_RADIUS
        local tailStartY = paddedHeight

        -- Add tail based on bubble type
        if bubbleType == "say" then
            -- Speech bubble tail following Canvas bezierCurveTo and arcTo calls
            table.insert(path, string.format("C %f %f, %f %f, %f %f",
                tailStartX, tailStartY + 4,
                tailStartX + 4, tailStartY + 8,
                tailStartX + 4, tailStartY + 10))
            table.insert(path, string.format("A 2 2 0 0 1 %f %f", tailStartX + 2, tailStartY + 12))
            table.insert(path, string.format("C %f %f, %f %f, %f %f",
                tailStartX - 1, tailStartY + 12,
                tailStartX - 11, tailStartY + 8,
                tailStartX - 16, tailStartY))
        else
            -- Think bubble: partial circle attached to bubble
            -- Native: ctx.arc(-16, 0, 4, 0, Math.PI) creates a downward-facing semicircle
            -- The arc goes from angle 0 (right) to π (left), creating the bottom half of a circle
            local arcCenterX = tailStartX - 16
            local arcCenterY = tailStartY
            local arcRadius = 4
            local arcRightX = arcCenterX + arcRadius -- Start at right side of circle
            local arcLeftX = arcCenterX - arcRadius  -- End at left side of circle

            -- Draw line to the right side of the arc, then draw downward semicircle to left side
            table.insert(path, string.format("L %f %f", arcRightX, arcCenterY))
            table.insert(path, string.format("A %f %f 0 0 1 %f %f", arcRadius, arcRadius, arcLeftX, arcCenterY))
        end

        -- Close the path - this will connect back to the starting point
        table.insert(path, "Z")

        return table.concat(path, " ")
    end

    -- Apply stroke offset transformation like Canvas implementation
    local bubbleShapeGroupTransform = string.format("translate(%f,%f)", STROKE_WIDTH * 0.5, STROKE_WIDTH * 0.5)
    local flipTransform = pointsLeft and string.format("translate(%f,0) scale(-1,1)", paddedWidth) or nil

    local svgParts = {}
    table.insert(svgParts,
        string.format("<svg xmlns='http://www.w3.org/2000/svg' width='%d' height='%d' viewBox='0 0 %d %d'>",
            bubbleWidth, bubbleHeight, bubbleWidth, bubbleHeight))

    -- Bubble graphics group with stroke offset (possibly flipped)
    table.insert(svgParts, string.format("<g transform='%s'>", bubbleShapeGroupTransform))
    if flipTransform then
        table.insert(svgParts, string.format("<g transform='%s'>", flipTransform))
    end

    -- Main bubble shape - draw stroke first, then fill; ctx.fill();)
    local bubblePath = buildBubblePath()

    -- First draw stroke only (background)
    table.insert(svgParts, string.format(
        "<path d='%s' fill='none' stroke='%s' stroke-width='%f' />",
        bubblePath, strokeCss, STROKE_WIDTH))

    -- Then draw fill on top (foreground)
    table.insert(svgParts, string.format(
        "<path d='%s' fill='%s' stroke='none' />",
        bubblePath, fillCss))

    -- For think bubbles, we need a second transform group matching native Scratch's
    -- ctx.translate(paddedWidth - CORNER_RADIUS, paddedHeight) transformation
    if bubbleType == "think" then
        local tailTransform = string.format("translate(%f,%f)", paddedWidth - CORNER_RADIUS, paddedHeight)
        table.insert(svgParts, string.format("<g transform='%s'>", tailTransform))

        -- Draw detached circles in the transformed coordinate system
        -- Native positions: medium circle at (-9.25, 7.25), small circle at (-1.5, 9.5)
        -- These coordinates are relative to the tail transformation
        local mediumCircleX = -9.25
        local mediumCircleY = 7.25
        local smallCircleX = -1.5
        local smallCircleY = 9.5

        -- Medium circle - stroke first
        table.insert(svgParts, string.format(
            "<circle cx='%f' cy='%f' r='2.25' fill='none' stroke='%s' stroke-width='%f' />",
            mediumCircleX, mediumCircleY, strokeCss, STROKE_WIDTH))
        -- Medium circle - fill second
        table.insert(svgParts, string.format(
            "<circle cx='%f' cy='%f' r='2.25' fill='%s' stroke='none' />",
            mediumCircleX, mediumCircleY, fillCss))

        -- Small circle - stroke first
        table.insert(svgParts, string.format(
            "<circle cx='%f' cy='%f' r='1.5' fill='none' stroke='%s' stroke-width='%f' />",
            smallCircleX, smallCircleY, strokeCss, STROKE_WIDTH))
        -- Small circle - fill second
        table.insert(svgParts, string.format(
            "<circle cx='%f' cy='%f' r='1.5' fill='%s' stroke='none' />",
            smallCircleX, smallCircleY, fillCss))

        -- Close the tail transformation group
        table.insert(svgParts, "</g>")
    end

    if flipTransform then table.insert(svgParts, "</g>") end
    table.insert(svgParts, "</g>")

    -- Text (never flipped)
    -- Add text-rendering and font attributes to match native Canvas text rendering
    for i = 1, #textLines do
        local line = textLines[i]
        local tx = PADDING + (STROKE_WIDTH * 0.5)
        local ty = (PADDING + (LINE_HEIGHT * (i - 1)) + (FONT_HEIGHT_RATIO * FONT_SIZE)) + (STROKE_WIDTH * 0.5)
        table.insert(svgParts, string.format(
            "<text x='%f' y='%f' fill='%s' font-family='%s' font-size='%d' font-weight='500' text-rendering='geometricPrecision'>%s</text>",
            tx, ty, textCss, FONT_FAMILY, FONT_SIZE, self:_escape_xml(line)))
    end

    table.insert(svgParts, "</svg>")
    local svg = table.concat(svgParts)

    -- 3) Render with resvg
    local tree, perr = resvg.parse_data(svg, Global.resvgOptions)
    if not tree then
        log.warn("resvg.parse_data error: %s", tostring(perr))
        local iw, ih = math.max(1, math.floor(bubbleWidth)), math.max(1, math.floor(bubbleHeight))
        local empty = love.image.newImageData(iw, ih)
        return empty, iw, ih, drawX, drawY
    end

    -- Get SVG intrinsic dimensions (CSS pixels at 96 DPI)
    local size = tree:get_size()
    local width = math.ceil(size.width * Global.SVG_RESOLUTION_SCALE)
    local height = math.ceil(size.height * Global.SVG_RESOLUTION_SCALE)
    local transform = resvg.Transform.scale(Global.SVG_RESOLUTION_SCALE, Global.SVG_RESOLUTION_SCALE)

    -- MEMORY OPTIMIZATION: Zero-copy rendering directly to ImageData
    local imageData
    local ok, res = pcall(function()
        -- Create empty ImageData
        local imgData = love.image.newImageData(width, height, "rgba8")

        -- Get FFI pointer to ImageData's internal buffer
        local imageDataPtr = imgData:getFFIPointer()
        if not imageDataPtr then
            error("Failed to get FFI pointer from ImageData")
        end

        -- Render directly to ImageData's memory (zero-copy!)
        tree:render_to_buffer(width, height, imageDataPtr, transform)

        return imgData
    end)
    if ok and res then
        imageData = res
    else
        log.warn("Failed to render bubble with zero-copy: %s", tostring(res))
        local iw, ih = math.max(1, math.floor(bubbleWidth)), math.max(1, math.floor(bubbleHeight))
        local empty = love.image.newImageData(iw, ih)
        return empty, iw, ih, drawX, drawY
    end

    return imageData, width, height, drawX, drawY
end

--- XML escape helper for text content
---@param s string
---@return string
function BubbleRenderer:_escape_xml(s)
    s = s:gsub("&", "&amp;")
    s = s:gsub("<", "&lt;")
    s = s:gsub(">", "&gt;")
    s = s:gsub('"', "&quot;")
    s = s:gsub("'", "&apos;")
    return s
end

return BubbleRenderer
