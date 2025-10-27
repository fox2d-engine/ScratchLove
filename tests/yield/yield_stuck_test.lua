-- Test for isStuck() and yield behavior improvements
-- Tests P0 priority fixes for yield mechanism

local lust = require("tests.lust")
local describe, it, expect = lust.describe, lust.it, lust.expect

local SB3Builder = require("tests.sb3_builder")
local ProjectModel = require("parser.project_model")
local Runtime = require("vm.runtime")

describe("Yield and Stuck Detection", function()

    describe("isStuck() mechanism", function()
        it("should initialize stuck counter correctly", function()
            SB3Builder.resetCounter()
            local stage = SB3Builder.createStage()
            local projectJson = SB3Builder.createProject({stage})
            local project = ProjectModel:new(projectJson, {})
            local runtime = Runtime:new(project)
            runtime:initialize()

            -- Verify initial state
            expect(runtime.stuckCounter).to.equal(0)
            expect(runtime.tickStartTime).to.equal(0)
        end)

        it("should reset stuck counter on each update", function()
            SB3Builder.resetCounter()
            local stage = SB3Builder.createStage()
            local projectJson = SB3Builder.createProject({stage})
            local project = ProjectModel:new(projectJson, {})
            local runtime = Runtime:new(project)
            runtime:initialize()

            -- Simulate stuck counter increment
            runtime.stuckCounter = 50

            -- Call update (should reset)
            runtime:update(1/60)

            expect(runtime.stuckCounter).to.equal(0)
        end)

        it("should detect stuck after 100 calls if time exceeded", function()
            SB3Builder.resetCounter()
            local stage = SB3Builder.createStage()
            local projectJson = SB3Builder.createProject({stage})
            local project = ProjectModel:new(projectJson, {})
            local runtime = Runtime:new(project)
            runtime:initialize()

            -- Reset counter to start fresh
            runtime:resetStuckCounter()

            -- Call isStuck 99 times - should not be stuck
            for i = 1, 99 do
                local result = runtime:isStuck()
                expect(result).to.equal(false)
            end

            -- On 100th call, it checks real time
            -- Since we just started, should not be stuck (< 500ms)
            local result = runtime:isStuck()
            expect(result).to.equal(false)
        end)
    end)

    describe("Wait 0 behavior", function()
        it("should yield at least once even for wait 0", function()
            SB3Builder.resetCounter()
            local stage = SB3Builder.createStage()
            local sprite = SB3Builder.createSprite("TestSprite")

            -- Create wait 0 script
            local hatId, hatBlock = SB3Builder.Events.whenFlagClicked()
            local waitId, waitBlock = SB3Builder.Control.wait(0)
            local setId, setBlock = SB3Builder.Data.setVariable("done", "yes", "variable1")

            SB3Builder.addBlock(sprite, hatId, hatBlock)
            SB3Builder.addBlock(sprite, waitId, waitBlock)
            SB3Builder.addBlock(sprite, setId, setBlock)
            SB3Builder.linkBlocks(sprite, {hatId, waitId, setId})

            -- Add variable
            sprite.variables = {
                variable1 = {"done", 0}
            }

            local projectJson = SB3Builder.createProject({stage, sprite})
            local project = ProjectModel:new(projectJson, {})
            local runtime = Runtime:new(project)
            runtime:initialize()

            -- Broadcast green flag
            runtime:broadcastGreenFlag()

            -- Should have active threads
            local activeThreads = #runtime:getActiveThreads()
            expect(activeThreads > 0).to.be.truthy()

            -- First update - thread should still be active (yielded at least once)
            runtime:update(1/30) -- Use logic frame time to ensure execution

            -- Variable should not be set yet (thread yielded)
            local spriteTarget = runtime:getSpriteTargetByName("TestSprite")
            local variable = spriteTarget.variables["variable1"]
            expect(variable.value).to_not.equal("yes")

            -- Second update - thread should complete
            runtime:update(1/30) -- Use logic frame time to ensure execution

            -- Now variable should be set
            expect(variable.value).to.equal("yes")
        end)
    end)

    describe("Warp mode with stuck detection", function()
        it("should allow warp mode loops without hanging", function()
            SB3Builder.resetCounter()
            local stage = SB3Builder.createStage()
            local sprite = SB3Builder.createSprite("TestSprite")

            -- Add variable first
            sprite.variables = {
                variable1 = {"counter", 0}
            }

            -- Build blocks bottom-up (innermost first)
            local changeId, changeBlock = SB3Builder.Data.changeVariable("counter", 1, "variable1")
            local repeatId, repeatBlock = SB3Builder.Control.repeat_(10, changeId)  -- Pass substack ID
            local allAtOnceId, allAtOnceBlock = SB3Builder.Control.allAtOnce(repeatId)  -- Pass substack ID
            local hatId, hatBlock = SB3Builder.Events.whenFlagClicked()

            -- Add all blocks to sprite
            SB3Builder.addBlock(sprite, hatId, hatBlock)
            SB3Builder.addBlock(sprite, allAtOnceId, allAtOnceBlock)
            SB3Builder.addBlock(sprite, repeatId, repeatBlock)
            SB3Builder.addBlock(sprite, changeId, changeBlock)

            -- Link only the top-level blocks (hat -> allAtOnce)
            SB3Builder.linkBlocks(sprite, {hatId, allAtOnceId})

            local projectJson = SB3Builder.createProject({stage, sprite})
            local project = ProjectModel:new(projectJson, {})
            local runtime = Runtime:new(project)
            runtime:initialize()

            -- Broadcast green flag
            runtime:broadcastGreenFlag()

            -- Run with iteration limit (warp mode should complete quickly)
            local maxIterations = 100
            local iterations = 0
            while #runtime:getActiveThreads() > 0 and iterations < maxIterations do
                runtime:update(1/60)
                iterations = iterations + 1
            end

            -- Verify counter was incremented
            local spriteTarget = runtime:getSpriteTargetByName("TestSprite")
            local variable = spriteTarget.variables["variable1"]
            expect(variable.value).to.equal(10)

            -- Verify it didn't take too many iterations (warp mode should be fast)
            local shouldComplete = iterations < 50
            expect(shouldComplete).to.be.truthy()
        end)
    end)
end)
