-- Integration Test: Default Project
-- Basic project loading and execution test
--
-- Tests that a simple sb3 project can be loaded and executed

local lust = require("tests.lust")
local describe, it, expect = lust.describe, lust.it, lust.expect

local IntegrationHelper = require("tests.integration.integration_helper")
local ProjectModel = require("parser.project_model")
local Runtime = require("vm.runtime")

describe("Integration: Default Project", function()

    it("should load and execute a basic project", function()
        -- Basic project loading and execution test
        --
        -- Verification points:
        -- 1. Project data loads successfully
        -- 2. Runtime initializes without errors
        -- 3. Green flag broadcast starts execution
        -- 4. Project runs at least one frame
        -- 5. Runtime state is valid after execution

        local projectData, assetMap = IntegrationHelper.loadSB3Project("default.sb3")

        -- Verification 1: Project data loaded
        expect(projectData).to.exist()
        expect(projectData.targets).to.exist()
        expect(#projectData.targets > 0).to.be.truthy()

        -- Create and initialize runtime
        local project = ProjectModel:new(projectData, assetMap)
        local runtime = Runtime:new(project)
        runtime:initialize()

        -- Verification 2: Runtime initialized
        expect(runtime).to.exist()
        expect(runtime.stage).to.exist()

        -- Verification 3: Start execution
        runtime:broadcastGreenFlag()

        -- Verification 4: Run at least one frame
        local initialFrameCount = runtime.frameCount
        runtime:update(1/30) -- Use logic frame time to ensure execution
        expect(runtime.frameCount > initialFrameCount).to.be.truthy()

        -- Run to completion
        IntegrationHelper.runUntilComplete(runtime, 100)

        -- Verification 5: Runtime state is valid
        expect(runtime.stage).to.exist()
        expect(runtime.frameCount > 0).to.be.truthy()
    end)

end)