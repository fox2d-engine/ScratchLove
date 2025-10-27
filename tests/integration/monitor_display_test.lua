-- Monitor Display Test
-- Tests that monitors are visually displayed on the stage

local lust = require("tests.lust")
local describe, it, expect = lust.describe, lust.it, lust.expect
local SB3Builder = require("tests.sb3_builder")
local ProjectModel = require("parser.project_model")
local Runtime = require("vm.runtime")
local Renderer = require("renderer.renderer")

describe("Monitor Display", function()
    it("should display variable monitors on stage", function()
        SB3Builder.resetCounter()
        local stage = SB3Builder.createStage()
        local sprite = SB3Builder.createSprite("TestSprite")

        -- Create a variable
        local varId = SB3Builder.createVariable(stage, "my variable", 42)

        -- Create blocks to change the variable
        local hatId, hatBlock = SB3Builder.Events.whenFlagClicked()
        local setId, setBlock = SB3Builder.Data.setVariable("my variable", 100, varId)
        local changeId, changeBlock = SB3Builder.Data.changeVariable("my variable", 10, varId)

        SB3Builder.addBlock(sprite, hatId, hatBlock)
        SB3Builder.addBlock(sprite, setId, setBlock)
        SB3Builder.addBlock(sprite, changeId, changeBlock)
        SB3Builder.linkBlocks(sprite, {hatId, setId, changeId})

        -- Create a monitor for the variable
        local monitor = {
            id = varId,
            mode = "default",
            opcode = "data_variable",
            params = {VARIABLE = "my variable"},
            spriteName = nil, -- Stage variable
            value = 42,
            width = 0,
            height = 0,
            x = 10,
            y = 10,
            visible = true
        }

        local projectJson = SB3Builder.createProject({stage, sprite}, {monitor})
        local project = ProjectModel:new(projectJson, {})
        local runtime = Runtime:new(project)
        runtime:initialize()

        -- Create renderer and initialize monitor renderer
        local renderer = Renderer:new(runtime)
        runtime:setRenderer(renderer)

        -- Verify monitor renderer was created
        expect(renderer.monitorRenderer).to_not.be.nil()

        -- Verify monitor was registered
        expect(runtime.monitorManager).to_not.be.nil()
        expect(runtime.monitorManager.monitors[varId]).to_not.be.nil()
        expect(runtime.monitorManager.monitors[varId].visible).to.be.truthy()

        -- Run green flag to change variable
        runtime:broadcastGreenFlag()
        local maxIterations = 100
        local iterations = 0
        while #runtime:getActiveThreads() > 0 and iterations < maxIterations do
            runtime:update(1/60)
            iterations = iterations + 1
        end

        -- Verify variable changed
        local variable = runtime.stage.variables[varId]
        expect(variable).to_not.be.nil()
        expect(variable.value).to.equal(110) -- 100 + 10

        -- Verify monitor can get current value
        local monitor = runtime.monitorManager.monitors[varId]
        local value = monitor:getCurrentValue(runtime)
        expect(tonumber(value)).to.equal(110)

        print("✓ Monitor display test passed - monitors are integrated and can display values")
    end)

    it("should format numbers correctly in monitors", function()
        SB3Builder.resetCounter()
        local stage = SB3Builder.createStage()

        -- Create variables with different numeric values
        local varId1 = SB3Builder.createVariable(stage, "integer", 42)
        local varId2 = SB3Builder.createVariable(stage, "decimal", 3.14159265359)
        local varId3 = SB3Builder.createVariable(stage, "tiny", 0.000001)

        local projectJson = SB3Builder.createProject({stage})
        local project = ProjectModel:new(projectJson, {})
        local runtime = Runtime:new(project)
        runtime:initialize()

        local renderer = Renderer:new(runtime)
        runtime:setRenderer(renderer)

        -- Test monitor renderer formatting
        local monitorRenderer = renderer.monitorRenderer
        expect(monitorRenderer).to_not.be.nil()

        -- Test number formatting
        expect(monitorRenderer:formatValue(42, {})).to.equal("42")
        expect(monitorRenderer:formatValue(3.14159265359, {})).to.equal("3.141593") -- Rounds to 6 decimals
        expect(monitorRenderer:formatValue(0.000001, {})).to.equal("0.000001")

        -- Test table formatting (lists show length)
        expect(monitorRenderer:formatValue({1, 2, 3, 4, 5}, {})).to.equal("length: 5")

        print("✓ Monitor formatting test passed")
    end)
end)
