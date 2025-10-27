---Test suite for P2 yield improvements
---Verifies broadcast and wait allWaiting optimization and unified yield methods
local lust = require("tests.lust")
local describe, it, expect = lust.describe, lust.it, lust.expect

local SB3Builder = require("tests.sb3_builder")
local ProjectModel = require("parser.project_model")
local Runtime = require("vm.runtime")

describe("P2 Yield Improvements", function()
    describe("Broadcast and Wait - allWaiting Optimization", function()
        it("should complete broadcast and wait with waiting threads", function()
            SB3Builder.resetCounter()
            local stage = SB3Builder.createStage()
            local sprite1 = SB3Builder.createSprite("Sprite1")
            local sprite2 = SB3Builder.createSprite("Sprite2")

            local counterVar = SB3Builder.addVariable(sprite1, "counter", 0)
            local broadcastId = SB3Builder.addBroadcast(stage, "message")

            -- Sprite1: set counter=1, broadcast and wait, set counter=2
            local hat1, hatBlock1 = SB3Builder.Events.whenFlagClicked()
            local setVar1, setVarBlock1 = SB3Builder.Data.setVariable("counter", 1, counterVar)
            local broadcast1, broadcastBlock1 = SB3Builder.Events.broadcastAndWait("message", broadcastId)
            local setVar2, setVarBlock2 = SB3Builder.Data.setVariable("counter", 2, counterVar)

            SB3Builder.addBlock(sprite1, hat1, hatBlock1)
            SB3Builder.addBlock(sprite1, setVar1, setVarBlock1)
            SB3Builder.addBlock(sprite1, broadcast1, broadcastBlock1)
            SB3Builder.addBlock(sprite1, setVar2, setVarBlock2)
            SB3Builder.linkBlocks(sprite1, {hat1, setVar1, broadcast1, setVar2})

            -- Sprite2: receives broadcast, waits briefly
            local hat2, hatBlock2 = SB3Builder.Events.whenIReceive("message", broadcastId)
            local wait1, waitBlock1 = SB3Builder.Control.wait(0.01)

            SB3Builder.addBlock(sprite2, hat2, hatBlock2)
            SB3Builder.addBlock(sprite2, wait1, waitBlock1)
            SB3Builder.linkBlocks(sprite2, {hat2, wait1})

            local projectJson = SB3Builder.createProject({stage, sprite1, sprite2})
            local project = ProjectModel:new(projectJson, {})
            local runtime = Runtime:new(project)
            runtime:initialize()

            runtime:broadcastGreenFlag()

            local maxIterations = 200
            local iterations = 0
            while #runtime:getActiveThreads() > 0 and iterations < maxIterations do
                runtime:update(1/60)
                iterations = iterations + 1
            end

            -- Verify broadcast and wait completed (counter should be 2)
            local sprite1Target = runtime:getSpriteTargetByName("Sprite1")
            local counter = sprite1Target:lookupVariableByNameAndType("counter")
            expect(counter.value).to.equal(2)
        end)

        it("should complete broadcast and wait with multiple receivers", function()
            SB3Builder.resetCounter()
            local stage = SB3Builder.createStage()
            local sprite1 = SB3Builder.createSprite("Sprite1")
            local sprite2 = SB3Builder.createSprite("Sprite2")
            local sprite3 = SB3Builder.createSprite("Sprite3")

            local resultVar = SB3Builder.addVariable(sprite1, "result", 0)
            local broadcastId = SB3Builder.addBroadcast(stage, "test")

            -- Sprite1: broadcast and wait, then set result=100
            local hat1, hatBlock1 = SB3Builder.Events.whenFlagClicked()
            local broadcast1, broadcastBlock1 = SB3Builder.Events.broadcastAndWait("test", broadcastId)
            local setVar1, setVarBlock1 = SB3Builder.Data.setVariable("result", 100, resultVar)

            SB3Builder.addBlock(sprite1, hat1, hatBlock1)
            SB3Builder.addBlock(sprite1, broadcast1, broadcastBlock1)
            SB3Builder.addBlock(sprite1, setVar1, setVarBlock1)
            SB3Builder.linkBlocks(sprite1, {hat1, broadcast1, setVar1})

            -- Sprite2 and Sprite3: both wait on broadcast
            local hat2, hatBlock2 = SB3Builder.Events.whenIReceive("test", broadcastId)
            local wait2, waitBlock2 = SB3Builder.Control.wait(0.01)
            SB3Builder.addBlock(sprite2, hat2, hatBlock2)
            SB3Builder.addBlock(sprite2, wait2, waitBlock2)
            SB3Builder.linkBlocks(sprite2, {hat2, wait2})

            local hat3, hatBlock3 = SB3Builder.Events.whenIReceive("test", broadcastId)
            local wait3, waitBlock3 = SB3Builder.Control.wait(0.01)
            SB3Builder.addBlock(sprite3, hat3, hatBlock3)
            SB3Builder.addBlock(sprite3, wait3, waitBlock3)
            SB3Builder.linkBlocks(sprite3, {hat3, wait3})

            local projectJson = SB3Builder.createProject({stage, sprite1, sprite2, sprite3})
            local project = ProjectModel:new(projectJson, {})
            local runtime = Runtime:new(project)
            runtime:initialize()

            runtime:broadcastGreenFlag()

            local maxIterations = 200
            local iterations = 0
            while #runtime:getActiveThreads() > 0 and iterations < maxIterations do
                runtime:update(1/60)
                iterations = iterations + 1
            end

            -- Verify broadcast completed (result set to 100)
            local sprite1Target = runtime:getSpriteTargetByName("Sprite1")
            local result = sprite1Target:lookupVariableByNameAndType("result")
            expect(result.value).to.equal(100)
        end)
    end)

    describe("Unified Yield Methods", function()
        it("should use yieldLoop correctly in repeat loops", function()
            SB3Builder.resetCounter()
            local stage = SB3Builder.createStage()
            local sprite = SB3Builder.createSprite("TestSprite")

            local counterVar = SB3Builder.addVariable(sprite, "counter", 0)

            -- repeat 10 times { change counter by 1 }
            local hatId, hatBlock = SB3Builder.Events.whenFlagClicked()
            local changeId, changeBlock = SB3Builder.Data.changeVariable("counter", 1, counterVar)
            local repeatId, repeatBlock = SB3Builder.Control.repeat_(10, changeId)

            SB3Builder.addBlock(sprite, hatId, hatBlock)
            SB3Builder.addBlock(sprite, repeatId, repeatBlock)
            SB3Builder.addBlock(sprite, changeId, changeBlock)
            SB3Builder.linkBlocks(sprite, {hatId, repeatId})

            local projectJson = SB3Builder.createProject({stage, sprite})
            local project = ProjectModel:new(projectJson, {})
            local runtime = Runtime:new(project)
            runtime:initialize()

            runtime:broadcastGreenFlag()

            local maxIterations = 100
            local frameCount = 0
            while #runtime:getActiveThreads() > 0 and frameCount < maxIterations do
                runtime:update(1/30) -- Use logic frame time to ensure execution
                frameCount = frameCount + 1
            end

            -- Verify loop completed correctly
            local spriteTarget = runtime:getSpriteTargetByName("TestSprite")
            local counter = spriteTarget:lookupVariableByNameAndType("counter")
            expect(counter.value).to.equal(10)

            -- Pure computation loop should complete in 1 frame (no redraw requests)
            expect(frameCount).to.equal(1)
        end)

        it("should use yieldLoop correctly in repeat until loops", function()
            SB3Builder.resetCounter()
            local stage = SB3Builder.createStage()
            local sprite = SB3Builder.createSprite("TestSprite")

            local counterVar = SB3Builder.addVariable(sprite, "counter", 0)

            -- repeat until (counter > 5) { change counter by 1 }
            local hatId, hatBlock = SB3Builder.Events.whenFlagClicked()
            local changeId, changeBlock = SB3Builder.Data.changeVariable("counter", 1, counterVar)
            local variableId, variableBlock = SB3Builder.Data.variable("counter", counterVar)
            local condId, condBlock = SB3Builder.Operators.greaterThan(variableId, 5)
            local untilId, untilBlock = SB3Builder.Control.repeatUntil(condId, changeId)

            SB3Builder.addBlock(sprite, hatId, hatBlock)
            SB3Builder.addBlock(sprite, untilId, untilBlock)
            SB3Builder.addBlock(sprite, condId, condBlock)
            SB3Builder.addBlock(sprite, variableId, variableBlock)
            SB3Builder.addBlock(sprite, changeId, changeBlock)
            SB3Builder.linkBlocks(sprite, {hatId, untilId})

            local projectJson = SB3Builder.createProject({stage, sprite})
            local project = ProjectModel:new(projectJson, {})
            local runtime = Runtime:new(project)
            runtime:initialize()

            runtime:broadcastGreenFlag()

            local maxIterations = 100
            local frameCount = 0
            while #runtime:getActiveThreads() > 0 and frameCount < maxIterations do
                runtime:update(1/30) -- Use logic frame time to ensure execution
                frameCount = frameCount + 1
            end

            -- Verify loop completed correctly (counter > 5)
            local spriteTarget = runtime:getSpriteTargetByName("TestSprite")
            local counter = spriteTarget:lookupVariableByNameAndType("counter")
            expect(counter.value >= 6).to.be(true)

            -- Pure computation loop should complete in 1 frame (no redraw requests)
            expect(frameCount).to.equal(1)
        end)
    end)
end)

return lust
