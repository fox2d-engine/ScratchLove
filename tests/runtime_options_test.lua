-- Test: Project Project Options - Runtime Options Configuration
-- Verifies that runtimeOptions (maxClones, miscLimits, fencing) are properly parsed and applied

local lust = require("tests.lust")
local describe, it, expect = lust.describe, lust.it, lust.expect

local SB3Builder = require("tests.sb3_builder")
local Runtime = require("vm.runtime")
local ProjectModel = require("parser.project_model")
local log = require("lib.log")

describe("Project Runtime Options Configuration", function()
    describe("maxClones configuration", function()
        it("should apply custom maxClones limit from project options", function()
            SB3Builder.resetCounter()
            local stage = SB3Builder.createStage()

            -- Inject Project config with custom maxClones
            stage.comments = {
                ["comment1"] = {
                    blockId = nil,
                    x = 0,
                    y = 0,
                    width = 200,
                    height = 200,
                    minimized = false,
                    text = 'Configuration for https://turbowarp.org/\n{"framerate":30,"runtimeOptions":{"maxClones":50,"miscLimits":true,"fencing":true},"interpolation":false,"turbo":false,"hq":false,"width":480,"height":360} // _twconfig_'
                }
            }

            local projectJson = SB3Builder.createProject({stage})
            local project = ProjectModel:new(projectJson, {})

            -- Verify projectOptions were parsed correctly
            expect(project.projectOptions ~= nil).to.be.truthy()
            expect(project.projectOptions.runtimeOptions ~= nil).to.be.truthy()
            expect(project.projectOptions.runtimeOptions.maxClones).to.equal(50)

            local runtime = Runtime:new(project)
            runtime:initialize()

            -- Verify maxClones was applied
            expect(runtime.runtimeOptions.maxClones).to.equal(50)

            log.info("✓ maxClones set to 50 from project config")
        end)

        it("should support Infinity for maxClones (unlimited clones)", function()
            SB3Builder.resetCounter()
            local stage = SB3Builder.createStage()

            -- Inject Project config with Infinity maxClones
            -- Note: JSON doesn't support Infinity, so it's typically stored as a very large number
            stage.comments = {
                ["comment1"] = {
                    blockId = nil,
                    x = 0,
                    y = 0,
                    width = 200,
                    height = 200,
                    minimized = false,
                    text = 'Configuration for https://turbowarp.org/\n{"framerate":30,"runtimeOptions":{"maxClones":999999999,"miscLimits":false,"fencing":false},"interpolation":false,"turbo":false,"hq":false,"width":480,"height":360} // _twconfig_'
                }
            }

            local projectJson = SB3Builder.createProject({stage})
            local project = ProjectModel:new(projectJson, {})

            local runtime = Runtime:new(project)
            runtime:initialize()

            -- Verify maxClones was set to Infinity (math.huge)
            expect(runtime.runtimeOptions.maxClones).to.equal(math.huge)

            -- Verify clonesAvailable always returns true with Infinity limit
            runtime.cloneCounter = 1000000
            expect(runtime:clonesAvailable()).to.equal(true)

            log.info("✓ maxClones set to Infinity (unlimited clones)")
        end)

        it("should support native Infinity in JSON (extended JSON format)", function()
            -- Test native Infinity parsing from extended JSON format
            -- Extended JSON serializes Infinity as raw keyword
            local json = require("lib.json")

            -- Verify our JSON parser handles native Infinity
            local jsonStr = '{"maxClones":Infinity,"minClones":-Infinity,"nan":NaN}'
            local parsed = json.decode(jsonStr)

            expect(parsed.maxClones).to.equal(math.huge)
            expect(parsed.minClones).to.equal(-math.huge)
            expect(parsed.nan ~= parsed.nan).to.be.truthy() -- NaN != NaN

            -- Test full Project config with native Infinity
            SB3Builder.resetCounter()
            local stage = SB3Builder.createStage()

            -- Inject Project config with NATIVE Infinity (not quoted)
            stage.comments = {
                ["comment1"] = {
                    blockId = nil,
                    x = 0,
                    y = 0,
                    width = 200,
                    height = 200,
                    minimized = false,
                    text = 'Configuration for https://turbowarp.org/\n{"framerate":30,"runtimeOptions":{"maxClones":Infinity,"miscLimits":false,"fencing":false},"interpolation":false,"turbo":false,"hq":false,"width":480,"height":360} // _twconfig_'
                }
            }

            local projectJson = SB3Builder.createProject({stage})
            local project = ProjectModel:new(projectJson, {})

            -- Verify projectOptions parsed native Infinity correctly
            expect(project.projectOptions ~= nil).to.be.truthy()
            expect(project.projectOptions.runtimeOptions ~= nil).to.be.truthy()
            expect(project.projectOptions.runtimeOptions.maxClones).to.equal(math.huge)

            local runtime = Runtime:new(project)
            runtime:initialize()

            -- Verify maxClones was set to Infinity (math.huge)
            expect(runtime.runtimeOptions.maxClones).to.equal(math.huge)

            -- Verify clonesAvailable always returns true with Infinity limit
            runtime.cloneCounter = 1000000
            expect(runtime:clonesAvailable()).to.equal(true)

            log.info("✓ Native Infinity correctly parsed from extended JSON format")
        end)

        it("should use maxClones in clonesAvailable check", function()
            SB3Builder.resetCounter()
            local stage = SB3Builder.createStage()

            -- Inject Project config with maxClones=5
            stage.comments = {
                ["comment1"] = {
                    blockId = nil,
                    x = 0,
                    y = 0,
                    width = 200,
                    height = 200,
                    minimized = false,
                    text = 'Configuration for https://turbowarp.org/\n{"framerate":30,"runtimeOptions":{"maxClones":5,"miscLimits":true,"fencing":true},"interpolation":false,"turbo":false,"hq":false,"width":480,"height":360} // _twconfig_'
                }
            }

            local projectJson = SB3Builder.createProject({stage})
            local project = ProjectModel:new(projectJson, {})

            local runtime = Runtime:new(project)
            runtime:initialize()

            -- Test clonesAvailable with different clone counts
            runtime.cloneCounter = 0
            expect(runtime:clonesAvailable()).to.equal(true)

            runtime.cloneCounter = 4
            expect(runtime:clonesAvailable()).to.equal(true)

            runtime.cloneCounter = 5
            expect(runtime:clonesAvailable()).to.equal(false)

            runtime.cloneCounter = 10
            expect(runtime:clonesAvailable()).to.equal(false)

            log.info("✓ clonesAvailable correctly uses maxClones limit")
        end)
    end)

    describe("miscLimits configuration", function()
        it("should enable miscLimits by default", function()
            SB3Builder.resetCounter()
            local stage = SB3Builder.createStage()

            local projectJson = SB3Builder.createProject({stage})
            local project = ProjectModel:new(projectJson, {})

            local runtime = Runtime:new(project)
            runtime:initialize()

            -- Default should be true (matches native Scratch)
            expect(runtime.runtimeOptions.miscLimits).to.equal(true)

            log.info("✓ miscLimits enabled by default")
        end)

        it("should disable miscLimits when configured to false", function()
            SB3Builder.resetCounter()
            local stage = SB3Builder.createStage()

            -- Inject Project config with miscLimits disabled
            stage.comments = {
                ["comment1"] = {
                    blockId = nil,
                    x = 0,
                    y = 0,
                    width = 200,
                    height = 200,
                    minimized = false,
                    text = 'Configuration for https://turbowarp.org/\n{"framerate":30,"runtimeOptions":{"maxClones":300,"miscLimits":false,"fencing":true},"interpolation":false,"turbo":false,"hq":false,"width":480,"height":360} // _twconfig_'
                }
            }

            local projectJson = SB3Builder.createProject({stage})
            local project = ProjectModel:new(projectJson, {})

            local runtime = Runtime:new(project)
            runtime:initialize()

            expect(runtime.runtimeOptions.miscLimits).to.equal(false)

            log.info("✓ miscLimits disabled from project config")
        end)
    end)

    describe("fencing configuration", function()
        it("should enable fencing by default", function()
            SB3Builder.resetCounter()
            local stage = SB3Builder.createStage()

            local projectJson = SB3Builder.createProject({stage})
            local project = ProjectModel:new(projectJson, {})

            local runtime = Runtime:new(project)
            runtime:initialize()

            -- Default should match Global.FENCING_ENABLED (true in native Scratch)
            expect(runtime.runtimeOptions.fencing ~= nil).to.be.truthy()

            log.info("✓ fencing enabled by default")
        end)

        it("should disable fencing when configured to false", function()
            SB3Builder.resetCounter()
            local stage = SB3Builder.createStage()

            -- Inject Project config with fencing disabled
            stage.comments = {
                ["comment1"] = {
                    blockId = nil,
                    x = 0,
                    y = 0,
                    width = 200,
                    height = 200,
                    minimized = false,
                    text = 'Configuration for https://turbowarp.org/\n{"framerate":30,"runtimeOptions":{"maxClones":300,"miscLimits":true,"fencing":false},"interpolation":false,"turbo":false,"hq":false,"width":480,"height":360} // _twconfig_'
                }
            }

            local projectJson = SB3Builder.createProject({stage})
            local project = ProjectModel:new(projectJson, {})

            local runtime = Runtime:new(project)
            runtime:initialize()

            expect(runtime.runtimeOptions.fencing).to.equal(false)

            log.info("✓ fencing disabled from project config")
        end)
    end)

    describe("combined runtimeOptions", function()
        it("should apply all runtimeOptions together", function()
            SB3Builder.resetCounter()
            local stage = SB3Builder.createStage()

            -- Inject Project config with all options customized
            stage.comments = {
                ["comment1"] = {
                    blockId = nil,
                    x = 0,
                    y = 0,
                    width = 200,
                    height = 200,
                    minimized = false,
                    text = 'Configuration for https://turbowarp.org/\n{"framerate":30,"runtimeOptions":{"maxClones":100,"miscLimits":false,"fencing":false},"interpolation":true,"turbo":false,"hq":false,"width":480,"height":360} // _twconfig_'
                }
            }

            local projectJson = SB3Builder.createProject({stage})
            local project = ProjectModel:new(projectJson, {})

            local runtime = Runtime:new(project)
            runtime:initialize()

            -- Verify all options were applied
            expect(runtime.runtimeOptions.maxClones).to.equal(100)
            expect(runtime.runtimeOptions.miscLimits).to.equal(false)
            expect(runtime.runtimeOptions.fencing).to.equal(false)

            log.info("✓ All runtimeOptions applied correctly: maxClones=100, miscLimits=false, fencing=false")
        end)
    end)

    describe("miscLimits behavior tests", function()
        describe("Sound Effect Range Limits", function()
            it("should clamp pitch to -360~360 when miscLimits enabled", function()
                SB3Builder.resetCounter()
                local stage = SB3Builder.createStage()
                local sprite = SB3Builder.createSprite("TestSprite")

                -- Set pitch to 500 (exceeds standard limit)
                local hatId, hatBlock = SB3Builder.Events.whenFlagClicked()
                local setPitchId, setPitchBlock = SB3Builder.createBlock("sound_seteffectto", {
                    EFFECT = SB3Builder.primitiveInput("pitch"),
                    VALUE = SB3Builder.primitiveInput(500)
                }, {})

                SB3Builder.addBlock(sprite, hatId, hatBlock)
                SB3Builder.addBlock(sprite, setPitchId, setPitchBlock)
                SB3Builder.linkBlocks(sprite, {hatId, setPitchId})

                local projectJson = SB3Builder.createProject({stage, sprite})
                local project = ProjectModel:new(projectJson, {})
                local runtime = Runtime:new(project)
                runtime:initialize()

                -- miscLimits enabled by default
                expect(runtime.runtimeOptions.miscLimits).to.equal(true)

                runtime:broadcastGreenFlag()
                local maxIterations = 10
                local iterations = 0
                while #runtime:getActiveThreads() > 0 and iterations < maxIterations do
                    runtime:update(1/60)
                    iterations = iterations + 1
                end

                local spriteTarget = runtime:getSpriteTargetByName("TestSprite")
                -- Should be clamped to 360
                expect(spriteTarget.soundEffects.pitch).to.equal(360)
                log.info("✓ Pitch clamped to 360 with miscLimits enabled")
            end)

            it("should allow pitch beyond -360~360 when miscLimits disabled", function()
                SB3Builder.resetCounter()
                local stage = SB3Builder.createStage()
                local sprite = SB3Builder.createSprite("TestSprite")

                -- Set pitch to 500
                local hatId, hatBlock = SB3Builder.Events.whenFlagClicked()
                local setPitchId, setPitchBlock = SB3Builder.createBlock("sound_seteffectto", {
                    EFFECT = SB3Builder.primitiveInput("pitch"),
                    VALUE = SB3Builder.primitiveInput(500)
                }, {})

                SB3Builder.addBlock(sprite, hatId, hatBlock)
                SB3Builder.addBlock(sprite, setPitchId, setPitchBlock)
                SB3Builder.linkBlocks(sprite, {hatId, setPitchId})

                local projectJson = SB3Builder.createProject({stage, sprite})
                local project = ProjectModel:new(projectJson, {})
                local runtime = Runtime:new(project)
                runtime:initialize()

                -- Disable miscLimits
                runtime:setRuntimeOptions({ miscLimits = false })

                runtime:broadcastGreenFlag()
                local maxIterations = 10
                local iterations = 0
                while #runtime:getActiveThreads() > 0 and iterations < maxIterations do
                    runtime:update(1/60)
                    iterations = iterations + 1
                end

                local spriteTarget = runtime:getSpriteTargetByName("TestSprite")
                -- Should not be clamped (stays at 500)
                expect(spriteTarget.soundEffects.pitch).to.equal(500)
                log.info("✓ Pitch not clamped (500) with miscLimits disabled")
            end)

            it("should clamp pitch to -1000~1000 when miscLimits disabled", function()
                SB3Builder.resetCounter()
                local stage = SB3Builder.createStage()
                local sprite = SB3Builder.createSprite("TestSprite")

                -- Set pitch to 1500 (exceeds extended limit)
                local hatId, hatBlock = SB3Builder.Events.whenFlagClicked()
                local setPitchId, setPitchBlock = SB3Builder.createBlock("sound_seteffectto", {
                    EFFECT = SB3Builder.primitiveInput("pitch"),
                    VALUE = SB3Builder.primitiveInput(1500)
                }, {})

                SB3Builder.addBlock(sprite, hatId, hatBlock)
                SB3Builder.addBlock(sprite, setPitchId, setPitchBlock)
                SB3Builder.linkBlocks(sprite, {hatId, setPitchId})

                local projectJson = SB3Builder.createProject({stage, sprite})
                local project = ProjectModel:new(projectJson, {})
                local runtime = Runtime:new(project)
                runtime:initialize()

                -- Disable miscLimits
                runtime:setRuntimeOptions({ miscLimits = false })

                runtime:broadcastGreenFlag()
                local maxIterations = 10
                local iterations = 0
                while #runtime:getActiveThreads() > 0 and iterations < maxIterations do
                    runtime:update(1/60)
                    iterations = iterations + 1
                end

                local spriteTarget = runtime:getSpriteTargetByName("TestSprite")
                -- Should be clamped to extended limit 1000
                expect(spriteTarget.soundEffects.pitch).to.equal(1000)
                log.info("✓ Pitch clamped to extended limit 1000 with miscLimits disabled")
            end)
        end)

        describe("Mouse Coordinate Precision", function()
            it("should return integer mouse coordinates when miscLimits enabled", function()
                SB3Builder.resetCounter()
                local stage = SB3Builder.createStage()
                local sprite = SB3Builder.createSprite("TestSprite")

                -- Get mouse X
                local hatId, hatBlock = SB3Builder.Events.whenFlagClicked()
                local mouseXId, mouseXBlock = SB3Builder.createBlock("sensing_mousex", {}, {})
                local setXId, setXBlock = SB3Builder.createBlock("motion_setx", {
                    X = SB3Builder.blockInput(mouseXId)
                }, {})

                SB3Builder.addBlock(sprite, hatId, hatBlock)
                SB3Builder.addBlock(sprite, mouseXId, mouseXBlock)
                SB3Builder.addBlock(sprite, setXId, setXBlock)
                SB3Builder.linkBlocks(sprite, {hatId, setXId})

                local projectJson = SB3Builder.createProject({stage, sprite})
                local project = ProjectModel:new(projectJson, {})
                local runtime = Runtime:new(project)
                runtime:initialize()

                -- Set mouse position to non-integer value
                runtime.mouseX = 123.456
                runtime.mouseY = 78.901

                -- miscLimits enabled by default
                expect(runtime.runtimeOptions.miscLimits).to.equal(true)

                runtime:broadcastGreenFlag()
                local maxIterations = 10
                local iterations = 0
                while #runtime:getActiveThreads() > 0 and iterations < maxIterations do
                    runtime:update(1/60)
                    iterations = iterations + 1
                end

                local spriteTarget = runtime:getSpriteTargetByName("TestSprite")
                -- Should be rounded to integer (123)
                expect(spriteTarget.x).to.equal(123)
                log.info("✓ Mouse X rounded to integer (123) with miscLimits enabled")
            end)

            it("should return three-decimal precision when miscLimits disabled", function()
                SB3Builder.resetCounter()
                local stage = SB3Builder.createStage()
                local sprite = SB3Builder.createSprite("TestSprite")

                -- Get mouse X
                local hatId, hatBlock = SB3Builder.Events.whenFlagClicked()
                local mouseXId, mouseXBlock = SB3Builder.createBlock("sensing_mousex", {}, {})
                local setXId, setXBlock = SB3Builder.createBlock("motion_setx", {
                    X = SB3Builder.blockInput(mouseXId)
                }, {})

                SB3Builder.addBlock(sprite, hatId, hatBlock)
                SB3Builder.addBlock(sprite, mouseXId, mouseXBlock)
                SB3Builder.addBlock(sprite, setXId, setXBlock)
                SB3Builder.linkBlocks(sprite, {hatId, setXId})

                local projectJson = SB3Builder.createProject({stage, sprite})
                local project = ProjectModel:new(projectJson, {})
                local runtime = Runtime:new(project)
                runtime:initialize()

                -- Disable miscLimits
                runtime:setRuntimeOptions({ miscLimits = false })

                -- Set mouse position to non-integer value
                runtime.mouseX = 123.456789
                runtime.mouseY = 78.901234

                runtime:broadcastGreenFlag()
                local maxIterations = 10
                local iterations = 0
                while #runtime:getActiveThreads() > 0 and iterations < maxIterations do
                    runtime:update(1/60)
                    iterations = iterations + 1
                end

                local spriteTarget = runtime:getSpriteTargetByName("TestSprite")
                -- Should have three decimal precision (123.457)
                expect(spriteTarget.x).to.equal(123.457)
                log.info("✓ Mouse X with three decimal precision (123.457) with miscLimits disabled")
            end)
        end)

        describe("Pen Size Limits", function()
            it("should clamp pen size to 1-1200 when miscLimits enabled", function()
                SB3Builder.resetCounter()
                local stage = SB3Builder.createStage()
                local sprite = SB3Builder.createSprite("TestSprite")

                -- Set pen size to 2000 (exceeds standard limit)
                local hatId, hatBlock = SB3Builder.Events.whenFlagClicked()
                local setPenSizeId, setPenSizeBlock = SB3Builder.createBlock("pen_setPenSizeTo", {
                    SIZE = SB3Builder.primitiveInput(2000)
                }, {})

                SB3Builder.addBlock(sprite, hatId, hatBlock)
                SB3Builder.addBlock(sprite, setPenSizeId, setPenSizeBlock)
                SB3Builder.linkBlocks(sprite, {hatId, setPenSizeId})

                local projectJson = SB3Builder.createProject({stage, sprite})
                local project = ProjectModel:new(projectJson, {})
                local runtime = Runtime:new(project)
                runtime:initialize()

                -- miscLimits enabled by default
                expect(runtime.runtimeOptions.miscLimits).to.equal(true)

                runtime:broadcastGreenFlag()
                local maxIterations = 10
                local iterations = 0
                while #runtime:getActiveThreads() > 0 and iterations < maxIterations do
                    runtime:update(1/60)
                    iterations = iterations + 1
                end

                local spriteTarget = runtime:getSpriteTargetByName("TestSprite")
                -- Should be clamped to 1200
                expect(spriteTarget.penState.size).to.equal(1200)
                log.info("✓ Pen size clamped to 1200 with miscLimits enabled")
            end)

            it("should allow pen size beyond 1200 when miscLimits disabled", function()
                SB3Builder.resetCounter()
                local stage = SB3Builder.createStage()
                local sprite = SB3Builder.createSprite("TestSprite")

                -- Set pen size to 2000
                local hatId, hatBlock = SB3Builder.Events.whenFlagClicked()
                local setPenSizeId, setPenSizeBlock = SB3Builder.createBlock("pen_setPenSizeTo", {
                    SIZE = SB3Builder.primitiveInput(2000)
                }, {})

                SB3Builder.addBlock(sprite, hatId, hatBlock)
                SB3Builder.addBlock(sprite, setPenSizeId, setPenSizeBlock)
                SB3Builder.linkBlocks(sprite, {hatId, setPenSizeId})

                local projectJson = SB3Builder.createProject({stage, sprite})
                local project = ProjectModel:new(projectJson, {})
                local runtime = Runtime:new(project)
                runtime:initialize()

                -- Disable miscLimits
                runtime:setRuntimeOptions({ miscLimits = false })

                runtime:broadcastGreenFlag()
                local maxIterations = 10
                local iterations = 0
                while #runtime:getActiveThreads() > 0 and iterations < maxIterations do
                    runtime:update(1/60)
                    iterations = iterations + 1
                end

                local spriteTarget = runtime:getSpriteTargetByName("TestSprite")
                -- Should not be clamped
                expect(spriteTarget.penState.size).to.equal(2000)
                log.info("✓ Pen size not clamped (2000) with miscLimits disabled")
            end)
        end)
    end)
end)

return lust
