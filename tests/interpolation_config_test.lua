-- Test: Project Project Options - Interpolation Configuration
-- Verifies that the interpolation setting from _twconfig_ is properly applied to runtime

local lust = require("tests.lust")
local describe, it, expect = lust.describe, lust.it, lust.expect

local SB3Builder = require("tests.sb3_builder")
local Runtime = require("vm.runtime")
local ProjectModel = require("parser.project_model")
local log = require("lib.log")

describe("Project Interpolation Configuration", function()
    it("should enable interpolation when projectOptions.interpolation is true", function()
        -- Create minimal project using SB3Builder
        SB3Builder.resetCounter()
        local stage = SB3Builder.createStage()

        -- Manually inject Project config comment into stage
        stage.comments = {
            ["comment1"] = {
                blockId = nil,
                x = 0,
                y = 0,
                width = 200,
                height = 200,
                minimized = false,
                -- Project config comment with interpolation enabled
                text = "Configuration for https://turbowarp.org/\nYou can edit these settings by clicking on the stage.\n{\"framerate\":30,\"runtimeOptions\":{\"fencing\":true},\"interpolation\":true,\"turbo\":false,\"hq\":false,\"width\":480,\"height\":360} // _twconfig_"
            }
        }

        -- Create project
        local projectJson = SB3Builder.createProject({stage})
        local project = ProjectModel:new(projectJson, {})

        -- Verify projectOptions were parsed correctly
        expect(project.projectOptions ~= nil).to.be.truthy()
        expect(project.projectOptions.interpolation).to.equal(true)
        expect(project.projectOptions.framerate).to.equal(30)

        -- Create runtime and initialize
        local runtime = Runtime:new(project)

        -- Before initialization, interpolation should be at default (Global.INTERPOLATION_ENABLED)
        local Global = require("global")
        local expectedDefault = Global.INTERPOLATION_ENABLED
        expect(runtime.interpolationEnabled).to.equal(expectedDefault)

        -- Initialize runtime - this should apply project options
        runtime:initialize()

        -- After initialization, interpolation should be enabled (from projectOptions)
        expect(runtime.interpolationEnabled).to.equal(true)

        log.info("✓ Interpolation enabled from project config: %s", tostring(runtime.interpolationEnabled))
    end)

    it("should keep interpolation disabled when projectOptions.interpolation is false", function()
        -- Create project with interpolation explicitly disabled
        SB3Builder.resetCounter()
        local stage = SB3Builder.createStage()

        -- Inject Project config with interpolation disabled
        stage.comments = {
            ["comment1"] = {
                blockId = nil,
                x = 0,
                y = 0,
                width = 200,
                height = 200,
                minimized = false,
                text = "Configuration for https://turbowarp.org/\n{\"framerate\":30,\"interpolation\":false,\"turbo\":false,\"hq\":false,\"width\":480,\"height\":360} // _twconfig_"
            }
        }

        local projectJson = SB3Builder.createProject({stage})
        local project = ProjectModel:new(projectJson, {})
        expect(project.projectOptions.interpolation).to.equal(false)

        local runtime = Runtime:new(project)
        runtime:initialize()

        -- Interpolation should remain at default (not overridden to true)
        local Global = require("global")
        local expectedDefault = Global.INTERPOLATION_ENABLED
        expect(runtime.interpolationEnabled).to.equal(expectedDefault)

        log.info("✓ Interpolation kept at default when config is false: %s", tostring(runtime.interpolationEnabled))
    end)

    it("should use default interpolation when no projectOptions are present", function()
        -- Create project without any Project config
        SB3Builder.resetCounter()
        local stage = SB3Builder.createStage()

        local projectJson = SB3Builder.createProject({stage})
        local project = ProjectModel:new(projectJson, {})
        expect(project.projectOptions == nil).to.be.truthy()

        local runtime = Runtime:new(project)
        runtime:initialize()

        -- Should use Global default
        local Global = require("global")
        expect(runtime.interpolationEnabled).to.equal(Global.INTERPOLATION_ENABLED)

        log.info("✓ Interpolation uses default when no config: %s", tostring(runtime.interpolationEnabled))
    end)
end)

return lust
