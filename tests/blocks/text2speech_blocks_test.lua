-- Test: Text2Speech Extension Blocks
-- Verifies text2speech functionality including speak, setVoice, and setLanguage blocks

local lust = require("tests.lust")
local describe, it, expect = lust.describe, lust.it, lust.expect

local SB3Builder = require("tests.sb3_builder")
local Runtime = require("vm.runtime")
local ProjectModel = require("parser.project_model")
local log = require("lib.log")

describe("Text2Speech Extension", function()
    describe("Basic compilation", function()
        it("should compile text2speech_speakAndWait block", function()
            SB3Builder.resetCounter()
            local stage = SB3Builder.createStage()
            local sprite = SB3Builder.createSprite("Speaker")

            -- Create speak block
            local hatId, hatBlock = SB3Builder.Events.whenFlagClicked()
            local speakId, speakBlock = SB3Builder.createBlock("text2speech_speakAndWait", {
                WORDS = "Hello World"
            })

            SB3Builder.addBlock(sprite, hatId, hatBlock)
            SB3Builder.addBlock(sprite, speakId, speakBlock)
            SB3Builder.linkBlocks(sprite, {hatId, speakId})

            local projectJson = SB3Builder.createProject({stage, sprite})
            local project = ProjectModel:new(projectJson, {})

            -- Should compile without errors
            expect(project).to.exist()
            log.info("✓ text2speech_speakAndWait compiles successfully")
        end)

        it("should compile text2speech_setVoice block", function()
            SB3Builder.resetCounter()
            local stage = SB3Builder.createStage()
            local sprite = SB3Builder.createSprite("Speaker")

            local hatId, hatBlock = SB3Builder.Events.whenFlagClicked()
            local voiceId, voiceBlock = SB3Builder.createBlock("text2speech_setVoice", {
                VOICE = "squeak"
            })

            SB3Builder.addBlock(sprite, hatId, hatBlock)
            SB3Builder.addBlock(sprite, voiceId, voiceBlock)
            SB3Builder.linkBlocks(sprite, {hatId, voiceId})

            local projectJson = SB3Builder.createProject({stage, sprite})
            local project = ProjectModel:new(projectJson, {})

            expect(project).to.exist()
            log.info("✓ text2speech_setVoice compiles successfully")
        end)

        it("should compile text2speech_setLanguage block", function()
            SB3Builder.resetCounter()
            local stage = SB3Builder.createStage()
            local sprite = SB3Builder.createSprite("Speaker")

            local hatId, hatBlock = SB3Builder.Events.whenFlagClicked()
            local langId, langBlock = SB3Builder.createBlock("text2speech_setLanguage", {
                LANGUAGE = "en"
            })

            SB3Builder.addBlock(sprite, hatId, hatBlock)
            SB3Builder.addBlock(sprite, langId, langBlock)
            SB3Builder.linkBlocks(sprite, {hatId, langId})

            local projectJson = SB3Builder.createProject({stage, sprite})
            local project = ProjectModel:new(projectJson, {})

            expect(project).to.exist()
            log.info("✓ text2speech_setLanguage compiles successfully")
        end)
    end)

    describe("Voice state management", function()
        it("should initialize voice state with default values", function()
            SB3Builder.resetCounter()
            local stage = SB3Builder.createStage()
            local sprite = SB3Builder.createSprite("Speaker")

            local hatId, hatBlock = SB3Builder.Events.whenFlagClicked()
            local voiceId, voiceBlock = SB3Builder.createBlock("text2speech_setVoice", {
                VOICE = "tenor"
            })

            SB3Builder.addBlock(sprite, hatId, hatBlock)
            SB3Builder.addBlock(sprite, voiceId, voiceBlock)
            SB3Builder.linkBlocks(sprite, {hatId, voiceId})

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

            local spriteTarget = runtime:getSpriteTargetByName("Speaker")
            expect(spriteTarget.text2speechState).to.exist()
            expect(spriteTarget.text2speechState.voiceId).to.equal("tenor")

            log.info("✓ Voice state initialized and set correctly")
        end)

        it("should store language in stage target", function()
            SB3Builder.resetCounter()
            local stage = SB3Builder.createStage()
            local sprite = SB3Builder.createSprite("Speaker")

            local hatId, hatBlock = SB3Builder.Events.whenFlagClicked()
            local langId, langBlock = SB3Builder.createBlock("text2speech_setLanguage", {
                LANGUAGE = "es"
            })

            SB3Builder.addBlock(sprite, hatId, hatBlock)
            SB3Builder.addBlock(sprite, langId, langBlock)
            SB3Builder.linkBlocks(sprite, {hatId, langId})

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

            -- Find stage target
            local stageTarget = nil
            for _, target in ipairs(runtime.targets) do
                if target.isStage then
                    stageTarget = target
                    break
                end
            end
            expect(stageTarget.textToSpeechLanguage).to.equal("es")

            log.info("✓ Language stored in stage target")
        end)
    end)

    describe("Combined workflow", function()
        it("should set voice and language then attempt to speak", function()
            SB3Builder.resetCounter()
            local stage = SB3Builder.createStage()
            local sprite = SB3Builder.createSprite("Speaker")

            -- Create script: set voice -> set language -> speak
            local hatId, hatBlock = SB3Builder.Events.whenFlagClicked()

            local voiceId, voiceBlock = SB3Builder.createBlock("text2speech_setVoice", {
                VOICE = "kitten"
            })

            local langId, langBlock = SB3Builder.createBlock("text2speech_setLanguage", {
                LANGUAGE = "en"
            })

            local speakId, speakBlock = SB3Builder.createBlock("text2speech_speakAndWait", {
                WORDS = "Hello"
            })

            SB3Builder.addBlock(sprite, hatId, hatBlock)
            SB3Builder.addBlock(sprite, voiceId, voiceBlock)
            SB3Builder.addBlock(sprite, langId, langBlock)
            SB3Builder.addBlock(sprite, speakId, speakBlock)
            SB3Builder.linkBlocks(sprite, {hatId, voiceId, langId, speakId})

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

            -- Verify final state
            local spriteTarget = runtime:getSpriteTargetByName("Speaker")
            -- Find stage target
            local stageTarget = nil
            for _, target in ipairs(runtime.targets) do
                if target.isStage then
                    stageTarget = target
                    break
                end
            end

            expect(spriteTarget.text2speechState.voiceId).to.equal("kitten")
            expect(stageTarget.textToSpeechLanguage).to.equal("en")

            log.info("✓ Combined voice, language, and speak workflow executed")
        end)
    end)

    describe("Voice validation", function()
        it("should accept all valid voice IDs", function()
            local validVoices = {"alto", "tenor", "squeak", "giant", "kitten"}

            for _, voice in ipairs(validVoices) do
                SB3Builder.resetCounter()
                local stage = SB3Builder.createStage()
                local sprite = SB3Builder.createSprite("Speaker")

                local hatId, hatBlock = SB3Builder.Events.whenFlagClicked()
                local voiceId, voiceBlock = SB3Builder.createBlock("text2speech_setVoice", {
                    VOICE = voice
                })

                SB3Builder.addBlock(sprite, hatId, hatBlock)
                SB3Builder.addBlock(sprite, voiceId, voiceBlock)
                SB3Builder.linkBlocks(sprite, {hatId, voiceId})

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

                local spriteTarget = runtime:getSpriteTargetByName("Speaker")
                expect(spriteTarget.text2speechState.voiceId).to.equal(voice)
            end

            log.info("✓ All valid voice IDs accepted: alto, tenor, squeak, giant, kitten")
        end)
    end)

    describe("Language validation", function()
        it("should accept common language codes", function()
            local validLanguages = {"en", "es", "fr", "de", "zh-cn", "ja"}

            for _, lang in ipairs(validLanguages) do
                SB3Builder.resetCounter()
                local stage = SB3Builder.createStage()
                local sprite = SB3Builder.createSprite("Speaker")

                local hatId, hatBlock = SB3Builder.Events.whenFlagClicked()
                local langId, langBlock = SB3Builder.createBlock("text2speech_setLanguage", {
                    LANGUAGE = lang
                })

                SB3Builder.addBlock(sprite, hatId, hatBlock)
                SB3Builder.addBlock(sprite, langId, langBlock)
                SB3Builder.linkBlocks(sprite, {hatId, langId})

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

                -- Find stage target
            local stageTarget = nil
            for _, target in ipairs(runtime.targets) do
                if target.isStage then
                    stageTarget = target
                    break
                end
            end
                expect(stageTarget.textToSpeechLanguage).to.equal(lang)
            end

            log.info("✓ All tested language codes accepted: en, es, fr, de, zh-cn, ja")
        end)
    end)
end)
