local lust = require("tests.lust")
local describe, it, expect = lust.describe, lust.it, lust.expect

local SB3Builder = require("tests.sb3_builder")
local ProjectModel = require("parser.project_model")
local Runtime = require("vm.runtime")

-- Test AABB calculation with rotation centers by verifying containsPoint behavior
-- This directly tests the real-world use case without complex Transform mocking

describe("Rotation Center AABB Calculation", function()
    describe("Rotation center at image center (baseline)", function()
        it("should correctly detect points inside/outside sprite bounds", function()
            SB3Builder.resetCounter()
            local stage = SB3Builder.createStage()
            local sprite = SB3Builder.createSprite("TestSprite")

            -- Add a 100x100 costume with centered rotation point (50, 50)
            sprite.costumes = {{
                name = "costume1",
                dataFormat = "png",
                assetId = "test",
                bitmapResolution = 1,
                rotationCenterX = 50,
                rotationCenterY = 50,
                md5ext = "test.png"
            }}
            sprite.currentCostume = 0
            sprite.x = 0
            sprite.y = 0
            sprite.size = 100
            sprite.direction = 90  -- No rotation

            local projectJson = SB3Builder.createProject({stage, sprite})
            local project = ProjectModel:new(projectJson, {})
            local runtime = Runtime:new(project)
            runtime:initialize()

            local spriteTarget = runtime:getSpriteTargetByName("TestSprite")

            -- Mock costume image for AABB calculation
            spriteTarget:getCurrentCostume().image = {
                getWidth = function() return 100 end,
                getHeight = function() return 100 end
            }

            -- Points that should be inside (sprite at origin, 100x100 image)
            -- Sprite bounds: [-50, 50] x [-50, 50]
            expect(spriteTarget:containsPoint(0, 0)).to.be.truthy()      -- Center
            expect(spriteTarget:containsPoint(40, 40)).to.be.truthy()    -- Inside top-right
            expect(spriteTarget:containsPoint(-40, -40)).to.be.truthy()  -- Inside bottom-left

            -- Points that should be outside
            expect(spriteTarget:containsPoint(60, 0)).to_not.be.truthy() -- Right of bounds
            expect(spriteTarget:containsPoint(0, 60)).to_not.be.truthy() -- Above bounds
            expect(spriteTarget:containsPoint(-60, 0)).to_not.be.truthy() -- Left of bounds
        end)
    end)

    describe("Rotation center outside image", function()
        it("should handle rotation center far to the right and below (real project case)", function()
            SB3Builder.resetCounter()
            local stage = SB3Builder.createStage()
            local sprite = SB3Builder.createSprite("TestSprite")

            -- Real case from project 1226817474
            -- Image: 472x94 (at 2x resolution), rotation center: (459.5, 274.7)
            sprite.costumes = {{
                name = "costume1",
                dataFormat = "png",
                assetId = "test",
                bitmapResolution = 2,
                rotationCenterX = 459.5,
                rotationCenterY = 274.7,
                md5ext = "test.png"
            }}
            sprite.currentCostume = 0
            sprite.x = 0
            sprite.y = 0
            sprite.size = 100
            sprite.direction = 90

            local projectJson = SB3Builder.createProject({stage, sprite})
            local project = ProjectModel:new(projectJson, {})
            local runtime = Runtime:new(project)
            runtime:initialize()

            local spriteTarget = runtime:getSpriteTargetByName("TestSprite")
            spriteTarget:getCurrentCostume().image = {
                getWidth = function() return 472 end,
                getHeight = function() return 94 end
            }

            -- Expected AABB: [-229.8, 6.3] x [90.3, 137.3]
            -- Test points inside
            expect(spriteTarget:containsPoint(-100, 110)).to.be.truthy()  -- Left side
            expect(spriteTarget:containsPoint(0, 110)).to.be.truthy()     -- Near right edge
            expect(spriteTarget:containsPoint(-111, 113)).to.be.truthy()  -- Center of image

            -- Test points outside
            expect(spriteTarget:containsPoint(-240, 110)).to_not.be.truthy() -- Too far left
            expect(spriteTarget:containsPoint(20, 110)).to_not.be.truthy()   -- Too far right
            expect(spriteTarget:containsPoint(-100, 80)).to_not.be.truthy()  -- Below bounds
            expect(spriteTarget:containsPoint(-100, 150)).to_not.be.truthy() -- Above bounds
        end)

        it("should handle rotation center to the left and above", function()
            SB3Builder.resetCounter()
            local stage = SB3Builder.createStage()
            local sprite = SB3Builder.createSprite("TestSprite")

            sprite.costumes = {{
                name = "costume1",
                dataFormat = "png",
                assetId = "test",
                bitmapResolution = 1,
                rotationCenterX = -20,
                rotationCenterY = -30,
                md5ext = "test.png"
            }}
            sprite.currentCostume = 0
            sprite.x = 50
            sprite.y = 80
            sprite.size = 100

            local projectJson = SB3Builder.createProject({stage, sprite})
            local project = ProjectModel:new(projectJson, {})
            local runtime = Runtime:new(project)
            runtime:initialize()

            local spriteTarget = runtime:getSpriteTargetByName("TestSprite")
            spriteTarget:getCurrentCostume().image = {
                getWidth = function() return 100 end,
                getHeight = function() return 100 end
            }

            -- Expected center: (120, 0), bounds: [70, 170] x [-50, 50]
            expect(spriteTarget:containsPoint(120, 0)).to.be.truthy()    -- Center
            expect(spriteTarget:containsPoint(100, 20)).to.be.truthy()   -- Inside
            expect(spriteTarget:containsPoint(150, -30)).to.be.truthy()  -- Inside

            expect(spriteTarget:containsPoint(60, 0)).to_not.be.truthy()  -- Too far left
            expect(spriteTarget:containsPoint(180, 0)).to_not.be.truthy() -- Too far right
        end)
    end)

    describe("Different rotation angles with off-center rotation", function()
        it("should handle 90° rotation correctly", function()
            SB3Builder.resetCounter()
            local stage = SB3Builder.createStage()
            local sprite = SB3Builder.createSprite("TestSprite")

            sprite.costumes = {{
                name = "costume1",
                dataFormat = "png",
                assetId = "test",
                bitmapResolution = 1,
                rotationCenterX = 0,
                rotationCenterY = 0,
                md5ext = "test.png"
            }}
            sprite.currentCostume = 0
            sprite.x = 0
            sprite.y = 0
            sprite.size = 100
            sprite.direction = 180  -- 90° rotation from default

            local projectJson = SB3Builder.createProject({stage, sprite})
            local project = ProjectModel:new(projectJson, {})
            local runtime = Runtime:new(project)
            runtime:initialize()

            local spriteTarget = runtime:getSpriteTargetByName("TestSprite")
            spriteTarget:getCurrentCostume().image = {
                getWidth = function() return 200 end,
                getHeight = function() return 150 end
            }

            -- After 90° rotation with origin at (0,0):
            -- Corners: (0,0)->(0,0), (200,0)->(0,-200), (200,150)->(-150,-200), (0,150)->(-150,0)
            -- Expected AABB: [-150, 0] x [-200, 0]
            expect(spriteTarget:containsPoint(-75, -100)).to.be.truthy()   -- Center area
            expect(spriteTarget:containsPoint(-10, -50)).to.be.truthy()    -- Near origin
            expect(spriteTarget:containsPoint(-140, -190)).to.be.truthy()  -- Near corner

            expect(spriteTarget:containsPoint(10, -100)).to_not.be.truthy()  -- Too far right
            expect(spriteTarget:containsPoint(-160, -100)).to_not.be.truthy() -- Too far left
            expect(spriteTarget:containsPoint(-75, 10)).to_not.be.truthy()   -- Above bounds
        end)

        it("should handle 45° rotation with off-center rotation point", function()
            SB3Builder.resetCounter()
            local stage = SB3Builder.createStage()
            local sprite = SB3Builder.createSprite("TestSprite")

            sprite.costumes = {{
                name = "costume1",
                dataFormat = "png",
                assetId = "test",
                bitmapResolution = 1,
                rotationCenterX = 150,
                rotationCenterY = 80,
                md5ext = "test.png"
            }}
            sprite.currentCostume = 0
            sprite.x = 0
            sprite.y = 0
            sprite.size = 100
            sprite.direction = 135  -- 45° rotation

            local projectJson = SB3Builder.createProject({stage, sprite})
            local project = ProjectModel:new(projectJson, {})
            local runtime = Runtime:new(project)
            runtime:initialize()

            local spriteTarget = runtime:getSpriteTargetByName("TestSprite")
            spriteTarget:getCurrentCostume().image = {
                getWidth = function() return 200 end,
                getHeight = function() return 100 end
            }

            -- With 45° rotation, AABB should be expanded
            -- Just verify bounds are valid and some points work
            expect(spriteTarget:containsPoint(0, 0)).to.be.truthy()  -- Should contain origin area
        end)
    end)

    describe("Different rotation styles with off-center rotation", function()
        it("should handle left-right style with no flip", function()
            SB3Builder.resetCounter()
            local stage = SB3Builder.createStage()
            local sprite = SB3Builder.createSprite("TestSprite")

            sprite.costumes = {{
                name = "costume1",
                dataFormat = "png",
                assetId = "test",
                bitmapResolution = 1,
                rotationCenterX = 70,
                rotationCenterY = 30,
                md5ext = "test.png"
            }}
            sprite.currentCostume = 0
            sprite.x = 0
            sprite.y = 0
            sprite.size = 100
            sprite.direction = 90  -- Positive direction, no flip
            sprite.rotationStyle = "left-right"

            local projectJson = SB3Builder.createProject({stage, sprite})
            local project = ProjectModel:new(projectJson, {})
            local runtime = Runtime:new(project)
            runtime:initialize()

            local spriteTarget = runtime:getSpriteTargetByName("TestSprite")
            spriteTarget:getCurrentCostume().image = {
                getWidth = function() return 100 end,
                getHeight = function() return 100 end
            }

            -- Expected AABB: [-70, 30] x [-70, 30]
            expect(spriteTarget:containsPoint(-20, -20)).to.be.truthy()  -- Center
            expect(spriteTarget:containsPoint(-60, 20)).to.be.truthy()   -- Inside bounds

            expect(spriteTarget:containsPoint(-75, 0)).to_not.be.truthy() -- Outside left
            expect(spriteTarget:containsPoint(35, 0)).to_not.be.truthy()  -- Outside right
        end)

        it("should handle left-right style with horizontal flip", function()
            SB3Builder.resetCounter()
            local stage = SB3Builder.createStage()
            local sprite = SB3Builder.createSprite("TestSprite")

            sprite.costumes = {{
                name = "costume1",
                dataFormat = "png",
                assetId = "test",
                bitmapResolution = 1,
                rotationCenterX = 70,
                rotationCenterY = 30,
                md5ext = "test.png"
            }}
            sprite.currentCostume = 0
            sprite.x = 0
            sprite.y = 0
            sprite.size = 100
            sprite.direction = -90  -- Negative direction, flip
            sprite.rotationStyle = "left-right"

            local projectJson = SB3Builder.createProject({stage, sprite})
            local project = ProjectModel:new(projectJson, {})
            local runtime = Runtime:new(project)
            runtime:initialize()

            local spriteTarget = runtime:getSpriteTargetByName("TestSprite")
            spriteTarget:getCurrentCostume().image = {
                getWidth = function() return 100 end,
                getHeight = function() return 100 end
            }

            -- Expected AABB: [-30, 70] x [-70, 30] (flipped X)
            expect(spriteTarget:containsPoint(20, -20)).to.be.truthy()   -- Center
            expect(spriteTarget:containsPoint(60, 20)).to.be.truthy()    -- Inside bounds

            expect(spriteTarget:containsPoint(-35, 0)).to_not.be.truthy() -- Outside left
            expect(spriteTarget:containsPoint(75, 0)).to_not.be.truthy()  -- Outside right
        end)

        it("should handle don't rotate style", function()
            SB3Builder.resetCounter()
            local stage = SB3Builder.createStage()
            local sprite = SB3Builder.createSprite("TestSprite")

            sprite.costumes = {{
                name = "costume1",
                dataFormat = "png",
                assetId = "test",
                bitmapResolution = 1,
                rotationCenterX = 80,
                rotationCenterY = 20,
                md5ext = "test.png"
            }}
            sprite.currentCostume = 0
            sprite.x = 0
            sprite.y = 0
            sprite.size = 100
            sprite.direction = 180  -- Should ignore rotation
            sprite.rotationStyle = "don't rotate"

            local projectJson = SB3Builder.createProject({stage, sprite})
            local project = ProjectModel:new(projectJson, {})
            local runtime = Runtime:new(project)
            runtime:initialize()

            local spriteTarget = runtime:getSpriteTargetByName("TestSprite")
            spriteTarget:getCurrentCostume().image = {
                getWidth = function() return 100 end,
                getHeight = function() return 100 end
            }

            -- Expected AABB: [-80, 20] x [-80, 20]
            expect(spriteTarget:containsPoint(-30, -30)).to.be.truthy()  -- Center
            expect(spriteTarget:containsPoint(-70, 10)).to.be.truthy()   -- Inside

            expect(spriteTarget:containsPoint(-85, 0)).to_not.be.truthy() -- Outside left
            expect(spriteTarget:containsPoint(25, 0)).to_not.be.truthy()  -- Outside right
        end)
    end)

    describe("Different scales with off-center rotation", function()
        it("should handle 50% scale correctly", function()
            SB3Builder.resetCounter()
            local stage = SB3Builder.createStage()
            local sprite = SB3Builder.createSprite("TestSprite")

            sprite.costumes = {{
                name = "costume1",
                dataFormat = "png",
                assetId = "test",
                bitmapResolution = 1,
                rotationCenterX = 300,
                rotationCenterY = 200,
                md5ext = "test.png"
            }}
            sprite.currentCostume = 0
            sprite.x = 0
            sprite.y = -50
            sprite.size = 50  -- 50% scale

            local projectJson = SB3Builder.createProject({stage, sprite})
            local project = ProjectModel:new(projectJson, {})
            local runtime = Runtime:new(project)
            runtime:initialize()

            local spriteTarget = runtime:getSpriteTargetByName("TestSprite")
            spriteTarget:getCurrentCostume().image = {
                getWidth = function() return 300 end,
                getHeight = function() return 200 end
            }

            -- With 50% scale, image becomes 150x100
            -- Scaled rotation offset also reduces by half
            expect(spriteTarget:containsPoint(0, 0)).to.be.truthy()  -- Should be near bounds
        end)

        it("should handle 200% scale correctly", function()
            SB3Builder.resetCounter()
            local stage = SB3Builder.createStage()
            local sprite = SB3Builder.createSprite("TestSprite")

            sprite.costumes = {{
                name = "costume1",
                dataFormat = "png",
                assetId = "test",
                bitmapResolution = 1,
                rotationCenterX = 50,
                rotationCenterY = 50,
                md5ext = "test.png"
            }}
            sprite.currentCostume = 0
            sprite.x = 0
            sprite.y = 0
            sprite.size = 200  -- 200% scale

            local projectJson = SB3Builder.createProject({stage, sprite})
            local project = ProjectModel:new(projectJson, {})
            local runtime = Runtime:new(project)
            runtime:initialize()

            local spriteTarget = runtime:getSpriteTargetByName("TestSprite")
            spriteTarget:getCurrentCostume().image = {
                getWidth = function() return 100 end,
                getHeight = function() return 100 end
            }

            -- With 200% scale, image becomes 200x200 (centered)
            -- AABB: [-100, 100] x [-100, 100]
            expect(spriteTarget:containsPoint(0, 0)).to.be.truthy()     -- Center
            expect(spriteTarget:containsPoint(90, 90)).to.be.truthy()   -- Inside
            expect(spriteTarget:containsPoint(-90, -90)).to.be.truthy() -- Inside

            expect(spriteTarget:containsPoint(110, 0)).to_not.be.truthy()  -- Outside
            expect(spriteTarget:containsPoint(0, 110)).to_not.be.truthy()  -- Outside
        end)
    end)

    describe("High-resolution (2x) SVG images", function()
        it("should handle 2x bitmap resolution with off-center rotation", function()
            SB3Builder.resetCounter()
            local stage = SB3Builder.createStage()
            local sprite = SB3Builder.createSprite("TestSprite")

            sprite.costumes = {{
                name = "costume1",
                dataFormat = "svg",
                assetId = "test",
                bitmapResolution = 2,
                rotationCenterX = 250,
                rotationCenterY = 200,
                md5ext = "test.svg"
            }}
            sprite.currentCostume = 0
            sprite.x = 0
            sprite.y = 0
            sprite.size = 100

            local projectJson = SB3Builder.createProject({stage, sprite})
            local project = ProjectModel:new(projectJson, {})
            local runtime = Runtime:new(project)
            runtime:initialize()

            local spriteTarget = runtime:getSpriteTargetByName("TestSprite")
            spriteTarget:getCurrentCostume().image = {
                getWidth = function() return 400 end,
                getHeight = function() return 300 end
            }

            -- With 2x bitmap resolution, effective size is 200x150
            -- Expected center: (-25, 25), AABB: [-125, 75] x [-50, 100]
            expect(spriteTarget:containsPoint(-25, 25)).to.be.truthy()  -- Center
            expect(spriteTarget:containsPoint(0, 50)).to.be.truthy()    -- Inside
            expect(spriteTarget:containsPoint(-100, 0)).to.be.truthy()  -- Inside left

            expect(spriteTarget:containsPoint(-130, 25)).to_not.be.truthy() -- Outside left
            expect(spriteTarget:containsPoint(80, 25)).to_not.be.truthy()   -- Outside right
        end)
    end)
end)
