local lust = require("tests.lust")
local describe, it, expect = lust.describe, lust.it, lust.expect

-- Use the Transform from love_mock.lua (already loaded by test runner)
-- No need for local Transform mock here

-- Mock sprite and costume for testing
local function createMockSprite(x, y, direction, size, rotationStyle)
    local costume = {
        image = {
            getWidth = function() return 100 end,
            getHeight = function() return 100 end
        },
        rotationCenterX = 50,
        rotationCenterY = 50,
        bitmapResolution = 1
    }

    local sprite = {
        x = x or 0,
        y = y or 0,
        direction = direction or 90,
        size = size or 100,
        rotationStyle = rotationStyle or "all around",
        getCurrentCostume = function() return costume end
    }

    return sprite, costume
end

-- Current manual implementation (from transform_cache.lua)
local function calculateAABBManual(sprite)
    local Rectangle = require("utils.rectangle")
    local rect = Rectangle:new()

    local costume = sprite:getCurrentCostume()
    if not costume or not costume.image then
        return rect:setBounds(sprite.x, sprite.x, sprite.y, sprite.y)
    end

    local iw = costume.image:getWidth()
    local ih = costume.image:getHeight()
    local bitmapResolution = costume.bitmapResolution or 1

    local scale = sprite.size / 100
    local finalScale = scale / bitmapResolution

    local originX = costume.rotationCenterX or (iw / 2)
    local originY = costume.rotationCenterY or (ih / 2)

    local corners = {
        { -originX,     originY - ih },
        { iw - originX, originY - ih },
        { iw - originX, originY },
        { -originX,     originY }
    }

    local rotation = 0
    local scaleX = finalScale
    local scaleY = finalScale

    if sprite.rotationStyle == "all around" then
        rotation = math.rad(sprite.direction - 90)
    elseif sprite.rotationStyle == "left-right" and sprite.direction < 0 then
        scaleX = -finalScale
    end

    local minX, maxX = math.huge, -math.huge
    local minY, maxY = math.huge, -math.huge

    local cos_r = math.cos(rotation)
    local sin_r = math.sin(rotation)

    for _, corner in ipairs(corners) do
        local scaledX = corner[1] * scaleX
        local scaledY = corner[2] * scaleY

        local rotatedX = scaledX * cos_r - scaledY * sin_r
        local rotatedY = scaledX * sin_r + scaledY * cos_r

        local worldX = sprite.x + rotatedX
        local worldY = sprite.y + rotatedY

        minX = math.min(minX, worldX)
        maxX = math.max(maxX, worldX)
        minY = math.min(minY, worldY)
        maxY = math.max(maxY, worldY)
    end

    return rect:setBounds(minX, maxX, minY, maxY)
end

-- New Transform-based implementation (Scratch-inspired)
local function calculateAABBTransform(sprite)
    local Rectangle = require("utils.rectangle")
    local rect = Rectangle:new()

    local costume = sprite:getCurrentCostume()
    if not costume or not costume.image then
        return rect:setBounds(sprite.x, sprite.x, sprite.y, sprite.y)
    end

    local iw = costume.image:getWidth()
    local ih = costume.image:getHeight()
    local bitmapResolution = costume.bitmapResolution or 1

    local originX = costume.rotationCenterX or (iw / 2)
    local originY = costume.rotationCenterY or (ih / 2)

    -- Build transform matrix following Scratch's exact pattern:
    -- M = Translate(position) * Rotate * Translate(rotationAdjusted) * Scale(scaledSize)
    -- Note: In Scratch, _scale is the percentage (e.g., 100 for 100%), not normalized

    local transform = love.math.newTransform()

    -- 1. Translate to sprite position
    transform:translate(sprite.x, sprite.y)

    -- 2. Apply rotation based on rotation style
    local rotation = 0
    local scaleX = sprite.size  -- Use raw percentage value (like Scratch's _scale)
    local scaleY = sprite.size

    if sprite.rotationStyle == "all around" then
        rotation = math.rad(sprite.direction - 90)
        transform:rotate(rotation)
    elseif sprite.rotationStyle == "left-right" and sprite.direction < 0 then
        scaleX = -sprite.size
    end

    -- 3. Translate by rotation center adjustment (matching Scratch)
    -- rotationAdjusted = (rotationCenter - skinSize/2) * scale / 100 / bitmapResolution, with Y flipped
    local rotationAdjustedX = (originX - iw/2) * scaleX / 100 / bitmapResolution
    local rotationAdjustedY = -((originY - ih/2) * scaleY / 100 / bitmapResolution)  -- Y flipped
    transform:translate(rotationAdjustedX, rotationAdjustedY)

    -- 4. Scale by scaledSize (matching Scratch: skinSize * scale / 100 / bitmapResolution)
    local scaledSizeX = iw * scaleX / 100 / bitmapResolution
    local scaledSizeY = ih * scaleY / 100 / bitmapResolution
    transform:scale(scaledSizeX, scaledSizeY)

    -- Extract matrix components (row-major 2D affine matrix)
    local m = transform.matrix

    -- Scratch's initFromModelMatrix algorithm:
    -- Row-major: [m1 m2 m3 m4; m5 m6 m7 m8; ...]
    -- where m4 = translation X, m8 = translation Y
    local m30 = m[4]   -- x translation
    local m31 = m[8]   -- y translation

    -- Calculate AABB half-extents from rotation-scale matrix
    -- This assumes the base shape is a unit square from -0.5 to 0.5
    local x = math.abs(0.5 * m[1]) + math.abs(0.5 * m[5])
    local y = math.abs(0.5 * m[2]) + math.abs(0.5 * m[6])

    -- Set bounds
    local left = -x + m30
    local right = x + m30
    local bottom = -y + m31
    local top = y + m31

    return rect:setBounds(left, right, bottom, top)
end

describe("Transform AABB calculation", function()
    describe("Manual corner transformation method", function()
        it("should calculate AABB for sprite at origin with no rotation", function()
            local sprite = createMockSprite(0, 0, 90, 100, "all around")
            local aabb = calculateAABBManual(sprite)

            -- 100x100 image, centered at origin, size=100% -> AABB should be ±50
            expect(math.abs(aabb.left + 50) < 0.01).to.be.truthy()
            expect(math.abs(aabb.right - 50) < 0.01).to.be.truthy()
            expect(math.abs(aabb.bottom + 50) < 0.01).to.be.truthy()
            expect(math.abs(aabb.top - 50) < 0.01).to.be.truthy()
        end)

        it("should calculate AABB for sprite with 45° rotation", function()
            local sprite = createMockSprite(0, 0, 135, 100, "all around")
            local aabb = calculateAABBManual(sprite)

            -- At 45°, AABB should expand to ~70.7 (50 * sqrt(2))
            local expected = 50 * math.sqrt(2)
            expect(math.abs(aabb.left + expected) < 0.1).to.be.truthy()
            expect(math.abs(aabb.right - expected) < 0.1).to.be.truthy()
        end)

        it("should calculate AABB for sprite with 90° rotation", function()
            local sprite = createMockSprite(0, 0, 180, 100, "all around")
            local aabb = calculateAABBManual(sprite)

            -- 90° rotation should still be ±50 (square image)
            expect(math.abs(aabb.left + 50) < 0.01).to.be.truthy()
            expect(math.abs(aabb.right - 50) < 0.01).to.be.truthy()
        end)

        it("should calculate AABB for scaled sprite", function()
            local sprite = createMockSprite(0, 0, 90, 200, "all around")
            local aabb = calculateAABBManual(sprite)

            -- 200% size -> AABB should be ±100
            expect(math.abs(aabb.left + 100) < 0.01).to.be.truthy()
            expect(math.abs(aabb.right - 100) < 0.01).to.be.truthy()
        end)

        it("should calculate AABB for translated sprite", function()
            local sprite = createMockSprite(100, 50, 90, 100, "all around")
            local aabb = calculateAABBManual(sprite)

            -- Centered at (100, 50), size ±50
            expect(math.abs(aabb.left - 50) < 0.01).to.be.truthy()
            expect(math.abs(aabb.right - 150) < 0.01).to.be.truthy()
            expect(math.abs(aabb.bottom - 0) < 0.01).to.be.truthy()
            expect(math.abs(aabb.top - 100) < 0.01).to.be.truthy()
        end)

        it("should handle left-right rotation style with negative direction", function()
            local sprite = createMockSprite(0, 0, -90, 100, "left-right")
            local aabb = calculateAABBManual(sprite)

            -- Should flip horizontally but AABB stays the same
            expect(math.abs(aabb.left + 50) < 0.01).to.be.truthy()
            expect(math.abs(aabb.right - 50) < 0.01).to.be.truthy()
        end)

        it("should handle don't rotate style", function()
            local sprite = createMockSprite(0, 0, 180, 100, "don't rotate")
            local aabb = calculateAABBManual(sprite)

            -- Should not rotate, AABB stays as if direction=90
            expect(math.abs(aabb.left + 50) < 0.01).to.be.truthy()
            expect(math.abs(aabb.right - 50) < 0.01).to.be.truthy()
        end)
    end)

    describe("Transform-based method (Scratch-inspired)", function()
        it("should calculate AABB for sprite at origin with no rotation", function()
            local sprite = createMockSprite(0, 0, 90, 100, "all around")
            local aabb = calculateAABBTransform(sprite)

            expect(math.abs(aabb.left + 50) < 0.01).to.be.truthy()
            expect(math.abs(aabb.right - 50) < 0.01).to.be.truthy()
            expect(math.abs(aabb.bottom + 50) < 0.01).to.be.truthy()
            expect(math.abs(aabb.top - 50) < 0.01).to.be.truthy()
        end)

        it("should calculate AABB for sprite with 45° rotation", function()
            local sprite = createMockSprite(0, 0, 135, 100, "all around")
            local aabb = calculateAABBTransform(sprite)

            local expected = 50 * math.sqrt(2)
            expect(math.abs(aabb.left + expected) < 0.1).to.be.truthy()
            expect(math.abs(aabb.right - expected) < 0.1).to.be.truthy()
        end)

        it("should calculate AABB for sprite with 90° rotation", function()
            local sprite = createMockSprite(0, 0, 180, 100, "all around")
            local aabb = calculateAABBTransform(sprite)

            expect(math.abs(aabb.left + 50) < 0.01).to.be.truthy()
            expect(math.abs(aabb.right - 50) < 0.01).to.be.truthy()
        end)

        it("should calculate AABB for scaled sprite", function()
            local sprite = createMockSprite(0, 0, 90, 200, "all around")
            local aabb = calculateAABBTransform(sprite)

            expect(math.abs(aabb.left + 100) < 0.01).to.be.truthy()
            expect(math.abs(aabb.right - 100) < 0.01).to.be.truthy()
        end)

        it("should calculate AABB for translated sprite", function()
            local sprite = createMockSprite(100, 50, 90, 100, "all around")
            local aabb = calculateAABBTransform(sprite)

            expect(math.abs(aabb.left - 50) < 0.01).to.be.truthy()
            expect(math.abs(aabb.right - 150) < 0.01).to.be.truthy()
            expect(math.abs(aabb.bottom - 0) < 0.01).to.be.truthy()
            expect(math.abs(aabb.top - 100) < 0.01).to.be.truthy()
        end)
    end)

    describe("Method comparison", function()
        local function compareAABB(aabb1, aabb2, tolerance)
            tolerance = tolerance or 0.01
            return math.abs(aabb1.left - aabb2.left) < tolerance and
                   math.abs(aabb1.right - aabb2.right) < tolerance and
                   math.abs(aabb1.bottom - aabb2.bottom) < tolerance and
                   math.abs(aabb1.top - aabb2.top) < tolerance
        end

        it("should produce identical results at various rotations", function()
            for angle = 0, 360, 15 do
                local sprite = createMockSprite(0, 0, angle, 100, "all around")
                local manual = calculateAABBManual(sprite)
                local transform = calculateAABBTransform(sprite)

                expect(compareAABB(manual, transform, 0.1)).to.be.truthy()
            end
        end)

        it("should produce identical results at various scales", function()
            for scale = 50, 200, 25 do
                local sprite = createMockSprite(0, 0, 90, scale, "all around")
                local manual = calculateAABBManual(sprite)
                local transform = calculateAABBTransform(sprite)

                expect(compareAABB(manual, transform, 0.1)).to.be.truthy()
            end
        end)

        it("should produce identical results at various positions", function()
            local positions = {{0,0}, {100,100}, {-50,75}, {200,-100}}
            for _, pos in ipairs(positions) do
                local sprite = createMockSprite(pos[1], pos[2], 90, 100, "all around")
                local manual = calculateAABBManual(sprite)
                local transform = calculateAABBTransform(sprite)

                expect(compareAABB(manual, transform, 0.1)).to.be.truthy()
            end
        end)

        it("should produce identical results for combined transformations", function()
            local testCases = {
                {x=100, y=50, dir=45, size=150},
                {x=-75, y=125, dir=120, size=75},
                {x=0, y=0, dir=270, size=200},
                {x=200, y=-100, dir=315, size=50}
            }

            for _, case in ipairs(testCases) do
                local sprite = createMockSprite(case.x, case.y, case.dir, case.size, "all around")
                local manual = calculateAABBManual(sprite)
                local transform = calculateAABBTransform(sprite)

                expect(compareAABB(manual, transform, 0.1)).to.be.truthy()
            end
        end)
    end)
end)
