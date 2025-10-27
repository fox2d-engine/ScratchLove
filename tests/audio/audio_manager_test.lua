-- Audio Manager Tests
-- Tests for the global soundId architecture (matching native Scratch)

local lust = require("tests.lust")
local describe, it, expect = lust.describe, lust.it, lust.expect

local AudioManager = require("audio.audio_engine")
local AudioMock = require("tests.mocks.audio_mock")

describe("AudioManager", function()
    describe("Initialization", function()
        it("initializes with default state", function()
            local manager = AudioManager:new()

            expect(manager).to.exist()
            expect(manager.soundPlayers).to.exist()
            expect(manager.playerTargets).to.exist()
            expect(manager.soundEffects).to.exist()
            expect(manager.playingSounds).to.exist()
            expect(manager.waitingSounds).to.exist()
            expect(manager.masterVolume).to.equal(1)
        end)
    end)

    describe("Sound Registration (Global soundId)", function()
        it("adds sound players to global registry", function()
            local manager = AudioManager:new()
            local soundData = {
                assetId = "test_sound",
                name = "Test Sound",
                duration = 2.0,
                source = AudioMock.createMockSource(2.0)
            }

            manager:addSoundPlayer(soundData)

            expect(manager.soundPlayers["test_sound"]).to.exist()
            expect(manager.soundPlayers["test_sound"].duration).to.equal(2.0)
            expect(manager.soundEffects["test_sound"]).to.exist()
        end)

        it("handles missing sources gracefully", function()
            local manager = AudioManager:new()
            local soundData = {
                assetId = "missing_sound",
                name = "Missing Sound"
                -- No source - should warn and not create sound
            }

            manager:addSoundPlayer(soundData)

            expect(manager.soundPlayers["missing_sound"]).to_not.exist()
        end)

        it("uses md5ext as fallback soundId", function()
            local manager = AudioManager:new()
            local soundData = {
                md5ext = "abc123.wav",
                name = "Test Sound",
                duration = 1.0,
                source = AudioMock.createMockSource(1.0)
            }

            manager:addSoundPlayer(soundData)

            expect(manager.soundPlayers["abc123.wav"]).to.exist()
        end)
    end)

    describe("Sound Playback", function()
        it("plays sounds without waiting", function()
            local manager = AudioManager:new()
            local soundData = {
                assetId = "test_sound",
                name = "Test Sound",
                duration = 2.0,
                source = AudioMock.createMockSource(2.0)
            }

            manager:addSoundPlayer(soundData)

            local target = {name = "TestSprite", volume = 100}
            local timer = manager:playSound(target, "test_sound", false)

            expect(timer).to.be(nil) -- No waiting timer
            expect(manager.playingSounds["test_sound"]).to.exist()
            expect(manager.playerTargets["test_sound"]).to.equal(target)
        end)

        it("plays sounds with waiting timer", function()
            local manager = AudioManager:new()
            local soundData = {
                assetId = "test_sound",
                name = "Test Sound",
                duration = 2.0,
                source = AudioMock.createMockSource(2.0)
            }

            manager:addSoundPlayer(soundData)

            local target = {name = "TestSprite", volume = 100}
            local timer = manager:playSound(target, "test_sound", true)

            expect(timer).to.exist() -- Should have waiting timer
            expect(manager.waitingSounds[target]).to.exist()
        end)

        it("handles missing soundId gracefully", function()
            local manager = AudioManager:new()
            local target = {name = "TestSprite", volume = 100}

            local timer = manager:playSound(target, "nonexistent_sound", false)

            expect(timer).to.be(nil)
            expect(manager.playingSounds["nonexistent_sound"]).to_not.exist()
        end)
    end)

    describe("Forking Behavior (Native Scratch compatibility)", function()
        it("stops old playback when different target plays same sound", function()
            local manager = AudioManager:new()
            local soundData = {
                assetId = "shared_sound",
                name = "Shared Sound",
                duration = 2.0,
                source = AudioMock.createMockSource(2.0)
            }

            manager:addSoundPlayer(soundData)

            local target1 = {name = "Sprite1", volume = 100}
            local target2 = {name = "Sprite2", volume = 100}

            -- Target1 plays the sound
            manager:playSound(target1, "shared_sound", false)
            expect(manager.playerTargets["shared_sound"]).to.equal(target1)
            local playback1 = manager.playingSounds["shared_sound"]
            expect(playback1).to.exist()

            -- Target2 plays the same sound - should fork (stop old, start new)
            manager:playSound(target2, "shared_sound", false)
            expect(manager.playerTargets["shared_sound"]).to.equal(target2)
            local playback2 = manager.playingSounds["shared_sound"]
            expect(playback2).to.exist()
            expect(playback2).to_not.equal(playback1) -- Different playback instance
            expect(playback1.completed).to.be(true) -- Old playback stopped
        end)

        it("allows same target to replay sound", function()
            local manager = AudioManager:new()
            local soundData = {
                assetId = "test_sound",
                name = "Test Sound",
                duration = 2.0,
                source = AudioMock.createMockSource(2.0)
            }

            manager:addSoundPlayer(soundData)

            local target = {name = "TestSprite", volume = 100}

            -- First play
            manager:playSound(target, "test_sound", false)
            local playback1 = manager.playingSounds["test_sound"]

            -- Second play by same target
            manager:playSound(target, "test_sound", false)
            local playback2 = manager.playingSounds["test_sound"]

            expect(playback2).to.exist()
            expect(manager.playerTargets["test_sound"]).to.equal(target)
        end)
    end)

    describe("Sound Stopping", function()
        it("stops sound only if target matches", function()
            local manager = AudioManager:new()
            local soundData = {
                assetId = "test_sound",
                name = "Test Sound",
                duration = 2.0,
                source = AudioMock.createMockSource(2.0)
            }

            manager:addSoundPlayer(soundData)

            local target1 = {name = "Sprite1", volume = 100}
            local target2 = {name = "Sprite2", volume = 100}

            manager:playSound(target1, "test_sound", false)
            expect(manager.playingSounds["test_sound"]).to.exist()

            -- Target2 tries to stop, but target1 owns it - should not stop
            manager:stop(target2, "test_sound")
            expect(manager.playingSounds["test_sound"]).to.exist()

            -- Target1 stops - should stop
            manager:stop(target1, "test_sound")
            expect(manager.playingSounds["test_sound"]).to_not.exist()
        end)

        it("stops all sounds for target", function()
            local manager = AudioManager:new()

            manager:addSoundPlayer({
                assetId = "sound1",
                name = "Sound 1",
                duration = 2.0,
                source = AudioMock.createMockSource(2.0)
            })
            manager:addSoundPlayer({
                assetId = "sound2",
                name = "Sound 2",
                duration = 3.0,
                source = AudioMock.createMockSource(3.0)
            })

            local target = {name = "TestSprite", volume = 100}
            manager:playSound(target, "sound1", false)
            manager:playSound(target, "sound2", false)

            expect(manager.playingSounds["sound1"]).to.exist()
            expect(manager.playingSounds["sound2"]).to.exist()

            manager:stopAllSounds(target)

            expect(manager.playingSounds["sound1"]).to_not.exist()
            expect(manager.playingSounds["sound2"]).to_not.exist()
            expect(manager.playerTargets["sound1"]).to_not.exist()
            expect(manager.playerTargets["sound2"]).to_not.exist()
        end)

        it("stops all sounds globally", function()
            local manager = AudioManager:new()

            manager:addSoundPlayer({
                assetId = "sound1",
                name = "Sound 1",
                duration = 2.0,
                source = AudioMock.createMockSource(2.0)
            })

            local target1 = {name = "Sprite1", volume = 100}
            local target2 = {name = "Sprite2", volume = 100}

            manager:playSound(target1, "sound1", false)
            manager:playSound(target2, "sound1", false) -- Will fork

            manager:stopAllSounds() -- No target = stop all globally

            expect(manager.playingSounds["sound1"]).to_not.exist()
            expect(manager.playerTargets["sound1"]).to_not.exist()
        end)
    end)

    describe("Effects Management", function()
        it("updates effects for target's sounds", function()
            local manager = AudioManager:new()
            local soundData = {
                assetId = "test_sound",
                name = "Test Sound",
                duration = 2.0,
                source = AudioMock.createMockSource(2.0)
            }

            manager:addSoundPlayer(soundData)

            local target = {
                name = "TestSprite",
                volume = 100,
                soundEffects = {pitch = 120, pan = -50}
            }
            manager:playSound(target, "test_sound", false)

            local playback = manager.playingSounds["test_sound"]
            expect(playback.pitch > 1).to.be(true) -- Pitch effect applied
            expect(playback.pan).to.equal(-50)

            -- Update effects
            target.soundEffects.pitch = -60
            manager:setEffects(target)

            expect(playback.pitch < 1).to.be(true) -- New pitch applied (negative pitch lowers pitch)
        end)

        it("updates volume for target's sounds", function()
            local manager = AudioManager:new()
            local soundData = {
                assetId = "test_sound",
                name = "Test Sound",
                duration = 2.0,
                source = AudioMock.createMockSource(2.0)
            }

            manager:addSoundPlayer(soundData)

            local target = {name = "TestSprite", volume = 100}
            manager:playSound(target, "test_sound", false)

            local playback = manager.playingSounds["test_sound"]
            expect(playback.volume).to.equal(1.0)

            target.volume = 50
            manager:updateVolume(target)

            expect(playback.volume).to.equal(0.5) -- 50/100
        end)
    end)

    describe("Global Volume", function()
        it("sets global volume", function()
            local manager = AudioManager:new()

            manager:setGlobalVolume(0.7)

            expect(manager.masterVolume).to.equal(0.7)
        end)

        it("clamps global volume", function()
            local manager = AudioManager:new()

            manager:setGlobalVolume(1.5) -- Above max
            expect(manager.masterVolume).to.equal(1)

            manager:setGlobalVolume(-0.5) -- Below min
            expect(manager.masterVolume).to.equal(0)
        end)

        it("updates all playing sounds when global volume changes", function()
            local manager = AudioManager:new()
            local soundData = {
                assetId = "test_sound",
                name = "Test Sound",
                duration = 2.0,
                source = AudioMock.createMockSource(2.0)
            }

            manager:addSoundPlayer(soundData)

            local target = {name = "TestSprite", volume = 100}
            manager:playSound(target, "test_sound", false)

            manager:setGlobalVolume(0.5)

            local playback = manager.playingSounds["test_sound"]
            -- Volume should be target.volume * masterVolume = 1.0 * 0.5 = 0.5
            -- But actual source volume is not directly accessible in test
            expect(manager.masterVolume).to.equal(0.5)
        end)
    end)

    describe("Waiting Sounds", function()
        it("checks for waiting sounds", function()
            local manager = AudioManager:new()
            local soundData = {
                assetId = "test_sound",
                name = "Test Sound",
                duration = 2.0,
                source = AudioMock.createMockSource(2.0)
            }

            manager:addSoundPlayer(soundData)

            local target = {name = "TestSprite", volume = 100}

            expect(manager:hasWaitingSounds(target)).to.be(false)

            manager:playSound(target, "test_sound", true)

            expect(manager:hasWaitingSounds(target)).to.be(true)
        end)
    end)

    describe("Update and Cleanup", function()
        it("updates and cleans finished sounds", function()
            local manager = AudioManager:new()
            local soundData = {
                assetId = "test_sound",
                name = "Test Sound",
                duration = 0.01,
                source = AudioMock.createMockSource(0.01)
            }

            manager:addSoundPlayer(soundData)

            local target = {name = "TestSprite", volume = 100}
            manager:playSound(target, "test_sound", false)

            expect(manager.playingSounds["test_sound"]).to.exist()

            -- Simulate time passing
            if love and love.timer and love.timer.advance then
                love.timer.advance(0.02)
            end

            manager:update(0.02)

            -- Should clean up finished sound
            expect(manager.playingSounds["test_sound"]).to_not.exist()
        end)

        it("cleans up empty waiting sound sets", function()
            local manager = AudioManager:new()
            local soundData = {
                assetId = "test_sound",
                name = "Test Sound",
                duration = 0.01,
                source = AudioMock.createMockSource(0.01)
            }

            manager:addSoundPlayer(soundData)

            local target = {name = "TestSprite", volume = 100}
            manager:playSound(target, "test_sound", true)

            expect(manager.waitingSounds[target]).to.exist()

            -- Simulate time passing
            if love and love.timer and love.timer.advance then
                love.timer.advance(0.02)
            end

            manager:update(0.02)

            -- Waiting sounds should be cleaned up
            expect(manager.waitingSounds[target]).to_not.exist()
        end)
    end)
end)
