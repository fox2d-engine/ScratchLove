-- Event Blocks Tests
-- Tests for event block implementations based on native Scratch tests

-- Import testing framework
local lust = require("tests.lust")
local describe, it, expect = lust.describe, lust.it, lust.expect

-- Import project components
local SB3Builder = require("tests.sb3_builder")
local ProjectModel = require("parser.project_model")
local Runtime = require("vm.runtime")
local Thread = require("vm.thread")

describe("Event Blocks", function()
    describe("Broadcast and Wait (#760 - broadcastAndWait)", function()
        it("matches native broadcastAndWait thread scheduling", function()
            -- NOTE: This test was for interpreter mode which has been removed.
            -- Broadcast and wait is now handled by the compiled execution model.
            -- Skip this test as it tests internal interpreter details.
        end)

        it("should yield when threads are active and continue when done", function()
            SB3Builder.resetCounter()
            local stage = SB3Builder.createStage()
            local broadcastId = SB3Builder.addBroadcast(stage, "test")
            local resultId = SB3Builder.addVariable(stage, "result", 0)

            -- Main script: broadcast and wait -> increment result
            local hat1Id, hat1Block = SB3Builder.Events.whenFlagClicked()
            local broadcastWaitId, broadcastWaitBlock = SB3Builder.Events.broadcastAndWait("test", broadcastId)
            local change1Id, change1Block = SB3Builder.Data.changeVariable("result", 1, resultId)

            -- Receiving script: wait briefly -> increment result
            local hat2Id, hat2Block = SB3Builder.Events.whenIReceive("test", broadcastId)
            local waitId, waitBlock = SB3Builder.Control.wait(0.01)
            local change2Id, change2Block = SB3Builder.Data.changeVariable("result", 10, resultId)

            SB3Builder.addBlock(stage, hat1Id, hat1Block)
            SB3Builder.addBlock(stage, broadcastWaitId, broadcastWaitBlock)
            SB3Builder.addBlock(stage, change1Id, change1Block)
            SB3Builder.addBlock(stage, hat2Id, hat2Block)
            SB3Builder.addBlock(stage, waitId, waitBlock)
            SB3Builder.addBlock(stage, change2Id, change2Block)

            SB3Builder.linkBlocks(stage, { hat1Id, broadcastWaitId, change1Id })
            SB3Builder.linkBlocks(stage, { hat2Id, waitId, change2Id })

            local projectJson = SB3Builder.createProject({ stage })
            local project = ProjectModel:new(projectJson, {})
            local runtime = Runtime:new(project)
            runtime:initialize()

            runtime:broadcastGreenFlag()

            -- Run until completion
            -- Safe execution with iteration limit to prevent infinite loops
            local maxIterations = 100
            local iterations = 0
            while #runtime:getActiveThreads() > 0 and iterations < maxIterations do
                runtime:update(1 / 60)
                iterations = iterations + 1
            end

            local result = runtime.stage:lookupVariableByNameAndType("result")
            -- Both changes should execute: receiving script (10) + main script continuation (1) = 11
            expect(result.value).to.equal(11)
        end)

        it("should restart done threads that are still in runtime", function()
            SB3Builder.resetCounter()
            local stage = SB3Builder.createStage()
            local broadcastId = SB3Builder.addBroadcast(stage, "restart")
            local countId = SB3Builder.addVariable(stage, "count", 0)

            -- Main script: broadcast and wait twice
            local hat1Id, hat1Block = SB3Builder.Events.whenFlagClicked()
            local broadcast1Id, broadcast1Block = SB3Builder.Events.broadcastAndWait("restart", broadcastId)
            local broadcast2Id, broadcast2Block = SB3Builder.Events.broadcastAndWait("restart", broadcastId)

            -- Receiving script: increment counter
            local hat2Id, hat2Block = SB3Builder.Events.whenIReceive("restart", broadcastId)
            local changeId, changeBlock = SB3Builder.Data.changeVariable("count", 1, countId)

            SB3Builder.addBlock(stage, hat1Id, hat1Block)
            SB3Builder.addBlock(stage, broadcast1Id, broadcast1Block)
            SB3Builder.addBlock(stage, broadcast2Id, broadcast2Block)
            SB3Builder.addBlock(stage, hat2Id, hat2Block)
            SB3Builder.addBlock(stage, changeId, changeBlock)

            SB3Builder.linkBlocks(stage, { hat1Id, broadcast1Id, broadcast2Id })
            SB3Builder.linkBlocks(stage, { hat2Id, changeId })

            local projectJson = SB3Builder.createProject({ stage })
            local project = ProjectModel:new(projectJson, {})
            local runtime = Runtime:new(project)
            runtime:initialize()

            runtime:broadcastGreenFlag()

            -- Safe execution with iteration limit to prevent infinite loops
            local maxIterations = 100
            local iterations = 0
            while #runtime:getActiveThreads() > 0 and iterations < maxIterations do
                runtime:update(1 / 60)
                iterations = iterations + 1
            end

            local count = runtime.stage:lookupVariableByNameAndType("count")
            -- Should execute receiving script twice (once for each broadcast)
            expect(count.value).to.equal(2)
        end)
    end)

    describe("When Greater Than (Hat) - Loudness", function()
        it("matches native predicate logic", function()
            -- NOTE: This test was for interpreter mode which has been removed.
            -- Event predicate logic is now handled by the compiled execution model.
            -- Skip this test as it tests internal interpreter details.
        end)
    end)

    describe("Basic Event Flow", function()
        it("should execute when flag clicked scripts", function()
            SB3Builder.resetCounter()
            local stage = SB3Builder.createStage()
            local countId = SB3Builder.addVariable(stage, "flagClicks", 0)

            local hatId, hatBlock = SB3Builder.Events.whenFlagClicked()
            local changeId, changeBlock = SB3Builder.Data.changeVariable("flagClicks", 1, countId)

            SB3Builder.addBlock(stage, hatId, hatBlock)
            SB3Builder.addBlock(stage, changeId, changeBlock)
            SB3Builder.linkBlocks(stage, { hatId, changeId })

            local projectJson = SB3Builder.createProject({ stage })
            local project = ProjectModel:new(projectJson, {})
            local runtime = Runtime:new(project)
            runtime:initialize()

            -- Execute green flag
            runtime:broadcastGreenFlag()
            -- Safe execution with iteration limit to prevent infinite loops
            local maxIterations = 100
            local iterations = 0
            while #runtime:getActiveThreads() > 0 and iterations < maxIterations do
                runtime:update(1 / 60)
                iterations = iterations + 1
            end

            local flagClicks = runtime.stage:lookupVariableByNameAndType("flagClicks")
            expect(flagClicks.value).to.equal(1)

            -- Execute again
            runtime:broadcastGreenFlag()
            -- Safe execution with iteration limit to prevent infinite loops
            local maxIterations = 100
            local iterations = 0
            while #runtime:getActiveThreads() > 0 and iterations < maxIterations do
                runtime:update(1 / 60)
                iterations = iterations + 1
            end

            flagClicks = runtime.stage:lookupVariableByNameAndType("flagClicks")
            expect(flagClicks.value).to.equal(2)
        end)

        it("should handle multiple broadcast receivers", function()
            SB3Builder.resetCounter()
            local stage = SB3Builder.createStage()
            local sprite1 = SB3Builder.createSprite("Sprite1")
            local sprite2 = SB3Builder.createSprite("Sprite2")
            local broadcastId = SB3Builder.addBroadcast(stage, "multi")
            local count1Id = SB3Builder.addVariable(stage, "count1", 0)
            local count2Id = SB3Builder.addVariable(stage, "count2", 0)

            -- Stage broadcasts
            local hat1Id, hat1Block = SB3Builder.Events.whenFlagClicked()
            local broadcastId1, broadcastBlock = SB3Builder.Events.broadcast("multi", broadcastId)

            -- Sprite1 receives and increments count1
            local hat2Id, hat2Block = SB3Builder.Events.whenIReceive("multi", broadcastId)
            local change1Id, change1Block = SB3Builder.Data.changeVariable("count1", 1, count1Id)

            -- Sprite2 receives and increments count2
            local hat3Id, hat3Block = SB3Builder.Events.whenIReceive("multi", broadcastId)
            local change2Id, change2Block = SB3Builder.Data.changeVariable("count2", 1, count2Id)

            SB3Builder.addBlock(stage, hat1Id, hat1Block)
            SB3Builder.addBlock(stage, broadcastId1, broadcastBlock)
            SB3Builder.addBlock(sprite1, hat2Id, hat2Block)
            SB3Builder.addBlock(sprite1, change1Id, change1Block)
            SB3Builder.addBlock(sprite2, hat3Id, hat3Block)
            SB3Builder.addBlock(sprite2, change2Id, change2Block)

            SB3Builder.linkBlocks(stage, { hat1Id, broadcastId1 })
            SB3Builder.linkBlocks(sprite1, { hat2Id, change1Id })
            SB3Builder.linkBlocks(sprite2, { hat3Id, change2Id })

            local projectJson = SB3Builder.createProject({ stage, sprite1, sprite2 })
            local project = ProjectModel:new(projectJson, {})
            local runtime = Runtime:new(project)
            runtime:initialize()

            runtime:broadcastGreenFlag()
            -- Safe execution with iteration limit to prevent infinite loops
            local maxIterations = 100
            local iterations = 0
            while #runtime:getActiveThreads() > 0 and iterations < maxIterations do
                runtime:update(1 / 60)
                iterations = iterations + 1
            end

            local count1 = runtime.stage:lookupVariableByNameAndType("count1")
            local count2 = runtime.stage:lookupVariableByNameAndType("count2")
            expect(count1.value).to.equal(1)
            expect(count2.value).to.equal(1)
        end)

        it("should handle key press events", function()
            SB3Builder.resetCounter()
            local stage = SB3Builder.createStage()
            local countId = SB3Builder.addVariable(stage, "spacePressed", 0)

            local hatId, hatBlock = SB3Builder.createBlock("event_whenkeypressed", {}, {
                KEY_OPTION = SB3Builder.field("space")
            })
            local changeId, changeBlock = SB3Builder.Data.changeVariable("spacePressed", 1, countId)

            SB3Builder.addBlock(stage, hatId, hatBlock)
            SB3Builder.addBlock(stage, changeId, changeBlock)
            SB3Builder.linkBlocks(stage, { hatId, changeId })

            local projectJson = SB3Builder.createProject({ stage })
            local project = ProjectModel:new(projectJson, {})
            local runtime = Runtime:new(project)
            runtime:initialize()

            -- Simulate space key press
            runtime:broadcastKeyForTest("space")
            -- Safe execution with iteration limit to prevent infinite loops
            local maxIterations = 100
            local iterations = 0
            while #runtime:getActiveThreads() > 0 and iterations < maxIterations do
                runtime:update(1 / 60)
                iterations = iterations + 1
            end

            local spacePressed = runtime.stage:lookupVariableByNameAndType("spacePressed")
            expect(spacePressed.value).to.equal(1)
        end)

        it("should handle sprite clicked events", function()
            SB3Builder.resetCounter()
            local stage = SB3Builder.createStage()
            local sprite = SB3Builder.createSprite("ClickableSprite")
            local countId = SB3Builder.addVariable(stage, "clicked", 0)

            local hatId, hatBlock = SB3Builder.createBlock("event_whenthisspriteclicked", {}, {})
            local changeId, changeBlock = SB3Builder.Data.changeVariable("clicked", 1, countId)

            SB3Builder.addBlock(sprite, hatId, hatBlock)
            SB3Builder.addBlock(sprite, changeId, changeBlock)
            SB3Builder.linkBlocks(sprite, { hatId, changeId })

            local projectJson = SB3Builder.createProject({ stage, sprite })
            local project = ProjectModel:new(projectJson, {})
            local runtime = Runtime:new(project)
            runtime:initialize()

            -- Simulate sprite click
            local spriteTarget = runtime:getSpriteTargetByName("ClickableSprite")
            runtime:broadcastSpriteClickForTest(spriteTarget)
            -- Safe execution with iteration limit to prevent infinite loops
            local maxIterations = 100
            local iterations = 0
            while #runtime:getActiveThreads() > 0 and iterations < maxIterations do
                runtime:update(1 / 60)
                iterations = iterations + 1
            end

            local clicked = runtime.stage:lookupVariableByNameAndType("clicked")
            expect(clicked.value).to.equal(1)
        end)
    end)

    describe("Event Edge Cases", function()
        it("should handle broadcast with empty message name", function()
            SB3Builder.resetCounter()
            local stage = SB3Builder.createStage()
            local emptyBroadcastId = SB3Builder.addBroadcast(stage, "")
            local resultId = SB3Builder.addVariable(stage, "received", false)

            -- Broadcast empty message
            local hat1Id, hat1Block = SB3Builder.Events.whenFlagClicked()
            local broadcastId, broadcastBlock = SB3Builder.Events.broadcast("", emptyBroadcastId)

            -- Receive empty message
            local hat2Id, hat2Block = SB3Builder.Events.whenIReceive("", emptyBroadcastId)
            local setId, setBlock = SB3Builder.Data.setVariable("received", true, resultId)

            SB3Builder.addBlock(stage, hat1Id, hat1Block)
            SB3Builder.addBlock(stage, broadcastId, broadcastBlock)
            SB3Builder.addBlock(stage, hat2Id, hat2Block)
            SB3Builder.addBlock(stage, setId, setBlock)

            SB3Builder.linkBlocks(stage, { hat1Id, broadcastId })
            SB3Builder.linkBlocks(stage, { hat2Id, setId })

            local projectJson = SB3Builder.createProject({ stage })
            local project = ProjectModel:new(projectJson, {})
            local runtime = Runtime:new(project)
            runtime:initialize()

            runtime:broadcastGreenFlag()
            -- Safe execution with iteration limit to prevent infinite loops
            local maxIterations = 100
            local iterations = 0
            while #runtime:getActiveThreads() > 0 and iterations < maxIterations do
                runtime:update(1 / 60)
                iterations = iterations + 1
            end

            local received = runtime.stage:lookupVariableByNameAndType("received")
            expect(received.value).to.equal("true")
        end)

        it("should handle non-existent broadcast message gracefully", function()
            SB3Builder.resetCounter()
            local stage = SB3Builder.createStage()
            local resultId = SB3Builder.addVariable(stage, "attempted", false)

            -- Try to broadcast non-existent message
            local hatId, hatBlock = SB3Builder.Events.whenFlagClicked()
            local setId, setBlock = SB3Builder.Data.setVariable("attempted", true, resultId)

            -- Create broadcast block with invalid/missing ID
            local broadcastId, broadcastBlock = SB3Builder.createBlock("event_broadcast", {
                BROADCAST_INPUT = SB3Builder.blockInput("BROADCAST_INPUT", "nonexistent")
            }, {})

            SB3Builder.addBlock(stage, hatId, hatBlock)
            SB3Builder.addBlock(stage, broadcastId, broadcastBlock)
            SB3Builder.addBlock(stage, setId, setBlock)
            SB3Builder.linkBlocks(stage, { hatId, broadcastId, setId })

            local projectJson = SB3Builder.createProject({ stage })
            local project = ProjectModel:new(projectJson, {})
            local runtime = Runtime:new(project)
            runtime:initialize()

            -- Should not crash when broadcasting non-existent message
            runtime:broadcastGreenFlag()
            -- Safe execution with iteration limit to prevent infinite loops
            local maxIterations = 100
            local iterations = 0
            while #runtime:getActiveThreads() > 0 and iterations < maxIterations do
                runtime:update(1 / 60)
                iterations = iterations + 1
            end

            local attempted = runtime.stage:lookupVariableByNameAndType("attempted")
            expect(attempted.value).to.equal("true")
        end)
    end)
end)
