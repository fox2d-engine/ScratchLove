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
        local success, err = ImaAdpcmDecoder.decode(request.inputPath, request.outputPath)

        responseChannel:push({
            type = "complete",
            md5 = request.md5,
            success = success,
            error = err,
            outputPath = request.outputPath
        })
    elseif request.type == "quit" then
        break
    end
end
