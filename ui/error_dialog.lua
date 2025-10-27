-- Universal Error Dialog
-- A reusable error display overlay that can be shown anywhere in the application
-- Designed to be displayed on top of any content (loading screen, game runtime, etc.)

local Global = require("global")

-- Visual constants
local OVERLAY_COLOR = { 0, 0, 0, 0.6 }
local CARD_BG_COLOR = { 0.98, 0.98, 0.99, 0.95 }
local CARD_BORDER_COLOR = { 0.85, 0.85, 0.87, 1 }
local CARD_SHADOW_COLOR = { 0, 0, 0, 0.3 }
local ICON_COLOR = { 1, 0.6, 0, 1 }  -- Scratch orange
local TITLE_COLOR = { 0.42, 0.37, 0.71, 1 }  -- Scratch purple
local MESSAGE_COLOR = { 0.15, 0.15, 0.2, 1 }  -- Dark gray
local HINT_COLOR = { 0.35, 0.35, 0.4, 1 }  -- Medium gray
local DIVIDER_COLOR = { 0.88, 0.88, 0.9, 1 }
local DETAILS_BG_COLOR = { 0.95, 0.95, 0.97, 1 }
local DETAILS_BORDER_COLOR = { 0.8, 0.8, 0.82, 1 }
local DETAILS_TEXT_COLOR = { 0.2, 0.2, 0.25, 1 }

-- Layout constants
local CARD_MIN_WIDTH = 580
local CARD_NORMAL_HEIGHT = 380  -- Increased from 300 to show more error info
local CARD_DETAILS_HEIGHT = 520 -- Increased from 480 for more details space
local CARD_PADDING = 20         -- Reduced from 30 for more content space
local CARD_MARGIN = 60          -- Reduced from 80
local CORNER_RADIUS = 16
local ICON_RADIUS = 20          -- Reduced from 28 to make header smaller
local SHADOW_OFFSET = 4
local BORDER_WIDTH = 2
local PULSE_SPEED = 1.5
local PULSE_AMPLITUDE = 0.08

-- Font sizes
local FONT_SIZE_TITLE = 16      -- Reduced from 20
local FONT_SIZE_MESSAGE = 14    -- Reduced from 15
local FONT_SIZE_DETAILS = 11    -- Reduced from 12
local FONT_SIZE_HINT = 12       -- Reduced from 13

---@class ErrorDialog
---@field isVisible boolean Whether error dialog is currently shown
---@field errorTitle string Error title text
---@field errorMessage string Error message text
---@field errorDetails string|nil Optional detailed error information
---@field showDetails boolean Whether to show detailed error information
---@field titleFont love.Font Font for title text
---@field messageFont love.Font Font for message text
---@field detailsFont love.Font Font for details text
---@field hintFont love.Font Font for hint text
---@field onDismiss function|nil Callback when error is dismissed
---@field showTime number Time when error was shown
local ErrorDialog = {}
ErrorDialog.__index = ErrorDialog

---Create new error dialog
---@return ErrorDialog
function ErrorDialog:new()
    local self = setmetatable({}, ErrorDialog)

    self.isVisible = false
    self.errorTitle = ""
    self.errorMessage = ""
    self.errorDetails = nil
    self.showDetails = false
    self.onDismiss = nil
    self.showTime = 0

    -- Create fonts using constants
    self.titleFont = love.graphics.newFont(FONT_SIZE_TITLE)
    self.messageFont = love.graphics.newFont(FONT_SIZE_MESSAGE)
    self.detailsFont = love.graphics.newFont(FONT_SIZE_DETAILS)
    self.hintFont = love.graphics.newFont(FONT_SIZE_HINT)

    return self
end

---Show error dialog with message
---@param title string Error title (e.g., "Loading Failed", "Runtime Error")
---@param message string Main error message
---@param details string|nil Optional detailed error information (e.g., stack trace)
---@param onDismiss function|nil Optional callback when error is dismissed
function ErrorDialog:show(title, message, details, onDismiss)
    self.isVisible = true
    self.errorTitle = title
    self.errorMessage = message

    -- Limit details to 10KB to prevent performance issues with text rendering
    if details and #details > 10240 then
        self.errorDetails = details:sub(1, 10240) .. "\n\n... (truncated)"
    else
        self.errorDetails = details
    end

    -- Show details by default if available
    self.showDetails = (details ~= nil and details ~= "")
    self.onDismiss = onDismiss
    self.showTime = love.timer.getTime()
end

---Hide error dialog
function ErrorDialog:hide()
    self.isVisible = false
    self.errorTitle = ""
    self.errorMessage = ""
    self.errorDetails = nil
    self.showDetails = false

    if self.onDismiss then
        local callback = self.onDismiss
        self.onDismiss = nil
        callback()
    end
end

---Handle keyboard input
---@param key string The key name that was pressed (e.g., "d", "escape", "return")
---@return boolean handled True if the key was handled by the error dialog, false otherwise
function ErrorDialog:keypressed(key)
    if not self.isVisible then
        return false
    end

    if key == "d" and self.errorDetails then
        -- Toggle details view
        self.showDetails = not self.showDetails
        return true
    elseif key == "escape" then
        -- Only ESC key dismisses the error
        self:hide()
        return true
    end

    -- Other keys are ignored (only ESC dismisses)
    return true
end

---Draw error dialog overlay
function ErrorDialog:draw()
    if not self.isVisible then
        return
    end

    -- Use Scratch stage dimensions - this is drawn within the transform
    -- so it will be automatically scaled and positioned correctly on all platforms
    local screenWidth = Global.STAGE_WIDTH
    local screenHeight = Global.STAGE_HEIGHT
    local centerX = screenWidth / 2
    local centerY = screenHeight / 2

    -- Semi-transparent overlay
    love.graphics.setColor(unpack(OVERLAY_COLOR))
    love.graphics.rectangle("fill", 0, 0, screenWidth, screenHeight)

    -- Subtle pulsing effect
    local elapsed = love.timer.getTime() - self.showTime
    local pulse = (1 - PULSE_AMPLITUDE) + math.sin(elapsed * PULSE_SPEED) * PULSE_AMPLITUDE

    -- Error card dimensions
    local cardWidth = math.min(CARD_MIN_WIDTH, screenWidth - CARD_MARGIN)
    local cardHeight = self.showDetails and math.min(CARD_DETAILS_HEIGHT, screenHeight - CARD_MARGIN) or CARD_NORMAL_HEIGHT
    local cardX = centerX - cardWidth / 2
    local cardY = centerY - cardHeight / 2

    -- Card shadow
    love.graphics.setColor(unpack(CARD_SHADOW_COLOR))
    love.graphics.rectangle("fill", cardX + SHADOW_OFFSET, cardY + SHADOW_OFFSET, cardWidth, cardHeight, CORNER_RADIUS, CORNER_RADIUS)

    -- Card background with pulse
    local bgColor = {CARD_BG_COLOR[1], CARD_BG_COLOR[2], CARD_BG_COLOR[3], CARD_BG_COLOR[4] * pulse}
    love.graphics.setColor(unpack(bgColor))
    love.graphics.rectangle("fill", cardX, cardY, cardWidth, cardHeight, CORNER_RADIUS, CORNER_RADIUS)

    -- Card border
    love.graphics.setColor(unpack(CARD_BORDER_COLOR))
    love.graphics.setLineWidth(BORDER_WIDTH)
    love.graphics.rectangle("line", cardX, cardY, cardWidth, cardHeight, CORNER_RADIUS, CORNER_RADIUS)

    -- Error icon (orange circle with exclamation)
    local iconX = cardX + CARD_PADDING + 18  -- Adjusted for smaller icon
    local iconY = cardY + CARD_PADDING + 18

    -- Orange circle with pulse
    local iconColor = {ICON_COLOR[1], ICON_COLOR[2], ICON_COLOR[3], ICON_COLOR[4] * pulse}
    love.graphics.setColor(unpack(iconColor))
    love.graphics.circle("fill", iconX, iconY, ICON_RADIUS, 64)

    -- White exclamation mark
    love.graphics.setColor(1, 1, 1, 1)
    love.graphics.setLineWidth(4)  -- Reduced from 5
    love.graphics.line(iconX, iconY - ICON_RADIUS / 3, iconX, iconY + ICON_RADIUS / 6)
    love.graphics.circle("fill", iconX, iconY + ICON_RADIUS / 2.2, 2.5)  -- Reduced from 3

    -- Error title
    love.graphics.setFont(self.titleFont)
    love.graphics.setColor(unpack(TITLE_COLOR))
    love.graphics.print(self.errorTitle, iconX + ICON_RADIUS + 15, cardY + CARD_PADDING + 8)  -- Adjusted positioning

    -- Divider line (moved up to reduce header height)
    local dividerY = cardY + CARD_PADDING + 45  -- Reduced from 65
    love.graphics.setColor(unpack(DIVIDER_COLOR))
    love.graphics.setLineWidth(BORDER_WIDTH)
    love.graphics.line(cardX + CARD_PADDING, dividerY, cardX + cardWidth - CARD_PADDING, dividerY)

    -- Error message (wrapped)
    local messageX = cardX + CARD_PADDING
    local messageY = dividerY + 15  -- Reduced from 20
    local messageWidth = cardWidth - CARD_PADDING * 2

    -- Calculate maximum message height to prevent overlapping hint text
    local maxMessageHeight = (cardHeight - 35) - (dividerY - cardY + 15) - 25  -- Leave 25px gap before hint

    love.graphics.setFont(self.messageFont)
    love.graphics.setColor(unpack(MESSAGE_COLOR))

    local _, wrappedLines = self.messageFont:getWrap(self.errorMessage, messageWidth)

    -- Calculate how many lines we can show
    local lineHeight = 20
    local maxLines = math.floor(maxMessageHeight / lineHeight)
    local linesToShow = math.min(#wrappedLines, maxLines)

    for i = 1, linesToShow do
        love.graphics.print(wrappedLines[i], messageX, messageY + (i - 1) * lineHeight)
    end

    -- Show truncation indicator if needed
    if #wrappedLines > linesToShow then
        love.graphics.setColor(unpack(HINT_COLOR))
        love.graphics.print("... (text truncated, press D for details)", messageX, messageY + linesToShow * lineHeight)
    end

    local messageEndY = messageY + linesToShow * lineHeight + 15

    -- Details section (if available and toggled)
    if self.showDetails and self.errorDetails then
        -- Details box
        local detailsY = messageEndY
        local detailsHeight = cardHeight - (detailsY - cardY) - 60

        -- Safety check: ensure dimensions are positive
        if detailsHeight <= 20 or messageWidth <= 20 then
            -- Not enough space to show details, skip rendering
            goto skipDetails
        end

        -- Details background
        love.graphics.setColor(unpack(DETAILS_BG_COLOR))
        love.graphics.rectangle("fill", messageX, detailsY, messageWidth, detailsHeight, 8, 8)

        -- Details border
        love.graphics.setColor(unpack(DETAILS_BORDER_COLOR))
        love.graphics.setLineWidth(BORDER_WIDTH)
        love.graphics.rectangle("line", messageX, detailsY, messageWidth, detailsHeight, 8, 8)

        -- Details text (scrollable if needed)
        love.graphics.setFont(self.detailsFont)
        love.graphics.setColor(unpack(DETAILS_TEXT_COLOR))

        -- Use scissor to clip overflow with safe dimensions
        local scissorWidth = math.max(1, messageWidth - 10)
        local scissorHeight = math.max(1, detailsHeight - 10)
        love.graphics.setScissor(messageX + 5, detailsY + 5, scissorWidth, scissorHeight)

        -- Text wrapping with safety check (errorDetails already limited to 10KB in show())
        local _, detailLines = self.detailsFont:getWrap(self.errorDetails, messageWidth - 20)
        for i, line in ipairs(detailLines) do
            if i * 16 < detailsHeight - 10 then -- Only show lines that fit
                love.graphics.print(line, messageX + 10, detailsY + 5 + (i - 1) * 16)
            end
        end

        love.graphics.setScissor()
    end

    ::skipDetails::

    -- Hint text at bottom
    love.graphics.setFont(self.hintFont)
    love.graphics.setColor(unpack(HINT_COLOR))

    local hintY = cardY + cardHeight - 35
    local hintText = "Press ESC to dismiss"

    if self.errorDetails and not self.showDetails then
        hintText = "Press D to show details | ESC to dismiss"
    elseif self.errorDetails and self.showDetails then
        hintText = "Press D to hide details | ESC to dismiss"
    end

    local hintWidth = self.hintFont:getWidth(hintText)
    love.graphics.print(hintText, cardX + (cardWidth - hintWidth) / 2, hintY)
end

---Check if error dialog is currently visible
---@return boolean isVisible
function ErrorDialog:isShowing()
    return self.isVisible
end

return ErrorDialog
