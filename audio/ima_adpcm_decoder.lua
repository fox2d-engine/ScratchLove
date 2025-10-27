-- IMA ADPCM to PCM Decoder
-- Adapted from https://github.com/jwzhangjie/Adpcm_Pcm/blob/master/adpcm.c

local ffi = require("ffi")
local bit = require("bit")
local log = require("lib.log")

-- Localize frequently used functions for performance
local band = bit.band
local rshift = bit.rshift
local byte = string.byte
local sub = string.sub
local insert = table.insert
local concat = table.concat
local floor = math.floor
local min = math.min
local format = string.format
local unpack = love.data.unpack
local pack = love.data.pack

---@class ImaAdpcmDecoder
local ImaAdpcmDecoder = {}
ImaAdpcmDecoder.__index = ImaAdpcmDecoder

-- Index adjustment table for IMA ADPCM
local indexTable = {
    -1, -1, -1, -1, 2, 4, 6, 8,
    -1, -1, -1, -1, 2, 4, 6, 8
}

-- Quantizer step size lookup table
local stepsizeTable = {
    7, 8, 9, 10, 11, 12, 13, 14, 16, 17,
    19, 21, 23, 25, 28, 31, 34, 37, 41, 45,
    50, 55, 60, 66, 73, 80, 88, 97, 107, 118,
    130, 143, 157, 173, 190, 209, 230, 253, 279, 307,
    337, 371, 408, 449, 494, 544, 598, 658, 724, 796,
    876, 963, 1060, 1166, 1282, 1411, 1552, 1707, 1878, 2066,
    2272, 2499, 2749, 3024, 3327, 3660, 4026, 4428, 4871, 5358,
    5894, 6484, 7132, 7845, 8630, 9493, 10442, 11487, 12635, 13899,
    15289, 16818, 18500, 20350, 22385, 24623, 27086, 29794, 32767
}

---@class AdpcmState
---@field valprev number Previous output value
---@field index number Current step index

---Create a new ADPCM decoder state
---@return AdpcmState
local function createState()
    return {
        valprev = 0,
        index = 0
    }
end

---Clamp value to 16-bit signed integer range
---@param val number
---@return number
local function clamp16(val)
    if val > 32767 then
        return 32767
    elseif val < -32768 then
        return -32768
    else
        return val
    end
end

---Decode a single IMA ADPCM nibble to PCM sample
---@param nibble number 4-bit ADPCM code
---@param state AdpcmState Current decoder state
---@return number sample 16-bit PCM sample
local function decodeNibble(nibble, state)
    local step = stepsizeTable[state.index + 1] -- Lua uses 1-based indexing
    local diff = 0

    -- Calculate difference from nibble
    if band(nibble, 4) ~= 0 then
        diff = diff + step
    end
    if band(nibble, 2) ~= 0 then
        diff = diff + rshift(step, 1)
    end
    if band(nibble, 1) ~= 0 then
        diff = diff + rshift(step, 2)
    end
    diff = diff + rshift(step, 3)

    -- Apply sign bit
    if band(nibble, 8) ~= 0 then
        diff = -diff
    end

    -- Update predicted value
    state.valprev = clamp16(state.valprev + diff)

    -- Update step index
    state.index = state.index + indexTable[nibble + 1] -- Lua uses 1-based indexing

    -- Clamp step index
    if state.index < 0 then
        state.index = 0
    elseif state.index > 88 then
        state.index = 88
    end

    return state.valprev
end

---Check if data is IMA ADPCM format by examining WAV header
---@param data string Binary data
---@return boolean isAdpcm True if data appears to be IMA ADPCM
---@return number? blockAlign Block alignment for ADPCM data
---@return number? samplesPerBlock Samples per block
function ImaAdpcmDecoder.isImaAdpcm(data)
    if #data < 44 then
        return false
    end

    -- Check RIFF header
    if sub(data, 1, 4) ~= "RIFF" then
        return false
    end

    -- Check WAVE format
    if sub(data, 9, 12) ~= "WAVE" then
        return false
    end

    -- Find fmt chunk
    local pos = 13
    while pos < #data - 8 do
        local chunkId = sub(data, pos, pos + 3)
        local chunkSize = unpack("<I4", data, pos + 4)

        if chunkId == "fmt " then
            if pos + 8 + chunkSize > #data then
                return false
            end

            -- Check audio format (0x11 = IMA ADPCM)
            local audioFormat = unpack("<I2", data, pos + 8)
            if audioFormat == 0x11 then
                -- Get block alignment and calculate samples per block
                local numChannels = unpack("<I2", data, pos + 10)
                local blockAlign = unpack("<I2", data, pos + 20)
                local samplesPerBlock = nil

                -- Check if we have extended format info
                if chunkSize >= 20 then
                    local cbSize = unpack("<I2", data, pos + 24)
                    if cbSize >= 2 then
                        samplesPerBlock = unpack("<I2", data, pos + 26)
                    end
                end

                -- If no samples per block specified, calculate it
                if not samplesPerBlock then
                    -- Standard IMA ADPCM calculation
                    samplesPerBlock = (blockAlign - 4 * numChannels) * 2 / numChannels + 1
                end

                log.debug("Detected IMA ADPCM format: channels=" .. numChannels ..
                    ", blockAlign=" .. blockAlign .. ", samplesPerBlock=" .. samplesPerBlock)
                return true, blockAlign, samplesPerBlock
            end
            return false
        end

        pos = pos + 8 + chunkSize
        -- Ensure alignment to word boundary
        if chunkSize % 2 == 1 then
            pos = pos + 1
        end
    end

    return false
end

---Decode IMA ADPCM WAV file to PCM WAV with streaming read and write
---@param inputPath string Path to input ADPCM WAV file
---@param outputPath string Path to write the converted PCM WAV file
---@return boolean success True if conversion succeeded
---@return string? error Error message if decoding failed
function ImaAdpcmDecoder.decode(inputPath, outputPath)
    -- Open input file for reading
    local inputFile, inputErr = love.filesystem.newFile(inputPath, "r")
    if not inputFile then
        return false, "Failed to open input file: " .. tostring(inputErr)
    end

    -- Get file size
    local fileSize = inputFile:getSize()
    if fileSize < 44 then
        inputFile:close()
        return false, "File too small to be a valid WAV"
    end

    -- Read RIFF header (12 bytes)
    ---@type string|love.FileData
    local riffHeaderRaw = inputFile:read(12)
    if not riffHeaderRaw or #riffHeaderRaw < 12 then
        inputFile:close()
        return false, "Failed to read RIFF header"
    end
    ---@type string
    local riffHeader = tostring(riffHeaderRaw)

    -- Verify RIFF/WAVE format
    if sub(riffHeader, 1, 4) ~= "RIFF" or sub(riffHeader, 9, 12) ~= "WAVE" then
        inputFile:close()
        return false, "Not a valid WAVE file"
    end

    -- Find fmt and data chunks by reading chunk headers
    local fmtChunkData
    local dataChunkPos, dataChunkSize
    local numChannels, sampleRate, blockAlign, samplesPerBlock

    local pos = 12 -- Current position after RIFF header
    while pos < fileSize - 8 do
        -- Read chunk header (8 bytes)
        inputFile:seek(pos)
        ---@type string|love.FileData
        local chunkHeaderRaw = inputFile:read(8)
        if not chunkHeaderRaw or #chunkHeaderRaw < 8 then
            break
        end
        ---@type string
        local chunkHeader = tostring(chunkHeaderRaw)

        local chunkId = sub(chunkHeader, 1, 4)
        local chunkSize = unpack("<I4", chunkHeader, 5)

        if chunkId == "fmt " then
            -- Read fmt chunk data
            ---@type string|love.FileData
            local fmtChunkDataRaw = inputFile:read(chunkSize)
            if not fmtChunkDataRaw or #fmtChunkDataRaw < chunkSize then
                inputFile:close()
                return false, "Failed to read fmt chunk"
            end
            ---@type string
            fmtChunkData = tostring(fmtChunkDataRaw)

            -- Parse format chunk
            local audioFormat = unpack("<I2", fmtChunkData, 1)
            if audioFormat ~= 0x11 then
                inputFile:close()
                return false, "Not IMA ADPCM format (format=" .. audioFormat .. ")"
            end

            numChannels = unpack("<I2", fmtChunkData, 3)
            sampleRate = unpack("<I4", fmtChunkData, 5)
            blockAlign = unpack("<I2", fmtChunkData, 13)

            -- Get samples per block from extended format
            if #fmtChunkData >= 18 then
                local cbSize = unpack("<I2", fmtChunkData, 17)
                if cbSize >= 2 and #fmtChunkData >= 20 then
                    samplesPerBlock = unpack("<I2", fmtChunkData, 19)
                end
            end

            -- Calculate if not provided
            if not samplesPerBlock then
                samplesPerBlock = (blockAlign - 4 * numChannels) * 2 / numChannels + 1
            end
        elseif chunkId == "data" then
            -- Record data chunk position and size, but don't read it yet
            dataChunkPos = pos + 8
            dataChunkSize = chunkSize
        end

        pos = pos + 8 + chunkSize
        if chunkSize % 2 == 1 then
            pos = pos + 1 -- Word alignment
        end
    end

    if not fmtChunkData or not dataChunkPos then
        inputFile:close()
        return false, "Missing required chunks in WAV file"
    end

    log.debug(format("Decoding IMA ADPCM: channels=%d, rate=%d, blockAlign=%d, samplesPerBlock=%d",
        numChannels, sampleRate, blockAlign, samplesPerBlock))

    -- Calculate total PCM samples
    local blockCount = floor(dataChunkSize / blockAlign)
    local totalSamples = blockCount * samplesPerBlock * numChannels
    local pcmDataSize = totalSamples * 2

    -- Open output file for streaming write
    local outputFile, outputErr = love.filesystem.newFile(outputPath, "w")
    if not outputFile then
        inputFile:close()
        return false, "Failed to create output file: " .. tostring(outputErr)
    end

    -- Write RIFF header
    outputFile:write("RIFF")
    outputFile:write(pack("string", "<I4", 36 + pcmDataSize))
    outputFile:write("WAVE")

    -- Write fmt chunk
    outputFile:write("fmt ")
    outputFile:write(pack("string", "<I4", 16))
    outputFile:write(pack("string", "<I2", 1)) -- PCM format
    outputFile:write(pack("string", "<I2", numChannels))
    outputFile:write(pack("string", "<I4", sampleRate))
    outputFile:write(pack("string", "<I4", sampleRate * numChannels * 2)) -- Byte rate
    outputFile:write(pack("string", "<I2", numChannels * 2))              -- Block align
    outputFile:write(pack("string", "<I2", 16))                           -- Bits per sample

    -- Write data chunk header
    outputFile:write("data")
    outputFile:write(pack("string", "<I4", pcmDataSize))

    -- Process ADPCM blocks in streaming fashion (read one block at a time)
    local samplesWritten = 0
    local sampleBuffer = {} -- Small buffer to reduce write calls
    local bufferSize = 1024 -- Write in chunks of 1024 samples

    -- Pre-allocate write buffer for better performance
    local writeBuffer = {}
    local writeBufferSize = 0
    local maxWriteBufferSize = 8192 -- Write in larger chunks

    for blockIdx = 0, blockCount - 1 do
        -- Seek to block position and read one block
        local blockPos = dataChunkPos + blockIdx * blockAlign
        inputFile:seek(blockPos)
        ---@type string|love.FileData
        local blockDataRaw = inputFile:read(blockAlign)

        if not blockDataRaw or #blockDataRaw < blockAlign then
            break
        end
        ---@type string
        local blockData = tostring(blockDataRaw)

        -- Create states for each channel
        local states = {}
        for ch = 1, numChannels do
            states[ch] = createState()

            -- Read initial state from block header
            local headerOffset = (ch - 1) * 4 + 1
            local initialSample = unpack("<i2", blockData, headerOffset)
            local initialIndex = byte(blockData, headerOffset + 2)

            states[ch].valprev = initialSample
            states[ch].index = min(initialIndex, 88)

            -- Buffer initial sample
            insert(sampleBuffer, initialSample)
        end

        -- Decode ADPCM nibbles
        local dataOffset = numChannels * 4 + 1
        local nibbleData = sub(blockData, dataOffset)

        if numChannels == 1 then
            -- Mono: process nibbles sequentially
            local state = states[1] -- Cache state reference
            for i = 1, #nibbleData do
                local b = byte(nibbleData, i)
                -- Low nibble first
                local sample1 = decodeNibble(band(b, 0x0F), state)
                insert(sampleBuffer, sample1)
                -- High nibble second
                local sample2 = decodeNibble(rshift(b, 4), state)
                insert(sampleBuffer, sample2)

                -- Write buffer if it's full
                if #sampleBuffer >= bufferSize then
                    -- Build packed data in one go
                    for _, sample in ipairs(sampleBuffer) do
                        insert(writeBuffer, pack("string", "<i2", sample))
                        writeBufferSize = writeBufferSize + 1
                        samplesWritten = samplesWritten + 1
                    end

                    -- Write when buffer is large enough
                    if writeBufferSize >= maxWriteBufferSize then
                        outputFile:write(concat(writeBuffer))
                        writeBuffer = {}
                        writeBufferSize = 0
                    end

                    sampleBuffer = {}
                end
            end
        else
            -- Stereo: interleaved by groups of 8 samples (4 bytes) per channel
            local bytesPerChannel = 4
            local i = 1
            local leftSamples = {}
            local rightSamples = {}

            while i <= #nibbleData do
                -- Cache state references
                local leftState = states[1]
                local rightState = states[2]

                -- Process left channel group
                for j = 0, bytesPerChannel - 1 do
                    if i + j <= #nibbleData then
                        local b = byte(nibbleData, i + j)
                        local sample1 = decodeNibble(band(b, 0x0F), leftState)
                        local sample2 = decodeNibble(rshift(b, 4), leftState)
                        insert(leftSamples, sample1)
                        insert(leftSamples, sample2)
                    end
                end
                i = i + bytesPerChannel

                -- Process right channel group
                for j = 0, bytesPerChannel - 1 do
                    if i + j <= #nibbleData then
                        local b = byte(nibbleData, i + j)
                        local sample1 = decodeNibble(band(b, 0x0F), rightState)
                        local sample2 = decodeNibble(rshift(b, 4), rightState)
                        insert(rightSamples, sample1)
                        insert(rightSamples, sample2)
                    end
                end
                i = i + bytesPerChannel

                -- Interleave and buffer samples
                local minSamples = min(#leftSamples, #rightSamples)
                for k = 1, minSamples do
                    insert(sampleBuffer, leftSamples[k])
                    insert(sampleBuffer, rightSamples[k])

                    -- Write buffer if it's full
                    if #sampleBuffer >= bufferSize then
                        for _, sample in ipairs(sampleBuffer) do
                            insert(writeBuffer, pack("string", "<i2", sample))
                            writeBufferSize = writeBufferSize + 1
                            samplesWritten = samplesWritten + 1
                        end

                        -- Write when buffer is large enough
                        if writeBufferSize >= maxWriteBufferSize then
                            outputFile:write(concat(writeBuffer))
                            writeBuffer = {}
                            writeBufferSize = 0
                        end

                        sampleBuffer = {}
                    end
                end

                leftSamples = {}
                rightSamples = {}
            end
        end
    end

    -- Write any remaining samples in buffer
    if #sampleBuffer > 0 then
        for _, sample in ipairs(sampleBuffer) do
            insert(writeBuffer, pack("string", "<i2", sample))
            samplesWritten = samplesWritten + 1
        end
    end

    -- Flush write buffer
    if #writeBuffer > 0 then
        outputFile:write(concat(writeBuffer))
    end

    outputFile:close()
    inputFile:close()

    log.debug("Successfully decoded IMA ADPCM to PCM: " .. samplesWritten .. " samples written to " .. outputPath)

    return true
end

return ImaAdpcmDecoder
