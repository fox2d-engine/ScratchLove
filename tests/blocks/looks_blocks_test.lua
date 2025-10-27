-- Looks Blocks Test

local lust = require("tests.lust")
local describe, it, expect = lust.describe, lust.it, lust.expect

local SB3Builder = require("tests.sb3_builder")
local ProjectModel = require("parser.project_model")
local Runtime = require("vm.runtime")

describe("Looks Blocks", function()
    ---Test costume switching behavior for sprites or backdrops for stage
    ---@param costumes string[] List of costume names as strings
    ---@param arg string|number|boolean The argument to provide to the block
    ---@param currentCostume number|nil The 1-indexed default costume to start at (default: 1)
    ---@param isStage boolean|nil Whether the target is the stage (default: false)
    ---@return number result The 1-indexed costume index after switching
    local function testCostume(costumes, arg, currentCostume, isStage)
        currentCostume = currentCostume or 1
        isStage = isStage or false

        SB3Builder.resetCounter()
        local stage = SB3Builder.createStage()
        local sprite

        if isStage then
            -- Set up stage with backdrops
            stage.costumes = {}
            for i, name in ipairs(costumes) do
                table.insert(stage.costumes, SB3Builder.createCostume(name, "svg"))
            end
            sprite = stage
        else
            -- Set up sprite with costumes
            sprite = SB3Builder.createSprite("TestSprite")
            sprite.costumes = {}
            for i, name in ipairs(costumes) do
                table.insert(sprite.costumes, SB3Builder.createCostume(name, "svg"))
            end
        end

        -- Create switch costume/backdrop block
        local hatId, hatBlock = SB3Builder.Events.whenFlagClicked()
        local switchId, switchBlock

        if isStage then
            switchId, switchBlock = SB3Builder.Looks.switchBackdropTo(arg)
        else
            switchId, switchBlock = SB3Builder.Looks.switchCostumeTo(arg)
        end

        SB3Builder.addBlock(sprite, hatId, hatBlock)
        SB3Builder.addBlock(sprite, switchId, switchBlock)

        SB3Builder.linkBlocks(sprite, {hatId, switchId})

        -- Build and execute project
        local projectJson = SB3Builder.createProject({stage, sprite})
        local project = ProjectModel:new(projectJson, {})
        local runtime = Runtime:new(project)
        runtime:initialize()

        -- Set initial costume (convert from 1-indexed to 0-indexed)
        local target = isStage and runtime.stage or runtime:getSpriteTargetByName("TestSprite")
        target.currentCostume = currentCostume - 1

        -- Execute script with safe iteration limit
        runtime:broadcastGreenFlag()
        local maxIterations = 100
        local iterations = 0
        while #runtime:getActiveThreads() > 0 and iterations < maxIterations do
            runtime:update(1/60)
            iterations = iterations + 1
        end

        -- Return 1-indexed costume
        return target.currentCostume + 1
    end

    ---Test backdrop switching (convenience function)
    ---@param backdrops string[] List of backdrop names
    ---@param arg string|number|boolean The argument to provide to the block
    ---@param currentCostume number|nil The 1-indexed default backdrop to start at
    ---@return number result The 1-indexed backdrop index after switching
    local function testBackdrop(backdrops, arg, currentCostume)
        return testCostume(backdrops, arg, currentCostume, true)
    end

    describe("switch costume block", function()
        it("should do nothing for non-existent costumes", function()
            expect(testCostume({'a', 'b', 'c', 'd'}, 'e', 3)).to.equal(3)
        end)

        it("should handle numeric vs string arguments correctly", function()
            -- Numeric arguments are costume index
            expect(testCostume({'a', 'b', 'c', '2'}, 2)).to.equal(2)
            -- String arguments are costume names first, then coerced to index
            expect(testCostume({'a', 'b', 'c', '2'}, '2')).to.equal(4)
            expect(testCostume({'a', 'b', 'c'}, '2')).to.equal(2)
        end)

        it("should handle 'previous costume' and 'next costume'", function()
            expect(testCostume({'a', 'b', 'c', 'd'}, 'previous costume', 3)).to.equal(2)
            expect(testCostume({'a', 'b', 'c', 'd'}, 'next costume', 2)).to.equal(3)
        end)

        it("should allow 'previous costume' and 'next costume' to be overridden", function()
            expect(testCostume({'a', 'previous costume', 'c', 'd'}, 'previous costume')).to.equal(2)
            expect(testCostume({'next costume', 'b', 'c', 'd'}, 'next costume')).to.equal(1)
        end)

        it("should treat NaN, Infinity, and true as first costume", function()
            expect(testCostume({'a', 'b', 'c', 'd'}, 0/0, 2)).to.equal(1) -- NaN
            expect(testCostume({'a', 'b', 'c', 'd'}, true, 2)).to.equal(1)
            expect(testCostume({'a', 'b', 'c', 'd'}, math.huge, 2)).to.equal(1) -- Infinity
            expect(testCostume({'a', 'b', 'c', 'd'}, -math.huge, 2)).to.equal(1) -- -Infinity
        end)

        it("should ignore backdrop commands", function()
            expect(testCostume({'a', 'b', 'c', 'd'}, 'previous backdrop', 3)).to.equal(3)
            expect(testCostume({'a', 'b', 'c', 'd'}, 'next backdrop', 3)).to.equal(3)
        end)

        it("should ignore whitespace-only strings", function()
            expect(testCostume({'a', 'b', 'c', 'd'}, '    ', 2)).to.equal(2)
        end)

        it("should treat false as 0 (last costume)", function()
            expect(testCostume({'a', 'b', 'c', 'd'}, false)).to.equal(4)
        end)

        it("should use booleans as costume names when possible", function()
            expect(testCostume({'a', 'true', 'false', 'd'}, false)).to.equal(3)
            expect(testCostume({'a', 'true', 'false', 'd'}, true)).to.equal(2)
        end)

        it("should wrap costume indices around", function()
            expect(testCostume({'a', 'b', 'c', 'd'}, -1)).to.equal(3)
            expect(testCostume({'a', 'b', 'c', 'd'}, -4)).to.equal(4)
            expect(testCostume({'a', 'b', 'c', 'd'}, 10)).to.equal(2)
        end)
    end)

    describe("switch backdrop block", function()
        it("should do nothing for non-existent backdrops", function()
            expect(testBackdrop({'a', 'b', 'c', 'd'}, 'e', 3)).to.equal(3)
        end)

        it("should handle numeric vs string arguments correctly", function()
            expect(testBackdrop({'a', 'b', 'c', '2'}, 2)).to.equal(2)
            expect(testBackdrop({'a', 'b', 'c', '2'}, '2')).to.equal(4)
        end)

        it("should handle 'previous backdrop' and 'next backdrop'", function()
            expect(testBackdrop({'a', 'b', 'c', 'd'}, 'previous backdrop', 3)).to.equal(2)
            expect(testBackdrop({'a', 'b', 'c', 'd'}, 'next backdrop', 2)).to.equal(3)
        end)

        it("should allow backdrop commands to be overridden", function()
            expect(testBackdrop({'a', 'previous backdrop', 'c', 'd'}, 'previous backdrop', 4)).to.equal(2)
            expect(testBackdrop({'next backdrop', 'b', 'c', 'd'}, 'next backdrop', 3)).to.equal(1)
            expect(testBackdrop({'random backdrop', 'b', 'c', 'd'}, 'random backdrop')).to.equal(1)
        end)

        it("should treat NaN, Infinity, and true as first backdrop", function()
            expect(testBackdrop({'a', 'b', 'c', 'd'}, 0/0, 2)).to.equal(1) -- NaN
            expect(testBackdrop({'a', 'b', 'c', 'd'}, true, 2)).to.equal(1)
            expect(testBackdrop({'a', 'b', 'c', 'd'}, math.huge, 2)).to.equal(1) -- Infinity
            expect(testBackdrop({'a', 'b', 'c', 'd'}, -math.huge, 2)).to.equal(1) -- -Infinity
        end)

        it("should ignore costume commands", function()
            expect(testBackdrop({'a', 'b', 'c', 'd'}, 'previous costume', 3)).to.equal(3)
            expect(testBackdrop({'a', 'b', 'c', 'd'}, 'next costume', 3)).to.equal(3)
        end)

        it("should ignore whitespace-only strings", function()
            expect(testBackdrop({'a', 'b', 'c', 'd'}, '    ', 2)).to.equal(2)
        end)

        it("should treat false as 0 (last backdrop)", function()
            expect(testBackdrop({'a', 'b', 'c', 'd'}, false)).to.equal(4)
        end)

        it("should use booleans as backdrop names when possible", function()
            expect(testBackdrop({'a', 'true', 'false', 'd'}, false)).to.equal(3)
            expect(testBackdrop({'a', 'true', 'false', 'd'}, true)).to.equal(2)
        end)

        it("should wrap backdrop indices around", function()
            expect(testBackdrop({'a', 'b', 'c', 'd'}, -1)).to.equal(3)
            expect(testBackdrop({'a', 'b', 'c', 'd'}, -4)).to.equal(4)
            expect(testBackdrop({'a', 'b', 'c', 'd'}, 10)).to.equal(2)
        end)
    end)

    describe("costume/backdrop number/name reporter", function()
        it("should return 1-indexed costume number", function()
            SB3Builder.resetCounter()
            local stage = SB3Builder.createStage()
            local sprite = SB3Builder.createSprite("TestSprite")

            -- Add costumes
            sprite.costumes = {
                SB3Builder.createCostume("first", "svg"),
                SB3Builder.createCostume("second", "svg"),
                SB3Builder.createCostume("third", "svg")
            }

            -- Add variable to store result
            local varId = SB3Builder.addVariable(sprite, "result", 0)

            -- Use reporter as input to setVariable command block
            local hatId, hatBlock = SB3Builder.Events.whenFlagClicked()
            local reportId, reportBlock = SB3Builder.Looks.costumeNumberName("number")
            local setId, setBlock = SB3Builder.Data.setVariable("result", reportId, varId)

            SB3Builder.addBlock(sprite, hatId, hatBlock)
            SB3Builder.addBlock(sprite, reportId, reportBlock)
            SB3Builder.addBlock(sprite, setId, setBlock)
            SB3Builder.linkBlocks(sprite, {hatId, setId})

            local projectJson = SB3Builder.createProject({stage, sprite})
            local project = ProjectModel:new(projectJson, {})
            local runtime = Runtime:new(project)
            runtime:initialize()

            local target = runtime:getSpriteTargetByName("TestSprite")
            target.currentCostume = 0 -- 0-indexed internally

            -- Execute through runtime
            runtime:broadcastGreenFlag()
            local maxIterations = 10
            local iterations = 0
            while #runtime:getActiveThreads() > 0 and iterations < maxIterations do
                runtime:update(1/60)
                iterations = iterations + 1
            end

            -- Check variable value
            local variable = target.variables[varId]
            expect(variable.value).to.equal(1)
        end)

        it("should return costume name", function()
            SB3Builder.resetCounter()
            local stage = SB3Builder.createStage()
            local sprite = SB3Builder.createSprite("TestSprite")

            sprite.costumes = {
                SB3Builder.createCostume("first name", "svg"),
                SB3Builder.createCostume("second name", "svg"),
                SB3Builder.createCostume("third name", "svg")
            }

            -- Add variable to store result
            local varId = SB3Builder.addVariable(sprite, "result", "")

            -- Use reporter as input to setVariable command block
            local hatId, hatBlock = SB3Builder.Events.whenFlagClicked()
            local reportId, reportBlock = SB3Builder.Looks.costumeNumberName("name")
            local setId, setBlock = SB3Builder.Data.setVariable("result", reportId, varId)

            SB3Builder.addBlock(sprite, hatId, hatBlock)
            SB3Builder.addBlock(sprite, reportId, reportBlock)
            SB3Builder.addBlock(sprite, setId, setBlock)
            SB3Builder.linkBlocks(sprite, {hatId, setId})

            local projectJson = SB3Builder.createProject({stage, sprite})
            local project = ProjectModel:new(projectJson, {})
            local runtime = Runtime:new(project)
            runtime:initialize()

            local target = runtime:getSpriteTargetByName("TestSprite")
            target.currentCostume = 0 -- 0-indexed internally

            -- Execute through runtime
            runtime:broadcastGreenFlag()
            local maxIterations = 10
            local iterations = 0
            while #runtime:getActiveThreads() > 0 and iterations < maxIterations do
                runtime:update(1/60)
                iterations = iterations + 1
            end

            -- Check variable value
            local variable = target.variables[varId]
            expect(variable.value).to.equal("first name")
        end)

        it("should return 1-indexed backdrop number", function()
            SB3Builder.resetCounter()
            local stage = SB3Builder.createStage()

            stage.costumes = {
                SB3Builder.createCostume("first", "svg"),
                SB3Builder.createCostume("second", "svg"),
                SB3Builder.createCostume("third", "svg")
            }

            -- Add variable to store result
            local varId = SB3Builder.addVariable(stage, "result", 0)

            -- Use reporter as input to setVariable command block
            local hatId, hatBlock = SB3Builder.Events.whenFlagClicked()
            local reportId, reportBlock = SB3Builder.Looks.backdropNumberName("number")
            local setId, setBlock = SB3Builder.Data.setVariable("result", reportId, varId)

            SB3Builder.addBlock(stage, hatId, hatBlock)
            SB3Builder.addBlock(stage, reportId, reportBlock)
            SB3Builder.addBlock(stage, setId, setBlock)
            SB3Builder.linkBlocks(stage, {hatId, setId})

            local projectJson = SB3Builder.createProject({stage})
            local project = ProjectModel:new(projectJson, {})
            local runtime = Runtime:new(project)
            runtime:initialize()

            runtime.stage.currentCostume = 2 -- 0-indexed internally

            -- Execute through runtime
            runtime:broadcastGreenFlag()
            local maxIterations = 10
            local iterations = 0
            while #runtime:getActiveThreads() > 0 and iterations < maxIterations do
                runtime:update(1/60)
                iterations = iterations + 1
            end

            -- Check variable value
            local variable = runtime.stage.variables[varId]
            expect(variable.value).to.equal(3)
        end)

        it("should return backdrop name", function()
            SB3Builder.resetCounter()
            local stage = SB3Builder.createStage()

            stage.costumes = {
                SB3Builder.createCostume("first name", "svg"),
                SB3Builder.createCostume("second name", "svg"),
                SB3Builder.createCostume("third name", "svg")
            }

            -- Add variable to store result
            local varId = SB3Builder.addVariable(stage, "result", "")

            -- Use reporter as input to setVariable command block
            local hatId, hatBlock = SB3Builder.Events.whenFlagClicked()
            local reportId, reportBlock = SB3Builder.Looks.backdropNumberName("name")
            local setId, setBlock = SB3Builder.Data.setVariable("result", reportId, varId)

            SB3Builder.addBlock(stage, hatId, hatBlock)
            SB3Builder.addBlock(stage, reportId, reportBlock)
            SB3Builder.addBlock(stage, setId, setBlock)
            SB3Builder.linkBlocks(stage, {hatId, setId})

            local projectJson = SB3Builder.createProject({stage})
            local project = ProjectModel:new(projectJson, {})
            local runtime = Runtime:new(project)
            runtime:initialize()

            runtime.stage.currentCostume = 2 -- 0-indexed internally

            -- Execute through runtime
            runtime:broadcastGreenFlag()
            local maxIterations = 10
            local iterations = 0
            while #runtime:getActiveThreads() > 0 and iterations < maxIterations do
                runtime:update(1/60)
                iterations = iterations + 1
            end

            -- Check variable value
            local variable = runtime.stage.variables[varId]
            expect(variable.value).to.equal("third name")
        end)
    end)

    describe("say/think number formatting", function()
        ---Test say/think message formatting
        ---@param message any The message to format
        ---@param expected string The expected formatted result
        local function testSayFormat(message, expected)
            SB3Builder.resetCounter()
            local stage = SB3Builder.createStage()
            local sprite = SB3Builder.createSprite("TestSprite")

            local hatId, hatBlock = SB3Builder.Events.whenFlagClicked()
            local sayId, sayBlock = SB3Builder.Looks.say(message)

            SB3Builder.addBlock(sprite, hatId, hatBlock)
            SB3Builder.addBlock(sprite, sayId, sayBlock)
            SB3Builder.linkBlocks(sprite, {hatId, sayId})

            local projectJson = SB3Builder.createProject({stage, sprite})
            local project = ProjectModel:new(projectJson, {})
            local runtime = Runtime:new(project)
            runtime:initialize()

            -- Execute script with safe iteration limit
            runtime:broadcastGreenFlag()
            local maxIterations = 100
            local iterations = 0
            while #runtime:getActiveThreads() > 0 and iterations < maxIterations do
                runtime:update(1/60)
                iterations = iterations + 1
            end

            local target = runtime:getSpriteTargetByName("TestSprite")
            expect(target.currentMessage).to.equal(expected)
        end

        it("should round to 2 decimal places", function()
            testSayFormat(3.14159, "3.14")
        end)

        it("should not add decimal places to integers", function()
            testSayFormat(3, "3")
        end)

        it("should pad to 2 decimal places when needed", function()
            testSayFormat(3.1, "3.10")
        end)

        it("should not round small numbers that would become 0", function()
            testSayFormat(0.00125, "0.00125")
        end)

        it("should not round strings", function()
            testSayFormat("1.99999", "1.99999")
        end)
    end)

    describe("say for secs behavior", function()
        it("should not auto-clear message after timeout (matches native Scratch)", function()
            SB3Builder.resetCounter()
            local stage = SB3Builder.createStage()
            local sprite = SB3Builder.createSprite("TestSprite")

            -- Create the script: say "first" for 0.1s, say "final"
            local hatId, hatBlock = SB3Builder.Events.whenFlagClicked()
            local sayForSecsId, sayForSecsBlock = SB3Builder.Looks.sayForSecs("first message", 0.1)
            local sayId, sayBlock = SB3Builder.Looks.say("final message")

            SB3Builder.addBlock(sprite, hatId, hatBlock)
            SB3Builder.addBlock(sprite, sayForSecsId, sayForSecsBlock)
            SB3Builder.addBlock(sprite, sayId, sayBlock)

            -- Link blocks in sequence
            SB3Builder.linkBlocks(sprite, {hatId, sayForSecsId, sayId})

            local projectJson = SB3Builder.createProject({stage, sprite})
            local project = ProjectModel:new(projectJson, {})
            local runtime = Runtime:new(project)
            runtime:initialize()

            -- Execute script with safe iteration limit
            runtime:broadcastGreenFlag()
            local maxIterations = 200  -- Higher limit for timing-dependent test
            local iterations = 0
            while #runtime:getActiveThreads() > 0 and iterations < maxIterations do
                runtime:update(1/60)
                iterations = iterations + 1
            end

            -- Verify that the final message is displayed correctly
            -- This tests that sayForSecs doesn't auto-clear the message
            local target = runtime:getSpriteTargetByName("TestSprite")
            expect(target.currentMessage).to.equal("final message")
        end)

        it("should display message during timeout period", function()
            SB3Builder.resetCounter()
            local stage = SB3Builder.createStage()
            local sprite = SB3Builder.createSprite("TestSprite")

            local hatId, hatBlock = SB3Builder.Events.whenFlagClicked()
            local sayForSecsId, sayForSecsBlock = SB3Builder.Looks.sayForSecs("test message", 1.0)

            SB3Builder.addBlock(sprite, hatId, hatBlock)
            SB3Builder.addBlock(sprite, sayForSecsId, sayForSecsBlock)
            SB3Builder.linkBlocks(sprite, {hatId, sayForSecsId})

            local projectJson = SB3Builder.createProject({stage, sprite})
            local project = ProjectModel:new(projectJson, {})
            local runtime = Runtime:new(project)
            runtime:initialize()

            -- Start execution
            runtime:broadcastGreenFlag()

            -- Run a few frames to start the say for secs
            for i = 1, 5 do
                runtime:update(1/60)
            end

            -- Verify message is displayed during timeout
            local target = runtime:getSpriteTargetByName("TestSprite")
            expect(target.currentMessage).to.equal("test message")
        end)
    end)

    describe("graphic effects clamping", function()
        it("should clamp brightness effect", function()
            SB3Builder.resetCounter()
            local stage = SB3Builder.createStage()
            local sprite = SB3Builder.createSprite("TestSprite")

            local projectJson = SB3Builder.createProject({stage, sprite})
            local project = ProjectModel:new(projectJson, {})
            local runtime = Runtime:new(project)
            runtime:initialize()

            local target = runtime:getSpriteTargetByName("TestSprite")
            local BlockHelpers = require("runtime.block_helpers")

            -- Test high clamp
            BlockHelpers.Looks.seteffectto(target, {EFFECT = "brightness", VALUE = 500}, runtime, nil)
            expect(target:getEffect("brightness")).to.equal(100)

            -- Test low clamp
            BlockHelpers.Looks.seteffectto(target, {EFFECT = "brightness", VALUE = -500}, runtime, nil)
            expect(target:getEffect("brightness")).to.equal(-100)
        end)

        it("should clamp ghost effect", function()
            SB3Builder.resetCounter()
            local stage = SB3Builder.createStage()
            local sprite = SB3Builder.createSprite("TestSprite")

            local projectJson = SB3Builder.createProject({stage, sprite})
            local project = ProjectModel:new(projectJson, {})
            local runtime = Runtime:new(project)
            runtime:initialize()

            local target = runtime:getSpriteTargetByName("TestSprite")
            local BlockHelpers = require("runtime.block_helpers")

            -- Test high clamp
            BlockHelpers.Looks.seteffectto(target, {EFFECT = "ghost", VALUE = 500}, runtime, nil)
            expect(target:getEffect("ghost")).to.equal(100)

            -- Test low clamp
            BlockHelpers.Looks.seteffectto(target, {EFFECT = "ghost", VALUE = -500}, runtime, nil)
            expect(target:getEffect("ghost")).to.equal(0)
        end)

        it("should not clamp other effects beyond range limits", function()
            SB3Builder.resetCounter()
            local stage = SB3Builder.createStage()
            local sprite = SB3Builder.createSprite("TestSprite")

            local projectJson = SB3Builder.createProject({stage, sprite})
            local project = ProjectModel:new(projectJson, {})
            local runtime = Runtime:new(project)
            runtime:initialize()

            local target = runtime:getSpriteTargetByName("TestSprite")
            local BlockHelpers = require("runtime.block_helpers")

            -- Color effect should not be clamped
            BlockHelpers.Looks.seteffectto(target, {EFFECT = "color", VALUE = 500}, runtime, nil)
            expect(target:getEffect("color")).to.equal(500)

            BlockHelpers.Looks.seteffectto(target, {EFFECT = "color", VALUE = -500}, runtime, nil)
            expect(target:getEffect("color")).to.equal(-500)
        end)

        it("should clamp pixelate/mosaic effects at zero", function()
            SB3Builder.resetCounter()
            local stage = SB3Builder.createStage()
            local sprite = SB3Builder.createSprite("TestSprite")

            local projectJson = SB3Builder.createProject({stage, sprite})
            local project = ProjectModel:new(projectJson, {})
            local runtime = Runtime:new(project)
            runtime:initialize()

            local target = runtime:getSpriteTargetByName("TestSprite")
            local BlockHelpers = require("runtime.block_helpers")

            -- Pixelate should not go below 0
            BlockHelpers.Looks.seteffectto(target, {EFFECT = "pixelate", VALUE = -500}, runtime, nil)
            expect(target:getEffect("pixelate")).to.equal(0)

            -- Mosaic should not go below 0
            BlockHelpers.Looks.seteffectto(target, {EFFECT = "mosaic", VALUE = -500}, runtime, nil)
            expect(target:getEffect("mosaic")).to.equal(0)
        end)
    end)
end)