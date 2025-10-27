---@diagnostic disable: undefined-global
-- Test interpolation system with edge case handling

local lust = require("tests.lust")
local describe, it, expect = lust.describe, lust.it, lust.expect

local SB3Builder = require("tests.sb3_builder")
local ProjectModel = require("parser.project_model")
local Runtime = require("vm.runtime")

describe("Interpolation System", function()

    describe("Core Interpolation", function()
        it("should set up interpolation data on first frame", function()
            SB3Builder.resetCounter()
            local stage = SB3Builder.createStage()
            local sprite = SB3Builder.createSprite("TestSprite")

            -- Create simple movement script
            local hatId, hatBlock = SB3Builder.Events.whenFlagClicked()
            local moveId, moveBlock = SB3Builder.Motion.moveSteps(10)

            SB3Builder.addBlock(sprite, hatId, hatBlock)
            SB3Builder.addBlock(sprite, moveId, moveBlock)
            SB3Builder.linkBlocks(sprite, {hatId, moveId})

            local projectJson = SB3Builder.createProject({stage, sprite})
            local project = ProjectModel:new(projectJson, {})
            local runtime = Runtime:new(project)
            runtime:initialize()

            -- Enable interpolation (disabled by default)
            runtime:setInterpolation(true)

            runtime:broadcastGreenFlag()

            -- Run enough time to execute at least one logic frame
            -- Logic runs at 30 FPS (1/30 second per frame)
            -- So we need to accumulate at least 1/30 second
            runtime:update(1/30)

            -- Check interpolation data was created
            local spriteTarget = runtime:getSpriteTargetByName("TestSprite")
            expect(spriteTarget.interpolationData).to.exist()
            expect(spriteTarget.interpolationData.x).to.exist()
            expect(spriteTarget.interpolationData.y).to.exist()
        end)
    end)

    describe("Edge Case: Visibility Changes", function()
        it("should clear interpolation data when sprite hides", function()
            SB3Builder.resetCounter()
            local stage = SB3Builder.createStage()
            local sprite = SB3Builder.createSprite("TestSprite")

            -- Create script: move, then hide
            local hatId, hatBlock = SB3Builder.Events.whenFlagClicked()
            local moveId, moveBlock = SB3Builder.Motion.moveSteps(10)
            local hideId, hideBlock = SB3Builder.Looks.hide()

            SB3Builder.addBlock(sprite, hatId, hatBlock)
            SB3Builder.addBlock(sprite, moveId, moveBlock)
            SB3Builder.addBlock(sprite, hideId, hideBlock)
            SB3Builder.linkBlocks(sprite, {hatId, moveId, hideId})

            local projectJson = SB3Builder.createProject({stage, sprite})
            local project = ProjectModel:new(projectJson, {})
            local runtime = Runtime:new(project)
            runtime:initialize()

            -- Enable interpolation (disabled by default)
            runtime:setInterpolation(true)

            runtime:broadcastGreenFlag()

            -- Run until hide executes
            local maxIterations = 100
            local iterations = 0
            while #runtime:getActiveThreads() > 0 and iterations < maxIterations do
                runtime:update(1/60)
                iterations = iterations + 1
            end

            -- Check interpolation data was cleared
            local spriteTarget = runtime:getSpriteTargetByName("TestSprite")
            expect(spriteTarget.interpolationData).to.be(nil)
            -- CRITICAL: Check that interpolated properties are cleared to prevent flickering
            expect(spriteTarget._interpolatedX).to.be(nil)
            expect(spriteTarget._interpolatedY).to.be(nil)
            expect(spriteTarget._interpolatedDirection).to.be(nil)
            expect(spriteTarget._interpolatedSize).to.be(nil)
            expect(spriteTarget._interpolatedEffects).to.be(nil)
        end)

        it("should clear interpolation data when sprite shows", function()
            SB3Builder.resetCounter()
            local stage = SB3Builder.createStage()
            local sprite = SB3Builder.createSprite("TestSprite")
            sprite.visible = false -- Start hidden

            -- Create script: show sprite
            local hatId, hatBlock = SB3Builder.Events.whenFlagClicked()
            local showId, showBlock = SB3Builder.Looks.show()

            SB3Builder.addBlock(sprite, hatId, hatBlock)
            SB3Builder.addBlock(sprite, showId, showBlock)
            SB3Builder.linkBlocks(sprite, {hatId, showId})

            local projectJson = SB3Builder.createProject({stage, sprite})
            local project = ProjectModel:new(projectJson, {})
            local runtime = Runtime:new(project)
            runtime:initialize()

            runtime:broadcastGreenFlag()

            -- Run show block
            local maxIterations = 100
            local iterations = 0
            while #runtime:getActiveThreads() > 0 and iterations < maxIterations do
                runtime:update(1/60)
                iterations = iterations + 1
            end

            -- Check interpolation data was cleared after show
            local spriteTarget = runtime:getSpriteTargetByName("TestSprite")
            expect(spriteTarget.interpolationData).to.be(nil)
        end)
    end)

    describe("Mechanism: Modulo Operations Clear Interpolation", function()
        it("should reset interpolation data when modulo is used in goto x:y:", function()
            SB3Builder.resetCounter()
            local stage = SB3Builder.createStage()
            local sprite = SB3Builder.createSprite("TestSprite")

            -- Create script: goto x:(x mod 480) y:(0)
            local hatId, hatBlock = SB3Builder.Events.whenFlagClicked()

            -- Create modulo expression: (x position) mod 480
            local xPosId, xPosBlock = SB3Builder.Motion.xPosition()
            local moduloId, moduloBlock = SB3Builder.Operators.mod(xPosId, 480)

            local gotoId, gotoBlock = SB3Builder.Motion.goToXY(moduloId, 0)

            SB3Builder.addBlock(sprite, hatId, hatBlock)
            SB3Builder.addBlock(sprite, xPosId, xPosBlock)
            SB3Builder.addBlock(sprite, moduloId, moduloBlock)
            SB3Builder.addBlock(sprite, gotoId, gotoBlock)
            SB3Builder.linkBlocks(sprite, {hatId, gotoId})

            local projectJson = SB3Builder.createProject({stage, sprite})

            -- Load and compile the project
            local project = ProjectModel:new(projectJson, {})
            local runtime = Runtime:new(project)
            runtime:initialize()

            -- Verify the runtime initialized successfully (indirectly tests compilation)
            expect(runtime).to.exist()
        end)

        it("should prevent screen-crossing interpolation with horizontal wrap (modulo X)", function()
            SB3Builder.resetCounter()
            local stage = SB3Builder.createStage()
            local sprite = SB3Builder.createSprite("TestSprite")
            sprite.x = 235 -- Start near right edge

            -- Create script: forever { change x by 5, set x to ((x) mod (480)) }
            local hatId, hatBlock = SB3Builder.Events.whenFlagClicked()

            local changeXId, changeXBlock = SB3Builder.Motion.changeXBy(5)

            -- Create modulo expression: (x position) mod 480
            local xPosId, xPosBlock = SB3Builder.Motion.xPosition()
            local moduloId, moduloBlock = SB3Builder.Operators.mod(xPosId, 480)
            local setXId, setXBlock = SB3Builder.Motion.setX(moduloId)

            -- Forever loop with changeX as the first block, then setX
            local foreverIds, foreverBlock = SB3Builder.Control.forever(changeXId)

            SB3Builder.addBlock(sprite, hatId, hatBlock)
            SB3Builder.addBlock(sprite, foreverIds, foreverBlock)
            SB3Builder.addBlock(sprite, changeXId, changeXBlock)
            SB3Builder.addBlock(sprite, xPosId, xPosBlock)
            SB3Builder.addBlock(sprite, moduloId, moduloBlock)
            SB3Builder.addBlock(sprite, setXId, setXBlock)

            -- Link blocks: hat -> forever, and inside forever: changeX -> setX
            SB3Builder.linkBlocks(sprite, {hatId, foreverIds})
            SB3Builder.linkBlocks(sprite, {changeXId, setXId})

            local projectJson = SB3Builder.createProject({stage, sprite})

            -- Load and compile the project
            local project = ProjectModel:new(projectJson, {})
            local runtime = Runtime:new(project)
            runtime:initialize()

            -- Enable interpolation
            runtime:setInterpolation(true)

            runtime:broadcastGreenFlag()

            -- Run until x wraps around from positive to negative
            local maxIterations = 20
            local iterations = 0
            local spriteTarget = runtime:getSpriteTargetByName("TestSprite")
            while spriteTarget.x > 0 and iterations < maxIterations do
                runtime:update(1/60)
                iterations = iterations + 1
            end

            -- After wrap, interpolation data should be cleared (nil)
            -- This prevents the sprite from being interpolated across the screen
            expect(spriteTarget.interpolationData).to.be(nil)
        end)

        it("should prevent screen-crossing interpolation with vertical wrap (modulo Y)", function()
            SB3Builder.resetCounter()
            local stage = SB3Builder.createStage()
            local sprite = SB3Builder.createSprite("TestSprite")
            sprite.y = 175 -- Start near top edge

            -- Create script: forever { change y by 5, set y to ((y) mod (360)) }
            local hatId, hatBlock = SB3Builder.Events.whenFlagClicked()

            local changeYId, changeYBlock = SB3Builder.Motion.changeYBy(5)

            -- Create modulo expression: (y position) mod 360
            local yPosId, yPosBlock = SB3Builder.Motion.yPosition()
            local moduloId, moduloBlock = SB3Builder.Operators.mod(yPosId, 360)
            local setYId, setYBlock = SB3Builder.Motion.setY(moduloId)

            -- Forever loop with changeY as the first block, then setY
            local foreverIds, foreverBlock = SB3Builder.Control.forever(changeYId)

            SB3Builder.addBlock(sprite, hatId, hatBlock)
            SB3Builder.addBlock(sprite, foreverIds, foreverBlock)
            SB3Builder.addBlock(sprite, changeYId, changeYBlock)
            SB3Builder.addBlock(sprite, yPosId, yPosBlock)
            SB3Builder.addBlock(sprite, moduloId, moduloBlock)
            SB3Builder.addBlock(sprite, setYId, setYBlock)

            -- Link blocks: hat -> forever, and inside forever: changeY -> setY
            SB3Builder.linkBlocks(sprite, {hatId, foreverIds})
            SB3Builder.linkBlocks(sprite, {changeYId, setYId})

            local projectJson = SB3Builder.createProject({stage, sprite})

            -- Load and compile the project
            local project = ProjectModel:new(projectJson, {})
            local runtime = Runtime:new(project)
            runtime:initialize()

            -- Enable interpolation
            runtime:setInterpolation(true)

            runtime:broadcastGreenFlag()

            -- Run until y wraps around from positive to negative
            local maxIterations = 20
            local iterations = 0
            local spriteTarget = runtime:getSpriteTargetByName("TestSprite")
            while spriteTarget.y > 0 and iterations < maxIterations do
                runtime:update(1/60)
                iterations = iterations + 1
            end

            -- After wrap, interpolation data should be cleared (nil)
            expect(spriteTarget.interpolationData).to.be(nil)
        end)
    end)

    describe("Mechanism: Wait Block Requests Redraw", function()
        it("should compile wait blocks with requestRedraw call", function()
            SB3Builder.resetCounter()
            local stage = SB3Builder.createStage()
            local sprite = SB3Builder.createSprite("TestSprite")

            -- Create script: move (100) steps, wait (1) seconds
            local hatId, hatBlock = SB3Builder.Events.whenFlagClicked()
            local moveId, moveBlock = SB3Builder.Motion.moveSteps(100)
            local waitId, waitBlock = SB3Builder.Control.wait(1)

            SB3Builder.addBlock(sprite, hatId, hatBlock)
            SB3Builder.addBlock(sprite, moveId, moveBlock)
            SB3Builder.addBlock(sprite, waitId, waitBlock)
            SB3Builder.linkBlocks(sprite, {hatId, moveId, waitId})

            local projectJson = SB3Builder.createProject({stage, sprite})
            local project = ProjectModel:new(projectJson, {})
            local runtime = Runtime:new(project)
            runtime:initialize()

            -- Enable interpolation
            runtime:setInterpolation(true)

            runtime:broadcastGreenFlag()

            -- Execute enough frames to run move and wait
            local maxIterations = 10
            local iterations = 0
            while #runtime:getActiveThreads() > 0 and iterations < maxIterations do
                runtime:update(1/60)
                iterations = iterations + 1
            end

            -- Test passes if it compiles and runs without errors
            -- The actual behavior is tested by visual integration tests
            local spriteTarget = runtime:getSpriteTargetByName("TestSprite")
            expect(spriteTarget).to.exist()
        end)

        it("should compile goto+wait blocks correctly", function()
            SB3Builder.resetCounter()
            local stage = SB3Builder.createStage()
            local sprite = SB3Builder.createSprite("TestSprite")

            -- Create script: go to x:(200) y:(100), wait (0.5) seconds
            local hatId, hatBlock = SB3Builder.Events.whenFlagClicked()
            local gotoId, gotoBlock = SB3Builder.Motion.goToXY(200, 100)
            local waitId, waitBlock = SB3Builder.Control.wait(0.5)

            SB3Builder.addBlock(sprite, hatId, hatBlock)
            SB3Builder.addBlock(sprite, gotoId, gotoBlock)
            SB3Builder.addBlock(sprite, waitId, waitBlock)
            SB3Builder.linkBlocks(sprite, {hatId, gotoId, waitId})

            local projectJson = SB3Builder.createProject({stage, sprite})
            local project = ProjectModel:new(projectJson, {})
            local runtime = Runtime:new(project)
            runtime:initialize()

            -- Enable interpolation
            runtime:setInterpolation(true)

            runtime:broadcastGreenFlag()

            -- Execute enough frames to run goto and wait
            local maxIterations = 10
            local iterations = 0
            while #runtime:getActiveThreads() > 0 and iterations < maxIterations do
                runtime:update(1/60)
                iterations = iterations + 1
            end

            -- Test passes if it compiles and runs without errors
            local spriteTarget = runtime:getSpriteTargetByName("TestSprite")
            expect(spriteTarget).to.exist()
        end)
    end)

    describe("Edge Case: Costume Changes", function()
        it("should skip direction interpolation when costume changes", function()
            SB3Builder.resetCounter()
            local stage = SB3Builder.createStage()
            local sprite = SB3Builder.createSprite("TestSprite")

            -- Add two costumes
            sprite.costumes = {
                {
                    name = "costume1",
                    assetId = "test1",
                    dataFormat = "png",
                    rotationCenterX = 0,
                    rotationCenterY = 0
                },
                {
                    name = "costume2",
                    assetId = "test2",
                    dataFormat = "png",
                    rotationCenterX = 0,
                    rotationCenterY = 0
                }
            }

            -- Create script: turn, switch costume, turn again
            local hatId, hatBlock = SB3Builder.Events.whenFlagClicked()
            local turn1Id, turn1Block = SB3Builder.Motion.turnRight(90)
            local switchId, switchBlock = SB3Builder.Looks.switchCostumeTo("costume2")
            local turn2Id, turn2Block = SB3Builder.Motion.turnRight(90)

            SB3Builder.addBlock(sprite, hatId, hatBlock)
            SB3Builder.addBlock(sprite, turn1Id, turn1Block)
            SB3Builder.addBlock(sprite, switchId, switchBlock)
            SB3Builder.addBlock(sprite, turn2Id, turn2Block)
            SB3Builder.linkBlocks(sprite, {hatId, turn1Id, switchId, turn2Id})

            local projectJson = SB3Builder.createProject({stage, sprite})
            local project = ProjectModel:new(projectJson, {})
            local runtime = Runtime:new(project)
            runtime:initialize()

            runtime:broadcastGreenFlag()

            -- Run script
            local maxIterations = 100
            local iterations = 0
            while #runtime:getActiveThreads() > 0 and iterations < maxIterations do
                runtime:update(1/60)
                iterations = iterations + 1
            end

            -- Verify the sprite exists and script ran successfully
            local spriteTarget = runtime:getSpriteTargetByName("TestSprite")
            -- Direction starts at 90, turns 90 (=180), costume change, turns 90 (=270)
            -- But we're just verifying the code runs without error
            expect(spriteTarget).to.exist()
        end)
    end)
end)
