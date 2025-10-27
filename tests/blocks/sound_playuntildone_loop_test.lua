-- Sound Play Until Done in Loop Test
-- Verifies that playuntildone doesn't replay sound on every loop iteration

local lust = require("tests.lust")
local describe, it, expect = lust.describe, lust.it, lust.expect

local SB3Builder = require("tests.sb3_builder")
local ProjectModel = require("parser.project_model")
local Runtime = require("vm.runtime")
local AudioMock = require("tests.mocks.audio_mock")

describe("Sound playuntildone in Loops", function()
    it("should play sound only once per loop iteration when using playuntildone in forever loop", function()
        SB3Builder.resetCounter()
        local stage = SB3Builder.createStage()
        local sprite = SB3Builder.createSprite("TestSprite")
        local countVar = SB3Builder.addVariable(sprite, "count", 0)

        sprite.sounds = {
            {name = "test sound", assetId = "test_sound", dataFormat = "wav", duration = 0.05, source = AudioMock.createMockSource(0.05)}
        }

        -- Create: when flag clicked -> forever { play sound until done; change count by 1 }
        local hatId, hatBlock = SB3Builder.Events.whenFlagClicked()
        local playId, playBlock = SB3Builder.createBlock("sound_playuntildone", {}, {
            SOUND_MENU = SB3Builder.field("test sound")
        })
        local changeId, changeBlock = SB3Builder.Data.changeVariable("count", 1, countVar)

        SB3Builder.addBlock(sprite, hatId, hatBlock)
        SB3Builder.addBlock(sprite, playId, playBlock)
        SB3Builder.addBlock(sprite, changeId, changeBlock)
        SB3Builder.linkBlocks(sprite, {playId, changeId})

        local foreverIds, foreverBlock = SB3Builder.Control.forever(playId)
        SB3Builder.addBlock(sprite, foreverIds, foreverBlock)
        SB3Builder.linkBlocks(sprite, {hatId, foreverIds})

        local projectJson = SB3Builder.createProject({stage, sprite})
        local project = ProjectModel:new(projectJson, {})
        local runtime = Runtime:new(project)
        runtime:initialize()

        runtime:broadcastGreenFlag()

        -- Run for enough frames to let sound finish and loop execute a few times
        -- Sound duration is 0.05s = ~3 frames at 60fps
        local maxIterations = 30  -- ~0.5s = enough for ~2-3 sound completions
        local iterations = 0
        while iterations < maxIterations do
            runtime:update(1/60)
            iterations = iterations + 1
        end

        -- Get the count variable
        local spriteTarget = runtime:getSpriteTargetByName("TestSprite")
        local countVariable = spriteTarget:lookupVariableByNameAndType("count")

        -- Count should be approximately the number of times the sound finished
        -- With 0.05s duration and 0.5s runtime, we expect ~10 iterations
        -- But the important thing is that count should NOT be hundreds (which would happen if sound plays every frame)
        expect(countVariable.value < 100).to.be(true)  -- Should be < 100 (not hundreds/thousands)
        expect(countVariable.value > 0).to.be(true)    -- Should have executed at least once

        print(string.format("Sound playuntildone loop test: count = %s (expected ~10, should be < 100)", tostring(countVariable.value)))
    end)

    it("should not replay sound on each resume in repeat loop", function()
        SB3Builder.resetCounter()
        local stage = SB3Builder.createStage()
        local sprite = SB3Builder.createSprite("TestSprite")

        sprite.sounds = {
            {name = "test sound", assetId = "test_sound", dataFormat = "wav", duration = 0.05, source = AudioMock.createMockSource(0.05)}
        }

        -- Create: when flag clicked -> repeat 5 { play sound until done }
        local hatId, hatBlock = SB3Builder.Events.whenFlagClicked()
        local playId, playBlock = SB3Builder.createBlock("sound_playuntildone", {}, {
            SOUND_MENU = SB3Builder.field("test sound")
        })

        SB3Builder.addBlock(sprite, hatId, hatBlock)
        SB3Builder.addBlock(sprite, playId, playBlock)

        local repeatId, repeatBlock = SB3Builder.Control.repeat_(5, playId)
        SB3Builder.addBlock(sprite, repeatId, repeatBlock)
        SB3Builder.linkBlocks(sprite, {hatId, repeatId})

        local projectJson = SB3Builder.createProject({stage, sprite})
        local project = ProjectModel:new(projectJson, {})
        local runtime = Runtime:new(project)
        runtime:initialize()

        -- Track how many times playSound was called
        local originalPlaySound = runtime.audioEngine.playSound
        local playSoundCallCount = 0
        runtime.audioEngine.playSound = function(self, target, soundId, waitForDone)
            playSoundCallCount = playSoundCallCount + 1
            return originalPlaySound(self, target, soundId, waitForDone)
        end

        runtime:broadcastGreenFlag()

        -- Run until all threads complete or timeout
        local maxIterations = 100
        local iterations = 0
        while #runtime:getActiveThreads() > 0 and iterations < maxIterations do
            runtime:update(1/60)
            iterations = iterations + 1
        end

        -- Should have called playSound exactly 5 times (once per repeat iteration)
        -- NOT hundreds of times (once per frame)
        expect(playSoundCallCount).to.equal(5)

        print(string.format("Sound playuntildone repeat test: playSound called %d times (expected 5)", playSoundCallCount))
    end)
end)
