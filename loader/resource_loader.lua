-- Resource Loader for Main Thread
-- Loads project JSON and converts assets to Love2D resources
-- Runs only on main thread to safely use Love2D graphics API

local json = require("lib.json")
local ProjectModel = require("parser.project_model")
local path = require("pl.path")
local log = require("lib.log")
local resvg = require("resvg")
local Global = require("global")


---Replace Scratch font names with system font names in SVG content
---@param svgData string Original SVG content
---@return string Modified SVG content with system font names
local function replaceScratchFonts(svgData)
    -- Scratch font to system font mapping (using real font family names)
    -- Note: Escape special characters in Lua patterns (hyphens as %-)
    local fontReplacements = {
        ['font%-family="Sans Serif"'] = 'font-family="Noto Sans"',
        ['font%-family="Serif"'] = 'font-family="Source Serif Pro"',
        ['font%-family="Handwriting"'] = 'font-family="Handlee"',
        ['font%-family="Marker"'] = 'font-family="Knewave"',
        ['font%-family="Curly"'] = 'font-family="Griffy"',
        ['font%-family="Pixel"'] = 'font-family="Grand9K Pixel"',
        ['font%-family="Scratch"'] = 'font-family="ScratchFont"'
    }

    local modifiedSvg = svgData
    for scratchFont, systemFont in pairs(fontReplacements) do
        local newSvg, count = modifiedSvg:gsub(scratchFont, systemFont)
        if count > 0 then
            modifiedSvg = newSvg
            log.debug("Font replacement: " .. scratchFont .. " → " .. systemFont .. " (" .. count .. " times)")
        end
    end

    return modifiedSvg
end

---Extract viewBox coordinates from SVG data
---In Scratch 2.0+, rotationCenter is stored relative to the SVG's viewBox coordinate system.
---When viewBox has a non-zero origin, we need to compensate for this offset.
---@param svgData string SVG content as string
---@return table|nil viewBox Table with {x, y, width, height} or nil if not found
local function extractViewBox(svgData)
    -- Match viewBox attribute in <svg> tag
    -- Pattern matches: viewBox="x y width height" or viewBox='x y width height'
    -- Handles optional whitespace and supports negative numbers
    local x, y, w, h = svgData:match(
        '<svg[^>]-viewBox%s*=%s*["\']([%d.%-]+)%s+([%d.%-]+)%s+([%d.%-]+)%s+([%d.%-]+)["\']')

    if x then
        local viewBox = {
            x = tonumber(x) or 0,
            y = tonumber(y) or 0,
            width = tonumber(w) or 0,
            height = tonumber(h) or 0
        }

        log.debug("Extracted viewBox: x=%.2f, y=%.2f, width=%.2f, height=%.2f",
            viewBox.x, viewBox.y, viewBox.width, viewBox.height)

        return viewBox
    end

    -- No viewBox found - this is valid SVG, will use width/height attributes instead
    log.debug("No viewBox attribute found in SVG")
    return nil
end

---@class ResourceLoader
---@field assets table<string, Asset> Loaded asset storage
---@field adpcmThread love.Thread|nil ADPCM conversion thread
---@field adpcmRequestChannel love.Channel|nil Channel for ADPCM conversion requests
---@field adpcmResponseChannel love.Channel|nil Channel for ADPCM conversion responses
---@field pendingAdpcm table<string, table> Pending ADPCM conversions
local ResourceLoader = {}
ResourceLoader.__index = ResourceLoader

---@class Asset
---@field type string Asset type ("image" or "sound")
---@field data love.Image|love.Source The loaded Love2D object
---@field filename string Original filename
---@field imageData? love.ImageData Original ImageData for images (used for collision)
---@field originalFormat? string Original format (e.g., "svg" for rasterized SVGs)
---@field viewBoxOffsetX? number X offset from SVG viewBox (for rotation center compensation)
---@field viewBoxOffsetY? number Y offset from SVG viewBox (for rotation center compensation)

---Create new resource loader
---@return ResourceLoader
function ResourceLoader:new()
    local self = setmetatable({}, ResourceLoader)
    self.assets = {}
    self.pendingAdpcm = {}

    -- Initialize ADPCM conversion thread
    self.adpcmRequestChannel = love.thread.newChannel()
    self.adpcmResponseChannel = love.thread.getChannel("adpcm_response")

    -- Start worker thread for ADPCM conversion
    local threadCode = love.filesystem.read("loader/worker_adpcm.lua")
    if threadCode then
        self.adpcmThread = love.thread.newThread(threadCode)
        self.adpcmThread:start(self.adpcmRequestChannel)
    else
        log.warn("Failed to load ADPCM worker thread code")
    end

    return self
end

---Load project from extracted directory
---@param projectPath string Path to extracted project directory (relative to appdata)
---@param onProgress function|nil Progress callback: function(stage, progress, message)
---@return ProjectModel|nil model Loaded project model or nil on failure
---@return string|nil error Error message if loading failed
function ResourceLoader:loadProject(projectPath, onProgress)
    if onProgress then
        onProgress("parsing", 0.1, "Loading project.json...")
    end

    -- Load project.json
    local projectJsonPath = projectPath .. "/project.json"
    local projectJsonData = love.filesystem.read(projectJsonPath)

    if not projectJsonData then
        return nil, "Failed to read project.json from: " .. projectJsonPath
    end

    -- Parse project JSON
    local success, projectData = pcall(json.decode, projectJsonData)
    if not success then
        return nil, "Failed to parse project.json: " .. tostring(projectData)
    end

    if onProgress then
        onProgress("assets", 0.2, "Scanning assets...")
    end

    -- Collect asset filenames from project.json structure
    local assetFiles = {}
    local assetFileSet = {} -- Use set to avoid duplicates

    -- Extract costumes and sounds from all targets
    if projectData.targets then
        for _, target in ipairs(projectData.targets) do
            -- Collect costume assets
            if target.costumes then
                for _, costume in ipairs(target.costumes) do
                    -- Handle missing md5ext (fallback to assetId.dataFormat)
                    local md5ext = costume.md5ext
                    if not md5ext and costume.assetId and costume.dataFormat then
                        md5ext = costume.assetId .. "." .. costume.dataFormat
                        log.debug("Costume '" .. (costume.name or "unknown") ..
                                 "' missing md5ext, using fallback: " .. md5ext)
                    end

                    if md5ext and not assetFileSet[md5ext] then
                        table.insert(assetFiles, md5ext)
                        assetFileSet[md5ext] = true
                    end
                end
            end

            -- Collect sound assets
            if target.sounds then
                for _, sound in ipairs(target.sounds) do
                    -- Handle missing md5ext (fallback to assetId.dataFormat)
                    local md5ext = sound.md5ext
                    if not md5ext and sound.assetId and sound.dataFormat then
                        md5ext = sound.assetId .. "." .. sound.dataFormat
                        log.debug("Sound '" .. (sound.name or "unknown") ..
                                 "' missing md5ext, using fallback: " .. md5ext)
                    end

                    if md5ext and not assetFileSet[md5ext] then
                        table.insert(assetFiles, md5ext)
                        assetFileSet[md5ext] = true
                    end
                end
            end
        end
    end

    -- Clear previous assets
    self.assets = {}

    -- Load each asset based on project.json structure
    local totalAssets = #assetFiles
    if totalAssets > 0 then
        for i, filename in ipairs(assetFiles) do
            local progress = 0.2 + (i / totalAssets) * 0.7
            if onProgress then
                onProgress("assets", progress, "Loading: " .. filename)
            end

            local filePath = projectPath .. "/" .. filename
            self:loadAsset(filename, filePath)
        end
    end

    if onProgress then
        onProgress("model", 0.9, "Creating project model...")
    end

    -- Create project model
    local model = ProjectModel:new(projectData, self.assets, projectPath)

    if onProgress then
        onProgress("complete", 1.0, "Project loaded successfully")
    end

    return model, nil
end

---Load individual asset file
---@param filename string Asset filename (used for MD5 extraction)
---@param filePath string Full path to asset file (relative to appdata)
function ResourceLoader:loadAsset(filename, filePath)
    log.debug("Loading asset: " .. filename .. " from " .. filePath)
    local ext = path.extension(filename)
    if not ext then
        log.warn("Unknown asset type for file: " .. filename)
        return
    end

    ext = ext:lower()
    log.debug("Asset extension: " .. ext)

    if ext == ".png" or ext == ".jpg" or ext == ".jpeg" or ext == ".gif" or ext == ".bmp" then
        self:loadImage(filename, filePath)
    elseif ext == ".wav" or ext == ".mp3" then
        self:loadSound(filename, filePath)
    elseif ext == ".svg" then
        self:loadSVG(filename, filePath)
    else
        log.warn("Unknown asset type: " .. ext .. " for " .. filename)
    end
end

---Load image asset
---@param filename string Asset filename
---@param filePath string Full path to image file
function ResourceLoader:loadImage(filename, filePath)
    local imageData, image = nil, nil
    local success, result = pcall(function()
        imageData = love.image.newImageData(filePath)
        image = love.graphics.newImage(imageData)
        return image
    end)

    local md5 = filename:match("^([^%.]+)")
    if md5 then
        if success and result then
            -- Store both Image and ImageData for collision detection
            self.assets[md5] = {
                type = "image",
                data = result,         -- Love2D Image object
                imageData = imageData, -- ImageData for collision detection
                filename = filename
            }
            log.debug("Successfully loaded image: " .. filename .. " with MD5: " .. md5)
        else
            log.warn("Failed to load image '" .. filename .. "': " .. tostring(result))
        end
    else
        log.warn("Could not extract MD5 from filename: " .. filename)
    end
end

---Load SVG asset
---@param filename string Asset filename
---@param filePath string Full path to SVG file
function ResourceLoader:loadSVG(filename, filePath)
    -- Extract MD5 from filename
    local md5 = filename:match("^([^%.]+)")
    if not md5 then
        log.warn("Could not extract MD5 from SVG filename: " .. filename)
        return
    end

    -- Generate cache filename based on DPI scale
    local dirPath = path.dirname(filePath)
    local cacheFilename = string.format("%s/%s_x%d.png", dirPath, md5, Global.SVG_RESOLUTION_SCALE)

    -- Check if cached PNG exists
    if love.filesystem.getInfo(cacheFilename) then
        log.debug("Loading SVG from cache: " .. cacheFilename)
        local success, result = pcall(function()
            local imageData = love.image.newImageData(cacheFilename)
            return imageData
        end)

        if success and result then
            -- Successfully loaded from cache
            local image = love.graphics.newImage(result)
            image:setFilter("linear", "linear")
            pcall(function()
                image:setMipmapFilter("linear", 0)
            end)

            -- Read SVG data to extract viewBox (needed for rotation center compensation)
            local svgData = love.filesystem.read(filePath)
            local viewBox = svgData and extractViewBox(svgData) or nil

            self.assets[md5] = {
                type = "image",
                data = image,
                imageData = result,
                filename = filename,
                originalFormat = "svg",
                viewBoxOffsetX = viewBox and viewBox.x or 0,
                viewBoxOffsetY = viewBox and viewBox.y or 0,
            }
            log.info("Successfully loaded SVG from cache: " .. cacheFilename)
            return
        else
            log.warn("Failed to load cached PNG, will re-rasterize: " .. tostring(result))
        end
    end

    -- No cache or cache loading failed, perform rasterization
    -- Read SVG data first
    local svgData = love.filesystem.read(filePath)
    if not svgData then
        log.warn("Failed to read SVG file: " .. filename)
        return
    end

    -- Replace Scratch font names with system font names
    svgData = replaceScratchFonts(svgData)

    -- Extract viewBox for rotation center compensation (matching native Scratch)
    local viewBox = extractViewBox(svgData)

    log.debug("Loading SVG with resvg (pre-rasterize): " .. filename)

    -- Try to load with resvg
    local success, result = pcall(function()
        -- Parse SVG data into render tree
        local tree, err = resvg.Tree.from_data(svgData, Global.resvgOptions)
        if not tree then
            log.warn("Failed to parse SVG: " .. tostring(err))
            return nil
        end

        -- Get SVG intrinsic dimensions (CSS pixels at 96 DPI)
        local size = tree:get_size()

        -- Rasterize at 2x to match Scratch's bitmapResolution=2 convention
        local width = math.ceil(size.width * Global.SVG_RESOLUTION_SCALE)
        local height = math.ceil(size.height * Global.SVG_RESOLUTION_SCALE)

        -- Apply an explicit scale so resvg content fills the target pixmap.
        -- Without this, resvg renders at intrinsic size into a larger pixmap,
        -- which makes the image appear smaller and offsets rotation centers.
        local transform = resvg.Transform.scale(Global.SVG_RESOLUTION_SCALE, Global.SVG_RESOLUTION_SCALE)

        -- CRITICAL MEMORY OPTIMIZATION: Zero-copy rendering
        -- Instead of rendering to pixmap then copying, render directly to ImageData's memory

        -- Step 1: Create empty ImageData
        local imageData = love.image.newImageData(width, height, "rgba8")

        -- Step 2: Get FFI pointer to ImageData's internal buffer
        local imageDataPtr = imageData:getFFIPointer()
        if not imageDataPtr then
            error("Failed to get FFI pointer from ImageData")
        end

        -- Step 3: Render directly to ImageData's memory using the new API (zero-copy!)
        tree:render_to_buffer(width, height, imageDataPtr, transform)

        return imageData
    end)

    if success and result then
        -- Save to cache for future use
        local cacheSuccess, cacheError = pcall(function()
            result:encode("png", cacheFilename)
        end)

        if cacheSuccess then
            log.debug("Saved rasterized SVG to cache: " .. cacheFilename)
        else
            log.warn("Failed to save SVG cache: " .. tostring(cacheError))
        end

        -- Create Love2D Image from ImageData
        local image = love.graphics.newImage(result)

        -- Set linear filtering for SVGs since they are pre-rasterized at high quality
        -- This provides smooth scaling while preserving the 2x rasterization quality
        image:setFilter("linear", "linear")
        pcall(function()
            image:setMipmapFilter("linear", 0)
        end)

        -- Store as unified format - same as bitmap
        self.assets[md5] = {
            type = "image",     -- Treat SVG as image after rasterization
            data = image,       -- Love2D Image for rendering
            imageData = result, -- ImageData for collision detection
            filename = filename,
            originalFormat = "svg",
            -- Store viewBox offset for rotation center compensation (matching native Scratch)
            viewBoxOffsetX = viewBox and viewBox.x or 0,
            viewBoxOffsetY = viewBox and viewBox.y or 0,
        }
    else
        log.warn("Failed to load SVG '" .. filename .. "' - resvg error: " .. tostring(result))
        -- build a empty image
        local emptyImageData = love.image.newImageData(1, 1)
        local emptyImage = love.graphics.newImage(emptyImageData)
        self.assets[md5] = {
            type = "image",
            data = emptyImage,
            imageData = emptyImageData,
            filename = filename,
            originalFormat = "svg",
            viewBoxOffsetX = viewBox and viewBox.x or 0,
            viewBoxOffsetY = viewBox and viewBox.y or 0,
        }
    end
end

---Load sound asset
---@param filename string Asset filename
---@param filePath string Full path to sound file
function ResourceLoader:loadSound(filename, filePath)
    local success, result = pcall(function()
        return love.audio.newSource(filePath, "static")
    end)

    local md5 = filename:match("^([^%.]+)")
    if md5 then
        if success and result then
            self.assets[md5] = {
                type = "sound",
                data = result,
                filename = filename
            }
            log.debug("Successfully loaded sound: " .. filename)
        else
            -- Standard audio loading failed, try ADPCM conversion
            log.info("Standard audio loading failed for '" .. filename .. "', attempting ADPCM conversion...")

            -- First check if we already have a converted PCM file
            local dirPath = path.dirname(filePath)
            local pcmFilename = dirPath .. "/" .. md5 .. "_pcm.wav"

            if love.filesystem.getInfo(pcmFilename) then
                -- Converted file already exists, try to load it directly
                log.info("Found existing converted PCM file: " .. pcmFilename)

                local pcmSuccess, pcmSource = pcall(function()
                    return love.audio.newSource(pcmFilename, "static")
                end)

                if pcmSuccess and pcmSource then
                    self.assets[md5] = {
                        type = "sound",
                        data = pcmSource,
                        filename = filename,
                        originalFormat = "ima_adpcm",
                        convertedPath = pcmFilename
                    }
                    log.info("Successfully loaded existing converted PCM audio: " .. filename)
                    return
                else
                    log.warn("Failed to load existing converted PCM audio, will re-convert: " .. tostring(pcmSource))
                end
            end

            if not (self.adpcmThread and self.adpcmRequestChannel) then
                error("ADPCM worker thread failed to start, cannot process audio: " .. filename)
            end

            -- Send conversion request to worker thread (decoder will check format internally)
            self.adpcmRequestChannel:push({
                type = "convert",
                md5 = md5,
                inputPath = filePath,  -- Pass file path for streaming
                outputPath = pcmFilename
            })

            -- Track pending conversion
            self.pendingAdpcm[md5] = {
                filename = filename,
                pcmFilename = pcmFilename,
                originalError = tostring(result)  -- Store original load error for better diagnostics
            }

            log.info("ADPCM conversion queued for: " .. filename)
        end
    end
end

---Get loaded assets
---@return table<string, Asset> assets Map of MD5 hash to asset data
function ResourceLoader:getAssets()
    return self.assets
end

---Check if there are pending ADPCM conversions
---@return boolean hasPending True if there are pending conversions
---@return number count Number of pending conversions
function ResourceLoader:hasPendingAdpcm()
    local count = 0
    for _ in pairs(self.pendingAdpcm) do
        count = count + 1
    end
    return count > 0, count
end

---Check for completed ADPCM conversions
---@return boolean hasCompletions True if any conversions completed
function ResourceLoader:checkAdpcmConversions()
    if not self.adpcmResponseChannel then
        return false
    end

    local hasCompletions = false
    local response = self.adpcmResponseChannel:pop()

    while response do
        if response.type == "complete" then
            local pending = self.pendingAdpcm[response.md5]
            if pending then
                if response.success then
                    log.info("ADPCM conversion completed for: " .. pending.filename)

                    -- Try loading the converted PCM file
                    local pcmSuccess, pcmSource = pcall(function()
                        return love.audio.newSource(response.outputPath, "static")
                    end)

                    if pcmSuccess and pcmSource then
                        self.assets[response.md5] = {
                            type = "sound",
                            data = pcmSource,
                            filename = pending.filename,
                            originalFormat = "ima_adpcm",
                            convertedPath = response.outputPath
                        }
                        log.info("Successfully loaded converted IMA ADPCM audio: " .. pending.filename)
                    else
                        log.warn("Failed to load converted PCM audio: " .. tostring(pcmSource))
                    end
                else
                    log.warn("ADPCM conversion failed for " .. pending.filename .. ": " .. tostring(response.error))
                end

                self.pendingAdpcm[response.md5] = nil
                hasCompletions = true
            end
        elseif response.type == "progress" then
            -- Could display progress if needed
            log.debug("ADPCM conversion progress: " .. (response.progress * 100) .. "%")
        end

        response = self.adpcmResponseChannel:pop()
    end

    return hasCompletions
end

---Clear all loaded assets
function ResourceLoader:clear()
    self.assets = {}

    -- Clean up thread if needed
    if self.adpcmThread then
        self.adpcmRequestChannel:push({ type = "quit" })
        self.adpcmThread:wait()
        self.adpcmThread = nil
    end

    self.pendingAdpcm = {}
end

return ResourceLoader
