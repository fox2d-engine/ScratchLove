local ffi = require("ffi")

ffi.cdef [[
    typedef struct { uint8_t r, g, b, a; } Pixel;
]]

local costumeImageData
local costume
local redLine

local backgroundCanvas
local debugCanvas = nil
local spriteX
local spriteY
local spriteRotation

local moveSpeed
local rotateSpeed

local testCount
local dpiScale = 1

local function checkColorCollisionCPU(sprite_x, sprite_y, sprite_image_data, background_canvas, check_r, check_g, check_b,
                                      rotation)
    local sprite_width = sprite_image_data:getWidth()
    local sprite_height = sprite_image_data:getHeight()

    local center_x = sprite_width / 2
    local center_y = sprite_height / 2

    local bg_data = background_canvas:newImageData()
    local canvas_width = bg_data:getWidth()
    local canvas_height = bg_data:getHeight()

    local sprite_pixels = ffi.cast("Pixel*", sprite_image_data:getFFIPointer())
    local bg_pixels = ffi.cast("Pixel*", bg_data:getFFIPointer())

    local target_r = math.floor(check_r * 255 + 0.5)
    local target_g = math.floor(check_g * 255 + 0.5)
    local target_b = math.floor(check_b * 255 + 0.5)
    local epsilon = 25

    local cos_r = math.cos(rotation)
    local sin_r = math.sin(rotation)

    for sy = 0, sprite_height - 1 do
        local sprite_row_offset = sy * sprite_width

        for sx = 0, sprite_width - 1 do
            local sprite_pixel = sprite_pixels[sprite_row_offset + sx]

                local dx = sx - center_x
                local dy = sy - center_y

                local rotated_x = dx * cos_r - dy * sin_r
                local rotated_y = dx * sin_r + dy * cos_r

                local canvas_x = math.floor((sprite_x + center_x + rotated_x) * dpiScale)
                local canvas_y = math.floor((sprite_y + center_y + rotated_y) * dpiScale)

                if canvas_x >= 0 and canvas_x < canvas_width and
                    canvas_y >= 0 and canvas_y < canvas_height then

                    local bg_pixel = bg_pixels[canvas_y * canvas_width + canvas_x]

                    if math.abs(bg_pixel.r - target_r) < epsilon and
                        math.abs(bg_pixel.g - target_g) < epsilon and
                        math.abs(bg_pixel.b - target_b) < epsilon and
                        bg_pixel.a > 25 then
                        return true, canvas_x / dpiScale, canvas_y / dpiScale
                    end
                end
            end
        end
    end

    return false, nil, nil
end

local alphaThresholdShader = love.graphics.newShader [[
    vec4 effect(vec4 color, Image texture, vec2 texture_coords, vec2 screen_coords) {
        vec4 pixel = Texel(texture, texture_coords);
        // Only draw pixels with alpha > 0.1
        if (pixel.a < 0.1) {
            discard;
        }
        return pixel * color;
    }
]]

local temp_canvas_cache = nil

local function checkColorCollisionGPU(sprite_x, sprite_y, sprite_image, background_canvas, check_r, check_g, check_b,
                                      rotation)
    local sprite_width = sprite_image:getWidth()
    local sprite_height = sprite_image:getHeight()

    if not temp_canvas_cache then
        temp_canvas_cache = love.graphics.newCanvas(love.graphics.getWidth(), love.graphics.getHeight())
    end

    local temp_canvas = temp_canvas_cache

    local prev_canvas = love.graphics.getCanvas()
    local prev_blend_mode = love.graphics.getBlendMode()
    local prev_shader = love.graphics.getShader()

    local function sprite_stencil()
        love.graphics.push()
        love.graphics.translate(sprite_x + sprite_width / 2, sprite_y + sprite_height / 2)
        love.graphics.rotate(rotation)
        love.graphics.setColor(1, 1, 1, 1)
        love.graphics.setShader(alphaThresholdShader)
        love.graphics.draw(sprite_image, -sprite_width / 2, -sprite_height / 2)
        love.graphics.setShader()
        love.graphics.pop()
    end

    love.graphics.setCanvas({ temp_canvas, stencil = true })
    love.graphics.clear(0, 0, 0, 0)

    love.graphics.stencil(sprite_stencil, "replace", 1, false)

    love.graphics.setStencilTest("equal", 1)

    love.graphics.setBlendMode("alpha", "premultiplied")
    love.graphics.setColor(1, 1, 1, 1)
    love.graphics.draw(background_canvas, 0, 0)

    love.graphics.setStencilTest()
    love.graphics.setBlendMode(prev_blend_mode)
    love.graphics.setShader(prev_shader)

    love.graphics.setCanvas(prev_canvas)

    local diagonal = math.sqrt(sprite_width * sprite_width + sprite_height * sprite_height)
    local center_x = (sprite_x + sprite_width / 2) * dpiScale
    local center_y = (sprite_y + sprite_height / 2) * dpiScale

    local canvas_pixel_width = love.graphics.getPixelWidth()
    local canvas_pixel_height = love.graphics.getPixelHeight()

    local region_x = math.max(0, math.floor(center_x - diagonal / 2 * dpiScale))
    local region_y = math.max(0, math.floor(center_y - diagonal / 2 * dpiScale))
    local region_w = math.min(canvas_pixel_width - region_x, math.ceil(diagonal * dpiScale))
    local region_h = math.min(canvas_pixel_height - region_y, math.ceil(diagonal * dpiScale))

    if region_w <= 0 or region_h <= 0 then
        return false, nil, nil
    end

    local imagedata = temp_canvas:newImageData(1, 1, region_x, region_y, region_w, region_h)

    if debugMode then
        if debugCanvas then
            debugCanvas:release()
        end
        debugCanvas = love.graphics.newCanvas(love.graphics.getWidth(), love.graphics.getHeight())
        local prev = love.graphics.getCanvas()
        love.graphics.setCanvas(debugCanvas)
        love.graphics.setColor(1, 1, 1, 1)
        love.graphics.draw(temp_canvas, 0, 0)
        love.graphics.setCanvas(prev)
    end

    local pixels = ffi.cast("Pixel*", imagedata:getFFIPointer())
    local width = imagedata:getWidth()
    local height = imagedata:getHeight()

    local target_r = math.floor(check_r * 255 + 0.5)
    local target_g = math.floor(check_g * 255 + 0.5)
    local target_b = math.floor(check_b * 255 + 0.5)
    local epsilon = 25

    local inv_dpi = 1 / dpiScale
    local step = 2

    for y = 0, height - 1, step do
        local row_offset = y * width

        for x = 0, width - 1, step do
            local pixel = pixels[row_offset + x]

            if pixel.a > 25 then
                local dr = pixel.r > target_r and pixel.r - target_r or target_r - pixel.r
                if dr < epsilon then
                    local dg = pixel.g > target_g and pixel.g - target_g or target_g - pixel.g
                    if dg < epsilon then
                        local db = pixel.b > target_b and pixel.b - target_b or target_b - pixel.b
                        if db < epsilon then
                            local result_x = (region_x + x) * inv_dpi
                            local result_y = (region_y + y) * inv_dpi
                            return true, result_x, result_y
                        end
                    end
                end
            end
        end
    end

    return false, nil, nil
end

function love.load()
    dpiScale = love.graphics.getDPIScale()
    print("DPI Scale:", dpiScale)
    print("Window size (logical):", love.graphics.getWidth(), "x", love.graphics.getHeight())
    print("Window size (pixels):", love.graphics.getPixelWidth(), "x", love.graphics.getPixelHeight())

    local imageFiles = { "cat.png", "costume1.png", "sprite.png" }
    local imageLoaded = false

    for _, filename in ipairs(imageFiles) do
        local success, data = pcall(love.image.newImageData, filename)
        if success then
            costumeImageData = data
            costume = love.graphics.newImage(data)
            imageLoaded = true
            print("Loaded image:", filename)
            break
        end
    end

    if not imageLoaded then
        error("No valid image file found (tried: cat.png, costume1.png, sprite.png)")
    end

    local redLineData = love.image.newImageData("red-line.png")
    redLine = love.graphics.newImage(redLineData)

    backgroundCanvas = love.graphics.newCanvas(love.graphics.getWidth(), love.graphics.getHeight())

    love.graphics.setCanvas(backgroundCanvas)
    love.graphics.setColor(1, 1, 1, 1)
    love.graphics.setCanvas()

    spriteX = love.graphics.getWidth() / 2
    spriteY = love.graphics.getHeight() / 2


    testCount = 0

    debugMode = false

    print("Costume size:", costume:getWidth(), "x", costume:getHeight())
    print("Red line size:", redLine:getWidth(), "x", redLine:getHeight())
    print("Red line position: 10, 300")
    print("Controls: Arrow keys to move, Q/E to rotate")
    print("========================================")
end

function love.update(dt)
    local moveDistance = moveSpeed * dt

    if love.keyboard.isDown("left") then
        spriteX = spriteX - moveDistance
    end
    if love.keyboard.isDown("right") then
        spriteX = spriteX + moveDistance
    end
    if love.keyboard.isDown("up") then
        spriteY = spriteY - moveDistance
    end
    if love.keyboard.isDown("down") then
        spriteY = spriteY + moveDistance
    end

    local rotateAmount = rotateSpeed * dt

    if love.keyboard.isDown("q") then
        spriteRotation = spriteRotation - rotateAmount
    end
    if love.keyboard.isDown("e") then
        spriteRotation = spriteRotation + rotateAmount
    end

    spriteRotation = spriteRotation % (2 * math.pi)
end

function love.draw()
    love.graphics.setColor(1, 1, 1, 1)
    love.graphics.draw(backgroundCanvas, 0, 0)

    love.graphics.push()
    love.graphics.translate(spriteX + costume:getWidth() / 2, spriteY + costume:getHeight() / 2)
    love.graphics.rotate(spriteRotation)
    love.graphics.setColor(1, 1, 1, 1)
    love.graphics.draw(costume, -costume:getWidth() / 2, -costume:getHeight() / 2)
    love.graphics.pop()

    local cpu_start = love.timer.getTime()
    local cpu_collision, cpu_x, cpu_y = checkColorCollisionCPU(
        spriteX, spriteY, costumeImageData, backgroundCanvas,
        spriteRotation
    )
    local cpu_time = (love.timer.getTime() - cpu_start) * 1000

    local gpu_start = love.timer.getTime()
    local gpu_collision, gpu_x, gpu_y = checkColorCollisionGPU(
        spriteX, spriteY, costume, backgroundCanvas,
        spriteRotation
    )
    local gpu_time = (love.timer.getTime() - gpu_start) * 1000

    love.graphics.setColor(0, 0, 0, 1)
    love.graphics.print("Color Collision Test", 10, 10)
    love.graphics.print(string.format("Position: (%.0f, %.0f) | Rotation: %.1f°",
        spriteX, spriteY, math.deg(spriteRotation)), 10, 30)

    if cpu_collision then
        love.graphics.setColor(1, 0, 0, 1)
        love.graphics.print(string.format("CPU: COLLISION at (%d, %d) [%.2fms]", cpu_x, cpu_y, cpu_time), 10, 50)
    else
        love.graphics.setColor(0, 0.5, 0, 1)
        love.graphics.print(string.format("CPU: No collision [%.2fms]", cpu_time), 10, 50)
    end

    if gpu_collision then
        love.graphics.setColor(0, 0, 1, 1)
        love.graphics.print(string.format("GPU: COLLISION at (%d, %d) [%.2fms]", gpu_x, gpu_y, gpu_time), 10, 70)
    else
        love.graphics.setColor(0, 0.5, 0, 1)
        love.graphics.print(string.format("GPU: No collision [%.2fms]", gpu_time), 10, 70)
    end

    if cpu_collision ~= gpu_collision then
        love.graphics.setColor(1, 0.5, 0, 1)
        love.graphics.print("MISMATCH!", 10, 90)
    else
        love.graphics.setColor(0, 0.7, 0, 1)
        love.graphics.print("Methods agree", 10, 90)
    end

    love.graphics.push()
    love.graphics.translate(spriteX + costume:getWidth() / 2, spriteY + costume:getHeight() / 2)
    love.graphics.rotate(spriteRotation)
    love.graphics.setColor(0, 0, 1, 0.3)
    love.graphics.rectangle("line", -costume:getWidth() / 2, -costume:getHeight() / 2, costume:getWidth(),
        costume:getHeight())
    love.graphics.pop()

    love.graphics.setColor(1, 0, 0, 0.3)
    love.graphics.rectangle("line", 10, 300, redLine:getWidth(), redLine:getHeight())

    if cpu_collision then
        love.graphics.setColor(1, 0, 0, 0.8)
        love.graphics.circle("fill", cpu_x, cpu_y, 10)
        love.graphics.setColor(1, 1, 1, 1)
        love.graphics.circle("line", cpu_x, cpu_y, 10)

        love.graphics.setColor(1, 1, 1, 1)
        love.graphics.print("C", cpu_x - 4, cpu_y - 7)
    end

    if gpu_collision then
        love.graphics.setColor(0, 0.3, 1, 0.8)
        love.graphics.circle("fill", gpu_x, gpu_y, 10)
        love.graphics.setColor(1, 1, 1, 1)
        love.graphics.circle("line", gpu_x, gpu_y, 10)

        love.graphics.setColor(1, 1, 1, 1)
        love.graphics.print("G", gpu_x - 4, gpu_y - 7)
    end

    if cpu_collision and gpu_collision then
        local distance = math.sqrt((cpu_x - gpu_x) ^ 2 + (cpu_y - gpu_y) ^ 2)
        if distance < 5 then
            love.graphics.setColor(0.5, 0, 0.8, 0.5)
            love.graphics.circle("line", (cpu_x + gpu_x) / 2, (cpu_y + gpu_y) / 2, 15)
            love.graphics.setLineWidth(2)
            love.graphics.circle("line", (cpu_x + gpu_x) / 2, (cpu_y + gpu_y) / 2, 15)
            love.graphics.setLineWidth(1)
        end
    end

    if debugMode and debugCanvas then
        love.graphics.setColor(0, 1, 1, 0.3)
        love.graphics.draw(debugCanvas, 0, 0)

        love.graphics.setColor(0, 0.5, 1, 1)
        love.graphics.print("DEBUG MODE: Showing GPU stencil area (cyan overlay)", 10, 110)
    end

    love.graphics.setColor(0, 0, 0, 0.7)
    love.graphics.print("Arrow keys: Move | Q/E: Rotate | D: Debug | I: Info | T: Test pos | SPACE: Test | ESC: Quit", 10,
        love.graphics.getHeight() - 30)
end

function love.keypressed(key)
    if key == "escape" then
        love.event.quit()
    elseif key == "d" then
        debugMode = not debugMode
        print("Debug mode:", debugMode and "ON" or "OFF")
    elseif key == "i" then
        print("\n=== DPI & Canvas Info ===")
        print(string.format("DPI Scale: %.2f", dpiScale))
        print(string.format("Window: %dx%d (logical)", love.graphics.getWidth(), love.graphics.getHeight()))
        print(string.format("Window: %dx%d (pixels)", love.graphics.getPixelWidth(), love.graphics.getPixelHeight()))

        local bg_data = backgroundCanvas:newImageData()
        print(string.format("Background Canvas ImageData: %dx%d", bg_data:getWidth(), bg_data:getHeight()))
        print(string.format("Sprite Position: (%.0f, %.0f) logical", spriteX, spriteY))
        print(string.format("Sprite Position: (%.0f, %.0f) pixels", spriteX * dpiScale, spriteY * dpiScale))
    elseif key == "space" then
        testCount = testCount + 1

        local cpu_start = love.timer.getTime()
        local cpu_collision, cpu_x, cpu_y = checkColorCollisionCPU(
            spriteX, spriteY, costumeImageData, backgroundCanvas,
            1, 0, 0, spriteRotation
        )
        local cpu_time = (love.timer.getTime() - cpu_start) * 1000

        local gpu_start = love.timer.getTime()
        local gpu_collision, gpu_x, gpu_y = checkColorCollisionGPU(
            spriteX, spriteY, costume, backgroundCanvas,
            1, 0, 0, spriteRotation
        )
        local gpu_time = (love.timer.getTime() - gpu_start) * 1000

        print(string.format("\n=== Test #%d ===", testCount))
        print(string.format("Position: (%.0f, %.0f) | Rotation: %.1f°",
            spriteX, spriteY, math.deg(spriteRotation)))
        print(string.format("CPU: %s [%.2fms]",
            cpu_collision and string.format("COLLISION at (%d, %d)", cpu_x, cpu_y) or "No collision", cpu_time))
        print(string.format("GPU: %s [%.2fms]",
            gpu_collision and string.format("COLLISION at (%d, %d)", gpu_x, gpu_y) or "No collision", gpu_time))

        if cpu_collision ~= gpu_collision then
            print("[WARNING] Methods disagree!")
        else
            print("[OK] Methods agree")
        end
    elseif key == "r" then
        spriteX = love.graphics.getWidth() / 2 - costume:getWidth() / 2
        spriteY = love.graphics.getHeight() / 2 - costume:getHeight() / 2
        spriteRotation = 0
        print("\nPosition reset to center")
    elseif key == "t" then
        spriteX = 100
        spriteRotation = 0
        print("\n=== Test Position (should hit red line) ===")
        print(string.format("Position: (%.0f, %.0f), Rotation: 0°", spriteX, spriteY))

        local cpu_start = love.timer.getTime()
        local cpu_collision, cpu_x, cpu_y = checkColorCollisionCPU(
            spriteX, spriteY, costumeImageData, backgroundCanvas,
            1, 0, 0, spriteRotation
        )
        local cpu_time = (love.timer.getTime() - cpu_start) * 1000

        local gpu_start = love.timer.getTime()
        local gpu_collision, gpu_x, gpu_y = checkColorCollisionGPU(
            spriteX, spriteY, costume, backgroundCanvas,
            1, 0, 0, spriteRotation
        )
        local gpu_time = (love.timer.getTime() - gpu_start) * 1000

        print(string.format("CPU: %s [%.2fms]",
            cpu_collision and string.format("COLLISION at (%d, %d)", cpu_x, cpu_y) or "No collision", cpu_time))
        print(string.format("GPU: %s [%.2fms]",
            gpu_collision and string.format("COLLISION at (%d, %d)", gpu_x, gpu_y) or "No collision", gpu_time))
    elseif key == "c" then
        os.execute("clear")
        print("Color Collision Test - Console cleared")
        print("Controls: Arrow keys to move, Q/E to rotate")
    end
end
