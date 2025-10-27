-- Real test for warp mode inheritance
-- Verifies that warp mode is INHERITED from caller, not just from definition

local lust = require("tests.lust")
local describe, it, expect = lust.describe, lust.it, lust.expect

local SB3Builder = require("tests.sb3_builder")
local ProjectModel = require("parser.project_model")
local Runtime = require("vm.runtime")

describe("Warp Mode Inheritance - Real Behavior", function()
    it("should inherit warp mode from caller (warp caller -> non-warp callee should use warp)", function()
        SB3Builder.resetCounter()

        local stage = SB3Builder.createStage()
        local sprite = SB3Builder.createSprite("TestSprite")

        local varId = SB3Builder.addVariable(sprite, "counter", 0)

        -- Define NON-warp procedure "slowFunc" that has a loop with wait
        local slowDefId, slowDefBlock, slowProtoId, slowProtoBlock =
            SB3Builder.Procedures.definition("slowFunc", {}, {}, {}, false) -- NOT warp!

        -- Inside slowFunc: repeat 3 times { change counter by 1, wait 0.1 }
        local changeId, changeBlock = SB3Builder.Data.changeVariable("counter", 1, varId)
        local waitId, waitBlock = SB3Builder.Control.wait(0.1)
        local repeatId, repeatBlock = SB3Builder.Control.repeat_(3, changeId)

        SB3Builder.addBlock(sprite, slowProtoId, slowProtoBlock)
        SB3Builder.addBlock(sprite, slowDefId, slowDefBlock)
        SB3Builder.addBlock(sprite, repeatId, repeatBlock)
        SB3Builder.addBlock(sprite, changeId, changeBlock)
        SB3Builder.addBlock(sprite, waitId, waitBlock)
        SB3Builder.linkBlocks(sprite, {slowDefId, repeatId})
        SB3Builder.linkBlocks(sprite, {changeId, waitId})

        -- Define WARP procedure "fastFunc" that calls slowFunc
        local fastDefId, fastDefBlock, fastProtoId, fastProtoBlock =
            SB3Builder.Procedures.definition("fastFunc", {}, {}, {}, true) -- WARP!

        -- Call slowFunc (the key: this call should use WARP variant due to inheritance)
        local callSlowId, callSlowBlock =
            SB3Builder.Procedures.call("slowFunc", {}, {}, {}, {}, false) -- callee is NOT warp

        SB3Builder.addBlock(sprite, fastProtoId, fastProtoBlock)
        SB3Builder.addBlock(sprite, fastDefId, fastDefBlock)
        SB3Builder.addBlock(sprite, callSlowId, callSlowBlock)
        SB3Builder.linkBlocks(sprite, {fastDefId, callSlowId})

        -- Main script: call fastFunc
        local hatId, hatBlock = SB3Builder.Events.whenFlagClicked()
        local callFastId, callFastBlock =
            SB3Builder.Procedures.call("fastFunc", {}, {}, {}, {}, true)

        SB3Builder.addBlock(sprite, hatId, hatBlock)
        SB3Builder.addBlock(sprite, callFastId, callFastBlock)
        SB3Builder.linkBlocks(sprite, {hatId, callFastId})

        local projectJson = SB3Builder.createProject({stage, sprite})
        local project = ProjectModel:new(projectJson, {})
        local runtime = Runtime:new(project)
        runtime:initialize()

        runtime.compilerOptions = runtime.compilerOptions or {}
        runtime.compilerOptions.enabled = true

        runtime:broadcastGreenFlag()

        -- Run for multiple frames
        local maxIterations = 100
        local iterations = 0
        while #runtime:getActiveThreads() > 0 and iterations < maxIterations do
            runtime:update(1/60)
            iterations = iterations + 1
        end

        -- CRITICAL TEST:
        -- If warp inheritance works: should complete in ~2-3 frames (warp mode skips waits)
        -- If warp inheritance FAILS: would take many frames (3 waits * 0.1s = many frames)
        print("Iterations with warp inheritance: " .. iterations)
        expect(iterations <= 5).to.be(true) -- Should be very fast with warp

        -- Verify counter was incremented
        local spriteTarget = runtime:getSpriteTargetByName("TestSprite")
        local counterVar = nil
        for _, var in pairs(spriteTarget.variables) do
            if var.name == "counter" then
                counterVar = var
                break
            end
        end
        expect(counterVar).to_not.be(nil)
        expect(counterVar.value).to.equal(3)
    end)

    it("should NOT inherit warp mode when caller is not warp", function()
        SB3Builder.resetCounter()

        local stage = SB3Builder.createStage()
        local sprite = SB3Builder.createSprite("TestSprite")

        local varId = SB3Builder.addVariable(sprite, "counter", 0)

        -- Define NON-warp procedure "slowFunc" with waits
        local slowDefId, slowDefBlock, slowProtoId, slowProtoBlock =
            SB3Builder.Procedures.definition("slowFunc", {}, {}, {}, false)

        local changeId, changeBlock = SB3Builder.Data.changeVariable("counter", 1, varId)
        local waitId, waitBlock = SB3Builder.Control.wait(0.05)

        SB3Builder.addBlock(sprite, slowProtoId, slowProtoBlock)
        SB3Builder.addBlock(sprite, slowDefId, slowDefBlock)
        SB3Builder.addBlock(sprite, changeId, changeBlock)
        SB3Builder.addBlock(sprite, waitId, waitBlock)
        SB3Builder.linkBlocks(sprite, {slowDefId, changeId, waitId})

        -- Define NON-warp procedure "normalFunc" that calls slowFunc
        local normalDefId, normalDefBlock, normalProtoId, normalProtoBlock =
            SB3Builder.Procedures.definition("normalFunc", {}, {}, {}, false) -- NOT warp

        local callSlowId, callSlowBlock =
            SB3Builder.Procedures.call("slowFunc", {}, {}, {}, {}, false)

        SB3Builder.addBlock(sprite, normalProtoId, normalProtoBlock)
        SB3Builder.addBlock(sprite, normalDefId, normalDefBlock)
        SB3Builder.addBlock(sprite, callSlowId, callSlowBlock)
        SB3Builder.linkBlocks(sprite, {normalDefId, callSlowId})

        -- Main script: call normalFunc
        local hatId, hatBlock = SB3Builder.Events.whenFlagClicked()
        local callNormalId, callNormalBlock =
            SB3Builder.Procedures.call("normalFunc", {}, {}, {}, {}, false)

        SB3Builder.addBlock(sprite, hatId, hatBlock)
        SB3Builder.addBlock(sprite, callNormalId, callNormalBlock)
        SB3Builder.linkBlocks(sprite, {hatId, callNormalId})

        local projectJson = SB3Builder.createProject({stage, sprite})
        local project = ProjectModel:new(projectJson, {})
        local runtime = Runtime:new(project)
        runtime:initialize()

        runtime.compilerOptions = runtime.compilerOptions or {}
        runtime.compilerOptions.enabled = true

        runtime:broadcastGreenFlag()

        local maxIterations = 100
        local iterations = 0
        while #runtime:getActiveThreads() > 0 and iterations < maxIterations do
            runtime:update(1/60)
            iterations = iterations + 1
        end

        -- WITHOUT warp inheritance: should take more frames (wait actually waits)
        print("Iterations without warp: " .. iterations)
        expect(iterations > 2).to.be(true) -- Should take multiple frames

        local spriteTarget = runtime:getSpriteTargetByName("TestSprite")
        local counterVar = nil
        for _, var in pairs(spriteTarget.variables) do
            if var.name == "counter" then
                counterVar = var
                break
            end
        end
        expect(counterVar).to_not.be(nil)
        expect(counterVar.value).to.equal(1)
    end)
end)
