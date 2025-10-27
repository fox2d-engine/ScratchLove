-- Test suite for CloudVariableStorage
-- Verifies that cloud variables are correctly saved and loaded from persistent storage

local lust = require("tests.lust")
local describe, it, expect = lust.describe, lust.it, lust.expect

local CloudVariableStorage = require("vm.cloud_variable_storage")
local Runtime = require("vm.runtime")
local ProjectModel = require("parser.project_model")
local SB3Builder = require("tests.sb3_builder")

describe("CloudVariableStorage", function()
    describe("Basic storage operations", function()
        it("should create storage instance with projectPath", function()
            local storage = CloudVariableStorage:new("test_project")
            expect(storage.projectPath).to.equal("test_project")
            expect(type(storage.cloudData)).to.equal("table")
        end)

        it("should store and retrieve cloud variable values (async, non-blocking)", function()
            local storage = CloudVariableStorage:new("test_project")
            local varId = "test_var_id"
            local value = 42

            -- Set value (should be async and non-blocking)
            local ok = storage:set(varId, value)
            expect(ok).to.equal(true)

            -- Get value from cache (should be immediate)
            local retrieved = storage:get(varId)
            expect(retrieved).to.equal(value)

            -- Verify pending save flag is set
            expect(storage.pendingSave).to.equal(true)
        end)

        it("should coerce non-numeric cloud variable values to numbers", function()
            local storage = CloudVariableStorage:new("test_project")
            local varId = "test_var_id"

            -- Set string value (should coerce to number)
            local ok = storage:set(varId, "123")
            expect(ok).to.equal(true)
            expect(storage:get(varId)).to.equal(123)

            -- Set string value that converts to 0
            ok = storage:set(varId, "invalid")
            expect(ok).to.equal(true)
            expect(storage:get(varId)).to.equal(0)
        end)
    end)

    describe("Runtime integration", function()
        it("should save and load cloud variables through runtime", function()
            -- Create project with cloud variable
            SB3Builder.resetCounter()
            local stage = SB3Builder.createStage()

            -- Create cloud variable using correct API
            local cloudVarId = SB3Builder.addVariable(stage, "CloudScore", 100, true)

            -- Create green flag script that sets cloud variable
            local hatId, hatBlock = SB3Builder.Events.whenFlagClicked()
            local setVarId, setVarBlock = SB3Builder.Data.setVariable("CloudScore", 200, cloudVarId)

            SB3Builder.addBlock(stage, hatId, hatBlock)
            SB3Builder.addBlock(stage, setVarId, setVarBlock)
            SB3Builder.linkBlocks(stage, {hatId, setVarId})

            -- Build project
            local projectJson = SB3Builder.createProject({stage})
            local project = ProjectModel:new(projectJson, {}, "test_cloud_project")

            -- Initialize runtime
            local runtime = Runtime:new(project)
            runtime:initialize()

            -- Clear any existing cloud variable data
            if runtime.cloudStorage then
                runtime.cloudStorage.cloudData = {}
            end

            -- Run green flag to set cloud variable
            runtime:broadcastGreenFlag()
            local maxIterations = 100
            local iterations = 0
            while #runtime:getActiveThreads() > 0 and iterations < maxIterations do
                runtime:update(1/60)
                iterations = iterations + 1
            end

            -- Verify cloud variable was set
            local stageVar = runtime.stage.variables[cloudVarId]
            expect(stageVar).to.exist()
            expect(stageVar.value).to.equal(200)

            -- Verify cloud variable was saved to storage
            if runtime.cloudStorage then
                local savedValue = runtime.cloudStorage:get(cloudVarId)
                expect(savedValue).to.equal(200)
            end
        end)

        it("should load cloud variables on runtime initialization", function()
            -- Create project with cloud variable
            SB3Builder.resetCounter()
            local stage = SB3Builder.createStage()

            -- Create cloud variable with initial value using correct API
            local cloudVarId = SB3Builder.addVariable(stage, "HighScore", 0, true)

            -- Build project
            local projectJson = SB3Builder.createProject({stage})
            local project = ProjectModel:new(projectJson, {}, "test_cloud_load_project")

            -- Pre-populate cloud storage with saved value
            local runtime1 = Runtime:new(project)
            runtime1:initialize()

            if runtime1.cloudStorage then
                runtime1.cloudStorage:set(cloudVarId, 999)
                -- Must flush to write to disk before loading in new runtime
                runtime1.cloudStorage:flush()
            end

            -- Create new runtime instance to test loading
            local runtime2 = Runtime:new(project)
            runtime2:initialize()

            -- Verify cloud variable was loaded from storage
            local stageVar = runtime2.stage.variables[cloudVarId]
            expect(stageVar).to.exist()
            expect(stageVar.value).to.equal(999)
        end)

        it("should coerce non-numeric values when saving cloud variables", function()
            -- Create project with cloud variable
            SB3Builder.resetCounter()
            local stage = SB3Builder.createStage()

            -- Create cloud variable using correct API
            local cloudVarId = SB3Builder.addVariable(stage, "Score", 100, true)

            local projectJson = SB3Builder.createProject({stage})
            local project = ProjectModel:new(projectJson, {}, "test_numeric_cloud")

            local runtime = Runtime:new(project)
            runtime:initialize()

            -- Set non-numeric value through runtime (will coerce to number)
            runtime:saveCloudVariable(cloudVarId, "123")
            expect(runtime.cloudStorage:get(cloudVarId)).to.equal(123)

            runtime:saveCloudVariable(cloudVarId, "invalid")
            expect(runtime.cloudStorage:get(cloudVarId)).to.equal(0)
        end)

        it("should flush cloud variables synchronously on demand", function()
            -- Create project with cloud variable
            SB3Builder.resetCounter()
            local stage = SB3Builder.createStage()

            -- Create cloud variable using correct API
            local cloudVarId = SB3Builder.addVariable(stage, "TestVar", 50, true)

            local projectJson = SB3Builder.createProject({stage})
            local project = ProjectModel:new(projectJson, {}, "test_flush_project")

            local runtime = Runtime:new(project)
            runtime:initialize()

            -- Set cloud variable value
            runtime:saveCloudVariable(cloudVarId, 999)

            -- Verify value is in cache
            expect(runtime.cloudStorage:get(cloudVarId)).to.equal(999)

            -- Flush should save synchronously
            local success = runtime.cloudStorage:flush()
            expect(success).to.equal(true)

            -- Load in new storage instance to verify persistence
            local newStorage = CloudVariableStorage:new("test_flush_project")
            newStorage:load()
            expect(newStorage:get(cloudVarId)).to.equal(999)
        end)
    end)

    describe("Persistence", function()
        it("should persist cloud variables across runtime instances", function()
            -- Create first runtime and set cloud variable
            SB3Builder.resetCounter()
            local stage1 = SB3Builder.createStage()

            -- Create cloud variable using correct API
            local cloudVarId = SB3Builder.addVariable(stage1, "GameLevel", 5, true)

            local projectJson1 = SB3Builder.createProject({stage1})
            local project1 = ProjectModel:new(projectJson1, {}, "test_persist_project")

            local runtime1 = Runtime:new(project1)
            runtime1:initialize()

            -- Set cloud variable value
            local var1 = runtime1.stage.variables[cloudVarId]
            var1.value = 42
            runtime1:saveCloudVariable(cloudVarId, 42)

            -- Must flush to write to disk before loading in new runtime
            runtime1.cloudStorage:flush()

            -- Create second runtime with same project path
            SB3Builder.resetCounter()
            local stage2 = SB3Builder.createStage()

            -- Create cloud variable with same ID (manually set ID to match)
            stage2.variables[cloudVarId] = { "GameLevel", 0, true }

            local projectJson2 = SB3Builder.createProject({stage2})
            local project2 = ProjectModel:new(projectJson2, {}, "test_persist_project") -- Same path

            local runtime2 = Runtime:new(project2)
            runtime2:initialize()

            -- Verify value was loaded from storage
            local var2 = runtime2.stage.variables[cloudVarId]
            expect(var2.value).to.equal(42)
        end)
    end)
end)
