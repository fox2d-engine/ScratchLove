-- Sound Effects Tests
-- Tests for sound effect implementations (pitch, pan, volume)

local lust = require("tests.lust")
local describe, it, expect = lust.describe, lust.it, lust.expect

local AudioManager = require("audio.audio_engine")
local AudioMock = require("tests.mocks.audio_mock")

describe("Sound Effects Implementation", function()
    describe("Pitch Effect", function()
        it("should calculate pitch ratio correctly using 2^(value/120) formula", function()
            local manager = AudioManager:new()
            local soundData = {
                assetId = "test_sound",
                name = "Test Sound",
                duration = 1.0,
                source = AudioMock.createMockSource(1.0)
            }

            manager:addSoundPlayer(soundData)

            local target = {
                name = "TestSprite",
                volume = 100,
                soundEffects = {pitch = 0, pan = 0}
            }

            -- Test pitch = 0 (no change)
            manager:playSound(target, "test_sound", false)
            local playback = manager.playingSounds["test_sound"]
            expect(playback.pitch).to.equal(1.0)  -- 2^(0/120) = 1

            -- Test pitch = 120 (one octave up)
            target.soundEffects.pitch = 120
            manager:setEffects(target)
            expect(playback.pitch).to.equal(2.0)  -- 2^(120/120) = 2

            -- Test pitch = -120 (one octave down)
            target.soundEffects.pitch = -120
            manager:setEffects(target)
            expect(playback.pitch).to.equal(0.5)  -- 2^(-120/120) = 0.5

            -- Test pitch = 60 (half octave up)
            target.soundEffects.pitch = 60
            manager:setEffects(target)
            local expected = math.pow(2, 60/120)  -- 2^(0.5) ≈ 1.414
            expect(math.abs(playback.pitch - expected) < 0.001).to.be(true)
        end)

        it("should clamp pitch to 0.1..10 range", function()
            local manager = AudioManager:new()
            local soundData = {
                assetId = "test_sound",
                name = "Test Sound",
                duration = 1.0,
                source = AudioMock.createMockSource(1.0)
            }

            manager:addSoundPlayer(soundData)

            local target = {
                name = "TestSprite",
                volume = 100,
                soundEffects = {pitch = 360, pan = 0}  -- 3 octaves up: 2^3 = 8
            }

            manager:playSound(target, "test_sound", false)
            local playback = manager.playingSounds["test_sound"]
            expect(playback.pitch).to.equal(8.0)  -- Within clamp range

            -- Test extreme value beyond clamp
            target.soundEffects.pitch = 600  -- Would be 2^5 = 32, clamped to 10
            manager:setEffects(target)
            expect(playback.pitch).to.equal(10.0)

            target.soundEffects.pitch = -600  -- Would be 2^(-5) = 0.03125, clamped to 0.1
            manager:setEffects(target)
            expect(playback.pitch).to.equal(0.1)
        end)
    end)

    describe("Pan Effect", function()
        it("should apply pan to mono sources using position", function()
            local manager = AudioManager:new()
            local mockSource = AudioMock.createMockSource(1.0)

            -- Mock channel count for mono
            mockSource.getChannelCount = function() return 1 end

            local soundData = {
                assetId = "test_sound",
                name = "Test Sound",
                duration = 1.0,
                source = mockSource
            }

            manager:addSoundPlayer(soundData)

            local target = {
                name = "TestSprite",
                volume = 100,
                soundEffects = {pitch = 0, pan = -100}  -- Full left
            }

            manager:playSound(target, "test_sound", false)
            local playback = manager.playingSounds["test_sound"]
            expect(playback.pan).to.equal(-100)

            -- playback.source is the cloned source, not the original mockSource
            local playbackSource = playback.source
            expect(playbackSource._pan).to.equal(-1)  -- pan/100 = -1

            -- Test center pan
            target.soundEffects.pan = 0
            manager:setEffects(target)
            expect(playbackSource._pan).to.equal(0)

            -- Test full right
            target.soundEffects.pan = 100
            manager:setEffects(target)
            expect(playbackSource._pan).to.equal(1)
        end)

        it("should warn but not crash for stereo sources", function()
            local manager = AudioManager:new()
            local mockSource = AudioMock.createMockSource(1.0)

            -- Mock channel count for stereo
            mockSource.getChannelCount = function() return 2 end

            local soundData = {
                assetId = "test_sound",
                name = "Test Sound",
                duration = 1.0,
                source = mockSource
            }

            manager:addSoundPlayer(soundData)

            local target = {
                name = "TestSprite",
                volume = 100,
                soundEffects = {pitch = 0, pan = -100}
            }

            -- Should not crash, just warn
            manager:playSound(target, "test_sound", false)
            local playback = manager.playingSounds["test_sound"]
            expect(playback).to.exist()
            expect(playback.pan).to.equal(-100)  -- Pan value is stored but not applied
        end)
    end)

    describe("Volume Effect", function()
        it("should apply volume correctly with master volume", function()
            local manager = AudioManager:new()
            local mockSource = AudioMock.createMockSource(1.0)

            local soundData = {
                assetId = "test_sound",
                name = "Test Sound",
                duration = 1.0,
                source = mockSource
            }

            manager:addSoundPlayer(soundData)

            -- Set master volume to 0.8
            manager:setGlobalVolume(0.8)

            local target = {
                name = "TestSprite",
                volume = 50,  -- 50%
                soundEffects = {pitch = 0, pan = 0}
            }

            manager:playSound(target, "test_sound", false)

            -- Get the cloned source used for playback
            local playback = manager.playingSounds["test_sound"]
            local playbackSource = playback.source

            -- Final volume should be target.volume * masterVolume = 0.5 * 0.8 = 0.4
            expect(playbackSource._volume).to.equal(0.4)
        end)
    end)

    describe("Effect State Management", function()
        it("should update effects only for sounds owned by target", function()
            local manager = AudioManager:new()
            local soundData = {
                assetId = "shared_sound",
                name = "Shared Sound",
                duration = 1.0,
                source = AudioMock.createMockSource(1.0)
            }

            manager:addSoundPlayer(soundData)

            local target1 = {
                name = "Sprite1",
                volume = 100,
                soundEffects = {pitch = 120, pan = 0}
            }

            local target2 = {
                name = "Sprite2",
                volume = 100,
                soundEffects = {pitch = -120, pan = 0}
            }

            -- Target1 plays first
            manager:playSound(target1, "shared_sound", false)
            local playback = manager.playingSounds["shared_sound"]
            expect(playback.pitch).to.equal(2.0)  -- pitch=120 → 2^1 = 2

            -- Target2 takes over (forking)
            manager:playSound(target2, "shared_sound", false)
            playback = manager.playingSounds["shared_sound"]
            expect(playback.pitch).to.equal(0.5)  -- pitch=-120 → 2^(-1) = 0.5

            -- Now target1 tries to update effects - should have no effect
            -- because target2 owns the sound now
            manager:setEffects(target1)
            expect(playback.pitch).to.equal(0.5)  -- Still target2's pitch
        end)
    end)
end)
