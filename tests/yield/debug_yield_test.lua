---Debug test to understand yield behavior
local lust = require("tests.lust")
local describe, it, expect = lust.describe, lust.it, lust.expect

local SB3Builder = require("tests.sb3_builder")
local ProjectModel = require("parser.project_model")
local Runtime = require("vm.runtime")

describe("Debug Yield Behavior", function()
    it("should show frame count for repeat loop", function()
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

        -- Check if script is warp mode
        local spriteTarget = runtime:getSpriteTargetByName("TestSprite")
        print("\n=== Debug Info ===")
        print("Sprite target found:", spriteTarget ~= nil)
        print("Turbo mode:", runtime.sequencer.turboMode)
        print("Redraw requested:", runtime.redrawRequested)

        runtime:broadcastGreenFlag()

        local frameCount = 0
        local maxFrames = 100
        while #runtime:getActiveThreads() > 0 and frameCount < maxFrames do
            local threadsBefore = #runtime:getActiveThreads()
            runtime:update(1/60)
            frameCount = frameCount + 1
            local threadsAfter = #runtime:getActiveThreads()

            -- Print info for first few frames
            if frameCount <= 15 then
                local counter = spriteTarget:lookupVariableByNameAndType("counter")
                print(string.format("Frame %d: counter=%s, threads before=%d, after=%d",
                    frameCount, tostring(counter.value), threadsBefore, threadsAfter))
            end
        end

        local counter = spriteTarget:lookupVariableByNameAndType("counter")
        print(string.format("Total frames: %d, Final counter: %s", frameCount, tostring(counter.value)))
        print("==================\n")

        expect(counter.value).to.equal(10)
    end)
end)

return lust
