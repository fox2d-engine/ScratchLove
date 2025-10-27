-- Clone Sound Tests
-- Tests for sound playback behavior with clones

local lust = require("tests.lust")
local describe, it, expect = lust.describe, lust.it, lust.expect

local SB3Builder = require("tests.sb3_builder")
local ProjectModel = require("parser.project_model")
local Runtime = require("vm.runtime")
local AudioMock = require("tests.mocks.audio_mock")

describe("Clone Sound Behavior", function()
    it("should allow original sprite and clone to have independent sound playback with different soundIds", function()
        SB3Builder.resetCounter()
        local stage = SB3Builder.createStage()
        local sprite = SB3Builder.createSprite("TestSprite")

        -- Add two different sounds
        sprite.sounds = {
            {name = "sound1", assetId = "asset1", dataFormat = "wav", duration = 1.0, source = AudioMock.createMockSource(1.0)},
            {name = "sound2", assetId = "asset2", dataFormat = "wav", duration = 1.0, source = AudioMock.createMockSource(1.0)}
        }

        -- Original sprite: play sound1
        local hat1Id, hat1Block = SB3Builder.Events.whenFlagClicked()
        local play1Id, play1Block = SB3Builder.createBlock("sound_play", {}, {
            SOUND_MENU = SB3Builder.field("sound1")
        })

        -- Clone: play sound2 when started
        local hat2Id, hat2Block = SB3Builder.Control.whenStartAsClone()
        local play2Id, play2Block = SB3Builder.createBlock("sound_play", {}, {
            SOUND_MENU = SB3Builder.field("sound2")
        })

        -- Create clone block
        local cloneId, cloneBlock, menuId, menuBlock = SB3Builder.Control.createCloneOf("_myself_")

        SB3Builder.addBlock(sprite, hat1Id, hat1Block)
        SB3Builder.addBlock(sprite, play1Id, play1Block)
        SB3Builder.addBlock(sprite, cloneId, cloneBlock)
        SB3Builder.addBlock(sprite, menuId, menuBlock)
        SB3Builder.linkBlocks(sprite, {hat1Id, play1Id, cloneId})

        SB3Builder.addBlock(sprite, hat2Id, hat2Block)
        SB3Builder.addBlock(sprite, play2Id, play2Block)
        SB3Builder.linkBlocks(sprite, {hat2Id, play2Id})

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

        -- Both sounds should be playing (different soundIds)
        expect(runtime.audioEngine.playingSounds["asset1"]).to.exist()
        expect(runtime.audioEngine.playingSounds["asset2"]).to.exist()

        -- Verify they have different targets
        local target1 = runtime.audioEngine.playerTargets["asset1"]
        local target2 = runtime.audioEngine.playerTargets["asset2"]
        expect(target1).to.exist()
        expect(target2).to.exist()
        expect(target1 ~= target2).to.be(true) -- Different targets
    end)

    it("should fork sound playback when original sprite and clone play SAME sound", function()
        SB3Builder.resetCounter()
        local stage = SB3Builder.createStage()
        local sprite = SB3Builder.createSprite("TestSprite")

        sprite.sounds = {
            {name = "shared_sound", assetId = "shared", dataFormat = "wav", duration = 1.0, source = AudioMock.createMockSource(1.0)}
        }

        -- Original sprite: play shared sound
        local hat1Id, hat1Block = SB3Builder.Events.whenFlagClicked()
        local play1Id, play1Block = SB3Builder.createBlock("sound_play", {}, {
            SOUND_MENU = SB3Builder.field("shared_sound")
        })

        -- Clone: also play the same shared sound
        local hat2Id, hat2Block = SB3Builder.Control.whenStartAsClone()
        local play2Id, play2Block = SB3Builder.createBlock("sound_play", {}, {
            SOUND_MENU = SB3Builder.field("shared_sound")
        })

        -- Create clone block
        local cloneId, cloneBlock, menuId, menuBlock = SB3Builder.Control.createCloneOf("_myself_")

        SB3Builder.addBlock(sprite, hat1Id, hat1Block)
        SB3Builder.addBlock(sprite, play1Id, play1Block)
        SB3Builder.addBlock(sprite, cloneId, cloneBlock)
        SB3Builder.addBlock(sprite, menuId, menuBlock)
        SB3Builder.linkBlocks(sprite, {hat1Id, play1Id, cloneId})

        SB3Builder.addBlock(sprite, hat2Id, hat2Block)
        SB3Builder.addBlock(sprite, play2Id, play2Block)
        SB3Builder.linkBlocks(sprite, {hat2Id, play2Id})

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

        -- Only ONE playback should exist (forking behavior)
        expect(runtime.audioEngine.playingSounds["shared"]).to.exist()

        -- The clone should be the current player (it played last)
        local currentTarget = runtime.audioEngine.playerTargets["shared"]
        expect(currentTarget).to.exist()
        expect(currentTarget.isClone).to.be(true) -- Clone took over playback
    end)

    it("should allow multiple clones to play different sounds simultaneously", function()
        SB3Builder.resetCounter()
        local stage = SB3Builder.createStage()
        local sprite = SB3Builder.createSprite("TestSprite")

        sprite.sounds = {
            {name = "sound1", assetId = "asset1", dataFormat = "wav", duration = 1.0, source = AudioMock.createMockSource(1.0)},
            {name = "sound2", assetId = "asset2", dataFormat = "wav", duration = 1.0, source = AudioMock.createMockSource(1.0)}
        }

        -- Clone 1: play sound1
        local hat1Id, hat1Block = SB3Builder.Control.whenStartAsClone()
        local play1Id, play1Block = SB3Builder.createBlock("sound_play", {}, {
            SOUND_MENU = SB3Builder.field("sound1")
        })

        -- Create two clones
        local hatMainId, hatMainBlock = SB3Builder.Events.whenFlagClicked()
        local clone1Id, clone1Block, menu1Id, menu1Block = SB3Builder.Control.createCloneOf("_myself_")
        local clone2Id, clone2Block, menu2Id, menu2Block = SB3Builder.Control.createCloneOf("_myself_")

        SB3Builder.addBlock(sprite, hatMainId, hatMainBlock)
        SB3Builder.addBlock(sprite, clone1Id, clone1Block)
        SB3Builder.addBlock(sprite, menu1Id, menu1Block)
        SB3Builder.addBlock(sprite, clone2Id, clone2Block)
        SB3Builder.addBlock(sprite, menu2Id, menu2Block)
        SB3Builder.linkBlocks(sprite, {hatMainId, clone1Id, clone2Id})

        SB3Builder.addBlock(sprite, hat1Id, hat1Block)
        SB3Builder.addBlock(sprite, play1Id, play1Block)
        SB3Builder.linkBlocks(sprite, {hat1Id, play1Id})

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

        -- Both clones will play sound1, but only the last one survives (forking)
        expect(runtime.audioEngine.playingSounds["asset1"]).to.exist()

        -- Verify a clone is the current player
        local currentTarget = runtime.audioEngine.playerTargets["asset1"]
        expect(currentTarget).to.exist()
        expect(currentTarget.isClone).to.be(true)
    end)
end)
