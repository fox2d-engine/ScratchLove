local lust = require("tests.lust")
local describe, it, expect = lust.describe, lust.it, lust.expect

local SB3Builder = require("tests.sb3_builder")
local Runtime = require("vm.runtime")
local ProjectModel = require("parser.project_model")

-- Test worldToLocal optimization
describe("Sprite worldToLocal optimization", function()

    -- Helper to create a mock sprite with transform cache
    local function createTestSprite(x, y, direction, size, rotationStyle, costumeWidth, costumeHeight, rotCenterX, rotCenterY)
        SB3Builder.resetCounter()
        local stage = SB3Builder.createStage()

        -- Create costume
        local costume = {
            assetId = "test",
            name = "costume1",
            rotationCenterX = rotCenterX or (costumeWidth or 100) / 2,
            rotationCenterY = rotCenterY or (costumeHeight or 100) / 2,
            bitmapResolution = 1,
            dataFormat = "png"
        }

        -- Create sprite with costume
        local sprite = SB3Builder.createSprite("TestSprite", {
            x = x or 0,
            y = y or 0,
            direction = direction or 90,
            size = size or 100,
            rotationStyle = rotationStyle or "all around",
            costumes = {costume},
            currentCostume = 0
        })

        -- Create project
        local projectJson = SB3Builder.createProject({stage, sprite})
        local project = ProjectModel:new(projectJson, {})
        local runtime = Runtime:new(project)
        runtime:initialize()

        local spriteTarget = runtime:getSpriteTargetByName("TestSprite")

        -- Mock costume image
        local mockImage = {
            getWidth = function() return costumeWidth or 100 end,
            getHeight = function() return costumeHeight or 100 end
        }

        spriteTarget.costumes[1].image = mockImage

        return spriteTarget
    end

    describe("Method comparison", function()
        local function compareResults(manual, transform, tolerance)
            tolerance = tolerance or 0.01
            return math.abs(manual[1] - transform[1]) < tolerance and
                   math.abs(manual[2] - transform[2]) < tolerance
        end

        it("should produce identical results for sprite at origin with no rotation", function()
            local sprite = createTestSprite(0, 0, 90, 100, "all around", 100, 100, 50, 50)

            local worldX, worldY = 25, 30
            local manual = {sprite:worldToLocalManual(worldX, worldY, 100, 100)}
            local transform = {sprite:worldToLocal(worldX, worldY, 100, 100)}

            expect(compareResults(manual, transform, 0.1)).to.be.truthy()
        end)

        it("should produce identical results for scaled sprite", function()
            local sprite = createTestSprite(0, 0, 90, 200, "all around", 100, 100, 50, 50)

            local worldX, worldY = 50, 60
            local manual = {sprite:worldToLocalManual(worldX, worldY, 100, 100)}
            local transform = {sprite:worldToLocal(worldX, worldY, 100, 100)}

            expect(compareResults(manual, transform, 0.1)).to.be.truthy()
        end)

        it("should produce identical results for translated sprite", function()
            local sprite = createTestSprite(100, 50, 90, 100, "all around", 100, 100, 50, 50)

            local worldX, worldY = 125, 75
            local manual = {sprite:worldToLocalManual(worldX, worldY, 100, 100)}
            local transform = {sprite:worldToLocal(worldX, worldY, 100, 100)}

            expect(compareResults(manual, transform, 0.1)).to.be.truthy()
        end)

        it("should produce identical results for left-right rotation style", function()
            local sprite = createTestSprite(0, 0, -90, 100, "left-right", 100, 100, 50, 50)

            local worldX, worldY = 15, 25
            local manual = {sprite:worldToLocalManual(worldX, worldY, 100, 100)}
            local transform = {sprite:worldToLocal(worldX, worldY, 100, 100)}

            expect(compareResults(manual, transform, 0.1)).to.be.truthy()
        end)

        it("should produce identical results for don't rotate style", function()
            local sprite = createTestSprite(0, 0, 180, 100, "don't rotate", 100, 100, 50, 50)

            local worldX, worldY = 20, 30
            local manual = {sprite:worldToLocalManual(worldX, worldY, 100, 100)}
            local transform = {sprite:worldToLocal(worldX, worldY, 100, 100)}

            expect(compareResults(manual, transform, 0.1)).to.be.truthy()
        end)

        it("should produce identical results for off-center rotation", function()
            local sprite = createTestSprite(0, 0, 90, 100, "all around", 100, 100, 25, 75)

            local worldX, worldY = 10, 15
            local manual = {sprite:worldToLocalManual(worldX, worldY, 100, 100)}
            local transform = {sprite:worldToLocal(worldX, worldY, 100, 100)}

            expect(compareResults(manual, transform, 0.1)).to.be.truthy()
        end)
    end)

    describe("Edge cases", function()
        it("should handle sprite without costume", function()
            local sprite = createTestSprite(0, 0, 90, 100, "all around", 100, 100, 50, 50)
            sprite.costumes = {}

            local manual = {sprite:worldToLocalManual(10, 20, 100, 100)}
            local transform = {sprite:worldToLocal(10, 20, 100, 100)}

            -- Both should return center
            expect(manual[1]).to.equal(50)
            expect(manual[2]).to.equal(50)
            expect(transform[1]).to.equal(50)
            expect(transform[2]).to.equal(50)
        end)

        it("should handle very small sprite size", function()
            local sprite = createTestSprite(0, 0, 90, 1, "all around", 100, 100, 50, 50)

            local worldX, worldY = 0.1, 0.2
            local manual = {sprite:worldToLocalManual(worldX, worldY, 100, 100)}
            local transform = {sprite:worldToLocal(worldX, worldY, 100, 100)}

            expect(math.abs(manual[1] - transform[1]) < 1).to.be.truthy()
            expect(math.abs(manual[2] - transform[2]) < 1).to.be.truthy()
        end)

        it("should handle very large sprite size", function()
            local sprite = createTestSprite(0, 0, 90, 500, "all around", 100, 100, 50, 50)

            local worldX, worldY = 100, 150
            local manual = {sprite:worldToLocalManual(worldX, worldY, 100, 100)}
            local transform = {sprite:worldToLocal(worldX, worldY, 100, 100)}

            expect(math.abs(manual[1] - transform[1]) < 0.1).to.be.truthy()
            expect(math.abs(manual[2] - transform[2]) < 0.1).to.be.truthy()
        end)
    end)
end)
