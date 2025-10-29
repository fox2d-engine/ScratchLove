-- Mock Love2D for Testing
-- Provides a minimal Love2D API mock for testing without the actual framework

local MockLove = {}

-- Store original love table if it exists
local originalLove = rawget(_G, "love")

-- Mock timer module
local mockTimer = {
    _time = 0,
    _lastCallTime = 0,
    _callCount = 0
}

function mockTimer.getTime()
    -- In real Love2D, getTime() naturally advances
    -- Simulate this by adding micro-increments on frequent calls
    mockTimer._callCount = mockTimer._callCount + 1

    -- Add small time increment every few calls to simulate real time passage
    -- This prevents infinite loops in sequencer while keeping behavior realistic
    if mockTimer._callCount % 10 == 0 then
        mockTimer._time = mockTimer._time + 0.0001  -- 0.1ms per 10 calls
    end

    return mockTimer._time
end

function mockTimer.getDelta()
    return 1/60  -- Assume 60 FPS
end

-- Helper methods for testing
function mockTimer.setTime(time)
    mockTimer._time = time
end

function mockTimer.advance(seconds)
    mockTimer._time = mockTimer._time + seconds
end

function mockTimer.reset()
    mockTimer._time = 0
    mockTimer._callCount = 0
end

-- Mock audio module
local mockAudio = {
    stop = function() end,
    setVolume = function(volume) end,
    getVolume = function() return 1.0 end,
    play = function(source) end,
    pause = function() end,
    resume = function() end
}

-- Mock graphics module
local mockGraphics = {
    autoOffsetX = 0,
    autoOffsetY = 0,
    autoScale = 1,
}

local currentColor = { 1, 1, 1, 1 }
local currentBlendMode, currentAlphaMode = "alpha", "alphamultiply"

function mockGraphics.getCanvas()
    return nil
end

function mockGraphics.setCanvas(_) end

function mockGraphics.getWidth()
    return 480
end

function mockGraphics.getHeight()
    return 360
end

function mockGraphics.getDPIScale()
    return 1  -- Return 1 for tests to have predictable behavior
end

function mockGraphics.clear() end

function mockGraphics.draw() end

function mockGraphics.setColor(r, g, b, a)
    currentColor[1], currentColor[2], currentColor[3], currentColor[4] = r, g, b, a
end

function mockGraphics.getColor()
    return currentColor[1], currentColor[2], currentColor[3], currentColor[4]
end

function mockGraphics.rectangle() end

function mockGraphics.circle() end

function mockGraphics.line() end

function mockGraphics.print() end

function mockGraphics.points() end

function mockGraphics.setPointSize(_) end

function mockGraphics.setLineWidth(_) end

function mockGraphics.setLineStyle(_) end

function mockGraphics.setLineJoin(_) end

function mockGraphics.setShader(_) end

function mockGraphics.newMesh(vertices, mode, usage)
    return {
        vertices = vertices,
        mode = mode,
        usage = usage
    }
end

-- Canvas creation for pen renderer
function mockGraphics.newCanvas(width, height, format)
    return {
        _width = width or 480,
        _height = height or 360,
        _format = format or "normal",
        setFilter = function() end,
        getDimensions = function(self) return self._width, self._height end,
        getWidth = function(self) return self._width end,
        getHeight = function(self) return self._height end,
        renderTo = function(self, func)
            if func then func() end
        end
    }
end

function mockGraphics.getBlendMode()
    return currentBlendMode, currentAlphaMode
end

function mockGraphics.setBlendMode(mode, alphamode)
    currentBlendMode = mode or currentBlendMode
    currentAlphaMode = alphamode or currentAlphaMode
end

function mockGraphics.newShader(_)
    -- Return a mock shader object for testing
    return {
        send = function() end,
        sendColor = function() end,
        getWarnings = function() return "" end
    }
end

function mockGraphics.newImage(_)
    return {
        getWidth = function() return 64 end,
        getHeight = function() return 64 end
    }
end

function mockGraphics.newFont(filename, size)
    return {
        getWidth = function(text) return (text and #text or 0) * (size or 12) * 0.6 end,
        getHeight = function() return size or 12 end,
        setFilter = function() end
    }
end

function mockGraphics.newImageData(width, height)
    return {
        getWidth = function() return width end,
        getHeight = function() return height end,
        setPixel = function() end,
        getPixel = function() return 0, 0, 0, 1 end
    }
end

function mockGraphics.push() end

function mockGraphics.pop() end

function mockGraphics.translate() end

function mockGraphics.scale() end

function mockGraphics.rotate() end

-- Mock keyboard module
local mockKeyboard = {
    _pressed = {},

    isDown = function(key)
        return mockKeyboard._pressed[key] or false
    end,

    -- Test helper methods
    setKeyDown = function(key, down)
        mockKeyboard._pressed[key] = down
    end,

    reset = function()
        mockKeyboard._pressed = {}
    end
}

-- Mock mouse module
local mockMouse = {
    _x = 0,
    _y = 0,
    _pressed = false,

    getX = function() return mockMouse._x end,
    getY = function() return mockMouse._y end,
    isDown = function() return mockMouse._pressed end,

    -- Test helper methods
    setPosition = function(x, y)
        mockMouse._x = x
        mockMouse._y = y
    end,

    setPressed = function(pressed)
        mockMouse._pressed = pressed
    end,

    reset = function()
        mockMouse._x = 0
        mockMouse._y = 0
        mockMouse._pressed = false
    end
}

-- Mock filesystem module
local mockFilesystem = {
    _mockFiles = {}  -- In-memory file storage for testing
}

---Check if a file exists in mock filesystem
---@param path string File path
---@return boolean exists True if file exists
function mockFilesystem.exists(path)
    return mockFilesystem._mockFiles[path] ~= nil
end

---Read file from mock filesystem
---@param path string File path
---@return string|nil data File data or nil if not found
---@return string|nil error Error message if failed
function mockFilesystem.read(path)
    return mockFilesystem._mockFiles[path], nil
end

---Write file to mock filesystem
---@param path string File path
---@param data string Data to write
---@return boolean success True if successful
---@return string|nil error Error message if failed
function mockFilesystem.write(path, data)
    mockFilesystem._mockFiles[path] = data
    return true, nil
end

---Get file info from mock filesystem
---@param path string File path
---@return table|nil info File info or nil if not found
function mockFilesystem.getInfo(path)
    if mockFilesystem._mockFiles[path] then
        return {
            type = "file",
            size = #mockFilesystem._mockFiles[path]
        }
    end
    return nil
end

---Create a new file handle for reading/writing
---@param path string File path
---@param mode string "r" for read, "w" for write
---@return table|nil file Mock file object or nil on failure
---@return string|nil error Error message if failed
function mockFilesystem.newFile(path, mode)
    local file = {
        _path = path,
        _mode = mode,
        _position = 0,  -- 0-based byte offset (like C file operations)
        _closed = false
    }

    ---Read bytes from file
    ---@param self table File handle
    ---@param bytes number Number of bytes to read
    ---@return string|love.Data|nil data Read data or nil on error
    ---@return string|nil error Error message if failed
    function file:read(bytes)
        if self._closed then
            return nil, "File is closed"
        end

        if self._mode ~= "r" then
            return nil, "File not opened for reading"
        end

        local data = mockFilesystem._mockFiles[self._path]
        if not data then
            return nil, "File not found: " .. self._path
        end

        if self._position >= #data then
            return nil, "End of file"
        end

        -- Lua string.sub is 1-based, so add 1 to convert from 0-based offset
        local startPos = self._position + 1
        local endPos = self._position + bytes
        local chunk = data:sub(startPos, endPos)
        self._position = self._position + #chunk
        return chunk, nil
    end

    ---Write data to file
    ---@param self table File handle
    ---@param data string Data to write
    ---@return boolean success True if successful
    ---@return string|nil error Error message if failed
    function file:write(data)
        if self._closed then
            return false, "File is closed"
        end

        if self._mode ~= "w" then
            return false, "File not opened for writing"
        end

        mockFilesystem._mockFiles[self._path] = (mockFilesystem._mockFiles[self._path] or "") .. data
        return true, nil
    end

    ---Seek to a position in the file
    ---@param self table File handle
    ---@param position number Byte position (0-based offset)
    ---@return boolean success True if successful
    function file:seek(position)
        if self._closed then
            return false
        end
        self._position = position
        return true
    end

    ---Close the file handle
    ---@param self table File handle
    ---@return boolean success Always true
    function file:close()
        self._closed = true
        return true
    end

    ---Check if file is open
    ---@param self table File handle
    ---@return boolean open True if file is open
    function file:isOpen()
        return not self._closed
    end

    ---Get file size
    ---@param self table File handle
    ---@return number size File size in bytes
    function file:getSize()
        if self._mode == "r" then
            local data = mockFilesystem._mockFiles[self._path]
            return data and #data or 0
        else
            -- For write mode, return current data size
            return #(mockFilesystem._mockFiles[self._path] or "")
        end
    end

    return file, nil
end

---Reset mock filesystem (clear all files)
function mockFilesystem.reset()
    mockFilesystem._mockFiles = {}
end

-- Mock data module for binary data operations
local mockData = {}

---Pack values into binary string
---@param container string Container type ("string")
---@param format string Pack format string (e.g. "<I4" for little-endian 32-bit int, "B" for byte)
---@param ... any Values to pack
---@return string packed Packed binary data
function mockData.pack(container, format, ...)
    local values = {...}
    local result = ""

    -- Handle byte format (B)
    if format:match("B") then
        for _, value in ipairs(values) do
            local num = tonumber(value) or 0
            result = result .. string.char(num % 256)
        end
        return result
    end

    -- Parse format: < or > for endianness, I for unsigned int, i for signed int
    local size = tonumber(format:match("%d+")) or 1
    local isSigned = format:match("i%d") ~= nil

    for _, value in ipairs(values) do
        local num = tonumber(value) or 0

        -- Handle negative numbers for signed types
        if isSigned and num < 0 then
            num = num + (256 ^ size)
        end

        -- Pack as little-endian bytes
        for _ = 1, size do
            result = result .. string.char(num % 256)
            num = math.floor(num / 256)
        end
    end

    return result
end

---Unpack binary string into values
---@param format string Unpack format string (e.g. "<I4" for unsigned, "<i2" for signed)
---@param data string Binary data to unpack
---@param pos? number Starting position (default: 1)
---@return number value Unpacked value
---@return number nextPos Next position after unpacked data
function mockData.unpack(format, data, pos)
    pos = pos or 1
    local size = tonumber(format:match("%d+"))

    if not size then
        error("Invalid format string: " .. format)
    end

    if pos + size - 1 > #data then
        error("Not enough data to unpack")
    end

    -- Unpack as little-endian
    local value = 0
    for i = 0, size - 1 do
        local byte = string.byte(data, pos + i)
        value = value + byte * (256 ^ i)
    end

    -- Handle signed types (lowercase 'i')
    local isSigned = format:match("i%d") ~= nil
    if isSigned then
        local maxValue = 256 ^ size
        local signBit = maxValue / 2
        if value >= signBit then
            value = value - maxValue
        end
    end

    return value, pos + size
end

-- Mock image module
local mockImage = {
    newImageData = function(width, height)
        return {
            getWidth = function() return width end,
            getHeight = function() return height end,
            setPixel = function() end,
            getPixel = function() return 0, 0, 0, 1 end
        }
    end
}

-- Mock joystick module
local mockJoystick = {
    getJoysticks = function()
        -- Return empty array - no joysticks in test environment
        return {}
    end
}

-- Mock system module
local mockSystem = {
    _os = "OS X"  -- Default to OS X for tests
}

function mockSystem.getOS()
    return mockSystem._os
end

-- Test helper to override OS
function mockSystem.setOS(os)
    mockSystem._os = os
end

-- Mock math module for Transform API
local mockMath = {
    newTransform = function()
        local transform = {
            matrix = {
                1, 0, 0, 0,  -- column 1
                0, 1, 0, 0,  -- column 2
                0, 0, 1, 0,  -- column 3
                0, 0, 0, 1   -- column 4
            }
        }

        function transform:reset()
            self.matrix = {
                1, 0, 0, 0,
                0, 1, 0, 0,
                0, 0, 1, 0,
                0, 0, 0, 1
            }
            return self
        end

        function transform:translate(x, y)
            local m = self.matrix
            -- Row-major matrix: [m1 m2 m3 m4; m5 m6 m7 m8; m9 m10 m11 m12; 0 0 0 1]
            -- M * T(x,y) updates translation column (m4, m8, m12)
            m[4] = m[1]*x + m[2]*y + m[4]
            m[8] = m[5]*x + m[6]*y + m[8]
            m[12] = m[9]*x + m[10]*y + m[12]
            -- m[16] stays 1 (for affine transforms, row 4 is always [0 0 0 1])
            return self
        end

        function transform:rotate(angle)
            local c = math.cos(angle)
            local s = math.sin(angle)
            local m = self.matrix

            -- Row-major M * R(angle) where R = [c -s 0 0; s c 0 0; 0 0 1 0; 0 0 0 1]
            -- Save original values before modifying
            local m1, m2 = m[1], m[2]
            local m5, m6 = m[5], m[6]
            local m9, m10 = m[9], m[10]

            -- Row 1: [m1 m2 m3 m4] * R
            m[1] = c*m1 + s*m2
            m[2] = -s*m1 + c*m2
            -- m[3] and m[4] unchanged for 2D rotation

            -- Row 2: [m5 m6 m7 m8] * R
            m[5] = c*m5 + s*m6
            m[6] = -s*m5 + c*m6
            -- m[7] and m[8] unchanged

            -- Row 3: [m9 m10 m11 m12] * R
            m[9] = c*m9 + s*m10
            m[10] = -s*m9 + c*m10
            -- m[11] and m[12] unchanged

            -- Row 4 unchanged for 2D rotation
            return self
        end

        function transform:scale(sx, sy)
            sy = sy or sx
            local m = self.matrix

            -- Row-major M * S(sx, sy) where S = [sx 0 0 0; 0 sy 0 0; 0 0 1 0; 0 0 0 1]
            -- Each row: [m_i1*sx, m_i2*sy, m_i3, m_i4]
            m[1] = m[1] * sx
            m[2] = m[2] * sy

            m[5] = m[5] * sx
            m[6] = m[6] * sy

            m[9] = m[9] * sx
            m[10] = m[10] * sy

            -- m[3], m[4], m[7], m[8], m[11], m[12] unchanged for 2D scale
            -- Row 4 unchanged
            return self
        end

        function transform:getMatrix()
            return unpack(self.matrix)
        end

        function transform:setMatrix(e11, e12, e13, e14,
                                      e21, e22, e23, e24,
                                      e31, e32, e33, e34,
                                      e41, e42, e43, e44)
            local m = self.matrix
            m[1], m[2], m[3], m[4] = e11, e12, e13, e14
            m[5], m[6], m[7], m[8] = e21, e22, e23, e24
            m[9], m[10], m[11], m[12] = e31, e32, e33, e34
            m[13], m[14], m[15], m[16] = e41, e42, e43, e44
            return self
        end

        function transform:transformPoint(x, y)
            local m = self.matrix
            -- 2D affine transformation: [x', y'] = M * [x, y, 0, 1]
            -- x' = m1*x + m2*y + m3*0 + m4*1 = m1*x + m2*y + m4
            -- y' = m5*x + m6*y + m7*0 + m8*1 = m5*x + m6*y + m8
            local x_prime = m[1]*x + m[2]*y + m[4]
            local y_prime = m[5]*x + m[6]*y + m[8]
            return x_prime, y_prime
        end

        return transform
    end
}

-- Create mock love table
local mockLove = {
    timer = mockTimer,
    audio = mockAudio,
    graphics = mockGraphics,
    keyboard = mockKeyboard,
    mouse = mockMouse,
    filesystem = mockFilesystem,
    data = mockData,
    image = mockImage,
    joystick = mockJoystick,
    system = mockSystem,
    math = mockMath
}

-- Mock utf8 module for LuaJIT compatibility
local mockUtf8 = {}

mockUtf8.sub = function(s, i, j) return string.sub(s, i, j) end
mockUtf8.char = function(...) return string.char(...) end
mockUtf8.offset = function(s, n)
    -- Simple ASCII-based offset for testing
    -- For UTF-8 strings, this is simplified but works for basic test cases
    if n <= 0 then return nil end
    if n > #s then return #s + 1 end
    return n
end

mockUtf8.codes = function(s)
    -- Proper UTF-8 codepoint iterator
    local pos = 1
    local len = #s
    return function()
        if pos > len then return nil end

        local byte1 = string.byte(s, pos)
        local codepoint
        local nextPos

        if byte1 < 0x80 then
            -- Single-byte character (ASCII)
            codepoint = byte1
            nextPos = pos + 1
        elseif byte1 < 0xE0 then
            -- Two-byte character
            local byte2 = string.byte(s, pos + 1) or 0
            codepoint = ((byte1 - 0xC0) * 64) + (byte2 - 0x80)
            nextPos = pos + 2
        elseif byte1 < 0xF0 then
            -- Three-byte character (most CJK characters)
            local byte2 = string.byte(s, pos + 1) or 0
            local byte3 = string.byte(s, pos + 2) or 0
            codepoint = ((byte1 - 0xE0) * 4096) + ((byte2 - 0x80) * 64) + (byte3 - 0x80)
            nextPos = pos + 3
        else
            -- Four-byte character
            local byte2 = string.byte(s, pos + 1) or 0
            local byte3 = string.byte(s, pos + 2) or 0
            local byte4 = string.byte(s, pos + 3) or 0
            codepoint = ((byte1 - 0xF0) * 262144) + ((byte2 - 0x80) * 4096) +
                       ((byte3 - 0x80) * 64) + (byte4 - 0x80)
            nextPos = pos + 4
        end

        local currentPos = pos
        pos = nextPos
        return currentPos, codepoint
    end
end

mockUtf8.len = function(s)
    -- Count UTF-8 codepoints, not bytes
    local count = 0
    for _ in mockUtf8.codes(s) do
        count = count + 1
    end
    return count
end

-- Installation functions
function MockLove.install()
    rawset(_G, "love", mockLove)

    -- Install utf8 module using preload
    package.preload['utf8'] = function() return mockUtf8 end

    -- Install socket module with gettime() for high precision time
    package.preload['socket'] = function()
        return {
            gettime = function()
                -- Return high precision Unix timestamp
                -- Use os.time() + fractional seconds from os.clock()
                local seconds = os.time()
                local fractional = os.clock() % 1  -- Get fractional part
                return seconds + fractional
            end
        }
    end
end

function MockLove.uninstall()
    rawset(_G, "love", originalLove)
end

-- Reset all mock state
function MockLove.reset()
    mockTimer.reset()
    mockKeyboard.reset()
    mockMouse.reset()
    mockFilesystem.reset()
end

-- Export the mock for direct access if needed
MockLove.mock = mockLove

return MockLove
