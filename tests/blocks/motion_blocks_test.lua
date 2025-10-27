-- Motion Blocks Tests
-- Tests for motion block implementations based on native Scratch tests

-- Import testing framework
local lust = require("tests.lust")
local describe, it, expect = lust.describe, lust.it, lust.expect

-- Import project components
local SB3Builder = require("tests.sb3_builder")
local ProjectModel = require("parser.project_model")
local Runtime = require("vm.runtime")
local Global = require("global")

describe("Motion Blocks", function()
    describe("Basic Movement", function()
        it("should move sprite by steps", function()
            SB3Builder.resetCounter()
            local stage = SB3Builder.createStage()
            local sprite = SB3Builder.createSprite("TestSprite")

            -- Set initial position
            sprite.x = 0
            sprite.y = 0
            sprite.direction = 90

            local hatId, hatBlock = SB3Builder.Events.whenFlagClicked()
            local moveId, moveBlock = SB3Builder.Motion.moveSteps(10)

            SB3Builder.addBlock(sprite, hatId, hatBlock)
            SB3Builder.addBlock(sprite, moveId, moveBlock)
            SB3Builder.linkBlocks(sprite, {hatId, moveId})

            local projectData = SB3Builder.createProject({stage, sprite})
            local project = ProjectModel:new(projectData, projectData.assets)
            local runtime = Runtime:new(project)
            runtime:initialize()

            runtime:broadcastGreenFlag()
            local maxIterations = 100
            local iterations = 0
            while #runtime:getActiveThreads() > 0 and iterations < maxIterations do
                runtime:update(1/60)
                iterations = iterations + 1
            end

            local spriteTarget = runtime:getSpriteTargetByName("TestSprite")
            expect(spriteTarget.x).to.equal(10) -- Moved 10 steps to the right (direction 90)
            expect(spriteTarget.y).to.equal(0)  -- Y unchanged
        end)

        it("should turn clockwise and counterclockwise", function()
            SB3Builder.resetCounter()
            local stage = SB3Builder.createStage()
            local sprite = SB3Builder.createSprite("TestSprite")

            -- Set initial direction
            sprite.direction = 90

            local hatId, hatBlock = SB3Builder.Events.whenFlagClicked()
            local turnRightId, turnRightBlock = SB3Builder.Motion.turnRight(15)
            local turnLeftId, turnLeftBlock = SB3Builder.Motion.turnLeft(30)

            SB3Builder.addBlock(sprite, hatId, hatBlock)
            SB3Builder.addBlock(sprite, turnRightId, turnRightBlock)
            SB3Builder.addBlock(sprite, turnLeftId, turnLeftBlock)
            SB3Builder.linkBlocks(sprite, {hatId, turnRightId, turnLeftId})

            local projectData = SB3Builder.createProject({stage, sprite})
            local project = ProjectModel:new(projectData, projectData.assets)
            local runtime = Runtime:new(project)
            runtime:initialize()

            runtime:broadcastGreenFlag()
            local maxIterations = 100
            local iterations = 0
            while #runtime:getActiveThreads() > 0 and iterations < maxIterations do
                runtime:update(1/60)
                iterations = iterations + 1
            end

            local spriteTarget = runtime:getSpriteTargetByName("TestSprite")
            expect(spriteTarget.direction).to.equal(75) -- 90 + 15 - 30 = 75
        end)

        it("should go to specific x,y coordinates", function()
            SB3Builder.resetCounter()
            local stage = SB3Builder.createStage()
            local sprite = SB3Builder.createSprite("TestSprite")

            local hatId, hatBlock = SB3Builder.Events.whenFlagClicked()
            local gotoId, gotoBlock = SB3Builder.Motion.goToXY(50, -100)

            SB3Builder.addBlock(sprite, hatId, hatBlock)
            SB3Builder.addBlock(sprite, gotoId, gotoBlock)
            SB3Builder.linkBlocks(sprite, {hatId, gotoId})

            local projectData = SB3Builder.createProject({stage, sprite})
            local project = ProjectModel:new(projectData, projectData.assets)
            local runtime = Runtime:new(project)
            runtime:initialize()

            runtime:broadcastGreenFlag()
            local maxIterations = 100
            local iterations = 0
            while #runtime:getActiveThreads() > 0 and iterations < maxIterations do
                runtime:update(1/60)
                iterations = iterations + 1
            end

            local spriteTarget = runtime:getSpriteTargetByName("TestSprite")
            expect(spriteTarget.x).to.equal(50)
            expect(spriteTarget.y).to.equal(-100)
        end)

        it("should point in specific direction", function()
            SB3Builder.resetCounter()
            local stage = SB3Builder.createStage()
            local sprite = SB3Builder.createSprite("TestSprite")

            local hatId, hatBlock = SB3Builder.Events.whenFlagClicked()
            local pointId, pointBlock = SB3Builder.Motion.pointInDirection(135)

            SB3Builder.addBlock(sprite, hatId, hatBlock)
            SB3Builder.addBlock(sprite, pointId, pointBlock)
            SB3Builder.linkBlocks(sprite, {hatId, pointId})

            local projectData = SB3Builder.createProject({stage, sprite})
            local project = ProjectModel:new(projectData, projectData.assets)
            local runtime = Runtime:new(project)
            runtime:initialize()

            runtime:broadcastGreenFlag()
            local maxIterations = 100
            local iterations = 0
            while #runtime:getActiveThreads() > 0 and iterations < maxIterations do
                runtime:update(1/60)
                iterations = iterations + 1
            end

            local spriteTarget = runtime:getSpriteTargetByName("TestSprite")
            expect(spriteTarget.direction).to.equal(135)
        end)
    end)

    describe("Coordinate Precision", function()
        it("should have limited precision for coordinates", function()
            -- Based on native test: "Coordinates have limited precision"
            SB3Builder.resetCounter()
            local stage = SB3Builder.createStage()
            local sprite = SB3Builder.createSprite("TestSprite")
            local xId = SB3Builder.addVariable(stage, "x", 0)
            local yId = SB3Builder.addVariable(stage, "y", 0)

            local hatId, hatBlock = SB3Builder.Events.whenFlagClicked()
            -- Go to very precise coordinates
            local gotoId, gotoBlock = SB3Builder.Motion.goToXY(0.999999999, 0.999999999)
            -- Get rounded coordinates
            local getXId, getXBlock = SB3Builder.Motion.xPosition()
            local getYId, getYBlock = SB3Builder.Motion.yPosition()
            local setXId, setXBlock = SB3Builder.createBlock("data_setvariableto", {
                VALUE = SB3Builder.blockInput(getXId)
            }, {
                VARIABLE = SB3Builder.field("x", xId)
            })
            local setYId, setYBlock = SB3Builder.createBlock("data_setvariableto", {
                VALUE = SB3Builder.blockInput(getYId)
            }, {
                VARIABLE = SB3Builder.field("y", yId)
            })

            SB3Builder.addBlock(sprite, hatId, hatBlock)
            SB3Builder.addBlock(sprite, gotoId, gotoBlock)
            SB3Builder.addBlock(sprite, getXId, getXBlock)
            SB3Builder.addBlock(sprite, getYId, getYBlock)
            SB3Builder.addBlock(sprite, setXId, setXBlock)
            SB3Builder.addBlock(sprite, setYId, setYBlock)
            SB3Builder.linkBlocks(sprite, {hatId, gotoId, setXId, setYId})

            local projectData = SB3Builder.createProject({stage, sprite})
            local project = ProjectModel:new(projectData, projectData.assets)
            local runtime = Runtime:new(project)
            runtime:initialize()

            runtime:broadcastGreenFlag()
            local maxIterations = 100
            local iterations = 0
            while #runtime:getActiveThreads() > 0 and iterations < maxIterations do
                runtime:update(1/60)
                iterations = iterations + 1
            end

            local x = runtime.stage:lookupVariableByNameAndType("x")
            local y = runtime.stage:lookupVariableByNameAndType("y")

            -- Should round to 1 (limited precision)
            expect(x.value).to.equal(1)
            expect(y.value).to.equal(1)
        end)
    end)

    describe("Position Reporting", function()
        it("should report correct x and y positions", function()
            SB3Builder.resetCounter()
            local stage = SB3Builder.createStage()
            local sprite = SB3Builder.createSprite("TestSprite")
            local xId = SB3Builder.addVariable(stage, "reportedX", 0)
            local yId = SB3Builder.addVariable(stage, "reportedY", 0)

            local hatId, hatBlock = SB3Builder.Events.whenFlagClicked()
            local gotoId, gotoBlock = SB3Builder.Motion.goToXY(-50, 75)
            local getXId, getXBlock = SB3Builder.Motion.xPosition()
            local getYId, getYBlock = SB3Builder.Motion.yPosition()
            local setXId, setXBlock = SB3Builder.createBlock("data_setvariableto", {
                VALUE = SB3Builder.blockInput(getXId)
            }, {
                VARIABLE = SB3Builder.field("reportedX", xId)
            })
            local setYId, setYBlock = SB3Builder.createBlock("data_setvariableto", {
                VALUE = SB3Builder.blockInput(getYId)
            }, {
                VARIABLE = SB3Builder.field("reportedY", yId)
            })

            SB3Builder.addBlock(sprite, hatId, hatBlock)
            SB3Builder.addBlock(sprite, gotoId, gotoBlock)
            SB3Builder.addBlock(sprite, getXId, getXBlock)
            SB3Builder.addBlock(sprite, getYId, getYBlock)
            SB3Builder.addBlock(sprite, setXId, setXBlock)
            SB3Builder.addBlock(sprite, setYId, setYBlock)
            SB3Builder.linkBlocks(sprite, {hatId, gotoId, setXId, setYId})

            local projectData = SB3Builder.createProject({stage, sprite})
            local project = ProjectModel:new(projectData, projectData.assets)
            local runtime = Runtime:new(project)
            runtime:initialize()

            runtime:broadcastGreenFlag()
            local maxIterations = 100
            local iterations = 0
            while #runtime:getActiveThreads() > 0 and iterations < maxIterations do
                runtime:update(1/60)
                iterations = iterations + 1
            end

            local reportedX = runtime.stage:lookupVariableByNameAndType("reportedX")
            local reportedY = runtime.stage:lookupVariableByNameAndType("reportedY")
            expect(reportedX.value).to.equal(-50)
            expect(reportedY.value).to.equal(75)
        end)

        it("should report correct direction", function()
            SB3Builder.resetCounter()
            local stage = SB3Builder.createStage()
            local sprite = SB3Builder.createSprite("TestSprite")
            local dirId = SB3Builder.addVariable(stage, "direction", 0)

            local hatId, hatBlock = SB3Builder.Events.whenFlagClicked()
            local pointId, pointBlock = SB3Builder.Motion.pointInDirection(-45)
            local getDirId, getDirBlock = SB3Builder.Motion.direction()
            local setDirId, setDirBlock = SB3Builder.createBlock("data_setvariableto", {
                VALUE = SB3Builder.blockInput(getDirId)
            }, {
                VARIABLE = SB3Builder.field("direction", dirId)
            })

            SB3Builder.addBlock(sprite, hatId, hatBlock)
            SB3Builder.addBlock(sprite, pointId, pointBlock)
            SB3Builder.addBlock(sprite, getDirId, getDirBlock)
            SB3Builder.addBlock(sprite, setDirId, setDirBlock)
            SB3Builder.linkBlocks(sprite, {hatId, pointId, setDirId})

            local projectData = SB3Builder.createProject({stage, sprite})
            local project = ProjectModel:new(projectData, projectData.assets)
            local runtime = Runtime:new(project)
            runtime:initialize()

            runtime:broadcastGreenFlag()
            local maxIterations = 100
            local iterations = 0
            while #runtime:getActiveThreads() > 0 and iterations < maxIterations do
                runtime:update(1/60)
                iterations = iterations + 1
            end

            local direction = runtime.stage:lookupVariableByNameAndType("direction")
            expect(direction.value).to.equal(-45)
        end)
    end)

    describe("Directional Movement", function()
        it("should move in direction 0 (up)", function()
            SB3Builder.resetCounter()
            local stage = SB3Builder.createStage()
            local sprite = SB3Builder.createSprite("TestSprite")

            sprite.x = 0
            sprite.y = 0

            local hatId, hatBlock = SB3Builder.Events.whenFlagClicked()
            local pointId, pointBlock = SB3Builder.Motion.pointInDirection(0) -- Point up
            local moveId, moveBlock = SB3Builder.Motion.moveSteps(10)

            SB3Builder.addBlock(sprite, hatId, hatBlock)
            SB3Builder.addBlock(sprite, pointId, pointBlock)
            SB3Builder.addBlock(sprite, moveId, moveBlock)
            SB3Builder.linkBlocks(sprite, {hatId, pointId, moveId})

            local projectData = SB3Builder.createProject({stage, sprite})
            local project = ProjectModel:new(projectData, projectData.assets)
            local runtime = Runtime:new(project)
            runtime:initialize()

            runtime:broadcastGreenFlag()
            local maxIterations = 100
            local iterations = 0
            while #runtime:getActiveThreads() > 0 and iterations < maxIterations do
                runtime:update(1/60)
                iterations = iterations + 1
            end

            local spriteTarget = runtime:getSpriteTargetByName("TestSprite")
            expect(math.abs(spriteTarget.x) < 0.001).to.be.truthy() -- Should be ~0 (precision)
            expect(spriteTarget.y).to.equal(10) -- Moved up
        end)

        it("should move in direction 180 (down)", function()
            SB3Builder.resetCounter()
            local stage = SB3Builder.createStage()
            local sprite = SB3Builder.createSprite("TestSprite")

            sprite.x = 0
            sprite.y = 0

            local hatId, hatBlock = SB3Builder.Events.whenFlagClicked()
            local pointId, pointBlock = SB3Builder.Motion.pointInDirection(180) -- Point down
            local moveId, moveBlock = SB3Builder.Motion.moveSteps(15)

            SB3Builder.addBlock(sprite, hatId, hatBlock)
            SB3Builder.addBlock(sprite, pointId, pointBlock)
            SB3Builder.addBlock(sprite, moveId, moveBlock)
            SB3Builder.linkBlocks(sprite, {hatId, pointId, moveId})

            local projectData = SB3Builder.createProject({stage, sprite})
            local project = ProjectModel:new(projectData, projectData.assets)
            local runtime = Runtime:new(project)
            runtime:initialize()

            runtime:broadcastGreenFlag()
            local maxIterations = 100
            local iterations = 0
            while #runtime:getActiveThreads() > 0 and iterations < maxIterations do
                runtime:update(1/60)
                iterations = iterations + 1
            end

            local spriteTarget = runtime:getSpriteTargetByName("TestSprite")
            expect(math.abs(spriteTarget.x) < 0.001).to.be.truthy() -- Should be ~0 (precision)
            expect(spriteTarget.y).to.equal(-15) -- Moved down
        end)

        it("should move at angle 45 degrees", function()
            SB3Builder.resetCounter()
            local stage = SB3Builder.createStage()
            local sprite = SB3Builder.createSprite("TestSprite")

            sprite.x = 0
            sprite.y = 0

            local hatId, hatBlock = SB3Builder.Events.whenFlagClicked()
            local pointId, pointBlock = SB3Builder.Motion.pointInDirection(45) -- Northeast
            local moveId, moveBlock = SB3Builder.Motion.moveSteps(10)

            SB3Builder.addBlock(sprite, hatId, hatBlock)
            SB3Builder.addBlock(sprite, pointId, pointBlock)
            SB3Builder.addBlock(sprite, moveId, moveBlock)
            SB3Builder.linkBlocks(sprite, {hatId, pointId, moveId})

            local projectData = SB3Builder.createProject({stage, sprite})
            local project = ProjectModel:new(projectData, projectData.assets)
            local runtime = Runtime:new(project)
            runtime:initialize()

            runtime:broadcastGreenFlag()
            local maxIterations = 100
            local iterations = 0
            while #runtime:getActiveThreads() > 0 and iterations < maxIterations do
                runtime:update(1/60)
                iterations = iterations + 1
            end

            local spriteTarget = runtime:getSpriteTargetByName("TestSprite")
            -- 45 degrees: both x and y should be approximately 10 * cos(45°) ≈ 7.07
            local expectedDistance = 10 * math.cos(math.rad(45))
            expect(math.abs(spriteTarget.x - expectedDistance) < 0.01).to.be.truthy()
            expect(math.abs(spriteTarget.y - expectedDistance) < 0.01).to.be.truthy()
        end)
    end)

    describe("Set Position", function()
        it("should set x position independently", function()
            SB3Builder.resetCounter()
            local stage = SB3Builder.createStage()
            local sprite = SB3Builder.createSprite("TestSprite")

            sprite.x = 100
            sprite.y = 50

            local hatId, hatBlock = SB3Builder.Events.whenFlagClicked()
            local setXId, setXBlock = SB3Builder.Motion.setX(-25)

            SB3Builder.addBlock(sprite, hatId, hatBlock)
            SB3Builder.addBlock(sprite, setXId, setXBlock)
            SB3Builder.linkBlocks(sprite, {hatId, setXId})

            local projectData = SB3Builder.createProject({stage, sprite})
            local project = ProjectModel:new(projectData, projectData.assets)
            local runtime = Runtime:new(project)
            runtime:initialize()

            runtime:broadcastGreenFlag()
            local maxIterations = 100
            local iterations = 0
            while #runtime:getActiveThreads() > 0 and iterations < maxIterations do
                runtime:update(1/60)
                iterations = iterations + 1
            end

            local spriteTarget = runtime:getSpriteTargetByName("TestSprite")
            expect(spriteTarget.x).to.equal(-25) -- X changed
            expect(spriteTarget.y).to.equal(50)  -- Y unchanged
        end)

        it("should set y position independently", function()
            SB3Builder.resetCounter()
            local stage = SB3Builder.createStage()
            local sprite = SB3Builder.createSprite("TestSprite")

            sprite.x = 100
            sprite.y = 50

            local hatId, hatBlock = SB3Builder.Events.whenFlagClicked()
            local setYId, setYBlock = SB3Builder.Motion.setY(75)

            SB3Builder.addBlock(sprite, hatId, hatBlock)
            SB3Builder.addBlock(sprite, setYId, setYBlock)
            SB3Builder.linkBlocks(sprite, {hatId, setYId})

            local projectData = SB3Builder.createProject({stage, sprite})
            local project = ProjectModel:new(projectData, projectData.assets)
            local runtime = Runtime:new(project)
            runtime:initialize()

            runtime:broadcastGreenFlag()
            local maxIterations = 100
            local iterations = 0
            while #runtime:getActiveThreads() > 0 and iterations < maxIterations do
                runtime:update(1/60)
                iterations = iterations + 1
            end

            local spriteTarget = runtime:getSpriteTargetByName("TestSprite")
            expect(spriteTarget.x).to.equal(100) -- X unchanged
            expect(spriteTarget.y).to.equal(75)  -- Y changed
        end)

        it("should change x position by amount", function()
            SB3Builder.resetCounter()
            local stage = SB3Builder.createStage()
            local sprite = SB3Builder.createSprite("TestSprite")

            sprite.x = 20
            sprite.y = 30

            local hatId, hatBlock = SB3Builder.Events.whenFlagClicked()
            local changeXId, changeXBlock = SB3Builder.Motion.changeXBy(-15)

            SB3Builder.addBlock(sprite, hatId, hatBlock)
            SB3Builder.addBlock(sprite, changeXId, changeXBlock)
            SB3Builder.linkBlocks(sprite, {hatId, changeXId})

            local projectData = SB3Builder.createProject({stage, sprite})
            local project = ProjectModel:new(projectData, projectData.assets)
            local runtime = Runtime:new(project)
            runtime:initialize()

            runtime:broadcastGreenFlag()
            local maxIterations = 100
            local iterations = 0
            while #runtime:getActiveThreads() > 0 and iterations < maxIterations do
                runtime:update(1/60)
                iterations = iterations + 1
            end

            local spriteTarget = runtime:getSpriteTargetByName("TestSprite")
            expect(spriteTarget.x).to.equal(5)  -- 20 + (-15) = 5
            expect(spriteTarget.y).to.equal(30) -- Y unchanged
        end)

        it("should change y position by amount", function()
            SB3Builder.resetCounter()
            local stage = SB3Builder.createStage()
            local sprite = SB3Builder.createSprite("TestSprite")

            sprite.x = 20
            sprite.y = 30

            local hatId, hatBlock = SB3Builder.Events.whenFlagClicked()
            local changeYId, changeYBlock = SB3Builder.Motion.changeYBy(25)

            SB3Builder.addBlock(sprite, hatId, hatBlock)
            SB3Builder.addBlock(sprite, changeYId, changeYBlock)
            SB3Builder.linkBlocks(sprite, {hatId, changeYId})

            local projectData = SB3Builder.createProject({stage, sprite})
            local project = ProjectModel:new(projectData, projectData.assets)
            local runtime = Runtime:new(project)
            runtime:initialize()

            runtime:broadcastGreenFlag()
            local maxIterations = 100
            local iterations = 0
            while #runtime:getActiveThreads() > 0 and iterations < maxIterations do
                runtime:update(1/60)
                iterations = iterations + 1
            end

            local spriteTarget = runtime:getSpriteTargetByName("TestSprite")
            expect(spriteTarget.x).to.equal(20) -- X unchanged
            expect(spriteTarget.y).to.equal(55) -- 30 + 25 = 55
        end)
    end)

    describe("Boundary Handling", function()
        it("should handle stage boundaries correctly", function()
            SB3Builder.resetCounter()
            local stage = SB3Builder.createStage()
            local sprite = SB3Builder.createSprite("TestSprite")

            local hatId, hatBlock = SB3Builder.Events.whenFlagClicked()
            -- Try to go far beyond stage boundaries
            local gotoId, gotoBlock = SB3Builder.Motion.goToXY(1000, -1000)

            SB3Builder.addBlock(sprite, hatId, hatBlock)
            SB3Builder.addBlock(sprite, gotoId, gotoBlock)
            SB3Builder.linkBlocks(sprite, {hatId, gotoId})

            local projectData = SB3Builder.createProject({stage, sprite})
            local project = ProjectModel:new(projectData, projectData.assets)
            local runtime = Runtime:new(project)
            runtime:initialize()

            runtime:broadcastGreenFlag()
            local maxIterations = 100
            local iterations = 0
            while #runtime:getActiveThreads() > 0 and iterations < maxIterations do
                runtime:update(1/60)
                iterations = iterations + 1
            end

            local spriteTarget = runtime:getSpriteTargetByName("TestSprite")
            -- Coordinates should be clamped or allowed (depending on implementation)
            -- This test verifies the implementation doesn't crash
            expect(spriteTarget.x).to.exist()
            expect(spriteTarget.y).to.exist()
        end)

        it("should allow sprite to partially exceed boundaries with FENCE_WIDTH", function()
            SB3Builder.resetCounter()
            local stage = SB3Builder.createStage()
            local sprite = SB3Builder.createSprite("TestSprite")

            -- Create a 40x40 costume (half size = 20, which is larger than FENCE_WIDTH = 15)
            -- So fenceInset = min(15, 20) = 15
            local costume = {
                name = "costume1",
                bitmapResolution = 1,
                dataFormat = "svg",
                assetId = "test",
                md5ext = "test.svg",
                rotationCenterX = 20,
                rotationCenterY = 20
            }
            sprite.costumes = {costume}

            local hatId, hatBlock = SB3Builder.Events.whenFlagClicked()
            -- Try to move beyond right edge: stage right = 240
            -- With 40x40 costume centered, bounds are x-20 to x+20
            -- Fence allows: newLeft <= 240-15 = 225
            -- So max x = 225 + 20 = 245
            local gotoId, gotoBlock = SB3Builder.Motion.goToXY(300, 0)

            SB3Builder.addBlock(sprite, hatId, hatBlock)
            SB3Builder.addBlock(sprite, gotoId, gotoBlock)
            SB3Builder.linkBlocks(sprite, {hatId, gotoId})

            local projectData = SB3Builder.createProject({stage, sprite})
            local project = ProjectModel:new(projectData, projectData.assets)
            local runtime = Runtime:new(project)
            runtime:initialize()

            -- Mock costume image dimensions
            local spriteTarget = runtime:getSpriteTargetByName("TestSprite")
            local mockImage = {
                getWidth = function() return 40 end,
                getHeight = function() return 40 end
            }
            spriteTarget.costumes[1].image = mockImage

            runtime:broadcastGreenFlag()
            local maxIterations = 100
            local iterations = 0
            while #runtime:getActiveThreads() > 0 and iterations < maxIterations do
                runtime:update(1/60)
                iterations = iterations + 1
            end

            -- With FENCE_WIDTH=15 and 40x40 sprite:
            -- Right edge of sprite at fenced position should be: 240 + 15 = 255
            -- Center should be at: 255 - 20 = 235 (not 240, because we allow 15px to go beyond)
            expect(spriteTarget.x > Global.SCRATCH_MAX_X).to.be.truthy()  -- Can exceed stage boundary
            expect(spriteTarget.x <= Global.SCRATCH_MAX_X + Global.FENCE_WIDTH).to.be.truthy()  -- But not too far
        end)

        it("should fence small sprites by half their size", function()
            SB3Builder.resetCounter()
            local stage = SB3Builder.createStage()
            local sprite = SB3Builder.createSprite("TestSprite")

            -- Create a 20x20 costume (half size = 10, which is smaller than FENCE_WIDTH = 15)
            -- So fenceInset = min(15, 10) = 10
            local costume = {
                name = "costume1",
                bitmapResolution = 1,
                dataFormat = "svg",
                assetId = "test",
                md5ext = "test.svg",
                rotationCenterX = 10,
                rotationCenterY = 10
            }
            sprite.costumes = {costume}

            local hatId, hatBlock = SB3Builder.Events.whenFlagClicked()
            -- Try to move beyond right edge
            -- With 20x20 costume centered, bounds are x-10 to x+10
            -- Fence allows: newLeft <= 240-10 = 230
            -- So max x = 230 + 10 = 240
            local gotoId, gotoBlock = SB3Builder.Motion.goToXY(300, 0)

            SB3Builder.addBlock(sprite, hatId, hatBlock)
            SB3Builder.addBlock(sprite, gotoId, gotoBlock)
            SB3Builder.linkBlocks(sprite, {hatId, gotoId})

            local projectData = SB3Builder.createProject({stage, sprite})
            local project = ProjectModel:new(projectData, projectData.assets)
            local runtime = Runtime:new(project)
            runtime:initialize()

            -- Mock costume image dimensions
            local spriteTarget = runtime:getSpriteTargetByName("TestSprite")
            local mockImage = {
                getWidth = function() return 20 end,
                getHeight = function() return 20 end
            }
            spriteTarget.costumes[1].image = mockImage

            runtime:broadcastGreenFlag()
            local maxIterations = 100
            local iterations = 0
            while #runtime:getActiveThreads() > 0 and iterations < maxIterations do
                runtime:update(1/60)
                iterations = iterations + 1
            end

            -- With small sprite (20x20), inset is 10 (half size)
            -- Right edge at fenced position should be: 240 + 10 = 250
            -- Center should be at: 250 - 10 = 240 (exactly at stage boundary)
            expect(spriteTarget.x <= Global.SCRATCH_MAX_X + 10).to.be.truthy()
        end)

        it("should respect fencing=false option", function()
            SB3Builder.resetCounter()
            local stage = SB3Builder.createStage()
            local sprite = SB3Builder.createSprite("TestSprite")

            local hatId, hatBlock = SB3Builder.Events.whenFlagClicked()
            local gotoId, gotoBlock = SB3Builder.Motion.goToXY(1000, 500)

            SB3Builder.addBlock(sprite, hatId, hatBlock)
            SB3Builder.addBlock(sprite, gotoId, gotoBlock)
            SB3Builder.linkBlocks(sprite, {hatId, gotoId})

            local projectData = SB3Builder.createProject({stage, sprite})
            local project = ProjectModel:new(projectData, projectData.assets)
            local runtime = Runtime:new(project)
            runtime:initialize()

            -- Disable fencing
            runtime:setRuntimeOptions({fencing = false})

            runtime:broadcastGreenFlag()
            local maxIterations = 100
            local iterations = 0
            while #runtime:getActiveThreads() > 0 and iterations < maxIterations do
                runtime:update(1/60)
                iterations = iterations + 1
            end

            local spriteTarget = runtime:getSpriteTargetByName("TestSprite")
            -- With fencing disabled, sprite should be at exact requested position
            expect(spriteTarget.x).to.equal(1000)
            expect(spriteTarget.y).to.equal(500)
        end)
    end)

    describe("Edge Bounce Behavior", function()
        it("should bounce when hitting right edge", function()
            SB3Builder.resetCounter()
            local stage = SB3Builder.createStage()
            local sprite = SB3Builder.createSprite("TestSprite")

            -- Add a default costume so sprite has size for edge detection
            local costume = SB3Builder.createCostume("costume1", "svg")
            sprite.costumes = {costume}

            -- Position near right edge, facing right
            sprite.x = Global.SCRATCH_MAX_X - 5
            sprite.y = 0
            sprite.direction = 90

            local hatId, hatBlock = SB3Builder.Events.whenFlagClicked()
            local moveId, moveBlock = SB3Builder.Motion.moveSteps(20)  -- Move past right edge
            local bounceId, bounceBlock = SB3Builder.Motion.ifOnEdgeBounce()

            SB3Builder.addBlock(sprite, hatId, hatBlock)
            SB3Builder.addBlock(sprite, moveId, moveBlock)
            SB3Builder.addBlock(sprite, bounceId, bounceBlock)
            SB3Builder.linkBlocks(sprite, {hatId, moveId, bounceId})

            local projectData = SB3Builder.createProject({stage, sprite})
            local project = ProjectModel:new(projectData, projectData.assets)
            local runtime = Runtime:new(project)
            runtime:initialize()

            runtime:broadcastGreenFlag()
            local maxIterations = 100
            local iterations = 0
            while #runtime:getActiveThreads() > 0 and iterations < maxIterations do
                runtime:update(1/60)
                iterations = iterations + 1
            end

            local spriteTarget = runtime:getSpriteTargetByName("TestSprite")
            -- Should be at right edge and direction should have changed
            expect(spriteTarget.x < Global.SCRATCH_MAX_X).to.be.truthy()
            expect(spriteTarget.direction).to_not.equal(90)  -- Direction should change
        end)

        it("should bounce when hitting left edge", function()
            SB3Builder.resetCounter()
            local stage = SB3Builder.createStage()
            local sprite = SB3Builder.createSprite("TestSprite")

            -- Add a default costume so sprite has size for edge detection
            local costume = SB3Builder.createCostume("costume1", "svg")
            sprite.costumes = {costume}

            -- Position near left edge, facing left
            sprite.x = Global.SCRATCH_MIN_X + 5
            sprite.y = 0
            sprite.direction = 270

            local hatId, hatBlock = SB3Builder.Events.whenFlagClicked()
            local moveId, moveBlock = SB3Builder.Motion.moveSteps(20)  -- Move past left edge
            local bounceId, bounceBlock = SB3Builder.Motion.ifOnEdgeBounce()

            SB3Builder.addBlock(sprite, hatId, hatBlock)
            SB3Builder.addBlock(sprite, moveId, moveBlock)
            SB3Builder.addBlock(sprite, bounceId, bounceBlock)
            SB3Builder.linkBlocks(sprite, {hatId, moveId, bounceId})

            local projectData = SB3Builder.createProject({stage, sprite})
            local project = ProjectModel:new(projectData, projectData.assets)
            local runtime = Runtime:new(project)
            runtime:initialize()

            runtime:broadcastGreenFlag()
            local maxIterations = 100
            local iterations = 0
            while #runtime:getActiveThreads() > 0 and iterations < maxIterations do
                runtime:update(1/60)
                iterations = iterations + 1
            end

            local spriteTarget = runtime:getSpriteTargetByName("TestSprite")
            -- Should be at left boundary and direction should have changed
            expect(spriteTarget.x > Global.SCRATCH_MIN_X).to.be.truthy()
            expect(spriteTarget.direction).to_not.equal(270)  -- Direction should change
        end)

        it("should bounce when hitting top edge", function()
            SB3Builder.resetCounter()
            local stage = SB3Builder.createStage()
            local sprite = SB3Builder.createSprite("TestSprite")

            -- Add a default costume so sprite has size for edge detection
            local costume = SB3Builder.createCostume("costume1", "svg")
            sprite.costumes = {costume}

            -- Position near top edge, facing up
            sprite.x = 0
            sprite.y = Global.SCRATCH_MAX_Y - 5
            sprite.direction = 0

            local hatId, hatBlock = SB3Builder.Events.whenFlagClicked()
            local moveId, moveBlock = SB3Builder.Motion.moveSteps(20)  -- Move past top edge
            local bounceId, bounceBlock = SB3Builder.Motion.ifOnEdgeBounce()

            SB3Builder.addBlock(sprite, hatId, hatBlock)
            SB3Builder.addBlock(sprite, moveId, moveBlock)
            SB3Builder.addBlock(sprite, bounceId, bounceBlock)
            SB3Builder.linkBlocks(sprite, {hatId, moveId, bounceId})

            local projectData = SB3Builder.createProject({stage, sprite})
            local project = ProjectModel:new(projectData, projectData.assets)
            local runtime = Runtime:new(project)
            runtime:initialize()

            runtime:broadcastGreenFlag()
            local maxIterations = 100
            local iterations = 0
            while #runtime:getActiveThreads() > 0 and iterations < maxIterations do
                runtime:update(1/60)
                iterations = iterations + 1
            end

            local spriteTarget = runtime:getSpriteTargetByName("TestSprite")
            -- Should be at top boundary and direction should have changed
            expect(spriteTarget.y < Global.SCRATCH_MAX_Y).to.be.truthy()
            expect(spriteTarget.direction).to_not.equal(0)  -- Direction should change
        end)

        it("should bounce when hitting bottom edge", function()
            SB3Builder.resetCounter()
            local stage = SB3Builder.createStage()
            local sprite = SB3Builder.createSprite("TestSprite")

            -- Add a default costume so sprite has size for edge detection
            local costume = SB3Builder.createCostume("costume1", "svg")
            sprite.costumes = {costume}

            -- Position near bottom edge, facing down
            sprite.x = 0
            sprite.y = Global.SCRATCH_MIN_Y + 5
            sprite.direction = 180

            local hatId, hatBlock = SB3Builder.Events.whenFlagClicked()
            local moveId, moveBlock = SB3Builder.Motion.moveSteps(20)  -- Move past bottom edge
            local bounceId, bounceBlock = SB3Builder.Motion.ifOnEdgeBounce()

            SB3Builder.addBlock(sprite, hatId, hatBlock)
            SB3Builder.addBlock(sprite, moveId, moveBlock)
            SB3Builder.addBlock(sprite, bounceId, bounceBlock)
            SB3Builder.linkBlocks(sprite, {hatId, moveId, bounceId})

            local projectData = SB3Builder.createProject({stage, sprite})
            local project = ProjectModel:new(projectData, projectData.assets)
            local runtime = Runtime:new(project)
            runtime:initialize()

            runtime:broadcastGreenFlag()
            local maxIterations = 100
            local iterations = 0
            while #runtime:getActiveThreads() > 0 and iterations < maxIterations do
                runtime:update(1/60)
                iterations = iterations + 1
            end

            local spriteTarget = runtime:getSpriteTargetByName("TestSprite")
            -- Should be at or within bottom boundary and direction should have changed
            expect(spriteTarget.y >= Global.SCRATCH_MIN_Y).to.be.truthy()
            expect(spriteTarget.direction).to_not.equal(180)  -- Direction should change
        end)

        it("should handle corner bouncing", function()
            SB3Builder.resetCounter()
            local stage = SB3Builder.createStage()
            local sprite = SB3Builder.createSprite("TestSprite")

            -- Add a default costume so sprite has size for edge detection
            local costume = SB3Builder.createCostume("costume1", "svg")
            sprite.costumes = {costume}

            -- Position near top-right corner, facing diagonally
            sprite.x = Global.SCRATCH_MAX_X - 5
            sprite.y = Global.SCRATCH_MAX_Y - 5
            sprite.direction = 45  -- Northeast

            local hatId, hatBlock = SB3Builder.Events.whenFlagClicked()
            local moveId, moveBlock = SB3Builder.Motion.moveSteps(20)  -- Move into corner
            local bounceId, bounceBlock = SB3Builder.Motion.ifOnEdgeBounce()

            SB3Builder.addBlock(sprite, hatId, hatBlock)
            SB3Builder.addBlock(sprite, moveId, moveBlock)
            SB3Builder.addBlock(sprite, bounceId, bounceBlock)
            SB3Builder.linkBlocks(sprite, {hatId, moveId, bounceId})

            local projectData = SB3Builder.createProject({stage, sprite})
            local project = ProjectModel:new(projectData, projectData.assets)
            local runtime = Runtime:new(project)
            runtime:initialize()

            runtime:broadcastGreenFlag()
            local maxIterations = 100
            local iterations = 0
            while #runtime:getActiveThreads() > 0 and iterations < maxIterations do
                runtime:update(1/60)
                iterations = iterations + 1
            end

            local spriteTarget = runtime:getSpriteTargetByName("TestSprite")
            -- With FENCE_WIDTH, sprite center can exceed stage bounds slightly
            -- but must keep minimum visible pixels onscreen
            -- Just check that direction changed (bounce happened)
            expect(spriteTarget.direction).to_not.equal(45)  -- Direction should change
        end)
    end)

    describe("Rotation Style Behavior", function()
        it("should set rotation style to 'all around'", function()
            SB3Builder.resetCounter()
            local stage = SB3Builder.createStage()
            local sprite = SB3Builder.createSprite("TestSprite")

            local hatId, hatBlock = SB3Builder.Events.whenFlagClicked()
            local styleId, styleBlock = SB3Builder.Motion.setRotationStyle("all around")

            SB3Builder.addBlock(sprite, hatId, hatBlock)
            SB3Builder.addBlock(sprite, styleId, styleBlock)
            SB3Builder.linkBlocks(sprite, {hatId, styleId})

            local projectData = SB3Builder.createProject({stage, sprite})
            local project = ProjectModel:new(projectData, projectData.assets)
            local runtime = Runtime:new(project)
            runtime:initialize()

            runtime:broadcastGreenFlag()
            local maxIterations = 100
            local iterations = 0
            while #runtime:getActiveThreads() > 0 and iterations < maxIterations do
                runtime:update(1/60)
                iterations = iterations + 1
            end

            local spriteTarget = runtime:getSpriteTargetByName("TestSprite")
            expect(spriteTarget.rotationStyle).to.equal("all around")
        end)

        it("should set rotation style to 'left-right'", function()
            SB3Builder.resetCounter()
            local stage = SB3Builder.createStage()
            local sprite = SB3Builder.createSprite("TestSprite")

            local hatId, hatBlock = SB3Builder.Events.whenFlagClicked()
            local styleId, styleBlock = SB3Builder.Motion.setRotationStyle("left-right")

            SB3Builder.addBlock(sprite, hatId, hatBlock)
            SB3Builder.addBlock(sprite, styleId, styleBlock)
            SB3Builder.linkBlocks(sprite, {hatId, styleId})

            local projectData = SB3Builder.createProject({stage, sprite})
            local project = ProjectModel:new(projectData, projectData.assets)
            local runtime = Runtime:new(project)
            runtime:initialize()

            runtime:broadcastGreenFlag()
            local maxIterations = 100
            local iterations = 0
            while #runtime:getActiveThreads() > 0 and iterations < maxIterations do
                runtime:update(1/60)
                iterations = iterations + 1
            end

            local spriteTarget = runtime:getSpriteTargetByName("TestSprite")
            expect(spriteTarget.rotationStyle).to.equal("left-right")
        end)

        it("should set rotation style to 'don't rotate'", function()
            SB3Builder.resetCounter()
            local stage = SB3Builder.createStage()
            local sprite = SB3Builder.createSprite("TestSprite")

            local hatId, hatBlock = SB3Builder.Events.whenFlagClicked()
            local styleId, styleBlock = SB3Builder.Motion.setRotationStyle("don't rotate")

            SB3Builder.addBlock(sprite, hatId, hatBlock)
            SB3Builder.addBlock(sprite, styleId, styleBlock)
            SB3Builder.linkBlocks(sprite, {hatId, styleId})

            local projectData = SB3Builder.createProject({stage, sprite})
            local project = ProjectModel:new(projectData, projectData.assets)
            local runtime = Runtime:new(project)
            runtime:initialize()

            runtime:broadcastGreenFlag()
            local maxIterations = 100
            local iterations = 0
            while #runtime:getActiveThreads() > 0 and iterations < maxIterations do
                runtime:update(1/60)
                iterations = iterations + 1
            end

            local spriteTarget = runtime:getSpriteTargetByName("TestSprite")
            expect(spriteTarget.rotationStyle).to.equal("don't rotate")
        end)
    end)

    describe("Random Direction Tests", function()
        it("should point in random direction within valid range", function()
            SB3Builder.resetCounter()
            local stage = SB3Builder.createStage()
            local sprite = SB3Builder.createSprite("TestSprite")
            local dirId = SB3Builder.addVariable(stage, "direction", 0)

            local hatId, hatBlock = SB3Builder.Events.whenFlagClicked()
            local pointId, pointBlock = SB3Builder.Motion.pointTowards("_random_")
            local getDirId, getDirBlock = SB3Builder.Motion.direction()
            local setDirId, setDirBlock = SB3Builder.createBlock("data_setvariableto", {
                VALUE = SB3Builder.blockInput(getDirId)
            }, {
                VARIABLE = SB3Builder.field("direction", dirId)
            })

            SB3Builder.addBlock(sprite, hatId, hatBlock)
            SB3Builder.addBlock(sprite, pointId, pointBlock)
            SB3Builder.addBlock(sprite, getDirId, getDirBlock)
            SB3Builder.addBlock(sprite, setDirId, setDirBlock)
            SB3Builder.linkBlocks(sprite, {hatId, pointId, setDirId})

            local projectData = SB3Builder.createProject({stage, sprite})
            local project = ProjectModel:new(projectData, projectData.assets)
            local runtime = Runtime:new(project)
            runtime:initialize()

            runtime:broadcastGreenFlag()
            local maxIterations = 100
            local iterations = 0
            while #runtime:getActiveThreads() > 0 and iterations < maxIterations do
                runtime:update(1/60)
                iterations = iterations + 1
            end

            local direction = runtime.stage:lookupVariableByNameAndType("direction")
            -- Random direction should be in range -180 to +180
            expect(direction.value > -181).to.be.truthy()
            expect(direction.value < 181).to.be.truthy()
        end)

        it("should generate different random directions over multiple runs", function()
            SB3Builder.resetCounter()
            local stage = SB3Builder.createStage()
            local sprite = SB3Builder.createSprite("TestSprite")

            local directions = {}
            for i = 1, 10 do
                local hatId, hatBlock = SB3Builder.Events.whenFlagClicked()
                local pointId, pointBlock = SB3Builder.Motion.pointTowards("_random_")

                SB3Builder.addBlock(sprite, hatId, hatBlock)
                SB3Builder.addBlock(sprite, pointId, pointBlock)
                SB3Builder.linkBlocks(sprite, {hatId, pointId})

                local projectData = SB3Builder.createProject({stage, sprite})
                local project = ProjectModel:new(projectData, projectData.assets)
                local runtime = Runtime:new(project)
                runtime:initialize()

                runtime:broadcastGreenFlag()
                while #runtime:getActiveThreads() > 0 do
                    runtime:update(1/60)
                end

                local spriteTarget = runtime:getSpriteTargetByName("TestSprite")
                directions[i] = spriteTarget.direction
            end

            -- At least some directions should be different (not all the same)
            local allSame = true
            local firstDir = directions[1]
            for i = 2, 10 do
                if directions[i] ~= firstDir then
                    allSame = false
                    break
                end
            end
            expect(allSame).to.equal(false)  -- Should have some variation
        end)
    end)

    describe("Glide Animation Tests", function()
        it("should glide to coordinates over time", function()
            SB3Builder.resetCounter()
            local stage = SB3Builder.createStage()
            local sprite = SB3Builder.createSprite("TestSprite")

            sprite.x = 0
            sprite.y = 0

            local hatId, hatBlock = SB3Builder.Events.whenFlagClicked()
            local glideId, glideBlock = SB3Builder.Motion.glideToXY(0.1, 100, 50)  -- Quick glide

            SB3Builder.addBlock(sprite, hatId, hatBlock)
            SB3Builder.addBlock(sprite, glideId, glideBlock)
            SB3Builder.linkBlocks(sprite, {hatId, glideId})

            local projectData = SB3Builder.createProject({stage, sprite})
            local project = ProjectModel:new(projectData, projectData.assets)
            local runtime = Runtime:new(project)
            runtime:initialize()

            runtime:broadcastGreenFlag()
            -- Run for longer to allow glide to complete
            local maxIterations = 100
            local iterations = 0
            while #runtime:getActiveThreads() > 0 and iterations < maxIterations do
                runtime:update(1/60)
                iterations = iterations + 1
            end

            local spriteTarget = runtime:getSpriteTargetByName("TestSprite")
            expect(spriteTarget.x).to.equal(100)
            expect(spriteTarget.y).to.equal(50)
        end)

        it("should handle zero duration glide", function()
            SB3Builder.resetCounter()
            local stage = SB3Builder.createStage()
            local sprite = SB3Builder.createSprite("TestSprite")

            sprite.x = 0
            sprite.y = 0

            local hatId, hatBlock = SB3Builder.Events.whenFlagClicked()
            local glideId, glideBlock = SB3Builder.Motion.glideToXY(0, 50, 25)  -- Zero duration

            SB3Builder.addBlock(sprite, hatId, hatBlock)
            SB3Builder.addBlock(sprite, glideId, glideBlock)
            SB3Builder.linkBlocks(sprite, {hatId, glideId})

            local projectData = SB3Builder.createProject({stage, sprite})
            local project = ProjectModel:new(projectData, projectData.assets)
            local runtime = Runtime:new(project)
            runtime:initialize()

            runtime:broadcastGreenFlag()
            local maxIterations = 100
            local iterations = 0
            while #runtime:getActiveThreads() > 0 and iterations < maxIterations do
                runtime:update(1/60)
                iterations = iterations + 1
            end

            local spriteTarget = runtime:getSpriteTargetByName("TestSprite")
            -- Should immediately jump to target position
            expect(spriteTarget.x).to.equal(50)
            expect(spriteTarget.y).to.equal(25)
        end)

        it("should glide to random position", function()
            SB3Builder.resetCounter()
            local stage = SB3Builder.createStage()
            local sprite = SB3Builder.createSprite("TestSprite")

            sprite.x = 0
            sprite.y = 0

            local hatId, hatBlock = SB3Builder.Events.whenFlagClicked()
            local glideId, glideBlock = SB3Builder.Motion.glideTo(0.1, "_random_")

            SB3Builder.addBlock(sprite, hatId, hatBlock)
            SB3Builder.addBlock(sprite, glideId, glideBlock)
            SB3Builder.linkBlocks(sprite, {hatId, glideId})

            local projectData = SB3Builder.createProject({stage, sprite})
            local project = ProjectModel:new(projectData, projectData.assets)
            local runtime = Runtime:new(project)
            runtime:initialize()

            runtime:broadcastGreenFlag()
            local maxIterations = 100
            local iterations = 0
            while #runtime:getActiveThreads() > 0 and iterations < maxIterations do
                runtime:update(1/60)
                iterations = iterations + 1
            end

            local spriteTarget = runtime:getSpriteTargetByName("TestSprite")
            -- Should have moved to some position within stage bounds
            expect(spriteTarget.x >= Global.SCRATCH_MIN_X).to.be.truthy()
            expect(spriteTarget.x <= Global.SCRATCH_MAX_X).to.be.truthy()
            expect(spriteTarget.y >= Global.SCRATCH_MIN_Y).to.be.truthy()
            expect(spriteTarget.y <= Global.SCRATCH_MAX_Y).to.be.truthy()
        end)

        it("should execute blocks after glide completes", function()
            SB3Builder.resetCounter()
            local stage = SB3Builder.createStage()
            local sprite = SB3Builder.createSprite("TestSprite")

            -- Create a variable to track execution
            local varId = SB3Builder.addVariable(stage, "afterGlide", 0)

            sprite.x = 0
            sprite.y = 0

            local hatId, hatBlock = SB3Builder.Events.whenFlagClicked()
            local glideId, glideBlock = SB3Builder.Motion.glideToXY(0.1, 100, 50)  -- Quick glide
            local setVarId, setVarBlock = SB3Builder.Data.setVariable("afterGlide", 42, varId)  -- Should execute after glide

            SB3Builder.addBlock(sprite, hatId, hatBlock)
            SB3Builder.addBlock(sprite, glideId, glideBlock)
            SB3Builder.addBlock(sprite, setVarId, setVarBlock)
            SB3Builder.linkBlocks(sprite, {hatId, glideId, setVarId})

            local projectData = SB3Builder.createProject({stage, sprite})
            local project = ProjectModel:new(projectData, projectData.assets)
            local runtime = Runtime:new(project)
            runtime:initialize()

            runtime:broadcastGreenFlag()
            local maxIterations = 100
            local iterations = 0
            while #runtime:getActiveThreads() > 0 and iterations < maxIterations do
                runtime:update(1/60)
                iterations = iterations + 1
            end

            local spriteTarget = runtime:getSpriteTargetByName("TestSprite")
            local stageTarget = runtime.stage

            -- Check that glide completed
            expect(spriteTarget.x).to.equal(100)
            expect(spriteTarget.y).to.equal(50)

            -- Check that the block after glide was executed
            local afterGlideVar = stageTarget:lookupVariableByNameAndType("afterGlide")
            expect(afterGlideVar.value).to.equal(42)
        end)
    end)

    describe("Mouse Position Interaction Tests", function()
        it("should go to mouse position", function()
            SB3Builder.resetCounter()
            local stage = SB3Builder.createStage()
            local sprite = SB3Builder.createSprite("TestSprite")

            local hatId, hatBlock = SB3Builder.Events.whenFlagClicked()
            local gotoId, gotoBlock = SB3Builder.Motion.goTo("_mouse_")

            SB3Builder.addBlock(sprite, hatId, hatBlock)
            SB3Builder.addBlock(sprite, gotoId, gotoBlock)
            SB3Builder.linkBlocks(sprite, {hatId, gotoId})

            local projectData = SB3Builder.createProject({stage, sprite})
            local project = ProjectModel:new(projectData, projectData.assets)
            local runtime = Runtime:new(project)
            runtime:initialize()

            -- Set mouse position
            runtime.mouseX = 75
            runtime.mouseY = -25

            runtime:broadcastGreenFlag()
            local maxIterations = 100
            local iterations = 0
            while #runtime:getActiveThreads() > 0 and iterations < maxIterations do
                runtime:update(1/60)
                iterations = iterations + 1
            end

            local spriteTarget = runtime:getSpriteTargetByName("TestSprite")
            expect(spriteTarget.x).to.equal(75)
            expect(spriteTarget.y).to.equal(-25)
        end)

        it("should point towards mouse position", function()
            SB3Builder.resetCounter()
            local stage = SB3Builder.createStage()
            local sprite = SB3Builder.createSprite("TestSprite")
            local dirId = SB3Builder.addVariable(stage, "direction", 0)

            sprite.x = 0
            sprite.y = 0

            local hatId, hatBlock = SB3Builder.Events.whenFlagClicked()
            local pointId, pointBlock = SB3Builder.Motion.pointTowards("_mouse_")
            local getDirId, getDirBlock = SB3Builder.Motion.direction()
            local setDirId, setDirBlock = SB3Builder.createBlock("data_setvariableto", {
                VALUE = SB3Builder.blockInput(getDirId)
            }, {
                VARIABLE = SB3Builder.field("direction", dirId)
            })

            SB3Builder.addBlock(sprite, hatId, hatBlock)
            SB3Builder.addBlock(sprite, pointId, pointBlock)
            SB3Builder.addBlock(sprite, getDirId, getDirBlock)
            SB3Builder.addBlock(sprite, setDirId, setDirBlock)
            SB3Builder.linkBlocks(sprite, {hatId, pointId, setDirId})

            local projectData = SB3Builder.createProject({stage, sprite})
            local project = ProjectModel:new(projectData, projectData.assets)
            local runtime = Runtime:new(project)
            runtime:initialize()

            -- Set mouse position at 45 degree angle from sprite
            runtime.mouseX = 100
            runtime.mouseY = 100

            runtime:broadcastGreenFlag()
            local maxIterations = 100
            local iterations = 0
            while #runtime:getActiveThreads() > 0 and iterations < maxIterations do
                runtime:update(1/60)
                iterations = iterations + 1
            end

            local direction = runtime.stage:lookupVariableByNameAndType("direction")
            -- Should point towards northeast (approximately 45 degrees)
            expect(math.abs(direction.value - 45) < 1).to.be.truthy()
        end)

        it("should glide to mouse position", function()
            SB3Builder.resetCounter()
            local stage = SB3Builder.createStage()
            local sprite = SB3Builder.createSprite("TestSprite")

            sprite.x = 0
            sprite.y = 0

            local hatId, hatBlock = SB3Builder.Events.whenFlagClicked()
            local glideId, glideBlock = SB3Builder.Motion.glideTo(0.1, "_mouse_")

            SB3Builder.addBlock(sprite, hatId, hatBlock)
            SB3Builder.addBlock(sprite, glideId, glideBlock)
            SB3Builder.linkBlocks(sprite, {hatId, glideId})

            local projectData = SB3Builder.createProject({stage, sprite})
            local project = ProjectModel:new(projectData, projectData.assets)
            local runtime = Runtime:new(project)
            runtime:initialize()

            -- Set mouse position
            runtime.mouseX = 50
            runtime.mouseY = -75

            runtime:broadcastGreenFlag()
            local maxIterations = 100
            local iterations = 0
            while #runtime:getActiveThreads() > 0 and iterations < maxIterations do
                runtime:update(1/60)
                iterations = iterations + 1
            end

            local spriteTarget = runtime:getSpriteTargetByName("TestSprite")
            expect(spriteTarget.x).to.equal(50)
            expect(spriteTarget.y).to.equal(-75)
        end)
    end)

    describe("Sprite-to-Sprite Interaction Edge Cases", function()
        it("should handle going to non-existent sprite", function()
            SB3Builder.resetCounter()
            local stage = SB3Builder.createStage()
            local sprite = SB3Builder.createSprite("TestSprite")

            sprite.x = 10
            sprite.y = 20

            local hatId, hatBlock = SB3Builder.Events.whenFlagClicked()
            local gotoId, gotoBlock = SB3Builder.Motion.goTo("NonExistentSprite")

            SB3Builder.addBlock(sprite, hatId, hatBlock)
            SB3Builder.addBlock(sprite, gotoId, gotoBlock)
            SB3Builder.linkBlocks(sprite, {hatId, gotoId})

            local projectData = SB3Builder.createProject({stage, sprite})
            local project = ProjectModel:new(projectData, projectData.assets)
            local runtime = Runtime:new(project)
            runtime:initialize()

            runtime:broadcastGreenFlag()
            local maxIterations = 100
            local iterations = 0
            while #runtime:getActiveThreads() > 0 and iterations < maxIterations do
                runtime:update(1/60)
                iterations = iterations + 1
            end

            local spriteTarget = runtime:getSpriteTargetByName("TestSprite")
            -- Should not move (stay at original position)
            expect(spriteTarget.x).to.equal(10)
            expect(spriteTarget.y).to.equal(20)
        end)

        it("should handle pointing towards non-existent sprite", function()
            SB3Builder.resetCounter()
            local stage = SB3Builder.createStage()
            local sprite = SB3Builder.createSprite("TestSprite")

            sprite.direction = 45  -- Initial direction

            local hatId, hatBlock = SB3Builder.Events.whenFlagClicked()
            local pointId, pointBlock = SB3Builder.Motion.pointTowards("NonExistentSprite")

            SB3Builder.addBlock(sprite, hatId, hatBlock)
            SB3Builder.addBlock(sprite, pointId, pointBlock)
            SB3Builder.linkBlocks(sprite, {hatId, pointId})

            local projectData = SB3Builder.createProject({stage, sprite})
            local project = ProjectModel:new(projectData, projectData.assets)
            local runtime = Runtime:new(project)
            runtime:initialize()

            runtime:broadcastGreenFlag()
            local maxIterations = 100
            local iterations = 0
            while #runtime:getActiveThreads() > 0 and iterations < maxIterations do
                runtime:update(1/60)
                iterations = iterations + 1
            end

            local spriteTarget = runtime:getSpriteTargetByName("TestSprite")
            -- Direction should not change
            expect(spriteTarget.direction).to.equal(45)
        end)

        it("should handle gliding to non-existent sprite", function()
            SB3Builder.resetCounter()
            local stage = SB3Builder.createStage()
            local sprite = SB3Builder.createSprite("TestSprite")

            sprite.x = 30
            sprite.y = 40

            local hatId, hatBlock = SB3Builder.Events.whenFlagClicked()
            local glideId, glideBlock = SB3Builder.Motion.glideTo(0.1, "NonExistentSprite")

            SB3Builder.addBlock(sprite, hatId, hatBlock)
            SB3Builder.addBlock(sprite, glideId, glideBlock)
            SB3Builder.linkBlocks(sprite, {hatId, glideId})

            local projectData = SB3Builder.createProject({stage, sprite})
            local project = ProjectModel:new(projectData, projectData.assets)
            local runtime = Runtime:new(project)
            runtime:initialize()

            runtime:broadcastGreenFlag()
            local maxIterations = 100
            local iterations = 0
            while #runtime:getActiveThreads() > 0 and iterations < maxIterations do
                runtime:update(1/60)
                iterations = iterations + 1
            end

            local spriteTarget = runtime:getSpriteTargetByName("TestSprite")
            -- Should not move (stay at original position)
            expect(spriteTarget.x).to.equal(30)
            expect(spriteTarget.y).to.equal(40)
        end)

        it("should handle interaction between two sprites", function()
            SB3Builder.resetCounter()
            local stage = SB3Builder.createStage()
            local sprite1 = SB3Builder.createSprite("Sprite1")
            local sprite2 = SB3Builder.createSprite("Sprite2")

            sprite1.x = 0
            sprite1.y = 0
            sprite2.x = 50
            sprite2.y = 75

            local hatId, hatBlock = SB3Builder.Events.whenFlagClicked()
            local gotoId, gotoBlock = SB3Builder.Motion.goTo("Sprite2")

            SB3Builder.addBlock(sprite1, hatId, hatBlock)
            SB3Builder.addBlock(sprite1, gotoId, gotoBlock)
            SB3Builder.linkBlocks(sprite1, {hatId, gotoId})

            local projectData = SB3Builder.createProject({stage, sprite1, sprite2})
            local project = ProjectModel:new(projectData, projectData.assets)
            local runtime = Runtime:new(project)
            runtime:initialize()

            runtime:broadcastGreenFlag()
            local maxIterations = 100
            local iterations = 0
            while #runtime:getActiveThreads() > 0 and iterations < maxIterations do
                runtime:update(1/60)
                iterations = iterations + 1
            end

            local sprite1Target = runtime:getSpriteTargetByName("Sprite1")
            local sprite2Target = runtime:getSpriteTargetByName("Sprite2")
            -- Sprite1 should move to Sprite2's position
            expect(sprite1Target.x).to.equal(50)
            expect(sprite1Target.y).to.equal(75)
            -- Sprite2 should stay in place
            expect(sprite2Target.x).to.equal(50)
            expect(sprite2Target.y).to.equal(75)
        end)
    end)

    describe("Complex Movement Sequences", function()
        it("should handle multiple movements in sequence", function()
            SB3Builder.resetCounter()
            local stage = SB3Builder.createStage()
            local sprite = SB3Builder.createSprite("TestSprite")

            sprite.x = 0
            sprite.y = 0
            sprite.direction = 90

            local hatId, hatBlock = SB3Builder.Events.whenFlagClicked()
            local move1Id, move1Block = SB3Builder.Motion.moveSteps(10)  -- Move right 10
            local turn1Id, turn1Block = SB3Builder.Motion.turnRight(90)  -- Turn down
            local move2Id, move2Block = SB3Builder.Motion.moveSteps(5)   -- Move down 5
            local turn2Id, turn2Block = SB3Builder.Motion.turnLeft(90)   -- Turn right again
            local move3Id, move3Block = SB3Builder.Motion.moveSteps(15)  -- Move right 15

            SB3Builder.addBlock(sprite, hatId, hatBlock)
            SB3Builder.addBlock(sprite, move1Id, move1Block)
            SB3Builder.addBlock(sprite, turn1Id, turn1Block)
            SB3Builder.addBlock(sprite, move2Id, move2Block)
            SB3Builder.addBlock(sprite, turn2Id, turn2Block)
            SB3Builder.addBlock(sprite, move3Id, move3Block)
            SB3Builder.linkBlocks(sprite, {hatId, move1Id, turn1Id, move2Id, turn2Id, move3Id})

            local projectData = SB3Builder.createProject({stage, sprite})
            local project = ProjectModel:new(projectData, projectData.assets)
            local runtime = Runtime:new(project)
            runtime:initialize()

            runtime:broadcastGreenFlag()
            local maxIterations = 100
            local iterations = 0
            while #runtime:getActiveThreads() > 0 and iterations < maxIterations do
                runtime:update(1/60)
                iterations = iterations + 1
            end

            local spriteTarget = runtime:getSpriteTargetByName("TestSprite")
            expect(spriteTarget.x).to.equal(25)  -- 0 + 10 + 0 + 15 = 25
            expect(spriteTarget.y).to.equal(-5)  -- 0 + 0 + (-5) + 0 = -5
            expect(spriteTarget.direction).to.equal(90) -- Final direction
        end)
    end)
end)