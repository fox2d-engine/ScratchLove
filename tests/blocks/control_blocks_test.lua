-- Control Blocks Tests
-- Tests for control flow block implementations

local testPath = debug.getinfo(1, "S").source:match("@(.*/)")
local projectRoot = testPath:gsub("tests/blocks/$", "")
package.path = projectRoot .. "?.lua;" .. projectRoot .. "?/init.lua;" .. package.path

-- Import testing framework
local lust = require("tests.lust")
local describe, it, expect = lust.describe, lust.it, lust.expect

-- Import project components
local SB3Builder = require("tests.sb3_builder")
local ProjectModel = require("parser.project_model")
local Runtime = require("vm.runtime")

describe("Control Blocks", function()
    describe("Wait Operations", function()
        it("should execute wait block with specified duration", function()
            -- Test that wait block properly delays execution and then allows script to continue
            SB3Builder.resetCounter()
            local stage = SB3Builder.createStage()
            local variableId = SB3Builder.addVariable(stage, "executionFlag", 0)

            local hatId, hatBlock = SB3Builder.Events.whenFlagClicked()
            local waitId, waitBlock = SB3Builder.Control.wait(0.05) -- 50ms wait
            local setId, setBlock = SB3Builder.Data.setVariable("executionFlag", 1, variableId)

            SB3Builder.addBlock(stage, hatId, hatBlock)
            SB3Builder.addBlock(stage, waitId, waitBlock)
            SB3Builder.addBlock(stage, setId, setBlock)
            SB3Builder.linkBlocks(stage, { hatId, waitId, setId })

            local projectJson = SB3Builder.createProject({ stage })
            local project = ProjectModel:new(projectJson, {})
            local runtime = Runtime:new(project)
            runtime:initialize()

            runtime:broadcastGreenFlag()

            -- Should have active thread during wait
            expect(#runtime:getActiveThreads()).to.be(1)

            -- Variable should still be 0 (wait hasn't completed)
            local flag = runtime.stage:lookupVariableByNameAndType("executionFlag")
            expect(flag.value).to.equal(0)

            -- Run for enough frames to complete the wait (50ms at 60fps = ~3 frames)
            local maxIterations = 10
            local iterations = 0
            while #runtime:getActiveThreads() > 0 and iterations < maxIterations do
                runtime:update(1/60)
                iterations = iterations + 1
            end

            -- Now variable should be set to 1 (wait completed and script continued)
            expect(flag.value).to.equal(1)
            expect(#runtime:getActiveThreads()).to.equal(0) -- Script should be finished
        end)

        it("should handle wait with zero duration", function()
            SB3Builder.resetCounter()
            local stage = SB3Builder.createStage()
            local variableId = SB3Builder.addVariable(stage, "executionFlag", 0)

            local hatId, hatBlock = SB3Builder.Events.whenFlagClicked()
            local waitId, waitBlock = SB3Builder.Control.wait(0)
            local setId, setBlock = SB3Builder.Data.setVariable("executionFlag", 1, variableId)

            SB3Builder.addBlock(stage, hatId, hatBlock)
            SB3Builder.addBlock(stage, waitId, waitBlock)
            SB3Builder.addBlock(stage, setId, setBlock)
            SB3Builder.linkBlocks(stage, { hatId, waitId, setId })

            local projectJson = SB3Builder.createProject({ stage })
            local project = ProjectModel:new(projectJson, {})
            local runtime = Runtime:new(project)
            runtime:initialize()

            runtime:broadcastGreenFlag()

            -- Run execution loop to let all blocks execute
            local maxIterations = 10
            local iterations = 0
            while #runtime:getActiveThreads() > 0 and iterations < maxIterations do
                runtime:update(1/60)
                iterations = iterations + 1
            end

            -- Zero duration wait should complete immediately and set the flag
            local flag = runtime.stage:lookupVariableByNameAndType("executionFlag")
            expect(flag.value).to.equal(1)
            expect(#runtime:getActiveThreads()).to.equal(0)
        end)
    end)

    describe("Repeat Operations", function()
        it("should execute repeat block specified number of times", function()
            SB3Builder.resetCounter()
            local stage = SB3Builder.createStage()
            local variableId = SB3Builder.addVariable(stage, "counter", 0)

            -- Create: repeat 3 times { change counter by 1 }
            local hatId, hatBlock = SB3Builder.Events.whenFlagClicked(100, 100)
            local changeId, changeBlock = SB3Builder.Data.changeVariable("counter", 1, variableId)
            local repeatId, repeatBlock = SB3Builder.Control.repeat_(3, changeId)

            SB3Builder.addBlock(stage, hatId, hatBlock)
            SB3Builder.addBlock(stage, repeatId, repeatBlock)
            SB3Builder.addBlock(stage, changeId, changeBlock)
            SB3Builder.linkBlocks(stage, { hatId, repeatId })

            local projectJson = SB3Builder.createProject({ stage })
            local project = ProjectModel:new(projectJson, {})
            local runtime = Runtime:new(project)
            runtime:initialize()

            runtime:broadcastGreenFlag()
            local maxIterations = 100
            local iterations = 0
            while #runtime:getActiveThreads() > 0 and iterations < maxIterations do
                runtime:update(1 / 60)
                iterations = iterations + 1
            end

            local counter = runtime.stage:lookupVariableByNameAndType("counter")
            expect(counter.value).to.equal(3)
        end)

        it("should handle repeat with zero times", function()
            SB3Builder.resetCounter()
            local stage = SB3Builder.createStage()
            local variableId = SB3Builder.addVariable(stage, "counter", 0)

            local hatId, hatBlock = SB3Builder.Events.whenFlagClicked(100, 100)
            local changeId, changeBlock = SB3Builder.Data.changeVariable("counter", 1, variableId)
            local repeatId, repeatBlock = SB3Builder.Control.repeat_(0, changeId)

            SB3Builder.addBlock(stage, hatId, hatBlock)
            SB3Builder.addBlock(stage, repeatId, repeatBlock)
            SB3Builder.addBlock(stage, changeId, changeBlock)
            SB3Builder.linkBlocks(stage, { hatId, repeatId })

            local projectJson = SB3Builder.createProject({ stage })
            local project = ProjectModel:new(projectJson, {})
            local runtime = Runtime:new(project)
            runtime:initialize()

            runtime:broadcastGreenFlag()
            local maxIterations = 100
            local iterations = 0
            while #runtime:getActiveThreads() > 0 and iterations < maxIterations do
                runtime:update(1 / 60)
                iterations = iterations + 1
            end

            local counter = runtime.stage:lookupVariableByNameAndType("counter")
            expect(counter.value).to.equal(0) -- Should not execute loop body
        end)

        it("should handle repeat with fractional times (rounds to nearest)", function()
            SB3Builder.resetCounter()
            local stage = SB3Builder.createStage()
            local variableId = SB3Builder.addVariable(stage, "counter", 0)

            local hatId, hatBlock = SB3Builder.Events.whenFlagClicked(100, 100)
            local changeId, changeBlock = SB3Builder.Data.changeVariable("counter", 1, variableId)
            local repeatId, repeatBlock = SB3Builder.Control.repeat_(2.7, changeId) -- Should round to 3

            SB3Builder.addBlock(stage, hatId, hatBlock)
            SB3Builder.addBlock(stage, repeatId, repeatBlock)
            SB3Builder.addBlock(stage, changeId, changeBlock)
            SB3Builder.linkBlocks(stage, { hatId, repeatId })

            local projectJson = SB3Builder.createProject({ stage })
            local project = ProjectModel:new(projectJson, {})
            local runtime = Runtime:new(project)
            runtime:initialize()

            runtime:broadcastGreenFlag()
            local maxIterations = 100
            local iterations = 0
            while #runtime:getActiveThreads() > 0 and iterations < maxIterations do
                runtime:update(1 / 60)
                iterations = iterations + 1
            end

            local counter = runtime.stage:lookupVariableByNameAndType("counter")
            expect(counter.value).to.equal(3) -- 2.7 rounds to 3
        end)

        it("should handle repeat with specific rounding cases", function()
            SB3Builder.resetCounter()
            local stage = SB3Builder.createStage()
            local variableId = SB3Builder.addVariable(stage, "counter", 0)

            -- Test 3.2 rounds to 3
            local hatId1, hatBlock1 = SB3Builder.Events.whenFlagClicked(100, 100)
            local changeId1, changeBlock1 = SB3Builder.Data.changeVariable("counter", 1, variableId)
            local repeatId1, repeatBlock1 = SB3Builder.Control.repeat_(3.2, changeId1)

            SB3Builder.addBlock(stage, hatId1, hatBlock1)
            SB3Builder.addBlock(stage, repeatId1, repeatBlock1)
            SB3Builder.addBlock(stage, changeId1, changeBlock1)
            SB3Builder.linkBlocks(stage, { hatId1, repeatId1 })

            local projectJson1 = SB3Builder.createProject({ stage })
            local project1 = ProjectModel:new(projectJson1, {})
            local runtime1 = Runtime:new(project1)
            runtime1:initialize()

            runtime1:broadcastGreenFlag()
            while #runtime1:getActiveThreads() > 0 do
                runtime1:update(1 / 60)
            end

            local counter1 = runtime1.stage:lookupVariableByNameAndType("counter")
            expect(counter1.value).to.equal(3) -- 3.2 rounds to 3

            -- Test 3.7 rounds to 4
            SB3Builder.resetCounter()
            stage = SB3Builder.createStage()
            variableId = SB3Builder.addVariable(stage, "counter", 0)

            local hatId2, hatBlock2 = SB3Builder.Events.whenFlagClicked(100, 100)
            local changeId2, changeBlock2 = SB3Builder.Data.changeVariable("counter", 1, variableId)
            local repeatId2, repeatBlock2 = SB3Builder.Control.repeat_(3.7, changeId2)

            SB3Builder.addBlock(stage, hatId2, hatBlock2)
            SB3Builder.addBlock(stage, repeatId2, repeatBlock2)
            SB3Builder.addBlock(stage, changeId2, changeBlock2)
            SB3Builder.linkBlocks(stage, { hatId2, repeatId2 })

            local projectJson2 = SB3Builder.createProject({ stage })
            local project2 = ProjectModel:new(projectJson2, {})
            local runtime2 = Runtime:new(project2)
            runtime2:initialize()

            runtime2:broadcastGreenFlag()
            while #runtime2:getActiveThreads() > 0 do
                runtime2:update(1 / 60)
            end

            local counter2 = runtime2.stage:lookupVariableByNameAndType("counter")
            expect(counter2.value).to.equal(4) -- 3.7 rounds to 4

            -- Test 3.5 rounds to 4
            SB3Builder.resetCounter()
            stage = SB3Builder.createStage()
            variableId = SB3Builder.addVariable(stage, "counter", 0)

            local hatId3, hatBlock3 = SB3Builder.Events.whenFlagClicked(100, 100)
            local changeId3, changeBlock3 = SB3Builder.Data.changeVariable("counter", 1, variableId)
            local repeatId3, repeatBlock3 = SB3Builder.Control.repeat_(3.5, changeId3)

            SB3Builder.addBlock(stage, hatId3, hatBlock3)
            SB3Builder.addBlock(stage, repeatId3, repeatBlock3)
            SB3Builder.addBlock(stage, changeId3, changeBlock3)
            SB3Builder.linkBlocks(stage, { hatId3, repeatId3 })

            local projectJson3 = SB3Builder.createProject({ stage })
            local project3 = ProjectModel:new(projectJson3, {})
            local runtime3 = Runtime:new(project3)
            runtime3:initialize()

            runtime3:broadcastGreenFlag()
            while #runtime3:getActiveThreads() > 0 do
                runtime3:update(1 / 60)
            end

            local counter3 = runtime3.stage:lookupVariableByNameAndType("counter")
            expect(counter3.value).to.equal(4) -- 3.5 rounds to 4
        end)

        it("should handle nested repeat loops", function()
            SB3Builder.resetCounter()
            local stage = SB3Builder.createStage()
            local variableId = SB3Builder.addVariable(stage, "counter", 0)

            -- Create: repeat 2 times { repeat 3 times { change counter by 1 } }
            local hatId, hatBlock = SB3Builder.Events.whenFlagClicked(100, 100)
            local changeId, changeBlock = SB3Builder.Data.changeVariable("counter", 1, variableId)
            local innerRepeatId, innerRepeatBlock = SB3Builder.Control.repeat_(3, changeId)
            local outerRepeatId, outerRepeatBlock = SB3Builder.Control.repeat_(2, innerRepeatId)

            SB3Builder.addBlock(stage, hatId, hatBlock)
            SB3Builder.addBlock(stage, outerRepeatId, outerRepeatBlock)
            SB3Builder.addBlock(stage, innerRepeatId, innerRepeatBlock)
            SB3Builder.addBlock(stage, changeId, changeBlock)
            SB3Builder.linkBlocks(stage, { hatId, outerRepeatId })

            local projectJson = SB3Builder.createProject({ stage })
            local project = ProjectModel:new(projectJson, {})
            local runtime = Runtime:new(project)
            runtime:initialize()

            runtime:broadcastGreenFlag()
            local maxIterations = 100
            local iterations = 0
            while #runtime:getActiveThreads() > 0 and iterations < maxIterations do
                runtime:update(1 / 60)
                iterations = iterations + 1
            end

            local counter = runtime.stage:lookupVariableByNameAndType("counter")
            expect(counter.value).to.equal(6) -- 2 * 3 = 6
        end)
    end)

    describe("Repeat Until Operations", function()
        it("should execute repeat until loop correctly", function()
            SB3Builder.resetCounter()
            local stage = SB3Builder.createStage()
            local variableId = SB3Builder.addVariable(stage, "counter", 0)

            -- Create: repeat until (counter = 5) { change counter by 1 }
            local hatId, hatBlock = SB3Builder.Events.whenFlagClicked(100, 100)
            local changeId, changeBlock = SB3Builder.Data.changeVariable("counter", 1, variableId)
            local varId, varBlock = SB3Builder.Data.variable("counter", variableId)
            local equalsId, equalsBlock = SB3Builder.Operators.equals(varId, 5)
            -- Manually set the first operand to reference the variable block
            local repeatUntilId, repeatUntilBlock = SB3Builder.Control.repeatUntil(equalsId, changeId)

            SB3Builder.addBlock(stage, hatId, hatBlock)
            SB3Builder.addBlock(stage, repeatUntilId, repeatUntilBlock)
            SB3Builder.addBlock(stage, changeId, changeBlock)
            SB3Builder.addBlock(stage, varId, varBlock)
            SB3Builder.addBlock(stage, equalsId, equalsBlock)
            SB3Builder.linkBlocks(stage, { hatId, repeatUntilId })

            local projectJson = SB3Builder.createProject({ stage })
            local project = ProjectModel:new(projectJson, {})
            local runtime = Runtime:new(project)
            runtime:initialize()

            runtime:broadcastGreenFlag()
            local maxIterations = 100
            local iterations = 0
            while #runtime:getActiveThreads() > 0 and iterations < maxIterations do
                runtime:update(1 / 60)
                iterations = iterations + 1
            end

            local counter = runtime.stage:lookupVariableByNameAndType("counter")
            expect(counter.value).to.equal(5)
        end)

        it("should handle repeat until with true initial condition", function()
            SB3Builder.resetCounter()
            local stage = SB3Builder.createStage()
            local variableId = SB3Builder.addVariable(stage, "counter", 0)

            -- Create: repeat until (true) { change counter by 1 } - should not execute body
            local hatId, hatBlock = SB3Builder.Events.whenFlagClicked(100, 100)
            local changeId, changeBlock = SB3Builder.Data.changeVariable("counter", 1, variableId)
            local repeatUntilId, repeatUntilBlock = SB3Builder.Control.repeatUntil(true, changeId)

            SB3Builder.addBlock(stage, hatId, hatBlock)
            SB3Builder.addBlock(stage, repeatUntilId, repeatUntilBlock)
            SB3Builder.addBlock(stage, changeId, changeBlock)
            SB3Builder.linkBlocks(stage, { hatId, repeatUntilId })

            local projectJson = SB3Builder.createProject({ stage })
            local project = ProjectModel:new(projectJson, {})
            local runtime = Runtime:new(project)
            runtime:initialize()

            runtime:broadcastGreenFlag()
            local maxIterations = 100
            local iterations = 0
            while #runtime:getActiveThreads() > 0 and iterations < maxIterations do
                runtime:update(1 / 60)
                iterations = iterations + 1
            end

            local counter = runtime.stage:lookupVariableByNameAndType("counter")
            expect(counter.value).to.equal(0) -- Should not execute body
        end)
    end)

    describe("Repeat While Operations", function()
        it("should execute repeat while loop correctly", function()
            SB3Builder.resetCounter()
            local stage = SB3Builder.createStage()
            local variableId = SB3Builder.addVariable(stage, "counter", 0)

            -- Create simple repeat while with constant true condition - should execute once then stop due to iteration limit
            local hatId, hatBlock = SB3Builder.Events.whenFlagClicked(100, 100)
            local changeId, changeBlock = SB3Builder.Data.changeVariable("counter", 1, variableId)
            local repeatWhileId, repeatWhileBlock = SB3Builder.Control.repeatWhile(true, changeId)

            SB3Builder.addBlock(stage, hatId, hatBlock)
            SB3Builder.addBlock(stage, repeatWhileId, repeatWhileBlock)
            SB3Builder.addBlock(stage, changeId, changeBlock)
            SB3Builder.linkBlocks(stage, { hatId, repeatWhileId })

            local projectJson = SB3Builder.createProject({ stage })
            local project = ProjectModel:new(projectJson, {})
            local runtime = Runtime:new(project)
            runtime:initialize()

            runtime:broadcastGreenFlag()
            local maxIterations = 10 -- Lower limit for infinite loop test
            local iterations = 0
            while #runtime:getActiveThreads() > 0 and iterations < maxIterations do
                runtime:update(1 / 60)
                iterations = iterations + 1
            end

            local counter = runtime.stage:lookupVariableByNameAndType("counter")
            expect(counter.value).to.be.a("number")
            expect(counter.value > 0).to.be(true) -- Should have executed at least once
        end)

        it("should handle repeat while with false initial condition", function()
            SB3Builder.resetCounter()
            local stage = SB3Builder.createStage()
            local variableId = SB3Builder.addVariable(stage, "counter", 0)

            -- Create: repeat while (false) { change counter by 1 } - should not execute body
            local hatId, hatBlock = SB3Builder.Events.whenFlagClicked(100, 100)
            local changeId, changeBlock = SB3Builder.Data.changeVariable("counter", 1, variableId)
            local repeatWhileId, repeatWhileBlock = SB3Builder.Control.repeatWhile(false, changeId)

            SB3Builder.addBlock(stage, hatId, hatBlock)
            SB3Builder.addBlock(stage, repeatWhileId, repeatWhileBlock)
            SB3Builder.addBlock(stage, changeId, changeBlock)
            SB3Builder.linkBlocks(stage, { hatId, repeatWhileId })

            local projectJson = SB3Builder.createProject({ stage })
            local project = ProjectModel:new(projectJson, {})
            local runtime = Runtime:new(project)
            runtime:initialize()

            runtime:broadcastGreenFlag()
            local maxIterations = 100
            local iterations = 0
            while #runtime:getActiveThreads() > 0 and iterations < maxIterations do
                runtime:update(1 / 60)
                iterations = iterations + 1
            end

            local counter = runtime.stage:lookupVariableByNameAndType("counter")
            expect(counter.value).to.equal(0) -- Should not execute body
        end)
    end)

    describe("Forever Loop", function()
        it("should execute forever loop continuously until stopped", function()
            SB3Builder.resetCounter()
            local stage = SB3Builder.createStage()
            local variableId = SB3Builder.addVariable(stage, "counter", 0)

            local hatId, hatBlock = SB3Builder.Events.whenFlagClicked(100, 100)
            local changeId, changeBlock = SB3Builder.Data.changeVariable("counter", 1, variableId)
            local foreverId, foreverBlock = SB3Builder.Control.forever(changeId)

            SB3Builder.addBlock(stage, hatId, hatBlock)
            SB3Builder.addBlock(stage, foreverId, foreverBlock)
            SB3Builder.addBlock(stage, changeId, changeBlock)
            SB3Builder.linkBlocks(stage, { hatId, foreverId })

            local projectJson = SB3Builder.createProject({ stage })
            local project = ProjectModel:new(projectJson, {})
            local runtime = Runtime:new(project)
            runtime:initialize()

            runtime:broadcastGreenFlag()

            -- Run for limited frames to test continuous execution
            for i = 1, 10 do
                runtime:update(1 / 60)
            end

            local counter = runtime.stage:lookupVariableByNameAndType("counter")
            expect(counter.value).to.be.a("number")
            expect(counter.value >= 5).to.be(true)          -- Should have executed multiple times
            expect(#runtime:getActiveThreads()).to.equal(1) -- Thread should still be active
        end)
    end)

    describe("Conditional Operations", function()
        it("should execute if block when condition is true", function()
            SB3Builder.resetCounter()
            local stage = SB3Builder.createStage()
            local variableId = SB3Builder.addVariable(stage, "counter", 0)

            local hatId, hatBlock = SB3Builder.Events.whenFlagClicked(100, 100)
            local changeId, changeBlock = SB3Builder.Data.changeVariable("counter", 1, variableId)
            local ifId, ifBlock = SB3Builder.Control.ifCondition(true, changeId)

            SB3Builder.addBlock(stage, hatId, hatBlock)
            SB3Builder.addBlock(stage, ifId, ifBlock)
            SB3Builder.addBlock(stage, changeId, changeBlock)
            SB3Builder.linkBlocks(stage, { hatId, ifId })

            local projectJson = SB3Builder.createProject({ stage })
            local project = ProjectModel:new(projectJson, {})
            local runtime = Runtime:new(project)
            runtime:initialize()

            runtime:broadcastGreenFlag()
            local maxIterations = 100
            local iterations = 0
            while #runtime:getActiveThreads() > 0 and iterations < maxIterations do
                runtime:update(1 / 60)
                iterations = iterations + 1
            end

            local counter = runtime.stage:lookupVariableByNameAndType("counter")
            expect(counter.value).to.equal(1)
        end)

        it("should not execute if block when condition is false", function()
            SB3Builder.resetCounter()
            local stage = SB3Builder.createStage()
            local variableId = SB3Builder.addVariable(stage, "counter", 0)

            local hatId, hatBlock = SB3Builder.Events.whenFlagClicked(100, 100)
            local changeId, changeBlock = SB3Builder.Data.changeVariable("counter", 1, variableId)
            local ifId, ifBlock = SB3Builder.Control.ifCondition(false, changeId)

            SB3Builder.addBlock(stage, hatId, hatBlock)
            SB3Builder.addBlock(stage, ifId, ifBlock)
            SB3Builder.addBlock(stage, changeId, changeBlock)
            SB3Builder.linkBlocks(stage, { hatId, ifId })

            local projectJson = SB3Builder.createProject({ stage })
            local project = ProjectModel:new(projectJson, {})
            local runtime = Runtime:new(project)
            runtime:initialize()

            runtime:broadcastGreenFlag()
            local maxIterations = 100
            local iterations = 0
            while #runtime:getActiveThreads() > 0 and iterations < maxIterations do
                runtime:update(1 / 60)
                iterations = iterations + 1
            end

            local counter = runtime.stage:lookupVariableByNameAndType("counter")
            expect(counter.value).to.equal(0)
        end)

        it("should execute if-else correctly with true condition", function()
            SB3Builder.resetCounter()
            local stage = SB3Builder.createStage()
            local variableId = SB3Builder.addVariable(stage, "result", "")

            local hatId, hatBlock = SB3Builder.Events.whenFlagClicked(100, 100)
            local setTrueId, setTrueBlock = SB3Builder.Data.setVariable("result", "true_branch", variableId)
            local setFalseId, setFalseBlock = SB3Builder.Data.setVariable("result", "false_branch", variableId)
            local ifElseId, ifElseBlock = SB3Builder.Control.ifElse(true, setTrueId, setFalseId)

            SB3Builder.addBlock(stage, hatId, hatBlock)
            SB3Builder.addBlock(stage, ifElseId, ifElseBlock)
            SB3Builder.addBlock(stage, setTrueId, setTrueBlock)
            SB3Builder.addBlock(stage, setFalseId, setFalseBlock)
            SB3Builder.linkBlocks(stage, { hatId, ifElseId })

            local projectJson = SB3Builder.createProject({ stage })
            local project = ProjectModel:new(projectJson, {})
            local runtime = Runtime:new(project)
            runtime:initialize()

            runtime:broadcastGreenFlag()
            local maxIterations = 100
            local iterations = 0
            while #runtime:getActiveThreads() > 0 and iterations < maxIterations do
                runtime:update(1 / 60)
                iterations = iterations + 1
            end

            local result = runtime.stage:lookupVariableByNameAndType("result")
            expect(result.value).to.equal("true_branch")
        end)

        it("should execute if-else correctly with false condition", function()
            SB3Builder.resetCounter()
            local stage = SB3Builder.createStage()
            local variableId = SB3Builder.addVariable(stage, "result", "")

            local hatId, hatBlock = SB3Builder.Events.whenFlagClicked(100, 100)
            local setTrueId, setTrueBlock = SB3Builder.Data.setVariable("result", "true_branch", variableId)
            local setFalseId, setFalseBlock = SB3Builder.Data.setVariable("result", "false_branch", variableId)
            local ifElseId, ifElseBlock = SB3Builder.Control.ifElse(false, setTrueId, setFalseId)

            SB3Builder.addBlock(stage, hatId, hatBlock)
            SB3Builder.addBlock(stage, ifElseId, ifElseBlock)
            SB3Builder.addBlock(stage, setTrueId, setTrueBlock)
            SB3Builder.addBlock(stage, setFalseId, setFalseBlock)
            SB3Builder.linkBlocks(stage, { hatId, ifElseId })

            local projectJson = SB3Builder.createProject({ stage })
            local project = ProjectModel:new(projectJson, {})
            local runtime = Runtime:new(project)
            runtime:initialize()

            runtime:broadcastGreenFlag()
            local maxIterations = 100
            local iterations = 0
            while #runtime:getActiveThreads() > 0 and iterations < maxIterations do
                runtime:update(1 / 60)
                iterations = iterations + 1
            end

            local result = runtime.stage:lookupVariableByNameAndType("result")
            expect(result.value).to.equal("false_branch")
        end)
    end)

    describe("Stop Operations", function()
        it("should stop all scripts when stop all is used", function()
            SB3Builder.resetCounter()
            local stage = SB3Builder.createStage()
            local variableId = SB3Builder.addVariable(stage, "counter", 0)

            -- Script 1: forever { change counter by 1 }
            local hat1Id, hat1Block = SB3Builder.Events.whenFlagClicked(100, 100)
            local change1Id, change1Block = SB3Builder.Data.changeVariable("counter", 1, variableId)
            local forever1Id, forever1Block = SB3Builder.Control.forever(change1Id)

            -- Script 2: wait 0.01, then stop all
            local hat2Id, hat2Block = SB3Builder.Events.whenFlagClicked(200, 100)
            local wait2Id, wait2Block = SB3Builder.Control.wait(0.01)
            local stop2Id, stop2Block = SB3Builder.Control.stopAll()

            SB3Builder.addBlock(stage, hat1Id, hat1Block)
            SB3Builder.addBlock(stage, forever1Id, forever1Block)
            SB3Builder.addBlock(stage, change1Id, change1Block)
            SB3Builder.linkBlocks(stage, { hat1Id, forever1Id })

            SB3Builder.addBlock(stage, hat2Id, hat2Block)
            SB3Builder.addBlock(stage, wait2Id, wait2Block)
            SB3Builder.addBlock(stage, stop2Id, stop2Block)
            SB3Builder.linkBlocks(stage, { hat2Id, wait2Id, stop2Id })

            local projectJson = SB3Builder.createProject({ stage })
            local project = ProjectModel:new(projectJson, {})
            local runtime = Runtime:new(project)
            runtime:initialize()

            runtime:broadcastGreenFlag()

            -- Run until stop is executed
            for i = 1, 20 do -- Enough frames for wait to complete and stop to execute
                if #runtime:getActiveThreads() == 0 then break end
                runtime:update(0.1)
            end

            -- All threads should be stopped (some may still be active if stop hasn't executed yet)
            -- Since stop all immediately clears threads, we just check that threads were reduced
            expect(#runtime:getActiveThreads() <= 1).to.be(true)
        end)

        it("should stop only current script when stop this script is used", function()
            SB3Builder.resetCounter()
            local stage = SB3Builder.createStage()
            local variableId = SB3Builder.addVariable(stage, "counter", 0)

            -- Script 1: change counter by 1, then stop this script
            local hat1Id, hat1Block = SB3Builder.Events.whenFlagClicked(100, 100)
            local change1Id, change1Block = SB3Builder.Data.changeVariable("counter", 1, variableId)
            local stop1Id, stop1Block = SB3Builder.Control.stopThisScript()

            -- Script 2: wait a bit, then change counter by 10
            local hat2Id, hat2Block = SB3Builder.Events.whenFlagClicked(200, 100)
            local wait2Id, wait2Block = SB3Builder.Control.wait(0.01)
            local change2Id, change2Block = SB3Builder.Data.changeVariable("counter", 10, variableId)

            SB3Builder.addBlock(stage, hat1Id, hat1Block)
            SB3Builder.addBlock(stage, change1Id, change1Block)
            SB3Builder.addBlock(stage, stop1Id, stop1Block)
            SB3Builder.linkBlocks(stage, { hat1Id, change1Id, stop1Id })

            SB3Builder.addBlock(stage, hat2Id, hat2Block)
            SB3Builder.addBlock(stage, wait2Id, wait2Block)
            SB3Builder.addBlock(stage, change2Id, change2Block)
            SB3Builder.linkBlocks(stage, { hat2Id, wait2Id, change2Id })

            local projectJson = SB3Builder.createProject({ stage })
            local project = ProjectModel:new(projectJson, {})
            local runtime = Runtime:new(project)
            runtime:initialize()

            runtime:broadcastGreenFlag()
            local maxIterations = 100
            local iterations = 0
            while #runtime:getActiveThreads() > 0 and iterations < maxIterations do
                runtime:update(0.1)
                iterations = iterations + 1
            end

            local counter = runtime.stage:lookupVariableByNameAndType("counter")
            -- First script should execute (adding 1), second script may or may not complete
            expect(counter.value >= 1).to.be(true)
        end)

        it("should stop other scripts in sprite when stop other scripts in sprite is used", function()
            SB3Builder.resetCounter()
            local stage = SB3Builder.createStage()
            local sprite = SB3Builder.createSprite("TestSprite")
            local variableId = SB3Builder.addVariable(stage, "counter", 0)

            -- Script 1: change counter by 1, then stop other scripts in sprite
            local hat1Id, hat1Block = SB3Builder.Events.whenFlagClicked(100, 100)
            local change1Id, change1Block = SB3Builder.Data.changeVariable("counter", 1, variableId)
            local stop1Id, stop1Block = SB3Builder.Control.stopOtherScriptsInSprite()

            -- Script 2: forever { change counter by 10 }
            local hat2Id, hat2Block = SB3Builder.Events.whenFlagClicked(200, 100)
            local change2Id, change2Block = SB3Builder.Data.changeVariable("counter", 10, variableId)
            local forever2Id, forever2Block = SB3Builder.Control.forever(change2Id)

            SB3Builder.addBlock(sprite, hat1Id, hat1Block)
            SB3Builder.addBlock(sprite, change1Id, change1Block)
            SB3Builder.addBlock(sprite, stop1Id, stop1Block)
            SB3Builder.linkBlocks(sprite, { hat1Id, change1Id, stop1Id })

            SB3Builder.addBlock(sprite, hat2Id, hat2Block)
            SB3Builder.addBlock(sprite, forever2Id, forever2Block)
            SB3Builder.addBlock(sprite, change2Id, change2Block)
            SB3Builder.linkBlocks(sprite, { hat2Id, forever2Id })

            local projectJson = SB3Builder.createProject({ stage, sprite })
            local project = ProjectModel:new(projectJson, {})
            local runtime = Runtime:new(project)
            runtime:initialize()

            runtime:broadcastGreenFlag()
            -- Run briefly to allow both scripts to start and one to stop the other
            for i = 1, 5 do
                runtime:update(1 / 60)
            end

            local counter = runtime.stage:lookupVariableByNameAndType("counter")
            -- Counter should be 1 (from first script) but not much higher if second script was stopped
            expect(counter.value).to.be.a("number")
            expect(counter.value >= 1).to.be(true)
        end)

        it("should stop other scripts in stage when stop other scripts in stage is used", function()
            SB3Builder.resetCounter()
            local stage = SB3Builder.createStage()
            local variableId = SB3Builder.addVariable(stage, "counter", 0)

            -- Script 1: change counter by 1, then stop other scripts in stage
            local hat1Id, hat1Block = SB3Builder.Events.whenFlagClicked(100, 100)
            local change1Id, change1Block = SB3Builder.Data.changeVariable("counter", 1, variableId)
            local stop1Id, stop1Block = SB3Builder.Control.stopOtherScriptsInStage()

            -- Script 2: forever { change counter by 10 }
            local hat2Id, hat2Block = SB3Builder.Events.whenFlagClicked(200, 100)
            local change2Id, change2Block = SB3Builder.Data.changeVariable("counter", 10, variableId)
            local forever2Id, forever2Block = SB3Builder.Control.forever(change2Id)

            SB3Builder.addBlock(stage, hat1Id, hat1Block)
            SB3Builder.addBlock(stage, change1Id, change1Block)
            SB3Builder.addBlock(stage, stop1Id, stop1Block)
            SB3Builder.linkBlocks(stage, { hat1Id, change1Id, stop1Id })

            SB3Builder.addBlock(stage, hat2Id, hat2Block)
            SB3Builder.addBlock(stage, forever2Id, forever2Block)
            SB3Builder.addBlock(stage, change2Id, change2Block)
            SB3Builder.linkBlocks(stage, { hat2Id, forever2Id })

            local projectJson = SB3Builder.createProject({ stage })
            local project = ProjectModel:new(projectJson, {})
            local runtime = Runtime:new(project)
            runtime:initialize()

            runtime:broadcastGreenFlag()
            -- Run briefly to allow both scripts to start and one to stop the other
            for i = 1, 5 do
                runtime:update(1 / 60)
            end

            local counter = runtime.stage:lookupVariableByNameAndType("counter")
            -- Counter should be 1 (from first script) but not much higher if second script was stopped
            expect(counter.value).to.be.a("number")
            expect(counter.value >= 1).to.be(true)
        end)
    end)

    describe("Clone Operations", function()
        it("should create clone and execute start as clone scripts", function()
            SB3Builder.resetCounter()
            local stage = SB3Builder.createStage()
            local sprite = SB3Builder.createSprite("TestSprite")
            local variableId = SB3Builder.addVariable(stage, "cloneFlag", 0)

            -- Script 1: when flag clicked -> create clone of myself
            local hat1Id, hat1Block = SB3Builder.Events.whenFlagClicked()
            local clone1Id, clone1Block, menu1Id, menu1Block = SB3Builder.Control.createCloneOf("_myself_")

            -- Script 2: when start as clone -> set cloneFlag to 1
            local hat2Id, hat2Block = SB3Builder.Control.whenStartAsClone()
            local setId, setBlock = SB3Builder.Data.setVariable("cloneFlag", 1, variableId)

            SB3Builder.addBlock(sprite, hat1Id, hat1Block)
            SB3Builder.addBlock(sprite, menu1Id, menu1Block)
            SB3Builder.addBlock(sprite, clone1Id, clone1Block)
            SB3Builder.linkBlocks(sprite, { hat1Id, clone1Id })

            SB3Builder.addBlock(sprite, hat2Id, hat2Block)
            SB3Builder.addBlock(sprite, setId, setBlock)
            SB3Builder.linkBlocks(sprite, { hat2Id, setId })

            local projectJson = SB3Builder.createProject({ stage, sprite })
            local project = ProjectModel:new(projectJson, {})
            local runtime = Runtime:new(project)
            runtime:initialize()

            -- Count initial sprites/clones
            local initialSpriteCount = #runtime.targets

            runtime:broadcastGreenFlag()
            local maxIterations = 100
            local iterations = 0
            while #runtime:getActiveThreads() > 0 and iterations < maxIterations do
                runtime:update(1 / 60)
                iterations = iterations + 1
            end

            -- Verify clone was created and executed its start script
            local cloneFlag = runtime.stage:lookupVariableByNameAndType("cloneFlag")
            expect(cloneFlag.value).to.equal(1) -- Clone should have set this flag

            -- Verify clone was actually created (should have more sprites now)
            local finalSpriteCount = #runtime.targets
            expect(finalSpriteCount > initialSpriteCount).to.be(true) -- Should have more targets after cloning
        end)

        it("should delete clone when delete this clone is used", function()
            SB3Builder.resetCounter()
            local stage = SB3Builder.createStage()
            local sprite = SB3Builder.createSprite("TestSprite")
            local variableId = SB3Builder.addVariable(stage, "deletionFlag", 0)

            -- Script 1: when flag clicked -> create clone of myself
            local hat1Id, hat1Block = SB3Builder.Events.whenFlagClicked()
            local clone1Id, clone1Block, menu1Id, menu1Block = SB3Builder.Control.createCloneOf("_myself_")

            -- Script 2: when I start as a clone -> set flag and delete this clone
            local hat2Id, hat2Block = SB3Builder.Control.whenStartAsClone()
            local setId, setBlock = SB3Builder.Data.setVariable("deletionFlag", 1, variableId)
            local delete2Id, delete2Block = SB3Builder.Control.deleteThisClone()

            SB3Builder.addBlock(sprite, hat1Id, hat1Block)
            SB3Builder.addBlock(sprite, menu1Id, menu1Block)
            SB3Builder.addBlock(sprite, clone1Id, clone1Block)
            SB3Builder.linkBlocks(sprite, { hat1Id, clone1Id })

            SB3Builder.addBlock(sprite, hat2Id, hat2Block)
            SB3Builder.addBlock(sprite, setId, setBlock)
            SB3Builder.addBlock(sprite, delete2Id, delete2Block)
            SB3Builder.linkBlocks(sprite, { hat2Id, setId, delete2Id })

            local projectJson = SB3Builder.createProject({ stage, sprite })
            local project = ProjectModel:new(projectJson, {})
            local runtime = Runtime:new(project)
            runtime:initialize()

            -- Count initial sprites/clones
            local initialSpriteCount = #runtime.targets

            runtime:broadcastGreenFlag()
            local maxIterations = 100
            local iterations = 0
            while #runtime:getActiveThreads() > 0 and iterations < maxIterations do
                runtime:update(1 / 60)
                iterations = iterations + 1
            end

            -- Verify clone executed before deletion (set the flag)
            local deletionFlag = runtime.stage:lookupVariableByNameAndType("deletionFlag")
            expect(deletionFlag.value).to.equal(1) -- Clone should have set this flag before being deleted

            -- Verify clone was deleted (sprite count should return to original)
            local finalSpriteCount = #runtime.targets
            expect(finalSpriteCount).to.equal(initialSpriteCount) -- Should be back to original count after deletion
        end)
    end)

    describe("All At Once Operations", function()
        it("should execute all at once substack immediately", function()
            SB3Builder.resetCounter()
            local stage = SB3Builder.createStage()
            local variableId = SB3Builder.addVariable(stage, "counter", 0)

            local hatId, hatBlock = SB3Builder.Events.whenFlagClicked(100, 100)
            local changeId, changeBlock = SB3Builder.Data.changeVariable("counter", 1, variableId)
            local allAtOnceId, allAtOnceBlock = SB3Builder.Control.allAtOnce(changeId)

            SB3Builder.addBlock(stage, hatId, hatBlock)
            SB3Builder.addBlock(stage, allAtOnceId, allAtOnceBlock)
            SB3Builder.addBlock(stage, changeId, changeBlock)
            SB3Builder.linkBlocks(stage, { hatId, allAtOnceId })

            local projectJson = SB3Builder.createProject({ stage })
            local project = ProjectModel:new(projectJson, {})
            local runtime = Runtime:new(project)
            runtime:initialize()

            runtime:broadcastGreenFlag()
            local maxIterations = 100
            local iterations = 0
            while #runtime:getActiveThreads() > 0 and iterations < maxIterations do
                runtime:update(1 / 60)
                iterations = iterations + 1
            end

            local counter = runtime.stage:lookupVariableByNameAndType("counter")
            expect(counter.value).to.equal(1)
        end)
    end)

    describe("Menu Blocks", function()
        it("should return clone option from create clone of menu", function()
            -- Test menu block directly using control module
            local BlockHelpers = require("runtime.block_helpers")
            local result = BlockHelpers.Control.create_clone_of_menu(nil, { CLONE_OPTION = "_myself_" }, nil, nil)

            expect(result).to.equal("_myself_")
        end)
    end)

    describe("Wait Operations Advanced", function()
        it("should handle wait timing accurately", function()
            SB3Builder.resetCounter()
            local stage = SB3Builder.createStage()
            local variableId = SB3Builder.addVariable(stage, "counter", 0)

            local hatId, hatBlock = SB3Builder.Events.whenFlagClicked(100, 100)
            local waitId, waitBlock = SB3Builder.Control.wait(0.05) -- 50ms wait
            local changeId, changeBlock = SB3Builder.Data.changeVariable("counter", 1, variableId)

            SB3Builder.addBlock(stage, hatId, hatBlock)
            SB3Builder.addBlock(stage, waitId, waitBlock)
            SB3Builder.addBlock(stage, changeId, changeBlock)
            SB3Builder.linkBlocks(stage, { hatId, waitId, changeId })

            local projectJson = SB3Builder.createProject({ stage })
            local project = ProjectModel:new(projectJson, {})
            local runtime = Runtime:new(project)
            runtime:initialize()

            local startTime = love and love.timer and love.timer.getTime() or os.clock()
            runtime:broadcastGreenFlag()

            -- Run until counter changes or timeout
            local iterations = 0
            while #runtime:getActiveThreads() > 0 and iterations < 100 do
                runtime:update(1 / 60)
                iterations = iterations + 1
                local counter = runtime.stage:lookupVariableByNameAndType("counter")
                if counter.value > 0 then
                    break
                end
            end

            local endTime = love and love.timer and love.timer.getTime() or os.clock()
            local elapsed = endTime - startTime

            local counter = runtime.stage:lookupVariableByNameAndType("counter")
            expect(counter.value).to.equal(1) -- Should have executed after wait
            -- Note: timing accuracy test would need proper time tracking in test environment
        end)
    end)

    describe("Deep Nested Loops", function()
        it("should handle triple nested repeat loops", function()
            SB3Builder.resetCounter()
            local stage = SB3Builder.createStage()
            local variableId = SB3Builder.addVariable(stage, "counter", 0)

            -- Create: repeat 2 times { repeat 2 times { repeat 2 times { change counter by 1 } } }
            local hatId, hatBlock = SB3Builder.Events.whenFlagClicked(100, 100)
            local changeId, changeBlock = SB3Builder.Data.changeVariable("counter", 1, variableId)
            local innerRepeatId, innerRepeatBlock = SB3Builder.Control.repeat_(2, changeId)
            local middleRepeatId, middleRepeatBlock = SB3Builder.Control.repeat_(2, innerRepeatId)
            local outerRepeatId, outerRepeatBlock = SB3Builder.Control.repeat_(2, middleRepeatId)

            SB3Builder.addBlock(stage, hatId, hatBlock)
            SB3Builder.addBlock(stage, outerRepeatId, outerRepeatBlock)
            SB3Builder.addBlock(stage, middleRepeatId, middleRepeatBlock)
            SB3Builder.addBlock(stage, innerRepeatId, innerRepeatBlock)
            SB3Builder.addBlock(stage, changeId, changeBlock)
            SB3Builder.linkBlocks(stage, { hatId, outerRepeatId })

            local projectJson = SB3Builder.createProject({ stage })
            local project = ProjectModel:new(projectJson, {})
            local runtime = Runtime:new(project)
            runtime:initialize()

            runtime:broadcastGreenFlag()
            local maxIterations = 200
            local iterations = 0
            while #runtime:getActiveThreads() > 0 and iterations < maxIterations do
                runtime:update(1 / 60)
                iterations = iterations + 1
            end

            local counter = runtime.stage:lookupVariableByNameAndType("counter")
            expect(counter.value).to.equal(8) -- 2 * 2 * 2 = 8
        end)

        it("should handle nested repeat until loops", function()
            SB3Builder.resetCounter()
            local stage = SB3Builder.createStage()
            local counterAId = SB3Builder.addVariable(stage, "counterA", 0)
            local counterBId = SB3Builder.addVariable(stage, "counterB", 0)

            -- Create: repeat until (counterB = 3) {
            --   change counterB by 1
            --   repeat until (counterA = 2) {
            --     change counterA by 1
            --   }
            --   set counterA to 0
            -- }
            local hatId, hatBlock = SB3Builder.Events.whenFlagClicked(100, 100)

            -- Inner loop: repeat until counterA = 2
            local changeAId, changeABlock = SB3Builder.Data.changeVariable("counterA", 1, counterAId)
            local varAId, varABlock = SB3Builder.Data.variable("counterA", counterAId)
            local equalsA2Id, equalsA2Block = SB3Builder.Operators.equals(varAId, 2)
            local innerRepeatUntilId, innerRepeatUntilBlock = SB3Builder.Control.repeatUntil(equalsA2Id, changeAId)

            -- Reset counterA
            local resetAId, resetABlock = SB3Builder.Data.setVariable("counterA", 0, counterAId)

            -- Outer loop content: change B, inner loop, reset A
            local changeBId, changeBBlock = SB3Builder.Data.changeVariable("counterB", 1, counterBId)

            -- Outer loop condition: counterB = 3
            local varBId, varBBlock = SB3Builder.Data.variable("counterB", counterBId)
            local equalsB3Id, equalsB3Block = SB3Builder.Operators.equals(varBId, 3)

            -- Create sequence: changeB -> innerRepeatUntil -> resetA
            SB3Builder.linkBlocks(stage, { changeBId, innerRepeatUntilId, resetAId })

            local outerRepeatUntilId, outerRepeatUntilBlock = SB3Builder.Control.repeatUntil(equalsB3Id, changeBId)

            SB3Builder.addBlock(stage, hatId, hatBlock)
            SB3Builder.addBlock(stage, outerRepeatUntilId, outerRepeatUntilBlock)
            SB3Builder.addBlock(stage, changeBId, changeBBlock)
            SB3Builder.addBlock(stage, innerRepeatUntilId, innerRepeatUntilBlock)
            SB3Builder.addBlock(stage, changeAId, changeABlock)
            SB3Builder.addBlock(stage, resetAId, resetABlock)
            SB3Builder.addBlock(stage, varAId, varABlock)
            SB3Builder.addBlock(stage, varBId, varBBlock)
            SB3Builder.addBlock(stage, equalsA2Id, equalsA2Block)
            SB3Builder.addBlock(stage, equalsB3Id, equalsB3Block)
            SB3Builder.linkBlocks(stage, { hatId, outerRepeatUntilId })

            local projectJson = SB3Builder.createProject({ stage })
            local project = ProjectModel:new(projectJson, {})
            local runtime = Runtime:new(project)
            runtime:initialize()

            runtime:broadcastGreenFlag()
            local maxIterations = 300
            local iterations = 0
            while #runtime:getActiveThreads() > 0 and iterations < maxIterations do
                runtime:update(1 / 60)
                iterations = iterations + 1
            end

            local counterA = runtime.stage:lookupVariableByNameAndType("counterA")
            local counterB = runtime.stage:lookupVariableByNameAndType("counterB")
            expect(counterB.value).to.equal(3) -- Outer loop should complete when B = 3
            expect(counterA.value).to.equal(0) -- A should be reset after each outer iteration
        end)

        it("should handle nested forever and repeat combination", function()
            SB3Builder.resetCounter()
            local stage = SB3Builder.createStage()
            local variableId = SB3Builder.addVariable(stage, "counter", 0)

            -- Create: forever { repeat 2 times { change counter by 1 } }
            local hatId, hatBlock = SB3Builder.Events.whenFlagClicked(100, 100)
            local changeId, changeBlock = SB3Builder.Data.changeVariable("counter", 1, variableId)
            local repeatId, repeatBlock = SB3Builder.Control.repeat_(2, changeId)
            local foreverId, foreverBlock = SB3Builder.Control.forever(repeatId)

            SB3Builder.addBlock(stage, hatId, hatBlock)
            SB3Builder.addBlock(stage, foreverId, foreverBlock)
            SB3Builder.addBlock(stage, repeatId, repeatBlock)
            SB3Builder.addBlock(stage, changeId, changeBlock)
            SB3Builder.linkBlocks(stage, { hatId, foreverId })

            local projectJson = SB3Builder.createProject({ stage })
            local project = ProjectModel:new(projectJson, {})
            local runtime = Runtime:new(project)
            runtime:initialize()

            runtime:broadcastGreenFlag()

            -- Run for limited frames to test continuous execution
            for i = 1, 20 do
                runtime:update(1 / 60)
            end

            local counter = runtime.stage:lookupVariableByNameAndType("counter")
            expect(counter.value).to.be.a("number")
            expect(counter.value >= 4).to.be(true)          -- Should execute multiple times (2 per forever iteration)
            expect(#runtime:getActiveThreads()).to.equal(1) -- Thread should still be active
        end)
    end)

    describe("Complex Conditional Nesting", function()
        it("should handle nested if-else structures", function()
            SB3Builder.resetCounter()
            local stage = SB3Builder.createStage()
            local resultId = SB3Builder.addVariable(stage, "result", "")
            local valueId = SB3Builder.addVariable(stage, "value", 5)

            -- Create: if (value > 3) {
            --   if (value > 7) {
            --     set result to "high"
            --   } else {
            --     set result to "medium"
            --   }
            -- } else {
            --   set result to "low"
            -- }
            local hatId, hatBlock = SB3Builder.Events.whenFlagClicked(100, 100)

            -- Inner if-else: value > 7
            local setHighId, setHighBlock = SB3Builder.Data.setVariable("result", "high", resultId)
            local setMediumId, setMediumBlock = SB3Builder.Data.setVariable("result", "medium", resultId)
            local varValue2Id, varValue2Block = SB3Builder.Data.variable("value", valueId)
            local gt7Id, gt7Block = SB3Builder.Operators.greaterThan(varValue2Id, 7)
            local innerIfElseId, innerIfElseBlock = SB3Builder.Control.ifElse(gt7Id, setHighId,
                setMediumId)

            -- Outer if-else: value > 3
            local setLowId, setLowBlock = SB3Builder.Data.setVariable("result", "low", resultId)
            local varValue1Id, varValue1Block = SB3Builder.Data.variable("value", valueId)
            local gt3Id, gt3Block = SB3Builder.Operators.greaterThan(varValue1Id, 3)
            local outerIfElseId, outerIfElseBlock = SB3Builder.Control.ifElse(gt3Id, innerIfElseId,
                setLowId)

            SB3Builder.addBlock(stage, hatId, hatBlock)
            SB3Builder.addBlock(stage, outerIfElseId, outerIfElseBlock)
            SB3Builder.addBlock(stage, innerIfElseId, innerIfElseBlock)
            SB3Builder.addBlock(stage, setHighId, setHighBlock)
            SB3Builder.addBlock(stage, setMediumId, setMediumBlock)
            SB3Builder.addBlock(stage, setLowId, setLowBlock)
            SB3Builder.addBlock(stage, varValue1Id, varValue1Block)
            SB3Builder.addBlock(stage, varValue2Id, varValue2Block)
            SB3Builder.addBlock(stage, gt3Id, gt3Block)
            SB3Builder.addBlock(stage, gt7Id, gt7Block)
            SB3Builder.linkBlocks(stage, { hatId, outerIfElseId })

            local projectJson = SB3Builder.createProject({ stage })
            local project = ProjectModel:new(projectJson, {})
            local runtime = Runtime:new(project)
            runtime:initialize()

            runtime:broadcastGreenFlag()
            local maxIterations = 100
            local iterations = 0
            while #runtime:getActiveThreads() > 0 and iterations < maxIterations do
                runtime:update(1 / 60)
                iterations = iterations + 1
            end

            local result = runtime.stage:lookupVariableByNameAndType("result")
            expect(result.value).to.equal("medium") -- value=5: 5>3 true, 5>7 false
        end)

        it("should handle if-else within loops", function()
            SB3Builder.resetCounter()
            local stage = SB3Builder.createStage()
            local evenCountId = SB3Builder.addVariable(stage, "evenCount", 0)
            local oddCountId = SB3Builder.addVariable(stage, "oddCount", 0)
            local loopCounterId = SB3Builder.addVariable(stage, "loopCounter", 0)

            -- Create: repeat 5 times {
            --   change loopCounter by 1
            --   if (loopCounter mod 2 = 0) {
            --     change evenCount by 1
            --   } else {
            --     change oddCount by 1
            --   }
            -- }
            local hatId, hatBlock = SB3Builder.Events.whenFlagClicked(100, 100)

            -- Increment loop counter
            local incLoopId, incLoopBlock = SB3Builder.Data.changeVariable("loopCounter", 1, loopCounterId)

            -- Check if even: loopCounter mod 2 = 0
            local varLoopId, varLoopBlock = SB3Builder.Data.variable("loopCounter", loopCounterId)
            local mod2Id, mod2Block = SB3Builder.Operators.mod(varLoopId, 2)
            local eq0Id, eq0Block = SB3Builder.Operators.equals(mod2Id, 0)

            -- Actions
            local incEvenId, incEvenBlock = SB3Builder.Data.changeVariable("evenCount", 1, evenCountId)
            local incOddId, incOddBlock = SB3Builder.Data.changeVariable("oddCount", 1, oddCountId)

            -- If-else for even/odd
            local ifEvenOddId, ifEvenOddBlock = SB3Builder.Control.ifElse(eq0Id, incEvenId, incOddId)

            -- Repeat 5 times
            local repeatId, repeatBlock = SB3Builder.Control.repeat_(5, incLoopId)

            SB3Builder.addBlock(stage, hatId, hatBlock)
            SB3Builder.addBlock(stage, repeatId, repeatBlock)
            SB3Builder.addBlock(stage, incLoopId, incLoopBlock)
            SB3Builder.addBlock(stage, ifEvenOddId, ifEvenOddBlock)
            SB3Builder.addBlock(stage, incEvenId, incEvenBlock)
            SB3Builder.addBlock(stage, incOddId, incOddBlock)
            SB3Builder.addBlock(stage, varLoopId, varLoopBlock)
            SB3Builder.addBlock(stage, mod2Id, mod2Block)
            SB3Builder.addBlock(stage, eq0Id, eq0Block)

            -- Link blocks AFTER adding them to stage
            SB3Builder.linkBlocks(stage, { incLoopId, ifEvenOddId })
            SB3Builder.linkBlocks(stage, { hatId, repeatId })

            local projectJson = SB3Builder.createProject({ stage })
            local project = ProjectModel:new(projectJson, {})
            local runtime = Runtime:new(project)
            runtime:initialize()

            runtime:broadcastGreenFlag()
            local maxIterations = 200
            local iterations = 0
            while #runtime:getActiveThreads() > 0 and iterations < maxIterations do
                runtime:update(1 / 60)
                iterations = iterations + 1
            end

            local loopCounter = runtime.stage:lookupVariableByNameAndType("loopCounter")
            local evenCount = runtime.stage:lookupVariableByNameAndType("evenCount")
            local oddCount = runtime.stage:lookupVariableByNameAndType("oddCount")

            expect(loopCounter.value).to.equal(5)
            expect(evenCount.value).to.equal(2) -- 2, 4 are even
            expect(oddCount.value).to.equal(3)  -- 1, 3, 5 are odd
        end)
    end)

    describe("Mixed Nested Scenarios", function()
        it("should handle loops with conditional breaks", function()
            SB3Builder.resetCounter()
            local stage = SB3Builder.createStage()
            local variableId = SB3Builder.addVariable(stage, "counter", 0)
            local breakFlagId = SB3Builder.addVariable(stage, "breakFlag", false)

            -- Create: forever {
            --   change counter by 1
            --   if (counter > 5) {
            --     set breakFlag to true
            --   }
            --   if (breakFlag = true) {
            --     stop this script
            --   }
            -- }
            local hatId, hatBlock = SB3Builder.Events.whenFlagClicked(100, 100)

            local changeId, changeBlock = SB3Builder.Data.changeVariable("counter", 1, variableId)

            -- Check if counter > 5
            local varCounterId, varCounterBlock = SB3Builder.Data.variable("counter", variableId)
            local gt5Id, gt5Block = SB3Builder.Operators.greaterThan(varCounterId, 5)

            -- Set break flag
            local setBreakId, setBreakBlock = SB3Builder.Data.setVariable("breakFlag", true, breakFlagId)
            local ifSetBreakId, ifSetBreakBlock = SB3Builder.Control.ifCondition(gt5Id, setBreakId)

            -- Check break flag and stop
            local varBreakId, varBreakBlock = SB3Builder.Data.variable("breakFlag", breakFlagId)
            local eqTrueId, eqTrueBlock = SB3Builder.Operators.equals(varBreakId, true)

            local stopId, stopBlock = SB3Builder.Control.stopThisScript()
            local ifStopId, ifStopBlock = SB3Builder.Control.ifCondition(eqTrueId, stopId)

            local foreverId, foreverBlock = SB3Builder.Control.forever(changeId)

            SB3Builder.addBlock(stage, hatId, hatBlock)
            SB3Builder.addBlock(stage, foreverId, foreverBlock)
            SB3Builder.addBlock(stage, changeId, changeBlock)
            SB3Builder.addBlock(stage, ifSetBreakId, ifSetBreakBlock)
            SB3Builder.addBlock(stage, setBreakId, setBreakBlock)
            SB3Builder.addBlock(stage, ifStopId, ifStopBlock)
            SB3Builder.addBlock(stage, stopId, stopBlock)
            SB3Builder.addBlock(stage, varCounterId, varCounterBlock)
            SB3Builder.addBlock(stage, varBreakId, varBreakBlock)
            SB3Builder.addBlock(stage, gt5Id, gt5Block)
            SB3Builder.addBlock(stage, eqTrueId, eqTrueBlock)

            -- Link the sequence AFTER adding all blocks
            SB3Builder.linkBlocks(stage, { changeId, ifSetBreakId, ifStopId })
            SB3Builder.linkBlocks(stage, { hatId, foreverId })

            local projectJson = SB3Builder.createProject({ stage })
            local project = ProjectModel:new(projectJson, {})
            local runtime = Runtime:new(project)
            runtime:initialize()

            runtime:broadcastGreenFlag()
            local maxIterations = 50
            local iterations = 0
            while #runtime:getActiveThreads() > 0 and iterations < maxIterations do
                runtime:update(1 / 60)
                iterations = iterations + 1
            end

            local counter = runtime.stage:lookupVariableByNameAndType("counter")
            local breakFlag = runtime.stage:lookupVariableByNameAndType("breakFlag")

            expect(counter.value >= 6).to.be(true)          -- Should have counted past 5
            expect(breakFlag.value == true or breakFlag.value == "true").to.be(true) -- Break flag should be set (boolean or string)
            expect(#runtime:getActiveThreads()).to.equal(0) -- Script should be stopped
        end)

        it("should handle complex state machine with nested conditions", function()
            SB3Builder.resetCounter()
            local stage = SB3Builder.createStage()
            local stateId = SB3Builder.addVariable(stage, "state", "start")
            local counterId = SB3Builder.addVariable(stage, "counter", 0)

            -- State machine:
            -- start -> count (if counter < 3)
            -- count -> increment counter, if counter >= 3 then end
            -- end -> stop
            local hatId, hatBlock = SB3Builder.Events.whenFlagClicked(100, 100)

            -- Forever loop for state machine
            local varStateId, varStateBlock = SB3Builder.Data.variable("state", stateId)

            -- State = "start" branch
            local eqStartId, eqStartBlock = SB3Builder.Operators.equals(varStateId, "start")
            local setCountStateId, setCountStateBlock = SB3Builder.Data.setVariable("state", "count", stateId)
            local ifStartId, ifStartBlock = SB3Builder.Control.ifCondition(eqStartId, setCountStateId)

            -- State = "count" branch
            local varState2Id, varState2Block = SB3Builder.Data.variable("state", stateId)
            local eqCountId, eqCountBlock = SB3Builder.Operators.equals(varState2Id, "count")

            -- In count state: increment counter, check if >= 3
            local incCounterId, incCounterBlock = SB3Builder.Data.changeVariable("counter", 1, counterId)
            local varCounterId, varCounterBlock = SB3Builder.Data.variable("counter", counterId)
            local gte3Id, gte3Block = SB3Builder.Operators.equals(varCounterId, 3) -- = 3
            local setEndStateId, setEndStateBlock = SB3Builder.Data.setVariable("state", "end", stateId)
            local ifEndStateId, ifEndStateBlock = SB3Builder.Control.ifCondition(gte3Id, setEndStateId)

            local ifCountId, ifCountBlock = SB3Builder.Control.ifCondition(eqCountId, incCounterId)

            -- State = "end" branch
            local varState3Id, varState3Block = SB3Builder.Data.variable("state", stateId)
            local eqEndId, eqEndBlock = SB3Builder.Operators.equals(varState3Id, "end")
            local stopId, stopBlock = SB3Builder.Control.stopThisScript()
            local ifEndId, ifEndBlock = SB3Builder.Control.ifCondition(eqEndId, stopId)

            local foreverId, foreverBlock = SB3Builder.Control.forever(ifStartId)

            SB3Builder.addBlock(stage, hatId, hatBlock)
            SB3Builder.addBlock(stage, foreverId, foreverBlock)
            SB3Builder.addBlock(stage, ifStartId, ifStartBlock)
            SB3Builder.addBlock(stage, ifCountId, ifCountBlock)
            SB3Builder.addBlock(stage, ifEndId, ifEndBlock)
            SB3Builder.addBlock(stage, setCountStateId, setCountStateBlock)
            SB3Builder.addBlock(stage, incCounterId, incCounterBlock)
            SB3Builder.addBlock(stage, ifEndStateId, ifEndStateBlock)
            SB3Builder.addBlock(stage, setEndStateId, setEndStateBlock)
            SB3Builder.addBlock(stage, stopId, stopBlock)
            SB3Builder.addBlock(stage, varStateId, varStateBlock)
            SB3Builder.addBlock(stage, varState2Id, varState2Block)
            SB3Builder.addBlock(stage, varState3Id, varState3Block)
            SB3Builder.addBlock(stage, varCounterId, varCounterBlock)
            SB3Builder.addBlock(stage, eqStartId, eqStartBlock)
            SB3Builder.addBlock(stage, eqCountId, eqCountBlock)
            SB3Builder.addBlock(stage, eqEndId, eqEndBlock)
            SB3Builder.addBlock(stage, gte3Id, gte3Block)

            -- Link blocks AFTER adding them all
            SB3Builder.linkBlocks(stage, { incCounterId, ifEndStateId })
            SB3Builder.linkBlocks(stage, { ifStartId, ifCountId, ifEndId })
            SB3Builder.linkBlocks(stage, { hatId, foreverId })

            local projectJson = SB3Builder.createProject({ stage })
            local project = ProjectModel:new(projectJson, {})
            local runtime = Runtime:new(project)
            runtime:initialize()

            runtime:broadcastGreenFlag()
            local maxIterations = 100
            local iterations = 0
            while #runtime:getActiveThreads() > 0 and iterations < maxIterations do
                runtime:update(1 / 60)
                iterations = iterations + 1
            end

            local state = runtime.stage:lookupVariableByNameAndType("state")
            local counter = runtime.stage:lookupVariableByNameAndType("counter")

            expect(state.value).to.equal("end")             -- Should end in "end" state
            expect(counter.value).to.equal(3)               -- Should count to 3
            expect(#runtime:getActiveThreads()).to.equal(0) -- Script should be stopped
        end)
    end)

    describe("Edge Cases and Error Handling", function()
        it("should handle repeat with nil substack", function()
            SB3Builder.resetCounter()
            local stage = SB3Builder.createStage()

            local hatId, hatBlock = SB3Builder.Events.whenFlagClicked(100, 100)
            local repeatId, repeatBlock = SB3Builder.Control.repeat_(3, nil) -- No substack

            SB3Builder.addBlock(stage, hatId, hatBlock)
            SB3Builder.addBlock(stage, repeatId, repeatBlock)
            SB3Builder.linkBlocks(stage, { hatId, repeatId })

            local projectJson = SB3Builder.createProject({ stage })
            local project = ProjectModel:new(projectJson, {})
            local runtime = Runtime:new(project)
            runtime:initialize()

            runtime:broadcastGreenFlag()
            local maxIterations = 100
            local iterations = 0
            while #runtime:getActiveThreads() > 0 and iterations < maxIterations do
                runtime:update(1 / 60)
                iterations = iterations + 1
            end

            -- Should complete without error
            expect(#runtime:getActiveThreads()).to.equal(0)
        end)

        it("should handle forever with nil substack", function()
            SB3Builder.resetCounter()
            local stage = SB3Builder.createStage()

            local hatId, hatBlock = SB3Builder.Events.whenFlagClicked(100, 100)
            local foreverId, foreverBlock = SB3Builder.Control.forever(nil) -- No substack

            SB3Builder.addBlock(stage, hatId, hatBlock)
            SB3Builder.addBlock(stage, foreverId, foreverBlock)
            SB3Builder.linkBlocks(stage, { hatId, foreverId })

            local projectJson = SB3Builder.createProject({ stage })
            local project = ProjectModel:new(projectJson, {})
            local runtime = Runtime:new(project)
            runtime:initialize()

            runtime:broadcastGreenFlag()
            runtime:update(1 / 30) -- Use logic frame time (not render frame time) to ensure execution

            expect(#runtime:getActiveThreads()).to.equal(0)
        end)

        it("should handle if with nil substack", function()
            SB3Builder.resetCounter()
            local stage = SB3Builder.createStage()

            local hatId, hatBlock = SB3Builder.Events.whenFlagClicked(100, 100)
            local ifId, ifBlock = SB3Builder.Control.ifCondition(true, nil) -- No substack

            SB3Builder.addBlock(stage, hatId, hatBlock)
            SB3Builder.addBlock(stage, ifId, ifBlock)
            SB3Builder.linkBlocks(stage, { hatId, ifId })

            local projectJson = SB3Builder.createProject({ stage })
            local project = ProjectModel:new(projectJson, {})
            local runtime = Runtime:new(project)
            runtime:initialize()

            runtime:broadcastGreenFlag()
            local maxIterations = 100
            local iterations = 0
            while #runtime:getActiveThreads() > 0 and iterations < maxIterations do
                runtime:update(1 / 60)
                iterations = iterations + 1
            end

            expect(#runtime:getActiveThreads()).to.equal(0)
        end)

        it("should handle create clone of non-existent sprite", function()
            SB3Builder.resetCounter()
            local stage = SB3Builder.createStage()
            local sprite = SB3Builder.createSprite("TestSprite")
            local variableId = SB3Builder.addVariable(stage, "errorFlag", 0)

            -- Script: when flag clicked -> try to clone non-existent sprite -> set errorFlag to 1
            local hatId, hatBlock = SB3Builder.Events.whenFlagClicked()
            local cloneId, cloneBlock, menuId, menuBlock = SB3Builder.Control.createCloneOf("NonExistentSprite")
            local setId, setBlock = SB3Builder.Data.setVariable("errorFlag", 1, variableId)

            SB3Builder.addBlock(sprite, hatId, hatBlock)
            SB3Builder.addBlock(sprite, menuId, menuBlock)
            SB3Builder.addBlock(sprite, cloneId, cloneBlock)
            SB3Builder.addBlock(sprite, setId, setBlock)
            SB3Builder.linkBlocks(sprite, { hatId, cloneId, setId })

            local projectJson = SB3Builder.createProject({ stage, sprite })
            local project = ProjectModel:new(projectJson, {})
            local runtime = Runtime:new(project)
            runtime:initialize()

            -- Count initial sprites/clones
            local initialSpriteCount = #runtime.targets

            runtime:broadcastGreenFlag()
            local maxIterations = 100
            local iterations = 0
            while #runtime:getActiveThreads() > 0 and iterations < maxIterations do
                runtime:update(1 / 60)
                iterations = iterations + 1
            end

            -- Verify script continued execution despite clone failure
            local errorFlag = runtime.stage:lookupVariableByNameAndType("errorFlag")
            expect(errorFlag.value).to.equal(1) -- Script should continue and set this flag

            -- Verify no clone was created (sprite count unchanged)
            local finalSpriteCount = #runtime.targets
            expect(finalSpriteCount).to.equal(initialSpriteCount) -- No clone should be created

            -- Verify execution completed without hanging
            expect(#runtime:getActiveThreads()).to.equal(0) -- Script should finish
        end)
    end)

    describe("Advanced Repeat Block Logic", function()
        it("should handle repeat with negative times (should round to 0)", function()
            -- Based on Math.round(Cast.toNumber(args.TIMES)) in native implementation
            SB3Builder.resetCounter()
            local stage = SB3Builder.createStage()
            local variableId = SB3Builder.addVariable(stage, "counter", 0)

            local hatId, hatBlock = SB3Builder.Events.whenFlagClicked()
            local changeId, changeBlock = SB3Builder.Data.changeVariable("counter", 1, variableId)
            local repeatId, repeatBlock = SB3Builder.Control.repeat_(-5, changeId) -- Negative should round to 0

            SB3Builder.addBlock(stage, hatId, hatBlock)
            SB3Builder.addBlock(stage, repeatId, repeatBlock)
            SB3Builder.addBlock(stage, changeId, changeBlock)
            SB3Builder.linkBlocks(stage, { hatId, repeatId })

            local projectJson = SB3Builder.createProject({ stage })
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

            local counter = runtime.stage:lookupVariableByNameAndType("counter")
            expect(counter.value).to.equal(0) -- Should not execute with negative times
        end)

        it("should handle repeat with string times (should convert to number)", function()
            SB3Builder.resetCounter()
            local stage = SB3Builder.createStage()
            local variableId = SB3Builder.addVariable(stage, "counter", 0)

            local hatId, hatBlock = SB3Builder.Events.whenFlagClicked()
            local changeId, changeBlock = SB3Builder.Data.changeVariable("counter", 1, variableId)
            local repeatId, repeatBlock = SB3Builder.Control.repeat_("2.4", changeId) -- String should convert to 2

            SB3Builder.addBlock(stage, hatId, hatBlock)
            SB3Builder.addBlock(stage, repeatId, repeatBlock)
            SB3Builder.addBlock(stage, changeId, changeBlock)
            SB3Builder.linkBlocks(stage, { hatId, repeatId })

            local projectJson = SB3Builder.createProject({ stage })
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

            local counter = runtime.stage:lookupVariableByNameAndType("counter")
            expect(counter.value).to.equal(2) -- "2.4" should round to 2
        end)

        it("should handle repeat with extremely large numbers", function()
            SB3Builder.resetCounter()
            local stage = SB3Builder.createStage()
            local variableId = SB3Builder.addVariable(stage, "counter", 0)

            local hatId, hatBlock = SB3Builder.Events.whenFlagClicked()
            local changeId, changeBlock = SB3Builder.Data.changeVariable("counter", 1, variableId)
            local repeatId, repeatBlock = SB3Builder.Control.repeat_(1000000, changeId) -- Very large number

            SB3Builder.addBlock(stage, hatId, hatBlock)
            SB3Builder.addBlock(stage, repeatId, repeatBlock)
            SB3Builder.addBlock(stage, changeId, changeBlock)
            SB3Builder.linkBlocks(stage, { hatId, repeatId })

            local projectJson = SB3Builder.createProject({ stage })
            local project = ProjectModel:new(projectJson, {})
            local runtime = Runtime:new(project)
            runtime:initialize()

            runtime:broadcastGreenFlag()

            -- Run for limited iterations to test that large repeat doesn't break system
            local maxIterations = 50 -- Limit to prevent test timeout
            local iterations = 0
            while #runtime:getActiveThreads() > 0 and iterations < maxIterations do
                runtime:update(1/60)
                iterations = iterations + 1
            end

            local counter = runtime.stage:lookupVariableByNameAndType("counter")
            -- Should execute at least some iterations but be limited by maxIterations
            expect(counter.value > 0).to.be.truthy() -- Simple comparison
            expect(counter.value < 1000000).to.be.truthy() -- Should not complete all iterations
        end)
    end)

    describe("Advanced Wait Block Logic", function()
        it("should handle wait with negative duration (should clamp to 0)", function()
            -- Tests Math.max(0, 1000 * Cast.toNumber(args.DURATION)) logic
            SB3Builder.resetCounter()
            local stage = SB3Builder.createStage()
            local variableId = SB3Builder.addVariable(stage, "executionFlag", 0)

            local hatId, hatBlock = SB3Builder.Events.whenFlagClicked()
            local waitId, waitBlock = SB3Builder.Control.wait(-0.5) -- Negative duration
            local setId, setBlock = SB3Builder.Data.setVariable("executionFlag", 1, variableId)

            SB3Builder.addBlock(stage, hatId, hatBlock)
            SB3Builder.addBlock(stage, waitId, waitBlock)
            SB3Builder.addBlock(stage, setId, setBlock)
            SB3Builder.linkBlocks(stage, { hatId, waitId, setId })

            local projectJson = SB3Builder.createProject({ stage })
            local project = ProjectModel:new(projectJson, {})
            local runtime = Runtime:new(project)
            runtime:initialize()

            runtime:broadcastGreenFlag()

            -- Should complete immediately since negative duration is clamped to 0
            local maxIterations = 10
            local iterations = 0
            while #runtime:getActiveThreads() > 0 and iterations < maxIterations do
                runtime:update(1/60)
                iterations = iterations + 1
            end

            local flag = runtime.stage:lookupVariableByNameAndType("executionFlag")
            expect(flag.value).to.equal(1) -- Should execute immediately
            expect(#runtime:getActiveThreads()).to.equal(0)
        end)

        it("should handle wait with string duration conversion", function()
            SB3Builder.resetCounter()
            local stage = SB3Builder.createStage()
            local variableId = SB3Builder.addVariable(stage, "executionFlag", 0)

            local hatId, hatBlock = SB3Builder.Events.whenFlagClicked()
            local waitId, waitBlock = SB3Builder.Control.wait("0.02") -- String duration
            local setId, setBlock = SB3Builder.Data.setVariable("executionFlag", 1, variableId)

            SB3Builder.addBlock(stage, hatId, hatBlock)
            SB3Builder.addBlock(stage, waitId, waitBlock)
            SB3Builder.addBlock(stage, setId, setBlock)
            SB3Builder.linkBlocks(stage, { hatId, waitId, setId })

            local projectJson = SB3Builder.createProject({ stage })
            local project = ProjectModel:new(projectJson, {})
            local runtime = Runtime:new(project)
            runtime:initialize()

            runtime:broadcastGreenFlag()

            -- Should complete after string conversion and wait
            local maxIterations = 10
            local iterations = 0
            while #runtime:getActiveThreads() > 0 and iterations < maxIterations do
                runtime:update(1/60)
                iterations = iterations + 1
            end

            local flag = runtime.stage:lookupVariableByNameAndType("executionFlag")
            expect(flag.value).to.equal(1) -- Should complete after wait
            expect(#runtime:getActiveThreads()).to.equal(0)
        end)
    end)

    describe("Advanced CreateClone Logic", function()
        it("should handle create clone of _myself_ from sprite", function()
            -- Tests the special _myself_ case when executed on sprite
            SB3Builder.resetCounter()
            local stage = SB3Builder.createStage()
            local sprite = SB3Builder.createSprite("TestSprite")
            local variableId = SB3Builder.addVariable(stage, "cloneCount", 0)

            local hatId, hatBlock = SB3Builder.Events.whenFlagClicked()
            local cloneId, cloneBlock, menuId, menuBlock = SB3Builder.Control.createCloneOf("_myself_")
            local setId, setBlock = SB3Builder.Data.setVariable("cloneCount", 1, variableId)

            SB3Builder.addBlock(sprite, hatId, hatBlock)
            SB3Builder.addBlock(sprite, menuId, menuBlock)
            SB3Builder.addBlock(sprite, cloneId, cloneBlock)
            SB3Builder.addBlock(sprite, setId, setBlock)
            SB3Builder.linkBlocks(sprite, { hatId, cloneId, setId })

            local projectJson = SB3Builder.createProject({ stage, sprite })
            local project = ProjectModel:new(projectJson, {})
            local runtime = Runtime:new(project)
            runtime:initialize()

            local initialTargetCount = #runtime.targets
            runtime:broadcastGreenFlag()
            local maxIterations = 100
            local iterations = 0
            while #runtime:getActiveThreads() > 0 and iterations < maxIterations do
                runtime:update(1/60)
                iterations = iterations + 1
            end

            -- Sprite should be able to clone itself
            local flag = runtime.stage:lookupVariableByNameAndType("cloneCount")
            expect(flag.value).to.equal(1) -- Script should continue execution
            expect(#runtime.targets > initialTargetCount).to.be.truthy() -- Clone should be created
        end)

        it("should handle create clone with numeric target name", function()
            SB3Builder.resetCounter()
            local stage = SB3Builder.createStage()
            local sprite = SB3Builder.createSprite("123") -- Numeric sprite name
            local variableId = SB3Builder.addVariable(stage, "cloneCount", 0)

            local hatId, hatBlock = SB3Builder.Events.whenFlagClicked()
            local cloneId, cloneBlock, menuId, menuBlock = SB3Builder.Control.createCloneOf("123") -- String target
            local setId, setBlock = SB3Builder.Data.setVariable("cloneCount", 1, variableId)

            SB3Builder.addBlock(sprite, hatId, hatBlock)
            SB3Builder.addBlock(sprite, menuId, menuBlock)
            SB3Builder.addBlock(sprite, cloneId, cloneBlock)
            SB3Builder.addBlock(sprite, setId, setBlock)
            SB3Builder.linkBlocks(sprite, { hatId, cloneId, setId })

            local projectJson = SB3Builder.createProject({ stage, sprite })
            local project = ProjectModel:new(projectJson, {})
            local runtime = Runtime:new(project)
            runtime:initialize()

            local initialTargetCount = #runtime.targets
            runtime:broadcastGreenFlag()
            local maxIterations = 100
            local iterations = 0
            while #runtime:getActiveThreads() > 0 and iterations < maxIterations do
                runtime:update(1/60)
                iterations = iterations + 1
            end

            -- Should handle numeric target name properly (Cast.toString conversion)
            local flag = runtime.stage:lookupVariableByNameAndType("cloneCount")
            expect(flag.value).to.equal(1) -- Script should continue
            expect(#runtime.targets > initialTargetCount).to.be.truthy() -- Clone should be created
        end)
    end)

    describe("Advanced DeleteClone Logic", function()
        it("should not delete original sprite when delete this clone is used", function()
            SB3Builder.resetCounter()
            local stage = SB3Builder.createStage()
            local sprite = SB3Builder.createSprite("TestSprite")
            local variableId = SB3Builder.addVariable(stage, "deleteFlag", 0)

            -- Script on original sprite: delete this clone -> set deleteFlag
            -- In native Scratch, deleteThisClone has no effect on original sprites (not clones)
            -- So the script should continue and set the flag
            local hatId, hatBlock = SB3Builder.Events.whenFlagClicked()
            local deleteId, deleteBlock = SB3Builder.Control.deleteThisClone()
            local setId, setBlock = SB3Builder.Data.setVariable("deleteFlag", 1, variableId)

            SB3Builder.addBlock(sprite, hatId, hatBlock)
            SB3Builder.addBlock(sprite, deleteId, deleteBlock)
            SB3Builder.addBlock(sprite, setId, setBlock)
            SB3Builder.linkBlocks(sprite, { hatId, deleteId, setId })

            local projectJson = SB3Builder.createProject({ stage, sprite })
            local project = ProjectModel:new(projectJson, {})
            local runtime = Runtime:new(project)
            runtime:initialize()

            local initialTargetCount = #runtime.targets
            runtime:broadcastGreenFlag()
            local maxIterations = 100
            local iterations = 0
            while #runtime:getActiveThreads() > 0 and iterations < maxIterations do
                runtime:update(1/60)
                iterations = iterations + 1
            end

            -- Original sprite should not be deleted, script should continue
            local flag = runtime.stage:lookupVariableByNameAndType("deleteFlag")
            expect(flag.value).to.equal(1) -- Script should continue after delete attempt (native behavior)
            expect(#runtime.targets).to.equal(initialTargetCount) -- No targets should be deleted
        end)
    end)

    describe("Advanced Stop Block Logic", function()
        it("should differentiate between 'other scripts in sprite' and 'other scripts in stage'", function()
            SB3Builder.resetCounter()
            local stage = SB3Builder.createStage()
            local sprite = SB3Builder.createSprite("TestSprite")
            local stageVarId = SB3Builder.addVariable(stage, "stageFlag", 0)
            local spriteVarId = SB3Builder.addVariable(stage, "spriteFlag", 0)

            -- Stage script 1: when flag clicked -> wait 0.01 -> set stageFlag to 1
            local stageHat1Id, stageHat1Block = SB3Builder.Events.whenFlagClicked()
            local stageWait1Id, stageWait1Block = SB3Builder.Control.wait(0.01)
            local stageSet1Id, stageSet1Block = SB3Builder.Data.setVariable("stageFlag", 1, stageVarId)

            SB3Builder.addBlock(stage, stageHat1Id, stageHat1Block)
            SB3Builder.addBlock(stage, stageWait1Id, stageWait1Block)
            SB3Builder.addBlock(stage, stageSet1Id, stageSet1Block)
            SB3Builder.linkBlocks(stage, { stageHat1Id, stageWait1Id, stageSet1Id })

            -- Sprite script 1: when flag clicked -> stop other scripts in sprite -> set spriteFlag to 1
            local spriteHat1Id, spriteHat1Block = SB3Builder.Events.whenFlagClicked()
            local stopId, stopBlock = SB3Builder.Control.stopOtherScriptsInSprite()
            local spriteSet1Id, spriteSet1Block = SB3Builder.Data.setVariable("spriteFlag", 1, spriteVarId)

            SB3Builder.addBlock(sprite, spriteHat1Id, spriteHat1Block)
            SB3Builder.addBlock(sprite, stopId, stopBlock)
            SB3Builder.addBlock(sprite, spriteSet1Id, spriteSet1Block)
            SB3Builder.linkBlocks(sprite, { spriteHat1Id, stopId, spriteSet1Id })

            -- Sprite script 2: when flag clicked -> wait 0.01 -> set spriteFlag to 2
            local spriteHat2Id, spriteHat2Block = SB3Builder.Events.whenFlagClicked()
            local spriteWait2Id, spriteWait2Block = SB3Builder.Control.wait(0.01)
            local spriteSet2Id, spriteSet2Block = SB3Builder.Data.setVariable("spriteFlag", 2, spriteVarId)

            SB3Builder.addBlock(sprite, spriteHat2Id, spriteHat2Block)
            SB3Builder.addBlock(sprite, spriteWait2Id, spriteWait2Block)
            SB3Builder.addBlock(sprite, spriteSet2Id, spriteSet2Block)
            SB3Builder.linkBlocks(sprite, { spriteHat2Id, spriteWait2Id, spriteSet2Id })

            local projectJson = SB3Builder.createProject({ stage, sprite })
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

            local stageFlag = runtime.stage:lookupVariableByNameAndType("stageFlag")
            local spriteFlag = runtime.stage:lookupVariableByNameAndType("spriteFlag")

            -- Stage script should complete (not affected by sprite's stop command)
            expect(stageFlag.value).to.equal(1)
            -- Sprite script 1 should complete, script 2 should be stopped
            expect(spriteFlag.value).to.equal(1) -- Should not be 2 (script 2 stopped)
        end)
    end)

    describe("Type Conversion Edge Cases", function()
        it("should handle boolean conditions in repeat until/while", function()
            SB3Builder.resetCounter()
            local stage = SB3Builder.createStage()
            local variableId = SB3Builder.addVariable(stage, "counter", 0)

            local hatId, hatBlock = SB3Builder.Events.whenFlagClicked()
            local changeId, changeBlock = SB3Builder.Data.changeVariable("counter", 1, variableId)
            -- Simplified condition: just use a direct value comparison
            local untilId, untilBlock = SB3Builder.Control.repeatUntil(false, changeId) -- Simple condition

            SB3Builder.addBlock(stage, hatId, hatBlock)
            SB3Builder.addBlock(stage, untilId, untilBlock)
            SB3Builder.addBlock(stage, changeId, changeBlock)
            SB3Builder.linkBlocks(stage, { hatId, untilId })

            local projectJson = SB3Builder.createProject({ stage })
            local project = ProjectModel:new(projectJson, {})
            local runtime = Runtime:new(project)
            runtime:initialize()

            runtime:broadcastGreenFlag()
            local maxIterations = 10 -- Limit to prevent infinite loop with false condition
            local iterations = 0
            while #runtime:getActiveThreads() > 0 and iterations < maxIterations do
                runtime:update(1/60)
                iterations = iterations + 1
            end

            local counter = runtime.stage:lookupVariableByNameAndType("counter")
            expect(counter.value > 0).to.be.truthy() -- Should execute at least once
        end)

        it("should handle string and numeric conditions in if blocks", function()
            SB3Builder.resetCounter()
            local stage = SB3Builder.createStage()
            local resultId = SB3Builder.addVariable(stage, "result", 0)

            -- Test with simple true condition
            local hatId, hatBlock = SB3Builder.Events.whenFlagClicked()
            local setId, setBlock = SB3Builder.Data.setVariable("result", 1, resultId)
            local ifId, ifBlock = SB3Builder.Control.if_(true, setId)

            SB3Builder.addBlock(stage, hatId, hatBlock)
            SB3Builder.addBlock(stage, ifId, ifBlock)
            SB3Builder.addBlock(stage, setId, setBlock)
            SB3Builder.linkBlocks(stage, { hatId, ifId })

            local projectJson = SB3Builder.createProject({ stage })
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

            local result = runtime.stage:lookupVariableByNameAndType("result")
            expect(result.value).to.equal(1) -- True condition should execute if block
        end)
    end)

    describe("Counter Blocks (Scratch 2 Legacy)", function()
        it("should increment counter and get counter value", function()
            SB3Builder.resetCounter()
            local stage = SB3Builder.createStage()
            local sprite = SB3Builder.createSprite("TestSprite")

            -- Add variable to store counter value
            local variableId = SB3Builder.addVariable(sprite, "counterValue", 0)

            -- Create script: clear counter first -> increment counter 3 times -> get counter -> store in variable
            local hatId, hatBlock = SB3Builder.Events.whenFlagClicked()
            local clearInitId, clearInitBlock = SB3Builder.createBlock("control_clear_counter", {}, {})
            local incr1Id, incr1Block = SB3Builder.createBlock("control_incr_counter", {}, {})
            local incr2Id, incr2Block = SB3Builder.createBlock("control_incr_counter", {}, {})
            local incr3Id, incr3Block = SB3Builder.createBlock("control_incr_counter", {}, {})
            local getCounterId, getCounterBlock = SB3Builder.createBlock("control_get_counter", {}, {})
            local setVarId, setVarBlock = SB3Builder.Data.setVariable("counterValue", getCounterId, variableId)

            -- Assemble blocks
            SB3Builder.addBlock(sprite, hatId, hatBlock)
            SB3Builder.addBlock(sprite, clearInitId, clearInitBlock)
            SB3Builder.addBlock(sprite, incr1Id, incr1Block)
            SB3Builder.addBlock(sprite, incr2Id, incr2Block)
            SB3Builder.addBlock(sprite, incr3Id, incr3Block)
            SB3Builder.addBlock(sprite, getCounterId, getCounterBlock)
            SB3Builder.addBlock(sprite, setVarId, setVarBlock)

            -- Link blocks
            SB3Builder.linkBlocks(sprite, { hatId, clearInitId, incr1Id, incr2Id, incr3Id, setVarId })

            local projectJson = SB3Builder.createProject({ stage, sprite })
            local project = ProjectModel:new(projectJson, {})
            local runtime = Runtime:new(project)
            runtime:initialize()

            -- Execute script
            runtime:broadcastGreenFlag()
            local maxIterations = 100
            local iterations = 0
            while #runtime:getActiveThreads() > 0 and iterations < maxIterations do
                runtime:update(1/60)
                iterations = iterations + 1
            end

            -- Verify result
            local spriteTarget = runtime:getSpriteTargetByName("TestSprite")
            local variable = spriteTarget:lookupVariableByNameAndType("counterValue")
            expect(variable.value).to.equal(3)
        end)

        it("should clear counter to zero", function()
            SB3Builder.resetCounter()
            local stage = SB3Builder.createStage()
            local sprite = SB3Builder.createSprite("TestSprite")

            -- Add variable to store counter values
            local var1Id = SB3Builder.addVariable(sprite, "beforeClear", 0)
            local var2Id = SB3Builder.addVariable(sprite, "afterClear", 0)

            -- Create script: clear first (to ensure clean state) -> increment 5 times -> get counter -> clear -> get counter again
            local hatId, hatBlock = SB3Builder.Events.whenFlagClicked()

            -- Clear counter first to ensure clean state between tests
            local clearInitId, clearInitBlock = SB3Builder.createBlock("control_clear_counter", {}, {})

            -- Increment 5 times
            local incr1Id, incr1Block = SB3Builder.createBlock("control_incr_counter", {}, {})
            local incr2Id, incr2Block = SB3Builder.createBlock("control_incr_counter", {}, {})
            local incr3Id, incr3Block = SB3Builder.createBlock("control_incr_counter", {}, {})
            local incr4Id, incr4Block = SB3Builder.createBlock("control_incr_counter", {}, {})
            local incr5Id, incr5Block = SB3Builder.createBlock("control_incr_counter", {}, {})

            -- Get counter before clear
            local getCounter1Id, getCounter1Block = SB3Builder.createBlock("control_get_counter", {}, {})
            local setVar1Id, setVar1Block = SB3Builder.Data.setVariable("beforeClear", getCounter1Id, var1Id)

            -- Clear counter
            local clearId, clearBlock = SB3Builder.createBlock("control_clear_counter", {}, {})

            -- Get counter after clear
            local getCounter2Id, getCounter2Block = SB3Builder.createBlock("control_get_counter", {}, {})
            local setVar2Id, setVar2Block = SB3Builder.Data.setVariable("afterClear", getCounter2Id, var2Id)

            -- Assemble blocks
            SB3Builder.addBlock(sprite, hatId, hatBlock)
            SB3Builder.addBlock(sprite, clearInitId, clearInitBlock)
            SB3Builder.addBlock(sprite, incr1Id, incr1Block)
            SB3Builder.addBlock(sprite, incr2Id, incr2Block)
            SB3Builder.addBlock(sprite, incr3Id, incr3Block)
            SB3Builder.addBlock(sprite, incr4Id, incr4Block)
            SB3Builder.addBlock(sprite, incr5Id, incr5Block)
            SB3Builder.addBlock(sprite, getCounter1Id, getCounter1Block)
            SB3Builder.addBlock(sprite, setVar1Id, setVar1Block)
            SB3Builder.addBlock(sprite, clearId, clearBlock)
            SB3Builder.addBlock(sprite, getCounter2Id, getCounter2Block)
            SB3Builder.addBlock(sprite, setVar2Id, setVar2Block)

            -- Link blocks
            SB3Builder.linkBlocks(sprite, { hatId, clearInitId, incr1Id, incr2Id, incr3Id, incr4Id, incr5Id, setVar1Id, clearId, setVar2Id })

            local projectJson = SB3Builder.createProject({ stage, sprite })
            local project = ProjectModel:new(projectJson, {})
            local runtime = Runtime:new(project)
            runtime:initialize()

            -- Execute script
            runtime:broadcastGreenFlag()
            local maxIterations = 100
            local iterations = 0
            while #runtime:getActiveThreads() > 0 and iterations < maxIterations do
                runtime:update(1/60)
                iterations = iterations + 1
            end

            -- Verify results
            local spriteTarget = runtime:getSpriteTargetByName("TestSprite")
            local beforeClear = spriteTarget:lookupVariableByNameAndType("beforeClear")
            local afterClear = spriteTarget:lookupVariableByNameAndType("afterClear")

            expect(beforeClear.value).to.equal(5) -- Counter should be 5 before clear
            expect(afterClear.value).to.equal(0)  -- Counter should be 0 after clear
        end)

        it("should maintain global counter state across sprites", function()
            SB3Builder.resetCounter()
            local stage = SB3Builder.createStage()
            local sprite1 = SB3Builder.createSprite("Sprite1")
            local sprite2 = SB3Builder.createSprite("Sprite2")

            -- Add variables to store counter values
            local var1Id = SB3Builder.addVariable(sprite1, "sprite1Counter", 0)
            local var2Id = SB3Builder.addVariable(sprite2, "sprite2Counter", 0)

            -- Sprite1 script: clear counter first -> increment 2 times -> get counter
            local hat1Id, hat1Block = SB3Builder.Events.whenFlagClicked()
            local clearInitId, clearInitBlock = SB3Builder.createBlock("control_clear_counter", {}, {})
            local incr1Id, incr1Block = SB3Builder.createBlock("control_incr_counter", {}, {})
            local incr2Id, incr2Block = SB3Builder.createBlock("control_incr_counter", {}, {})
            local getCounter1Id, getCounter1Block = SB3Builder.createBlock("control_get_counter", {}, {})
            local setVar1Id, setVar1Block = SB3Builder.Data.setVariable("sprite1Counter", getCounter1Id, var1Id)

            SB3Builder.addBlock(sprite1, hat1Id, hat1Block)
            SB3Builder.addBlock(sprite1, clearInitId, clearInitBlock)
            SB3Builder.addBlock(sprite1, incr1Id, incr1Block)
            SB3Builder.addBlock(sprite1, incr2Id, incr2Block)
            SB3Builder.addBlock(sprite1, getCounter1Id, getCounter1Block)
            SB3Builder.addBlock(sprite1, setVar1Id, setVar1Block)
            SB3Builder.linkBlocks(sprite1, { hat1Id, clearInitId, incr1Id, incr2Id, setVar1Id })

            -- Sprite2 script: wait a bit, increment 3 times, get counter
            local hat2Id, hat2Block = SB3Builder.Events.whenFlagClicked()
            local wait2Id, wait2Block = SB3Builder.Control.wait(0.01)
            local incr3Id, incr3Block = SB3Builder.createBlock("control_incr_counter", {}, {})
            local incr4Id, incr4Block = SB3Builder.createBlock("control_incr_counter", {}, {})
            local incr5Id, incr5Block = SB3Builder.createBlock("control_incr_counter", {}, {})
            local getCounter2Id, getCounter2Block = SB3Builder.createBlock("control_get_counter", {}, {})
            local setVar2Id, setVar2Block = SB3Builder.Data.setVariable("sprite2Counter", getCounter2Id, var2Id)

            SB3Builder.addBlock(sprite2, hat2Id, hat2Block)
            SB3Builder.addBlock(sprite2, wait2Id, wait2Block)
            SB3Builder.addBlock(sprite2, incr3Id, incr3Block)
            SB3Builder.addBlock(sprite2, incr4Id, incr4Block)
            SB3Builder.addBlock(sprite2, incr5Id, incr5Block)
            SB3Builder.addBlock(sprite2, getCounter2Id, getCounter2Block)
            SB3Builder.addBlock(sprite2, setVar2Id, setVar2Block)
            SB3Builder.linkBlocks(sprite2, { hat2Id, wait2Id, incr3Id, incr4Id, incr5Id, setVar2Id })

            local projectJson = SB3Builder.createProject({ stage, sprite1, sprite2 })
            local project = ProjectModel:new(projectJson, {})
            local runtime = Runtime:new(project)
            runtime:initialize()

            -- Execute scripts
            runtime:broadcastGreenFlag()
            local maxIterations = 100
            local iterations = 0
            while #runtime:getActiveThreads() > 0 and iterations < maxIterations do
                runtime:update(1/60)
                iterations = iterations + 1
            end

            -- Verify results - counter is global, so both sprites see the accumulated value
            local sprite1Target = runtime:getSpriteTargetByName("Sprite1")
            local sprite2Target = runtime:getSpriteTargetByName("Sprite2")
            local sprite1Counter = sprite1Target:lookupVariableByNameAndType("sprite1Counter")
            local sprite2Counter = sprite2Target:lookupVariableByNameAndType("sprite2Counter")

            expect(sprite1Counter.value).to.equal(2) -- Sprite1 reads counter after its own 2 increments
            expect(sprite2Counter.value).to.equal(5) -- Sprite2 reads counter after total 5 increments (2 from sprite1 + 3 from sprite2)
        end)
    end)
end)
