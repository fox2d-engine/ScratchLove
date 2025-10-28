-- ADPCM Conversion Worker Thread
-- Runs in a separate thread to convert IMA ADPCM to PCM without blocking main thread

require("love.filesystem")
require("love.data")
local ImaAdpcmDecoder = require("audio.ima_adpcm_decoder")

-- Thread channels for communication
local requestChannel = ... -- Channel to receive conversion requests
local responseChannel = love.thread.getChannel("adpcm_response")

-- Main worker loop
while true do
    local request = requestChannel:demand()

    if request.type == "convert" then
        -- Decode with streaming: input path -> output path
        -- Wrap in pcall to catch any exceptions and prevent resource leaks
        local success, result, err = pcall(ImaAdpcmDecoder.decode, request.inputPath, request.outputPath)

        if not success then
            -- pcall returned false: an exception occurred
            responseChannel:push({
                type = "complete",
                md5 = request.md5,
                success = false,
                error = "Exception during decoding: " .. tostring(result),
                outputPath = request.outputPath
            })
        else
            -- pcall returned true: normal return from decode()
            responseChannel:push({
                type = "complete",
                md5 = request.md5,
                success = result,
                error = err,
                outputPath = request.outputPath
            })
        end
    elseif request.type == "quit" then
        break
    end
end
