-- Mock Audio Source for Testing
-- Provides Love2D Source-like interface for audio tests

---@class MockSource
---@field _duration number
---@field _isPlaying boolean
---@field _volume number
---@field _pitch number
---@field _pan number
---@field _startTime number
local MockSource = {}
MockSource.__index = MockSource

local function currentTime()
    if love and love.timer and love.timer.getTime then
        return love.timer.getTime()
    end
    return os.clock()
end

---@param duration number
---@return MockSource
local function createMockSource(duration)
    return setmetatable({
        _duration = duration or 0,
        _isPlaying = false,
        _volume = 1,
        _pitch = 1,
        _pan = 0,
        _startTime = 0
    }, MockSource)
end

function MockSource:clone()
    local clone = createMockSource(self._duration)
    clone._volume = self._volume
    clone._pitch = self._pitch
    clone._pan = self._pan
    -- Copy getChannelCount if it exists
    if self.getChannelCount then
        clone.getChannelCount = self.getChannelCount
    end
    return clone
end

function MockSource:play()
    self._isPlaying = true
    self._startTime = currentTime()
end

function MockSource:stop()
    self._isPlaying = false
end

function MockSource:isPlaying()
    if not self._isPlaying then
        return false
    end
    local elapsed = currentTime() - self._startTime
    if elapsed >= (self._duration / self._pitch) then
        self._isPlaying = false
    end
    return self._isPlaying
end

function MockSource:getDuration()
    return self._duration
end

function MockSource:setVolume(volume)
    self._volume = volume
end

function MockSource:setPitch(pitch)
    self._pitch = pitch
end

function MockSource:setPosition(x)
    self._pan = x
end

function MockSource:setRelative() end
function MockSource:setAttenuationDistances() end
function MockSource:setLooping() end

return {
    createMockSource = createMockSource,
    MockSource = MockSource
}