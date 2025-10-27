-- Sound Blocks Tests
-- Tests for sound block implementations

-- Import testing framework
local lust = require("tests.lust")
local describe, it, expect = lust.describe, lust.it, lust.expect

-- Import project components
local SB3Builder = require("tests.sb3_builder")
local ProjectModel = require("parser.project_model")
local Runtime = require("vm.runtime")
local AudioMock = require("tests.mocks.audio_mock")

describe("Sound Blocks", function()
    describe("Sound Selection and Playback", function()
        it("should play sound by name string", function()
            SB3Builder.resetCounter()
            local stage = SB3Builder.createStage()
            local sprite = SB3Builder.createSprite("TestSprite")

            -- Add sounds to sprite
            sprite.sounds = {
                {name = "first name", assetId = "first assetId", playing = false, source = AudioMock.createMockSource(1.0)},
                {name = "second name", assetId = "second assetId", playing = false, source = AudioMock.createMockSource(1.0)},
                {name = "third name", assetId = "third assetId", playing = false, source = AudioMock.createMockSource(1.0)},
                {name = "6", assetId = "fourth assetId", playing = false, source = AudioMock.createMockSource(1.0)}
            }

            -- Create script: when flag clicked -> play sound "second name"
            local hatId, hatBlock = SB3Builder.Events.whenFlagClicked()
            local playId, playBlock = SB3Builder.createBlock("sound_play", {}, {
                SOUND_MENU = SB3Builder.field("second name")
            })

            SB3Builder.addBlock(sprite, hatId, hatBlock)
            SB3Builder.addBlock(sprite, playId, playBlock)
            SB3Builder.linkBlocks(sprite, {hatId, playId})

            local projectJson = SB3Builder.createProject({stage, sprite})
            local project = ProjectModel:new(projectJson, {})
            local runtime = Runtime:new(project)
            runtime:initialize()

            runtime:broadcastGreenFlag()
            -- Safe execution with iteration limit
            local maxIterations = 100
            local iterations = 0
            while #runtime:getActiveThreads() > 0 and iterations < maxIterations do
                runtime:update(1/60)
                iterations = iterations + 1
            end

            -- Verify sound was registered in audio manager (global soundId registry)
            expect(runtime.audioEngine.soundPlayers["second assetId"]).to.exist()
        end)

        it("should play sound by number string 1-indexed", function()
            SB3Builder.resetCounter()
            local stage = SB3Builder.createStage()
            local sprite = SB3Builder.createSprite("TestSprite")

            sprite.sounds = {
                {name = "first name", assetId = "first assetId", playing = false, source = AudioMock.createMockSource(1.0)},
                {name = "second name", assetId = "second assetId", playing = false, source = AudioMock.createMockSource(1.0)},
                {name = "third name", assetId = "third assetId", playing = false, source = AudioMock.createMockSource(1.0)},
                {name = "6", assetId = "fourth assetId", playing = false, source = AudioMock.createMockSource(1.0)}
            }

            -- Test various string number indices
            local hatId, hatBlock = SB3Builder.Events.whenFlagClicked()
            local play1Id, play1Block = SB3Builder.createBlock("sound_play", {}, {
                SOUND_MENU = SB3Builder.field("1") -- Should play first sound
            })
            local play5Id, play5Block = SB3Builder.createBlock("sound_play", {}, {
                SOUND_MENU = SB3Builder.field("5") -- Should wrap to first sound
            })
            local play0Id, play0Block = SB3Builder.createBlock("sound_play", {}, {
                SOUND_MENU = SB3Builder.field("0") -- Should play last sound (4th)
            })

            SB3Builder.addBlock(sprite, hatId, hatBlock)
            SB3Builder.addBlock(sprite, play1Id, play1Block)
            SB3Builder.addBlock(sprite, play5Id, play5Block)
            SB3Builder.addBlock(sprite, play0Id, play0Block)
            SB3Builder.linkBlocks(sprite, {hatId, play1Id, play5Id, play0Id})

            local projectJson = SB3Builder.createProject({stage, sprite})
            local project = ProjectModel:new(projectJson, {})
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
            -- Verify sounds were registered through AudioManager (global soundId registry)
            expect(runtime.audioEngine.soundPlayers["first assetId"]).to.exist()
            expect(runtime.audioEngine.soundPlayers["fourth assetId"]).to.exist()
        end)

        it("should prioritize sound index when given numeric value", function()
            SB3Builder.resetCounter()
            local stage = SB3Builder.createStage()
            local sprite = SB3Builder.createSprite("TestSprite")

            sprite.sounds = {
                {name = "first", assetId = "first assetId", playing = false, source = AudioMock.createMockSource(1.0)},
                {name = "second", assetId = "second assetId", playing = false, source = AudioMock.createMockSource(1.0)},
                {name = "third", assetId = "third assetId", playing = false, source = AudioMock.createMockSource(1.0)},
                {name = "6", assetId = "fourth assetId", playing = false, source = AudioMock.createMockSource(1.0)}
            }

            -- Play sound using numeric index 6 - should wrap to second sound, not find name "6"
            local hatId, hatBlock = SB3Builder.Events.whenFlagClicked()
            -- Note: In actual implementation, need to handle numeric vs string differently
            -- This tests the index wrapping behavior when using actual numbers

            local projectJson = SB3Builder.createProject({stage, sprite})
            local project = ProjectModel:new(projectJson, {})
            local runtime = Runtime:new(project)
            runtime:initialize()

            -- Test via direct block execution to verify index wrapping
            local BlockHelpers = require("runtime.block_helpers")
            local spriteTarget = runtime:getSpriteTargetByName("TestSprite")

            -- Test numeric index 6 (should wrap to index 2, the second sound)
            BlockHelpers.Sound.play(spriteTarget, {SOUND_MENU = 6}, runtime, nil)

            -- Verify sound was registered through AudioManager (global soundId registry)
            expect(runtime.audioEngine.soundPlayers["second assetId"]).to.exist()
        end)

        it("should prioritize sound name when given string value", function()
            SB3Builder.resetCounter()
            local stage = SB3Builder.createStage()
            local sprite = SB3Builder.createSprite("TestSprite")

            sprite.sounds = {
                {name = "first", assetId = "first assetId", playing = false, source = AudioMock.createMockSource(1.0)},
                {name = "second", assetId = "second assetId", playing = false, source = AudioMock.createMockSource(1.0)},
                {name = "third", assetId = "third assetId", playing = false, source = AudioMock.createMockSource(1.0)},
                {name = "6", assetId = "fourth assetId", playing = false, source = AudioMock.createMockSource(1.0)}
            }

            local hatId, hatBlock = SB3Builder.Events.whenFlagClicked()
            local playId, playBlock = SB3Builder.createBlock("sound_play", {}, {
                SOUND_MENU = SB3Builder.field("6") -- Should find sound named "6", not index 6
            })

            SB3Builder.addBlock(sprite, hatId, hatBlock)
            SB3Builder.addBlock(sprite, playId, playBlock)
            SB3Builder.linkBlocks(sprite, {hatId, playId})

            local projectJson = SB3Builder.createProject({stage, sprite})
            local project = ProjectModel:new(projectJson, {})
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
            -- Should play the sound named "6" (fourth sound), not wrap index 6
            expect(runtime.audioEngine.soundPlayers["fourth assetId"]).to.exist()
        end)
    end)

    describe("Play Until Done", function()
        it("should wait for sound to finish with play until done", function()
            SB3Builder.resetCounter()
            local stage = SB3Builder.createStage()
            local sprite = SB3Builder.createSprite("TestSprite")
            local variableId = SB3Builder.addVariable(sprite, "finished", false)

            sprite.sounds = {
                {name = "test sound", assetId = "test", playing = false, duration = 0.1, source = AudioMock.createMockSource(0.1)} -- 0.1 second
            }

            local hatId, hatBlock = SB3Builder.Events.whenFlagClicked()
            local playId, playBlock = SB3Builder.createBlock("sound_playuntildone", {}, {
                SOUND_MENU = SB3Builder.field("test sound")
            })
            local setId, setBlock = SB3Builder.Data.setVariable("finished", true, variableId)

            SB3Builder.addBlock(sprite, hatId, hatBlock)
            SB3Builder.addBlock(sprite, playId, playBlock)
            SB3Builder.addBlock(sprite, setId, setBlock)
            SB3Builder.linkBlocks(sprite, {hatId, playId, setId})

            local projectJson = SB3Builder.createProject({stage, sprite})
            local project = ProjectModel:new(projectJson, {})
            local runtime = Runtime:new(project)
            runtime:initialize()

            runtime:broadcastGreenFlag()

            -- Complete execution - the "wait" should happen during execution
            local maxIterations = 100
            local iterations = 0
            while #runtime:getActiveThreads() > 0 and iterations < maxIterations do
                runtime:update(1/60)
                iterations = iterations + 1
            end

            -- Variable should be true after sound finishes and execution completes
            local spriteTarget = runtime:getSpriteTargetByName("TestSprite")
            local finished = spriteTarget:lookupVariableByNameAndType("finished")
            expect(finished.value).to.equal("true")
        end)
    end)

    describe("Stop All Sounds", function()
        it("should stop all sounds across all sprites", function()
            SB3Builder.resetCounter()
            local stage = SB3Builder.createStage()
            local sprite1 = SB3Builder.createSprite("Sprite1")
            local sprite2 = SB3Builder.createSprite("Sprite2")

            sprite1.sounds = {
                {name = "sound1", assetId = "sound1", playing = true}
            }
            sprite2.sounds = {
                {name = "sound2", assetId = "sound2", playing = true}
            }

            local hatId, hatBlock = SB3Builder.Events.whenFlagClicked()
            local stopId, stopBlock = SB3Builder.createBlock("sound_stopallsounds", {}, {})

            SB3Builder.addBlock(stage, hatId, hatBlock)
            SB3Builder.addBlock(stage, stopId, stopBlock)
            SB3Builder.linkBlocks(stage, {hatId, stopId})

            local projectJson = SB3Builder.createProject({stage, sprite1, sprite2})
            local project = ProjectModel:new(projectJson, {})
            local runtime = Runtime:new(project)
            runtime:initialize()

            runtime:broadcastGreenFlag()
            local maxIterations = 100
            local iterations = 0
            while #runtime:getActiveThreads() > 0 and iterations < maxIterations do
                runtime:update(1/60)
                iterations = iterations + 1
            end

            -- All sounds should be stopped - verify through AudioEngine
            local sprite1Target = runtime:getSpriteTargetByName("Sprite1")
            local sprite2Target = runtime:getSpriteTargetByName("Sprite2")

            -- Verify all sounds have been stopped (no playing sounds)
            expect(runtime.audioEngine.playingSounds[sprite1Target]).to.be(nil)
            expect(runtime.audioEngine.playingSounds[sprite2Target]).to.be(nil)
            expect(runtime.audioEngine:hasWaitingSounds(sprite1Target)).to.equal(false)
            expect(runtime.audioEngine:hasWaitingSounds(sprite2Target)).to.equal(false)
        end)
    end)

    describe("Volume Control", function()
        it("should set volume correctly", function()
            SB3Builder.resetCounter()
            local stage = SB3Builder.createStage()
            local sprite = SB3Builder.createSprite("TestSprite")
            sprite.volume = 100 -- Default volume

            local hatId, hatBlock = SB3Builder.Events.whenFlagClicked()
            local setVolumeId, setVolumeBlock = SB3Builder.createBlock("sound_setvolumeto", {
                VOLUME = SB3Builder.primitiveInput(75)
            }, {})

            SB3Builder.addBlock(sprite, hatId, hatBlock)
            SB3Builder.addBlock(sprite, setVolumeId, setVolumeBlock)
            SB3Builder.linkBlocks(sprite, {hatId, setVolumeId})

            local projectJson = SB3Builder.createProject({stage, sprite})
            local project = ProjectModel:new(projectJson, {})
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
            expect(spriteTarget.volume).to.equal(75)
        end)

        it("should change volume by amount", function()
            SB3Builder.resetCounter()
            local stage = SB3Builder.createStage()
            local sprite = SB3Builder.createSprite("TestSprite")
            sprite.volume = 50 -- Starting volume

            local hatId, hatBlock = SB3Builder.Events.whenFlagClicked()
            local changeVolumeId, changeVolumeBlock = SB3Builder.createBlock("sound_changevolumeby", {
                VOLUME = SB3Builder.primitiveInput(25)
            }, {})

            SB3Builder.addBlock(sprite, hatId, hatBlock)
            SB3Builder.addBlock(sprite, changeVolumeId, changeVolumeBlock)
            SB3Builder.linkBlocks(sprite, {hatId, changeVolumeId})

            local projectJson = SB3Builder.createProject({stage, sprite})
            local project = ProjectModel:new(projectJson, {})
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
            expect(spriteTarget.volume).to.equal(75) -- 50 + 25 = 75
        end)

        it("should clamp volume within valid range", function()
            SB3Builder.resetCounter()
            local stage = SB3Builder.createStage()
            local sprite = SB3Builder.createSprite("TestSprite")
            sprite.volume = 80

            local hatId, hatBlock = SB3Builder.Events.whenFlagClicked()
            local changeUpId, changeUpBlock = SB3Builder.createBlock("sound_changevolumeby", {
                VOLUME = SB3Builder.primitiveInput(50) -- Would go to 130, should clamp to 100
            }, {})
            local changeDownId, changeDownBlock = SB3Builder.createBlock("sound_changevolumeby", {
                VOLUME = SB3Builder.primitiveInput(-150) -- Would go to -50, should clamp to 0
            }, {})

            SB3Builder.addBlock(sprite, hatId, hatBlock)
            SB3Builder.addBlock(sprite, changeUpId, changeUpBlock)
            SB3Builder.addBlock(sprite, changeDownId, changeDownBlock)
            SB3Builder.linkBlocks(sprite, {hatId, changeUpId, changeDownId})

            local projectJson = SB3Builder.createProject({stage, sprite})
            local project = ProjectModel:new(projectJson, {})
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
            expect(spriteTarget.volume).to.equal(0) -- Should be clamped to 0
        end)

        it("should report current volume", function()
            SB3Builder.resetCounter()
            local stage = SB3Builder.createStage()
            local sprite = SB3Builder.createSprite("TestSprite")
            sprite.volume = 85
            local volumeVarId = SB3Builder.addVariable(sprite, "currentVolume", 0)

            local hatId, hatBlock = SB3Builder.Events.whenFlagClicked()
            local volumeId, volumeBlock = SB3Builder.createBlock("sound_volume", {}, {})
            local setId, setBlock = SB3Builder.createBlock("data_setvariableto", {
                VALUE = SB3Builder.blockInput(volumeId)
            }, {
                VARIABLE = SB3Builder.field("currentVolume", volumeVarId)
            })

            SB3Builder.addBlock(sprite, hatId, hatBlock)
            SB3Builder.addBlock(sprite, volumeId, volumeBlock)
            SB3Builder.addBlock(sprite, setId, setBlock)
            SB3Builder.linkBlocks(sprite, {hatId, setId})

            local projectJson = SB3Builder.createProject({stage, sprite})
            local project = ProjectModel:new(projectJson, {})
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
            local volumeVar = spriteTarget:lookupVariableByNameAndType("currentVolume")
            expect(volumeVar.value).to.equal(85)
        end)
    end)

    describe("Sound Effects", function()
        it("should set pitch effect correctly", function()
            SB3Builder.resetCounter()
            local stage = SB3Builder.createStage()
            local sprite = SB3Builder.createSprite("TestSprite")

            local hatId, hatBlock = SB3Builder.Events.whenFlagClicked()
            local effectId, effectBlock = SB3Builder.createBlock("sound_seteffectto", {
                EFFECT = SB3Builder.primitiveInput("pitch"),
                VALUE = SB3Builder.primitiveInput(100)
            }, {})

            SB3Builder.addBlock(sprite, hatId, hatBlock)
            SB3Builder.addBlock(sprite, effectId, effectBlock)
            SB3Builder.linkBlocks(sprite, {hatId, effectId})

            local projectJson = SB3Builder.createProject({stage, sprite})
            local project = ProjectModel:new(projectJson, {})
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
            expect(spriteTarget.soundEffects).to.exist()
            expect(spriteTarget.soundEffects.pitch).to.equal(100)
        end)

        it("should change sound effects by amount", function()
            SB3Builder.resetCounter()
            local stage = SB3Builder.createStage()
            local sprite = SB3Builder.createSprite("TestSprite", {
                soundEffects = {pitch = 50, pan = 0}
            })

            local hatId, hatBlock = SB3Builder.Events.whenFlagClicked()
            local effectId, effectBlock = SB3Builder.createBlock("sound_changeeffectby", {
                EFFECT = SB3Builder.primitiveInput("pitch"),
                VALUE = SB3Builder.primitiveInput(75)
            }, {})

            SB3Builder.addBlock(sprite, hatId, hatBlock)
            SB3Builder.addBlock(sprite, effectId, effectBlock)
            SB3Builder.linkBlocks(sprite, {hatId, effectId})

            local projectJson = SB3Builder.createProject({stage, sprite})
            local project = ProjectModel:new(projectJson, {})
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
            expect(spriteTarget.soundEffects.pitch).to.equal(125) -- 50 + 75 = 125
        end)

        it("should clamp pitch effect within valid range", function()
            SB3Builder.resetCounter()
            local stage = SB3Builder.createStage()
            local sprite = SB3Builder.createSprite("TestSprite")

            local hatId, hatBlock = SB3Builder.Events.whenFlagClicked()
            local effect1Id, effect1Block = SB3Builder.createBlock("sound_seteffectto", {
                EFFECT = SB3Builder.primitiveInput("pitch"),
                VALUE = SB3Builder.primitiveInput(500) -- Should clamp to 360
            }, {})
            local effect2Id, effect2Block = SB3Builder.createBlock("sound_seteffectto", {
                EFFECT = SB3Builder.primitiveInput("pitch"),
                VALUE = SB3Builder.primitiveInput(-500) -- Should clamp to -360
            }, {})

            SB3Builder.addBlock(sprite, hatId, hatBlock)
            SB3Builder.addBlock(sprite, effect1Id, effect1Block)
            SB3Builder.addBlock(sprite, effect2Id, effect2Block)
            SB3Builder.linkBlocks(sprite, {hatId, effect1Id, effect2Id})

            local projectJson = SB3Builder.createProject({stage, sprite})
            local project = ProjectModel:new(projectJson, {})
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
            expect(spriteTarget.soundEffects.pitch).to.equal(-360) -- Final value should be clamped
        end)

        it("should clamp pan effect within valid range", function()
            SB3Builder.resetCounter()
            local stage = SB3Builder.createStage()
            local sprite = SB3Builder.createSprite("TestSprite")

            local hatId, hatBlock = SB3Builder.Events.whenFlagClicked()
            local effect1Id, effect1Block = SB3Builder.createBlock("sound_seteffectto", {
                EFFECT = SB3Builder.primitiveInput("pan left/right"),
                VALUE = SB3Builder.primitiveInput(150) -- Should clamp to 100
            }, {})

            SB3Builder.addBlock(sprite, hatId, hatBlock)
            SB3Builder.addBlock(sprite, effect1Id, effect1Block)
            SB3Builder.linkBlocks(sprite, {hatId, effect1Id})

            local projectJson = SB3Builder.createProject({stage, sprite})
            local project = ProjectModel:new(projectJson, {})
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
            expect(spriteTarget.soundEffects.pan).to.equal(100) -- Should be clamped to max
        end)

        it("should clear all sound effects", function()
            SB3Builder.resetCounter()
            local stage = SB3Builder.createStage()
            local sprite = SB3Builder.createSprite("TestSprite")
            sprite.soundEffects = {pitch = 100, pan = -50}

            local hatId, hatBlock = SB3Builder.Events.whenFlagClicked()
            local clearId, clearBlock = SB3Builder.createBlock("sound_cleareffects", {}, {})

            SB3Builder.addBlock(sprite, hatId, hatBlock)
            SB3Builder.addBlock(sprite, clearId, clearBlock)
            SB3Builder.linkBlocks(sprite, {hatId, clearId})

            local projectJson = SB3Builder.createProject({stage, sprite})
            local project = ProjectModel:new(projectJson, {})
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
            expect(spriteTarget.soundEffects.pitch).to.equal(0)
            expect(spriteTarget.soundEffects.pan).to.equal(0)
        end)
    end)

    describe("Edge Cases and Error Handling", function()
        it("should handle playing non-existent sounds gracefully", function()
            SB3Builder.resetCounter()
            local stage = SB3Builder.createStage()
            local sprite = SB3Builder.createSprite("TestSprite")
            sprite.sounds = {}

            local hatId, hatBlock = SB3Builder.Events.whenFlagClicked()
            local playId, playBlock = SB3Builder.createBlock("sound_play", {}, {
                SOUND_MENU = SB3Builder.field("nonexistent")
            })

            SB3Builder.addBlock(sprite, hatId, hatBlock)
            SB3Builder.addBlock(sprite, playId, playBlock)
            SB3Builder.linkBlocks(sprite, {hatId, playId})

            local projectJson = SB3Builder.createProject({stage, sprite})
            local project = ProjectModel:new(projectJson, {})
            local runtime = Runtime:new(project)
            runtime:initialize()

            -- Should not crash when trying to play non-existent sound
            expect(function()
                runtime:broadcastGreenFlag()
                local maxIterations = 100
                local iterations = 0
                while #runtime:getActiveThreads() > 0 and iterations < maxIterations do
                    runtime:update(1/60)
                    iterations = iterations + 1
                end
            end).to_not.fail()
        end)

        it("should handle sprites with no sounds array", function()
            SB3Builder.resetCounter()
            local stage = SB3Builder.createStage()
            local sprite = SB3Builder.createSprite("TestSprite")
            -- Deliberately don't set sprite.sounds

            local hatId, hatBlock = SB3Builder.Events.whenFlagClicked()
            local playId, playBlock = SB3Builder.createBlock("sound_play", {}, {
                SOUND_MENU = SB3Builder.field("any sound")
            })

            SB3Builder.addBlock(sprite, hatId, hatBlock)
            SB3Builder.addBlock(sprite, playId, playBlock)
            SB3Builder.linkBlocks(sprite, {hatId, playId})

            local projectJson = SB3Builder.createProject({stage, sprite})
            local project = ProjectModel:new(projectJson, {})
            local runtime = Runtime:new(project)
            runtime:initialize()

            -- Should not crash when sprite has no sounds
            expect(function()
                runtime:broadcastGreenFlag()
                local maxIterations = 100
                local iterations = 0
                while #runtime:getActiveThreads() > 0 and iterations < maxIterations do
                    runtime:update(1/60)
                    iterations = iterations + 1
                end
            end).to_not.fail()
        end)

        it("should handle invalid effect names gracefully", function()
            SB3Builder.resetCounter()
            local stage = SB3Builder.createStage()
            local sprite = SB3Builder.createSprite("TestSprite")

            local hatId, hatBlock = SB3Builder.Events.whenFlagClicked()
            local effectId, effectBlock = SB3Builder.createBlock("sound_seteffectto", {
                EFFECT = SB3Builder.primitiveInput("invalid_effect"),
                VALUE = SB3Builder.primitiveInput(50)
            }, {})

            SB3Builder.addBlock(sprite, hatId, hatBlock)
            SB3Builder.addBlock(sprite, effectId, effectBlock)
            SB3Builder.linkBlocks(sprite, {hatId, effectId})

            local projectJson = SB3Builder.createProject({stage, sprite})
            local project = ProjectModel:new(projectJson, {})
            local runtime = Runtime:new(project)
            runtime:initialize()

            -- Should not crash with invalid effect name
            expect(function()
                runtime:broadcastGreenFlag()
                local maxIterations = 100
                local iterations = 0
                while #runtime:getActiveThreads() > 0 and iterations < maxIterations do
                    runtime:update(1/60)
                    iterations = iterations + 1
                end
            end).to_not.fail()
        end)

        it("should handle volume setting with non-numeric values", function()
            SB3Builder.resetCounter()
            local stage = SB3Builder.createStage()
            local sprite = SB3Builder.createSprite("TestSprite")
            sprite.volume = 50

            local hatId, hatBlock = SB3Builder.Events.whenFlagClicked()
            local setVolumeId, setVolumeBlock = SB3Builder.createBlock("sound_setvolumeto", {
                VOLUME = SB3Builder.primitiveInput("not a number")
            }, {})

            SB3Builder.addBlock(sprite, hatId, hatBlock)
            SB3Builder.addBlock(sprite, setVolumeId, setVolumeBlock)
            SB3Builder.linkBlocks(sprite, {hatId, setVolumeId})

            local projectJson = SB3Builder.createProject({stage, sprite})
            local project = ProjectModel:new(projectJson, {})
            local runtime = Runtime:new(project)
            runtime:initialize()

            runtime:broadcastGreenFlag()
            local maxIterations = 100
            local iterations = 0
            while #runtime:getActiveThreads() > 0 and iterations < maxIterations do
                runtime:update(1/60)
                iterations = iterations + 1
            end

            -- Should handle gracefully (Cast.toNumber should convert to 0)
            local spriteTarget = runtime:getSpriteTargetByName("TestSprite")
            expect(spriteTarget.volume).to.equal(0)
        end)
    end)
end)
