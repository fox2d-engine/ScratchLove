-- Test loop execution efficiency
-- Verifies that data loops execute quickly without unnecessary frame yields

local lust = require("tests.lust")
local describe, it, expect = lust.describe, lust.it, lust.expect

local SB3Builder = require("tests.sb3_builder")
local ProjectModel = require("parser.project_model")
local Runtime = require("vm.runtime")

describe("Loop Execution Efficiency", function()
    describe("Data Loop Performance", function()
        it("should execute 100 data operations in single frame without redraw requests", function()
            SB3Builder.resetCounter()
            local stage = SB3Builder.createStage()

            -- Create a variable to modify
            local counterVar = SB3Builder.addVariable(stage, "counter", 0)

            local hatId, hatBlock = SB3Builder.Events.whenFlagClicked()

            -- Create a repeat loop that does 100 data operations
            local repeatId, repeatBlock = SB3Builder.Control.repeat_(100, nil)

            -- Change variable by 1 (data operation, no visual effect)
            local changeId, changeBlock = SB3Builder.Data.changeVariable("counter", 1, counterVar)

            -- Build the structure
            SB3Builder.addBlock(stage, hatId, hatBlock)
            SB3Builder.addBlock(stage, repeatId, repeatBlock)
            SB3Builder.addBlock(stage, changeId, changeBlock)

            -- Link blocks: hat -> repeat -> change variable
            SB3Builder.linkBlocks(stage, {hatId, repeatId})

            -- Set repeat block's substack to point to change variable
            local Core = require("tests.sb3_builder.core")
            repeatBlock.inputs.SUBSTACK = Core.substackInput(changeId)

            local projectJson = SB3Builder.createProject({stage})
            local project = ProjectModel:new(projectJson, {})
            local runtime = Runtime:new(project)
            runtime:initialize()

            -- Start execution
            runtime:broadcastGreenFlag()

            -- Track execution frames
            local frameCount = 0
            local maxFrames = 10  -- Should complete in much fewer frames

            while #runtime:getActiveThreads() > 0 and frameCount < maxFrames do
                runtime:update(1/60)
                frameCount = frameCount + 1
            end

            -- Verify the loop completed
            local counter = runtime.stage:lookupVariableByNameAndType("counter")
            expect(counter.value).to.equal(100)

            -- Verify it completed efficiently (should take 1-2 frames max)
            expect(frameCount < 5).to.be.truthy()
            print("Data loop completed in " .. frameCount .. " frames")
        end)

        it("should yield appropriately when visual operations are involved", function()
            SB3Builder.resetCounter()
            local stage = SB3Builder.createStage()
            local sprite = SB3Builder.createSprite("TestSprite")

            local hatId, hatBlock = SB3Builder.Events.whenFlagClicked()

            -- Create a repeat loop that does visual operations
            local repeatId, repeatBlock = SB3Builder.Control.repeat_(10, nil)

            -- Move steps (visual operation that triggers redraw)
            local moveId, moveBlock = SB3Builder.Motion.moveSteps(1)

            -- Build the structure
            SB3Builder.addBlock(sprite, hatId, hatBlock)
            SB3Builder.addBlock(sprite, repeatId, repeatBlock)
            SB3Builder.addBlock(sprite, moveId, moveBlock)

            -- Link blocks
            SB3Builder.linkBlocks(sprite, {hatId, repeatId})

            -- Set repeat block's substack
            local Core = require("tests.sb3_builder.core")
            repeatBlock.inputs.SUBSTACK = Core.substackInput(moveId)

            local projectJson = SB3Builder.createProject({stage, sprite})
            local project = ProjectModel:new(projectJson, {})
            local runtime = Runtime:new(project)
            runtime:initialize()

            runtime:broadcastGreenFlag()

            -- Track execution frames
            local frameCount = 0
            local maxFrames = 20

            while #runtime:getActiveThreads() > 0 and frameCount < maxFrames do
                runtime:update(1/60)
                frameCount = frameCount + 1
            end

            -- Verify movement completed
            local spriteTarget = runtime:getSpriteTargetByName("TestSprite")
            expect(spriteTarget.x).to.equal(10)

            -- Visual operations should take more frames due to yields
            expect(frameCount > 5).to.be.truthy()
            print("Visual loop completed in " .. frameCount .. " frames")
        end)

        it("should handle mixed data and visual operations efficiently", function()
            SB3Builder.resetCounter()
            local stage = SB3Builder.createStage()
            local sprite = SB3Builder.createSprite("TestSprite")

            -- Create variables
            local counterVar = SB3Builder.addVariable(stage, "counter", 0)

            local hatId, hatBlock = SB3Builder.Events.whenFlagClicked()

            -- First: 50 data operations
            local repeat1Id, repeat1Block = SB3Builder.Control.repeat_(50, nil)
            local change1Id, change1Block = SB3Builder.Data.changeVariable("counter", 1, counterVar)

            -- Then: 1 visual operation (should trigger redraw)
            local moveId, moveBlock = SB3Builder.Motion.moveSteps(10)

            -- Finally: 50 more data operations
            local repeat2Id, repeat2Block = SB3Builder.Control.repeat_(50, nil)
            local change2Id, change2Block = SB3Builder.Data.changeVariable("counter", 1, counterVar)

            -- Build structure
            SB3Builder.addBlock(sprite, hatId, hatBlock)
            SB3Builder.addBlock(sprite, repeat1Id, repeat1Block)
            SB3Builder.addBlock(sprite, change1Id, change1Block)
            SB3Builder.addBlock(sprite, moveId, moveBlock)
            SB3Builder.addBlock(sprite, repeat2Id, repeat2Block)
            SB3Builder.addBlock(sprite, change2Id, change2Block)

            -- Link blocks: hat -> repeat1 -> move -> repeat2
            SB3Builder.linkBlocks(sprite, {hatId, repeat1Id, moveId, repeat2Id})

            -- Set substacks
            local Core = require("tests.sb3_builder.core")
            repeat1Block.inputs.SUBSTACK = Core.substackInput(change1Id)
            repeat2Block.inputs.SUBSTACK = Core.substackInput(change2Id)

            local projectJson = SB3Builder.createProject({stage, sprite})
            local project = ProjectModel:new(projectJson, {})
            local runtime = Runtime:new(project)
            runtime:initialize()

            runtime:broadcastGreenFlag()

            -- Track execution
            local frameCount = 0
            local maxFrames = 10

            while #runtime:getActiveThreads() > 0 and frameCount < maxFrames do
                runtime:update(1/60)
                frameCount = frameCount + 1
            end

            -- Verify results
            local counter = runtime.stage:lookupVariableByNameAndType("counter")
            expect(counter.value).to.equal(100)

            local spriteTarget = runtime:getSpriteTargetByName("TestSprite")
            expect(spriteTarget.x).to.equal(10)

            -- Should complete in 2-4 frames (first 50 data ops + move trigger yield, then remaining)
            expect(frameCount >= 2 and frameCount <= 4).to.be.truthy()
            print("Mixed operations completed in " .. frameCount .. " frames")
        end)
    end)
end)