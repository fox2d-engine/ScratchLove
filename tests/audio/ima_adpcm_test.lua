-- Test for IMA ADPCM decoder
local lust = require("tests.lust")
local ImaAdpcmDecoder = require("audio.ima_adpcm_decoder")

-- Note: Love2D mocks (love.data, love.filesystem) are provided by tests/mocks/love_mock.lua
-- which is automatically loaded by tests/run.lua

local describe = lust.describe
local it = lust.it
local expect = lust.expect

describe("IMA ADPCM Decoder", function()
    it("should detect IMA ADPCM format correctly", function()
        -- Create a minimal IMA ADPCM WAV header
        local header = {}

        -- RIFF header
        table.insert(header, "RIFF")
        table.insert(header, love.data.pack("string", "<I4", 100)) -- File size (dummy)
        table.insert(header, "WAVE")

        -- fmt chunk
        table.insert(header, "fmt ")
        table.insert(header, love.data.pack("string", "<I4", 20)) -- Chunk size
        table.insert(header, love.data.pack("string", "<I2", 0x11)) -- IMA ADPCM format
        table.insert(header, love.data.pack("string", "<I2", 1)) -- Channels
        table.insert(header, love.data.pack("string", "<I4", 22050)) -- Sample rate
        table.insert(header, love.data.pack("string", "<I4", 11155)) -- Byte rate
        table.insert(header, love.data.pack("string", "<I2", 256)) -- Block align
        table.insert(header, love.data.pack("string", "<I2", 4)) -- Bits per sample
        table.insert(header, love.data.pack("string", "<I2", 2)) -- cbSize
        table.insert(header, love.data.pack("string", "<I2", 505)) -- Samples per block

        -- Add padding to ensure we have enough data
        table.insert(header, string.rep("\0", 10)) -- Extra padding

        local testData = table.concat(header)

        local isAdpcm, blockAlign, samplesPerBlock = ImaAdpcmDecoder.isImaAdpcm(testData)
        expect(isAdpcm).to.equal(true)
        expect(blockAlign).to.equal(256)
        expect(samplesPerBlock).to.equal(505)
    end)

    it("should detect non-ADPCM format correctly", function()
        -- Create a PCM WAV header
        local header = {}

        -- RIFF header
        table.insert(header, "RIFF")
        table.insert(header, love.data.pack("string", "<I4", 100))
        table.insert(header, "WAVE")

        -- fmt chunk
        table.insert(header, "fmt ")
        table.insert(header, love.data.pack("string", "<I4", 16))
        table.insert(header, love.data.pack("string", "<I2", 1)) -- PCM format
        table.insert(header, love.data.pack("string", "<I2", 1)) -- Channels
        table.insert(header, love.data.pack("string", "<I4", 22050)) -- Sample rate
        table.insert(header, love.data.pack("string", "<I4", 44100)) -- Byte rate
        table.insert(header, love.data.pack("string", "<I2", 2)) -- Block align
        table.insert(header, love.data.pack("string", "<I2", 16)) -- Bits per sample

        local testData = table.concat(header)

        local isAdpcm = ImaAdpcmDecoder.isImaAdpcm(testData)
        expect(isAdpcm).to.equal(false)
    end)

    it("should decode simple ADPCM data", function()
        -- Create a minimal IMA ADPCM WAV file with a single block
        local wavData = {}

        -- RIFF header
        table.insert(wavData, "RIFF")
        table.insert(wavData, love.data.pack("string", "<I4", 56)) -- File size
        table.insert(wavData, "WAVE")

        -- fmt chunk
        table.insert(wavData, "fmt ")
        table.insert(wavData, love.data.pack("string", "<I4", 20)) -- Chunk size
        table.insert(wavData, love.data.pack("string", "<I2", 0x11)) -- IMA ADPCM format
        table.insert(wavData, love.data.pack("string", "<I2", 1)) -- Mono
        table.insert(wavData, love.data.pack("string", "<I4", 8000)) -- Sample rate
        table.insert(wavData, love.data.pack("string", "<I4", 4055)) -- Byte rate
        table.insert(wavData, love.data.pack("string", "<I2", 256)) -- Block align
        table.insert(wavData, love.data.pack("string", "<I2", 4)) -- Bits per sample
        table.insert(wavData, love.data.pack("string", "<I2", 2)) -- cbSize
        table.insert(wavData, love.data.pack("string", "<I2", 505)) -- Samples per block

        -- data chunk
        table.insert(wavData, "data")
        table.insert(wavData, love.data.pack("string", "<I4", 8)) -- Data size (small test)

        -- ADPCM data block (header + compressed nibbles)
        table.insert(wavData, love.data.pack("string", "<i2", 0)) -- Initial sample
        table.insert(wavData, love.data.pack("string", "B", 0)) -- Initial index
        table.insert(wavData, love.data.pack("string", "B", 0)) -- Reserved

        -- Some ADPCM nibbles (test data)
        table.insert(wavData, string.char(0x12, 0x34, 0x56, 0x78))

        local testData = table.concat(wavData)

        -- Write test data to mock file
        local inputPath = "test_input.wav"
        love.filesystem.write(inputPath, testData)

        -- Test decoding with file path (streaming)
        local success, err = ImaAdpcmDecoder.decode(inputPath, "test_output.wav")
        expect(success).to.equal(true)
        expect(err).to.equal(nil)
    end)
end)