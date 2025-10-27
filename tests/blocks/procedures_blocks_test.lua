-- Procedures Blocks Tests
-- Tests for procedures (custom blocks) implementation including recursive calls

-- Import testing framework
local lust = require("tests.lust")
local describe, it, expect = lust.describe, lust.it, lust.expect

-- Import project components
local SB3Builder = require("tests.sb3_builder")
local ProjectModel = require("parser.project_model")
local Runtime = require("vm.runtime")

describe("Procedures Blocks", function()
    describe("Basic Procedures", function()
        it("should execute a simple procedure call", function()
            SB3Builder.resetCounter()

            local stage = SB3Builder.createStage()
            local sprite = SB3Builder.createSprite("TestSprite")

            local resultId = SB3Builder.addVariable(sprite, "result", 0)

            -- Create procedure definition: "add ten %n"
            local procDefId, procDefBlock, protoId, prototypeBlock = SB3Builder.Procedures.definition(
                "add ten %n",
                { "x" },
                { "arg_x" },
                { 0 },
                false,
                100,
                100
            )

            -- Inside procedure: set result to (x + 10)
            local argXId, argXBlock = SB3Builder.Procedures.argumentReporter("x")
            local addId, addBlock = SB3Builder.Operators.add(SB3Builder.blockInput(argXId), 10)
            local setResultId, setResultBlock = SB3Builder.Data.setVariable("result", SB3Builder.blockInput(addId),
                resultId)

            -- Main script: when flag clicked -> call "add ten" with 5
            local hatId, hatBlock = SB3Builder.Events.whenFlagClicked()
            local Core = require("tests.sb3_builder.core")
            local callId, callBlock = SB3Builder.Procedures.call(
                "add ten %n",
                { "x" },
                { "arg_x" },
                { 0 },
                { 5 },
                false
            )

            -- Add all blocks
            SB3Builder.addBlock(sprite, procDefId, procDefBlock)
            SB3Builder.addBlock(sprite, protoId, prototypeBlock)
            SB3Builder.addBlock(sprite, argXId, argXBlock)
            SB3Builder.addBlock(sprite, addId, addBlock)
            SB3Builder.addBlock(sprite, setResultId, setResultBlock)
            SB3Builder.addBlock(sprite, hatId, hatBlock)
            SB3Builder.addBlock(sprite, callId, callBlock)

            -- Link procedure definition
            procDefBlock.next = setResultId

            -- Link main script
            SB3Builder.linkBlocks(sprite, { hatId, callId })

            local projectJson = SB3Builder.createProject({ stage, sprite })
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

            local spriteTarget = runtime:getSpriteTargetByName("TestSprite")
            local result = spriteTarget:lookupVariableByNameAndType("result")
            expect(result.value).to.equal(15) -- 5 + 10 = 15
        end)
    end)

    describe("Algorithm Preparatory Tests", function()
        it("should implement recursive procedure calls for quicksort structure", function()
            SB3Builder.resetCounter()
            local stage = SB3Builder.createStage()

            local callCountId = SB3Builder.addVariable(stage, "callCount", 0)
            local processedId = SB3Builder.addVariable(stage, "processed", 0)

            local hatId, hatBlock = SB3Builder.Events.whenFlagClicked()
            local Core = require("tests.sb3_builder.core")
            local mainCallId, mainCallBlock = SB3Builder.Procedures.call(
                "recursiveTest %n %n",
                { "low", "high" },
                { "arg_low", "arg_high" },
                { 1, 3 },
                { 1, 3 },
                false
            )

            local procDefId, procDefBlock, protoId, prototypeBlock = SB3Builder.Procedures.definition(
                "recursiveTest %n %n",
                { "low", "high" },
                { "arg_low", "arg_high" },
                { 1, 3 },
                false,
                200,
                100
            )

            local incCallCountId, incCallCountBlock = SB3Builder.Data.changeVariable("callCount", 1, callCountId)

            local argLowId, argLowBlock = SB3Builder.Procedures.argumentReporter("low")
            local argHighId, argHighBlock = SB3Builder.Procedures.argumentReporter("high")

            local conditionId, conditionBlock = SB3Builder.Operators.lessThan(SB3Builder.blockInput(argLowId),
                SB3Builder.blockInput(argHighId))

            local highMinus1Id, highMinus1Block = SB3Builder.Operators.subtract(SB3Builder.blockInput(argHighId), 1)
            local recursiveCallId, recursiveCallBlock = SB3Builder.Procedures.call(
                "recursiveTest %n %n",
                { "low", "high" },
                { "arg_low", "arg_high" },
                { 1, 3 },
                { SB3Builder.blockInput(argLowId), SB3Builder.blockInput(highMinus1Id) },
                false
            )

            local incProcessedId, incProcessedBlock = SB3Builder.Data.changeVariable("processed", 1, processedId)

            SB3Builder.addBlock(stage, hatId, hatBlock)
            SB3Builder.addBlock(stage, mainCallId, mainCallBlock)
            SB3Builder.addBlock(stage, procDefId, procDefBlock)
            SB3Builder.addBlock(stage, protoId, prototypeBlock)
            SB3Builder.addBlock(stage, incCallCountId, incCallCountBlock)
            SB3Builder.addBlock(stage, argLowId, argLowBlock)
            SB3Builder.addBlock(stage, argHighId, argHighBlock)
            SB3Builder.addBlock(stage, conditionId, conditionBlock)
            SB3Builder.addBlock(stage, highMinus1Id, highMinus1Block)
            SB3Builder.addBlock(stage, recursiveCallId, recursiveCallBlock)
            SB3Builder.addBlock(stage, incProcessedId, incProcessedBlock)

            SB3Builder.linkBlocks(stage, { hatId, mainCallId })

            local ifId, ifBlock = SB3Builder.Control.if_(conditionId, recursiveCallId)
            SB3Builder.addBlock(stage, ifId, ifBlock)

            SB3Builder.linkBlocks(stage, { incCallCountId, ifId })
            SB3Builder.linkBlocks(stage, { recursiveCallId, incProcessedId })

            procDefBlock.next = incCallCountId
            ifBlock.inputs.SUBSTACK = Core.substackInput(recursiveCallId)

            local projectJson = SB3Builder.createProject({ stage })
            local project = ProjectModel:new(projectJson, {})
            local runtime = Runtime:new(project)
            runtime:initialize()

            runtime:broadcastGreenFlag()
            local maxIterations = 1000
            local iterations = 0
            while #runtime:getActiveThreads() > 0 and iterations < maxIterations do
                runtime:update(1 / 60)
                iterations = iterations + 1
            end

            local callCount = runtime.stage:lookupVariableByNameAndType("callCount")
            expect(callCount).to.exist()
            expect(callCount.value).to.be.a("number")
            expect(callCount.value).to.equal(3)

            local processed = runtime.stage:lookupVariableByNameAndType("processed")
            expect(processed).to.exist()
            expect(processed.value).to.be.a("number")
            expect(processed.value).to.equal(2)
        end)

        it("should pass updated arguments for binary-style recursive calls", function()
            SB3Builder.resetCounter()
            local stage = SB3Builder.createStage()

            local startLogId = SB3Builder.addList(stage, "StartLog", {})

            local hatId, hatBlock = SB3Builder.Events.whenFlagClicked()
            local deleteLogId, deleteLogBlock = SB3Builder.Data.deleteAllOfList("StartLog", startLogId)
            local initialCallId, initialCallBlock = SB3Builder.Procedures.call(
                "binary split %n to %n",
                { "start", "end" },
                { "arg_start", "arg_end" },
                { 1, 1 },
                { 1, 3 },
                false
            )

            local procDefId, procDefBlock, protoId, prototypeBlock = SB3Builder.Procedures.definition(
                "binary split %n to %n",
                { "start", "end" },
                { "arg_start", "arg_end" },
                { 1, 1 },
                false,
                180,
                220
            )

            local Core = require("tests.sb3_builder.core")

            local startLogReporterId, startLogReporterBlock = SB3Builder.Procedures.argumentReporter("start")
            local addLogId, addLogBlock = SB3Builder.Data.addToList(SB3Builder.blockInput(startLogReporterId),
                "StartLog", startLogId)

            local baseStartReporterId, baseStartReporterBlock = SB3Builder.Procedures.argumentReporter("start")
            local baseEndReporterId, baseEndReporterBlock = SB3Builder.Procedures.argumentReporter("end")
            local baseConditionId, baseConditionBlock = SB3Builder.Operators.greaterThan(
                SB3Builder.blockInput(baseStartReporterId),
                SB3Builder.blockInput(baseEndReporterId)
            )
            local stopId, stopBlock = SB3Builder.Control.stopThisScript()
            local baseIfId, baseIfBlock = SB3Builder.Control.if_(baseConditionId, nil)
            baseIfBlock.inputs.SUBSTACK = Core.substackInput(stopId)

            local leftStartReporterId, leftStartReporterBlock = SB3Builder.Procedures.argumentReporter("start")
            local leftEndReporterId, leftEndReporterBlock = SB3Builder.Procedures.argumentReporter("end")
            local endMinusOneId, endMinusOneBlock = SB3Builder.Operators.subtract(
                SB3Builder.blockInput(leftEndReporterId),
                1
            )
            local leftCallId, leftCallBlock = SB3Builder.Procedures.call(
                "binary split %n to %n",
                { "start", "end" },
                { "arg_start", "arg_end" },
                { 1, 1 },
                { SB3Builder.blockInput(leftStartReporterId), SB3Builder.blockInput(endMinusOneId) },
                false
            )

            local rightStartReporterId, rightStartReporterBlock = SB3Builder.Procedures.argumentReporter("start")
            local startPlusOneId, startPlusOneBlock = SB3Builder.Operators.add(
                SB3Builder.blockInput(rightStartReporterId),
                1
            )
            local rightEndReporterId, rightEndReporterBlock = SB3Builder.Procedures.argumentReporter("end")
            local rightCallId, rightCallBlock = SB3Builder.Procedures.call(
                "binary split %n to %n",
                { "start", "end" },
                { "arg_start", "arg_end" },
                { 1, 1 },
                { SB3Builder.blockInput(startPlusOneId), SB3Builder.blockInput(rightEndReporterId) },
                false
            )

            SB3Builder.addBlock(stage, hatId, hatBlock)
            SB3Builder.addBlock(stage, deleteLogId, deleteLogBlock)
            SB3Builder.addBlock(stage, initialCallId, initialCallBlock)
            SB3Builder.addBlock(stage, procDefId, procDefBlock)
            SB3Builder.addBlock(stage, protoId, prototypeBlock)
            SB3Builder.addBlock(stage, startLogReporterId, startLogReporterBlock)
            SB3Builder.addBlock(stage, addLogId, addLogBlock)
            SB3Builder.addBlock(stage, baseStartReporterId, baseStartReporterBlock)
            SB3Builder.addBlock(stage, baseEndReporterId, baseEndReporterBlock)
            SB3Builder.addBlock(stage, baseConditionId, baseConditionBlock)
            SB3Builder.addBlock(stage, stopId, stopBlock)
            SB3Builder.addBlock(stage, baseIfId, baseIfBlock)
            SB3Builder.addBlock(stage, leftStartReporterId, leftStartReporterBlock)
            SB3Builder.addBlock(stage, leftEndReporterId, leftEndReporterBlock)
            SB3Builder.addBlock(stage, endMinusOneId, endMinusOneBlock)
            SB3Builder.addBlock(stage, leftCallId, leftCallBlock)
            SB3Builder.addBlock(stage, rightStartReporterId, rightStartReporterBlock)
            SB3Builder.addBlock(stage, startPlusOneId, startPlusOneBlock)
            SB3Builder.addBlock(stage, rightEndReporterId, rightEndReporterBlock)
            SB3Builder.addBlock(stage, rightCallId, rightCallBlock)

            SB3Builder.linkBlocks(stage, { hatId, deleteLogId, initialCallId })
            SB3Builder.linkBlocks(stage, { procDefId, addLogId, baseIfId, leftCallId, rightCallId })

            local projectJson = SB3Builder.createProject({ stage })
            local project = ProjectModel:new(projectJson, {})
            local runtime = Runtime:new(project)
            runtime:initialize()

            runtime:broadcastGreenFlag()
            local maxIterations = 2000
            local iterations = 0
            while #runtime:getActiveThreads() > 0 and iterations < maxIterations do
                runtime:update(1 / 60)
                iterations = iterations + 1
            end

            expect(iterations < maxIterations).to.be.truthy()

            local startLogList = runtime.stage:lookupVariableByNameAndType("StartLog", "list")
            expect(startLogList).to.exist()
            local seenValues = {}
            for _, value in ipairs(startLogList.value) do
                seenValues[value] = true
            end
            expect(seenValues[1]).to.be.truthy()
            expect(seenValues[2]).to.be.truthy()
            expect(seenValues[3]).to.be.truthy()
        end)

        it("should test repeatUntil block behavior with not condition", function()
            SB3Builder.resetCounter()
            local stage = SB3Builder.createStage()

            local counterId = SB3Builder.addVariable(stage, "counter", 0)

            local hatId, hatBlock = SB3Builder.Events.whenFlagClicked()
            local Core = require("tests.sb3_builder.core")

            -- counter = 0
            local setCounterId, setCounterBlock = SB3Builder.Data.setVariable("counter", 0, counterId)

            local counterVarId, counterVarBlock = SB3Builder.Data.variable("counter", counterId)
            local conditionId, conditionBlock = SB3Builder.Operators.lessThan(SB3Builder.blockInput(counterVarId), 3)
            local notCondId, notCondBlock = SB3Builder.Operators.not_(SB3Builder.blockInput(conditionId))
            local loopId, loopBlock = SB3Builder.Control.repeatUntil(notCondId, nil)

            local incCounterId, incCounterBlock = SB3Builder.Data.changeVariable("counter", 1, counterId)

            SB3Builder.addBlock(stage, hatId, hatBlock)
            SB3Builder.addBlock(stage, setCounterId, setCounterBlock)
            SB3Builder.addBlock(stage, counterVarId, counterVarBlock)
            SB3Builder.addBlock(stage, conditionId, conditionBlock)
            SB3Builder.addBlock(stage, notCondId, notCondBlock)
            SB3Builder.addBlock(stage, loopId, loopBlock)
            SB3Builder.addBlock(stage, incCounterId, incCounterBlock)

            SB3Builder.linkBlocks(stage, { hatId, setCounterId, loopId })

            loopBlock.inputs.SUBSTACK = Core.substackInput(incCounterId)

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

                if iterations <= 20 then
                    local counter_var = runtime.stage:lookupVariableByNameAndType("counter")
                end
            end

            local finalCounter = runtime.stage:lookupVariableByNameAndType("counter")
            expect(finalCounter).to.exist()
            expect(finalCounter.value).to.equal(3)
        end)

        it("should test variable reference bug in procedure context", function()
            SB3Builder.resetCounter()
            local stage = SB3Builder.createStage()

            local aId = SB3Builder.addVariable(stage, "a", 1)
            local bId = SB3Builder.addVariable(stage, "b", 0)

            local hatId, hatBlock = SB3Builder.Events.whenFlagClicked()
            local Core = require("tests.sb3_builder.core")
            local callId, callBlock = SB3Builder.Procedures.call(
                "test var ref",
                {},
                {},
                {},
                {},
                false
            )

            local procDefId, procDefBlock, protoId, prototypeBlock = SB3Builder.Procedures.definition(
                "test var ref",
                {},
                {},
                {},
                false,
                100,
                100
            )

            -- a = 1
            local setA1Id, setA1Block = SB3Builder.Data.setVariable("a", 1, aId)

            local aVarEarlyId, aVarEarlyBlock = SB3Builder.Data.variable("a", aId)

            local repeatId, repeatBlock = SB3Builder.Control.repeat_(3, nil)
            local incAId, incABlock = SB3Builder.Data.changeVariable("a", 1, aId)

            local setBId, setBBlock = SB3Builder.Data.setVariable("b", SB3Builder.blockInput(aVarEarlyId), bId)

            local aVarLateId, aVarLateBlock = SB3Builder.Data.variable("a", aId)
            local cId = SB3Builder.addVariable(stage, "c", 0)
            local setCId, setCBlock = SB3Builder.Data.setVariable("c", SB3Builder.blockInput(aVarLateId), cId)

            SB3Builder.addBlock(stage, hatId, hatBlock)
            SB3Builder.addBlock(stage, callId, callBlock)
            SB3Builder.addBlock(stage, procDefId, procDefBlock)
            SB3Builder.addBlock(stage, protoId, prototypeBlock)
            SB3Builder.addBlock(stage, setA1Id, setA1Block)
            SB3Builder.addBlock(stage, aVarEarlyId, aVarEarlyBlock)
            SB3Builder.addBlock(stage, repeatId, repeatBlock)
            SB3Builder.addBlock(stage, incAId, incABlock)
            SB3Builder.addBlock(stage, setBId, setBBlock)
            SB3Builder.addBlock(stage, aVarLateId, aVarLateBlock)
            SB3Builder.addBlock(stage, setCId, setCBlock)

            SB3Builder.linkBlocks(stage, { hatId, callId })
            SB3Builder.linkBlocks(stage, { setA1Id, repeatId, setBId, setCId })

            procDefBlock.next = setA1Id
            repeatBlock.inputs.SUBSTACK = Core.substackInput(incAId)

            local projectJson = SB3Builder.createProject({ stage })
            local project = ProjectModel:new(projectJson, {})
            local runtime = Runtime:new(project)
            runtime:initialize()

            runtime:broadcastGreenFlag()
            local maxIterations = 20
            local iterations = 0
            while #runtime:getActiveThreads() > 0 and iterations < maxIterations do
                runtime:update(1 / 60)
                iterations = iterations + 1
            end

            local finalA = runtime.stage:lookupVariableByNameAndType("a")
            local finalB = runtime.stage:lookupVariableByNameAndType("b")
            local finalC = runtime.stage:lookupVariableByNameAndType("c")

            expect(finalA.value).to.equal(4)

            expect(finalB.value).to.equal(4)
            expect(finalC.value).to.equal(4)
        end)

        it("should test recursive procedure variable scope", function()
            SB3Builder.resetCounter()
            local stage = SB3Builder.createStage()

            local counterId = SB3Builder.addVariable(stage, "counter", 0)
            local resultId = SB3Builder.addVariable(stage, "result", 0)

            local hatId, hatBlock = SB3Builder.Events.whenFlagClicked()
            local Core = require("tests.sb3_builder.core")
            local mainCallId, mainCallBlock = SB3Builder.Procedures.call(
                "recursive test %n",
                { "n" },
                { "arg_n" },
                { 3 },
                { 3 },
                false
            )

            local procDefId, procDefBlock, protoId, prototypeBlock = SB3Builder.Procedures.definition(
                "recursive test %n",
                { "n" },
                { "arg_n" },
                { 3 },
                false,
                200,
                100
            )

            local nArgId, nArgBlock = SB3Builder.Procedures.argumentReporter("n")

            -- counter = counter + 1
            local incCounterId, incCounterBlock = SB3Builder.Data.changeVariable("counter", 1, counterId)

            local counterVarEarlyId, counterVarEarlyBlock = SB3Builder.Data.variable("counter", counterId)

            local condId, condBlock = SB3Builder.Operators.lessThan(SB3Builder.blockInput(nArgId), 2)
            local equalCondId, equalCondBlock = SB3Builder.Operators.equals(SB3Builder.blockInput(nArgId), 1)
            local stopCondId, stopCondBlock = SB3Builder.Operators.or_(SB3Builder.blockInput(condId),
                SB3Builder.blockInput(equalCondId))

            local setResultId, setResultBlock = SB3Builder.Data.setVariable("result",
                SB3Builder.blockInput(counterVarEarlyId), resultId)

            local ifStopId, ifStopBlock = SB3Builder.Control.if_(stopCondId, setResultId)

            local nMinus1Id, nMinus1Block = SB3Builder.Operators.subtract(SB3Builder.blockInput(nArgId), 1)
            local recursiveCallId, recursiveCallBlock = SB3Builder.Procedures.call(
                "recursive test %n",
                { "n" },
                { "arg_n" },
                { 3 },
                { SB3Builder.blockInput(nMinus1Id) },
                false
            )

            local continueCondId, continueCondBlock = SB3Builder.Operators.not_(SB3Builder.blockInput(stopCondId))
            local ifContinueId, ifContinueBlock = SB3Builder.Control.if_(continueCondId, recursiveCallId)

            SB3Builder.addBlock(stage, hatId, hatBlock)
            SB3Builder.addBlock(stage, mainCallId, mainCallBlock)
            SB3Builder.addBlock(stage, procDefId, procDefBlock)
            SB3Builder.addBlock(stage, protoId, prototypeBlock)
            SB3Builder.addBlock(stage, nArgId, nArgBlock)
            SB3Builder.addBlock(stage, incCounterId, incCounterBlock)
            SB3Builder.addBlock(stage, counterVarEarlyId, counterVarEarlyBlock)
            SB3Builder.addBlock(stage, condId, condBlock)
            SB3Builder.addBlock(stage, equalCondId, equalCondBlock)
            SB3Builder.addBlock(stage, stopCondId, stopCondBlock)
            SB3Builder.addBlock(stage, setResultId, setResultBlock)
            SB3Builder.addBlock(stage, ifStopId, ifStopBlock)
            SB3Builder.addBlock(stage, nMinus1Id, nMinus1Block)
            SB3Builder.addBlock(stage, recursiveCallId, recursiveCallBlock)
            SB3Builder.addBlock(stage, continueCondId, continueCondBlock)
            SB3Builder.addBlock(stage, ifContinueId, ifContinueBlock)

            SB3Builder.linkBlocks(stage, { hatId, mainCallId })
            SB3Builder.linkBlocks(stage, { incCounterId, ifStopId, ifContinueId })
            -- recursiveCallId is now in ifContinueId's substack

            procDefBlock.next = incCounterId
            ifStopBlock.inputs.SUBSTACK = Core.substackInput(setResultId)

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

            local finalCounter = runtime.stage:lookupVariableByNameAndType("counter")
            local finalResult = runtime.stage:lookupVariableByNameAndType("result")

            expect(finalCounter.value).to.equal(3)

            expect(finalResult.value).to.equal(3)
        end)

        it("should test variable reference timing bug", function()
            SB3Builder.resetCounter()
            local stage = SB3Builder.createStage()

            local aId = SB3Builder.addVariable(stage, "a", 1)
            local bId = SB3Builder.addVariable(stage, "b", 0)

            local hatId, hatBlock = SB3Builder.Events.whenFlagClicked()

            local setA1Id, setA1Block = SB3Builder.Data.setVariable("a", 1, aId)

            local aVarEarlyId, aVarEarlyBlock = SB3Builder.Data.variable("a", aId)

            local setA5Id, setA5Block = SB3Builder.Data.setVariable("a", 5, aId)

            local setBEarlyId, setBEarlyBlock = SB3Builder.Data.setVariable("b", SB3Builder.blockInput(aVarEarlyId), bId)

            local aVarLateId, aVarLateBlock = SB3Builder.Data.variable("a", aId)

            local setA10Id, setA10Block = SB3Builder.Data.setVariable("a", 10, aId)

            local cId = SB3Builder.addVariable(stage, "c", 0)
            local setCLateId, setCLateBlock = SB3Builder.Data.setVariable("c", SB3Builder.blockInput(aVarLateId), cId)

            SB3Builder.addBlock(stage, hatId, hatBlock)
            SB3Builder.addBlock(stage, setA1Id, setA1Block)
            SB3Builder.addBlock(stage, aVarEarlyId, aVarEarlyBlock)
            SB3Builder.addBlock(stage, setA5Id, setA5Block)
            SB3Builder.addBlock(stage, setBEarlyId, setBEarlyBlock)
            SB3Builder.addBlock(stage, aVarLateId, aVarLateBlock)
            SB3Builder.addBlock(stage, setA10Id, setA10Block)
            SB3Builder.addBlock(stage, setCLateId, setCLateBlock)

            SB3Builder.linkBlocks(stage, { hatId, setA1Id, setA5Id, setBEarlyId, setA10Id, setCLateId })

            local projectJson = SB3Builder.createProject({ stage })
            local project = ProjectModel:new(projectJson, {})
            local runtime = Runtime:new(project)
            runtime:initialize()

            runtime:broadcastGreenFlag()
            local maxIterations = 10
            local iterations = 0
            while #runtime:getActiveThreads() > 0 and iterations < maxIterations do
                runtime:update(1 / 60)
                iterations = iterations + 1
            end

            local finalA = runtime.stage:lookupVariableByNameAndType("a")
            local finalB = runtime.stage:lookupVariableByNameAndType("b")
            local finalC = runtime.stage:lookupVariableByNameAndType("c")

            expect(finalA.value).to.equal(10)

            expect(finalC.value).to.equal(10)
        end)

        it("should test simple variable reference behavior", function()
            SB3Builder.resetCounter()
            local stage = SB3Builder.createStage()

            local aId = SB3Builder.addVariable(stage, "a", 1)
            local bId = SB3Builder.addVariable(stage, "b", 0)

            local hatId, hatBlock = SB3Builder.Events.whenFlagClicked()

            -- a = 5
            local setAId, setABlock = SB3Builder.Data.setVariable("a", 5, aId)

            local aVarId, aVarBlock = SB3Builder.Data.variable("a", aId)
            local setBId, setBBlock = SB3Builder.Data.setVariable("b", SB3Builder.blockInput(aVarId), bId)

            local setA2Id, setA2Block = SB3Builder.Data.setVariable("a", 10, aId)

            local aVar2Id, aVar2Block = SB3Builder.Data.variable("a", aId)
            local setB2Id, setB2Block = SB3Builder.Data.setVariable("b", SB3Builder.blockInput(aVar2Id), bId)

            SB3Builder.addBlock(stage, hatId, hatBlock)
            SB3Builder.addBlock(stage, setAId, setABlock)
            SB3Builder.addBlock(stage, aVarId, aVarBlock)
            SB3Builder.addBlock(stage, setBId, setBBlock)
            SB3Builder.addBlock(stage, setA2Id, setA2Block)
            SB3Builder.addBlock(stage, aVar2Id, aVar2Block)
            SB3Builder.addBlock(stage, setB2Id, setB2Block)

            SB3Builder.linkBlocks(stage, { hatId, setAId, setBId, setA2Id, setB2Id })

            local projectJson = SB3Builder.createProject({ stage })
            local project = ProjectModel:new(projectJson, {})
            local runtime = Runtime:new(project)
            runtime:initialize()

            runtime:broadcastGreenFlag()
            local maxIterations = 20
            local iterations = 0
            while #runtime:getActiveThreads() > 0 and iterations < maxIterations do
                runtime:update(1 / 60)
                iterations = iterations + 1
            end

            local finalA = runtime.stage:lookupVariableByNameAndType("a")
            local finalB = runtime.stage:lookupVariableByNameAndType("b")
            expect(finalA).to.exist()
            expect(finalB).to.exist()

            expect(finalA.value).to.equal(10)
        end)

        it("should implement simplified quicksort partition test", function()
            SB3Builder.resetCounter()
            local stage = SB3Builder.createStage()

            local testData = { 3, 1, 2 }
            local dataListId = SB3Builder.addList(stage, "Data", testData)

            local swap1Id = SB3Builder.addVariable(stage, "swap1", 0)
            local swap2Id = SB3Builder.addVariable(stage, "swap2", 0)

            local hatId, hatBlock = SB3Builder.Events.whenFlagClicked()
            local Core = require("tests.sb3_builder.core")

            local item1Id, item1Block = SB3Builder.Data.itemOfList(1, "Data", dataListId)
            local item2Id, item2Block = SB3Builder.Data.itemOfList(2, "Data", dataListId)
            local condId, condBlock = SB3Builder.Operators.greaterThan(SB3Builder.blockInput(item1Id),
                SB3Builder.blockInput(item2Id))

            local setSwap1Id, setSwap1Block = SB3Builder.Data.setVariable("swap1", SB3Builder.blockInput(item1Id),
                swap1Id)
            local replace1Id, replace1Block = SB3Builder.Data.replaceItemOfList(1, SB3Builder.blockInput(item2Id), "Data",
                dataListId)
            local swap1VarId, swap1VarBlock = SB3Builder.Data.variable("swap1", swap1Id)
            local replace2Id, replace2Block = SB3Builder.Data.replaceItemOfList(2, SB3Builder.blockInput(swap1VarId),
                "Data", dataListId)

            local ifSwapId, ifSwapBlock = SB3Builder.Control.if_(condId, setSwap1Id)

            SB3Builder.addBlock(stage, hatId, hatBlock)
            SB3Builder.addBlock(stage, item1Id, item1Block)
            SB3Builder.addBlock(stage, item2Id, item2Block)
            SB3Builder.addBlock(stage, condId, condBlock)
            SB3Builder.addBlock(stage, setSwap1Id, setSwap1Block)
            SB3Builder.addBlock(stage, replace1Id, replace1Block)
            SB3Builder.addBlock(stage, swap1VarId, swap1VarBlock)
            SB3Builder.addBlock(stage, replace2Id, replace2Block)
            SB3Builder.addBlock(stage, ifSwapId, ifSwapBlock)

            SB3Builder.linkBlocks(stage, { hatId, ifSwapId })
            SB3Builder.linkBlocks(stage, { setSwap1Id, replace1Id, replace2Id })

            ifSwapBlock.inputs.SUBSTACK = Core.substackInput(setSwap1Id)

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

            local finalDataList = runtime.stage:lookupVariableByNameAndType("Data", "list")
            local resultData = {}
            for i = 1, 3 do
                resultData[i] = tonumber(finalDataList.value[i])
            end

            expect(resultData[1] <= resultData[2]).to.be.truthy()
        end)

        it("should test simple partitioning logic first", function()
            SB3Builder.resetCounter()
            local stage = SB3Builder.createStage()

            local testData = { 2, 1 }
            local dataListId = SB3Builder.addList(stage, "Data", testData)

            local swapDefId, swapDefBlock, swapProtoId, swapProtoBlock = SB3Builder.Procedures.definition(
                "swap %n %n",
                { "i", "j" },
                { "arg_i", "arg_j" },
                { 1, 2 },
                false
            )

            local iArgId, iArgBlock = SB3Builder.Procedures.argumentReporter("i")
            local jArgId, jArgBlock = SB3Builder.Procedures.argumentReporter("j")

            -- temp = Data[i]
            local tempId = SB3Builder.addVariable(stage, "temp", 0)
            local dataIId, dataIBlock = SB3Builder.Data.itemOfList(SB3Builder.blockInput(iArgId), "Data", dataListId)
            local setTempId, setTempBlock = SB3Builder.Data.setVariable("temp", SB3Builder.blockInput(dataIId), tempId)

            -- Data[i] = Data[j]
            local dataJId, dataJBlock = SB3Builder.Data.itemOfList(SB3Builder.blockInput(jArgId), "Data", dataListId)
            local setDataIId, setDataIBlock = SB3Builder.Data.replaceItemOfList(SB3Builder.blockInput(iArgId),
                SB3Builder.blockInput(dataJId), "Data", dataListId)

            -- Data[j] = temp
            local tempVarId, tempVarBlock = SB3Builder.Data.variable("temp", tempId)
            local setDataJId, setDataJBlock = SB3Builder.Data.replaceItemOfList(SB3Builder.blockInput(jArgId),
                SB3Builder.blockInput(tempVarId), "Data", dataListId)

            local hatId, hatBlock = SB3Builder.Events.whenFlagClicked()
            local swapCallId, swapCallBlock = SB3Builder.Procedures.call(
                "swap %n %n",
                { "i", "j" },
                { "arg_i", "arg_j" },
                { 1, 2 },
                { 1, 2 },
                false
            )

            SB3Builder.addBlock(stage, hatId, hatBlock)
            SB3Builder.addBlock(stage, swapCallId, swapCallBlock)
            SB3Builder.addBlock(stage, swapDefId, swapDefBlock)
            SB3Builder.addBlock(stage, swapProtoId, swapProtoBlock)
            SB3Builder.addBlock(stage, iArgId, iArgBlock)
            SB3Builder.addBlock(stage, jArgId, jArgBlock)
            SB3Builder.addBlock(stage, dataIId, dataIBlock)
            SB3Builder.addBlock(stage, setTempId, setTempBlock)
            SB3Builder.addBlock(stage, dataJId, dataJBlock)
            SB3Builder.addBlock(stage, setDataIId, setDataIBlock)
            SB3Builder.addBlock(stage, tempVarId, tempVarBlock)
            SB3Builder.addBlock(stage, setDataJId, setDataJBlock)

            SB3Builder.linkBlocks(stage, { hatId, swapCallId })
            SB3Builder.linkBlocks(stage, { swapDefId, setTempId, setDataIId, setDataJId })

            local projectJson = SB3Builder.createProject({ stage })
            local project = ProjectModel:new(projectJson, {})
            local runtime = Runtime:new(project)
            runtime:initialize()

            local dataList = runtime.stage:lookupVariableByNameAndType("Data", "list")

            runtime:broadcastGreenFlag()
            local maxIterations = 10
            local iterations = 0
            while #runtime:getActiveThreads() > 0 and iterations < maxIterations do
                runtime:update(1 / 60)
                iterations = iterations + 1
            end

            expect(dataList.value[1]).to.equal(1)
            expect(dataList.value[2]).to.equal(2)
        end)

        it("should implement simple recursive countdown test", function()
            SB3Builder.resetCounter()
            local stage = SB3Builder.createStage()

            local counterId = SB3Builder.addVariable(stage, "counter", 0)

            local hatId, hatBlock = SB3Builder.Events.whenFlagClicked()
            local mainCallId, mainCallBlock = SB3Builder.Procedures.call(
                "countdown %n",
                { "n" },
                { "arg_n" },
                { 3 },
                { 3 },
                false
            )

            local defId, defBlock, protoId, protoBlock = SB3Builder.Procedures.definition(
                "countdown %n",
                { "n" },
                { "arg_n" },
                { 3 },
                false
            )

            local nArgId, nArgBlock = SB3Builder.Procedures.argumentReporter("n")

            local terminateCondId, terminateCondBlock = SB3Builder.Operators.lessThan(SB3Builder.blockInput(nArgId), 1)
            local stopId, stopBlock = SB3Builder.Control.stopThisScript()
            local ifTerminateId, ifTerminateBlock = SB3Builder.Control.if_(terminateCondId, stopId)

            local incCounterId, incCounterBlock = SB3Builder.Data.changeVariable("counter", 1, counterId)

            local nMinus1Id, nMinus1Block = SB3Builder.Operators.subtract(SB3Builder.blockInput(nArgId), 1)
            local recCallId, recCallBlock = SB3Builder.Procedures.call(
                "countdown %n",
                { "n" },
                { "arg_n" },
                { 3 },
                { SB3Builder.blockInput(nMinus1Id) },
                false
            )

            SB3Builder.addBlock(stage, hatId, hatBlock)
            SB3Builder.addBlock(stage, mainCallId, mainCallBlock)
            SB3Builder.addBlock(stage, defId, defBlock)
            SB3Builder.addBlock(stage, protoId, protoBlock)
            SB3Builder.addBlock(stage, nArgId, nArgBlock)
            SB3Builder.addBlock(stage, terminateCondId, terminateCondBlock)
            SB3Builder.addBlock(stage, stopId, stopBlock)
            SB3Builder.addBlock(stage, ifTerminateId, ifTerminateBlock)
            SB3Builder.addBlock(stage, incCounterId, incCounterBlock)
            SB3Builder.addBlock(stage, nMinus1Id, nMinus1Block)
            SB3Builder.addBlock(stage, recCallId, recCallBlock)

            SB3Builder.linkBlocks(stage, { hatId, mainCallId })
            SB3Builder.linkBlocks(stage, { defId, ifTerminateId, incCounterId, recCallId })

            local Core = require("tests.sb3_builder.core")
            ifTerminateBlock.inputs.SUBSTACK = Core.substackInput(stopId)

            local projectJson = SB3Builder.createProject({ stage })
            local project = ProjectModel:new(projectJson, {})
            local runtime = Runtime:new(project)
            runtime:initialize()

            runtime:broadcastGreenFlag()
            local maxIterations = 20
            local iterations = 0
            while #runtime:getActiveThreads() > 0 and iterations < maxIterations do
                runtime:update(1 / 60)
                iterations = iterations + 1
            end

            local counter = runtime.stage:lookupVariableByNameAndType("counter")

            expect(counter.value).to.equal(3)
            expect(iterations < maxIterations).to.be.truthy()
        end)

        it("should test recursive procedure with stop this script and main script continuation", function()
            SB3Builder.resetCounter()
            local stage = SB3Builder.createStage()

            local counterId = SB3Builder.addVariable(stage, "counter", 0)
            local resultId = SB3Builder.addVariable(stage, "result", 0)

            local procDefId, procDefBlock, protoId, prototypeBlock = SB3Builder.Procedures.definition(
                "simple recursive %n",
                { "n" },
                { "arg_n" },
                { 3 },
                false,
                100,
                100
            )

            local incCounterId, incCounterBlock = SB3Builder.Data.changeVariable("counter", 1, counterId)

            local nArgId, nArgBlock = SB3Builder.Procedures.argumentReporter("n")

            local stopCondId, stopCondBlock = SB3Builder.Operators.lessThan(SB3Builder.blockInput(nArgId), 2)
            local stopId, stopBlock = SB3Builder.Control.stopThisScript()
            local ifStopId, ifStopBlock = SB3Builder.Control.if_(stopCondId, stopId)

            local nMinus1Id, nMinus1Block = SB3Builder.Operators.subtract(SB3Builder.blockInput(nArgId), 1)
            local recursiveCallId, recursiveCallBlock = SB3Builder.Procedures.call(
                "simple recursive %n",
                { "n" },
                { "arg_n" },
                { 3 },
                { SB3Builder.blockInput(nMinus1Id) },
                false
            )

            local hatId, hatBlock = SB3Builder.Events.whenFlagClicked()
            local mainCallId, mainCallBlock = SB3Builder.Procedures.call(
                "simple recursive %n",
                { "n" },
                { "arg_n" },
                { 3 },
                { 3 },
                false
            )

            local setResultId, setResultBlock = SB3Builder.Data.setVariable("result", 99, resultId)

            SB3Builder.addBlock(stage, hatId, hatBlock)
            SB3Builder.addBlock(stage, mainCallId, mainCallBlock)
            SB3Builder.addBlock(stage, setResultId, setResultBlock)
            SB3Builder.addBlock(stage, procDefId, procDefBlock)
            SB3Builder.addBlock(stage, protoId, prototypeBlock)
            SB3Builder.addBlock(stage, incCounterId, incCounterBlock)
            SB3Builder.addBlock(stage, nArgId, nArgBlock)
            SB3Builder.addBlock(stage, stopCondId, stopCondBlock)
            SB3Builder.addBlock(stage, stopId, stopBlock)
            SB3Builder.addBlock(stage, ifStopId, ifStopBlock)
            SB3Builder.addBlock(stage, nMinus1Id, nMinus1Block)
            SB3Builder.addBlock(stage, recursiveCallId, recursiveCallBlock)

            SB3Builder.linkBlocks(stage, { hatId, mainCallId, setResultId })

            SB3Builder.linkBlocks(stage, { incCounterId, ifStopId, recursiveCallId })

            procDefBlock.next = incCounterId
            local Core = require("tests.sb3_builder.core")
            ifStopBlock.inputs.SUBSTACK = Core.substackInput(stopId)

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

            local finalCounter = runtime.stage:lookupVariableByNameAndType("counter")
            local finalResult = runtime.stage:lookupVariableByNameAndType("result")

            expect(finalCounter.value).to.equal(3)

            expect(finalResult.value).to.equal(99)

            expect(iterations < maxIterations).to.be.truthy()
        end)

        it("should test 'stop this script' in recursive procedure calls", function()
            SB3Builder.resetCounter()
            local stage = SB3Builder.createStage()

            local counterId = SB3Builder.addVariable(stage, "counter", 0)
            local resultId = SB3Builder.addVariable(stage, "result", 0)

            local procDefId, procDefBlock, protoId, prototypeBlock = SB3Builder.Procedures.definition(
                "recursive countdown %n",
                { "n" },
                { "arg_n" },
                { 5 },
                false,
                100,
                100
            )

            local incCounterId, incCounterBlock = SB3Builder.Data.changeVariable("counter", 1, counterId)

            local nArgId, nArgBlock = SB3Builder.Procedures.argumentReporter("n")

            local stopCondId, stopCondBlock = SB3Builder.Operators.lessThan(SB3Builder.blockInput(nArgId), 3)
            local stopId, stopBlock = SB3Builder.Control.stopThisScript()
            local ifStopId, ifStopBlock = SB3Builder.Control.if_(stopCondId, stopId)

            local nMinus1Id, nMinus1Block = SB3Builder.Operators.subtract(SB3Builder.blockInput(nArgId), 1)
            local recursiveCallId, recursiveCallBlock = SB3Builder.Procedures.call(
                "recursive countdown %n",
                { "n" },
                { "arg_n" },
                { 5 },
                { SB3Builder.blockInput(nMinus1Id) },
                false
            )

            local setResultId, setResultBlock = SB3Builder.Data.setVariable("result", 99, resultId)

            local hatId, hatBlock = SB3Builder.Events.whenFlagClicked()
            local mainCallId, mainCallBlock = SB3Builder.Procedures.call(
                "recursive countdown %n",
                { "n" },
                { "arg_n" },
                { 5 },
                { 5 },
                false
            )

            local setResult2Id, setResult2Block = SB3Builder.Data.setVariable("result", 88, resultId)

            SB3Builder.addBlock(stage, hatId, hatBlock)
            SB3Builder.addBlock(stage, mainCallId, mainCallBlock)
            SB3Builder.addBlock(stage, setResult2Id, setResult2Block)
            SB3Builder.addBlock(stage, procDefId, procDefBlock)
            SB3Builder.addBlock(stage, protoId, prototypeBlock)
            SB3Builder.addBlock(stage, incCounterId, incCounterBlock)
            SB3Builder.addBlock(stage, nArgId, nArgBlock)
            SB3Builder.addBlock(stage, stopCondId, stopCondBlock)
            SB3Builder.addBlock(stage, stopId, stopBlock)
            SB3Builder.addBlock(stage, ifStopId, ifStopBlock)
            SB3Builder.addBlock(stage, nMinus1Id, nMinus1Block)
            SB3Builder.addBlock(stage, recursiveCallId, recursiveCallBlock)
            SB3Builder.addBlock(stage, setResultId, setResultBlock)

            SB3Builder.linkBlocks(stage, { hatId, mainCallId, setResult2Id })

            SB3Builder.linkBlocks(stage, { incCounterId, ifStopId, recursiveCallId, setResultId })

            procDefBlock.next = incCounterId
            local Core = require("tests.sb3_builder.core")
            ifStopBlock.inputs.SUBSTACK = Core.substackInput(stopId)

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

            local finalCounter = runtime.stage:lookupVariableByNameAndType("counter")
            local finalResult = runtime.stage:lookupVariableByNameAndType("result")


            expect(finalCounter.value).to.equal(4)

            expect(finalResult.value).to.equal(88)


            expect(iterations < maxIterations).to.be.truthy()
        end)
    end)

    describe("Real World Algorithm Tests", function()
        it("should implement correct quicksort algorithm", function()
            SB3Builder.resetCounter()
            local stage = SB3Builder.createStage()

            local testData = {}
            math.randomseed(os.time())
            for i = 1, 100 do
                testData[i] = math.random(1, 1000)
            end

            local dataListId = SB3Builder.addList(stage, "Data", testData)

            local iId = SB3Builder.addVariable(stage, "i", 0)
            local jId = SB3Builder.addVariable(stage, "j", 0)
            local aId = SB3Builder.addVariable(stage, "a", 0)
            local bId = SB3Builder.addVariable(stage, "b", 0)
            local pivotId = SB3Builder.addVariable(stage, "pivot", 0)
            local cId = SB3Builder.addVariable(stage, "c", 0) -- temp variable for swap

            local hatId, hatBlock = SB3Builder.Events.whenFlagClicked()
            local mainCallId, mainCallBlock = SB3Builder.Procedures.call(
                "quick_sort %n %n",
                { "start", "end" },
                { "arg_start", "arg_end" },
                { 1, 100 },
                { 1, 100 },
                false
            )

            local defId, defBlock, protoId, protoBlock = SB3Builder.Procedures.definition(
                "quick_sort %n %n",
                { "start", "end" },
                { "arg_start", "arg_end" },
                { 1, 100 },
                false
            )

            local startArgId, startArgBlock = SB3Builder.Procedures.argumentReporter("start")
            local endArgId, endArgBlock = SB3Builder.Procedures.argumentReporter("end")

            local endMinusStartId, endMinusStartBlock = SB3Builder.Operators.subtract(SB3Builder.blockInput(endArgId),
                SB3Builder.blockInput(startArgId))
            local continueCondId, continueCondBlock = SB3Builder.Operators.lessThan(0,
                SB3Builder.blockInput(endMinusStartId))
            local ifContinueId, ifContinueBlock = SB3Builder.Control.if_(continueCondId, nil)

            local setI0Id, setI0Block = SB3Builder.Data.setVariable("i", 0, iId)
            local setJ1Id, setJ1Block = SB3Builder.Data.setVariable("j", 1, jId)

            -- pivot = Data[random(start to end)]
            local randomIndexId, randomIndexBlock = SB3Builder.Operators.random(SB3Builder.blockInput(startArgId),
                SB3Builder.blockInput(endArgId))
            local pivotValueId, pivotValueBlock = SB3Builder.Data.itemOfList(SB3Builder.blockInput(randomIndexId), "Data",
                dataListId)
            local setPivotId, setPivotBlock = SB3Builder.Data.setVariable("pivot", SB3Builder.blockInput(pivotValueId),
                pivotId)

            -- a = start, b = end
            local setAId, setABlock = SB3Builder.Data.setVariable("a", SB3Builder.blockInput(startArgId), aId)
            local setBId, setBBlock = SB3Builder.Data.setVariable("b", SB3Builder.blockInput(endArgId), bId)

            -- while (i < j) main loop
            local iVarId, iVarBlock = SB3Builder.Data.variable("i", iId)
            local jVarId, jVarBlock = SB3Builder.Data.variable("j", jId)
            local mainLoopCondId, mainLoopCondBlock = SB3Builder.Operators.lessThan(SB3Builder.blockInput(iVarId),
                SB3Builder.blockInput(jVarId))
            local mainLoopId, mainLoopBlock = SB3Builder.Control.repeatWhile(mainLoopCondId, nil)

            local aVar1Id, aVar1Block = SB3Builder.Data.variable("a", aId)
            local dataAId, dataABlock = SB3Builder.Data.itemOfList(SB3Builder.blockInput(aVar1Id), "Data", dataListId)
            local pivotVar1Id, pivotVar1Block = SB3Builder.Data.variable("pivot", pivotId)
            local leftScanCondId, leftScanCondBlock = SB3Builder.Operators.lessThan(SB3Builder.blockInput(dataAId),
                SB3Builder.blockInput(pivotVar1Id))
            local leftScanLoopId, leftScanLoopBlock = SB3Builder.Control.repeatWhile(leftScanCondId, nil)
            local incAId, incABlock = SB3Builder.Data.changeVariable("a", 1, aId)

            -- i = a
            local aVar2Id, aVar2Block = SB3Builder.Data.variable("a", aId)
            local setIId, setIBlock = SB3Builder.Data.setVariable("i", SB3Builder.blockInput(aVar2Id), iId)

            local bVar1Id, bVar1Block = SB3Builder.Data.variable("b", bId)
            local dataBId, dataBBlock = SB3Builder.Data.itemOfList(SB3Builder.blockInput(bVar1Id), "Data", dataListId)
            local pivotVar2Id, pivotVar2Block = SB3Builder.Data.variable("pivot", pivotId)
            local rightScanCondId, rightScanCondBlock = SB3Builder.Operators.greaterThan(SB3Builder.blockInput(dataBId),
                SB3Builder.blockInput(pivotVar2Id))
            local rightScanLoopId, rightScanLoopBlock = SB3Builder.Control.repeatWhile(rightScanCondId, nil)
            local decBId, decBBlock = SB3Builder.Data.changeVariable("b", -1, bId)

            -- j = b
            local bVar2Id, bVar2Block = SB3Builder.Data.variable("b", bId)
            local setJId, setJBlock = SB3Builder.Data.setVariable("j", SB3Builder.blockInput(bVar2Id), jId)

            -- if (i < j) then swap
            local iVar2Id, iVar2Block = SB3Builder.Data.variable("i", iId)
            local jVar2Id, jVar2Block = SB3Builder.Data.variable("j", jId)
            local swapCondId, swapCondBlock = SB3Builder.Operators.lessThan(SB3Builder.blockInput(iVar2Id),
                SB3Builder.blockInput(jVar2Id))
            local ifSwapId, ifSwapBlock = SB3Builder.Control.if_(swapCondId, nil)

            -- Swap logic: c = Data[i], Data[i] = Data[j], Data[j] = c
            local iVar3Id, iVar3Block = SB3Builder.Data.variable("i", iId)
            local dataI1Id, dataI1Block = SB3Builder.Data.itemOfList(SB3Builder.blockInput(iVar3Id), "Data", dataListId)
            local setCId, setCBlock = SB3Builder.Data.setVariable("c", SB3Builder.blockInput(dataI1Id), cId)

            local iVar4Id, iVar4Block = SB3Builder.Data.variable("i", iId)
            local jVar3Id, jVar3Block = SB3Builder.Data.variable("j", jId)
            local dataJ1Id, dataJ1Block = SB3Builder.Data.itemOfList(SB3Builder.blockInput(jVar3Id), "Data", dataListId)
            local replaceIId, replaceIBlock = SB3Builder.Data.replaceItemOfList(SB3Builder.blockInput(iVar4Id),
                SB3Builder.blockInput(dataJ1Id), "Data", dataListId)

            local jVar4Id, jVar4Block = SB3Builder.Data.variable("j", jId)
            local cVarId, cVarBlock = SB3Builder.Data.variable("c", cId)
            local replaceJId, replaceJBlock = SB3Builder.Data.replaceItemOfList(SB3Builder.blockInput(jVar4Id),
                SB3Builder.blockInput(cVarId), "Data", dataListId)

            -- a = a + 1, b = b - 1
            local incA2Id, incA2Block = SB3Builder.Data.changeVariable("a", 1, aId)
            local decB2Id, decB2Block = SB3Builder.Data.changeVariable("b", -1, bId)

            local iVar5Id, iVar5Block = SB3Builder.Data.variable("i", iId)
            local iMinus1Id, iMinus1Block = SB3Builder.Operators.subtract(SB3Builder.blockInput(iVar5Id), 1)
            local leftRecId, leftRecBlock = SB3Builder.Procedures.call(
                "quick_sort %n %n",
                { "start", "end" },
                { "arg_start", "arg_end" },
                { 1, 100 },
                { SB3Builder.blockInput(startArgId), SB3Builder.blockInput(iMinus1Id) },
                false
            )

            local iVar6Id, iVar6Block = SB3Builder.Data.variable("i", iId)
            local rightRecId, rightRecBlock = SB3Builder.Procedures.call(
                "quick_sort %n %n",
                { "start", "end" },
                { "arg_start", "arg_end" },
                { 1, 100 },
                { SB3Builder.blockInput(iVar6Id), SB3Builder.blockInput(endArgId) },
                false
            )


            SB3Builder.addBlock(stage, hatId, hatBlock)
            SB3Builder.addBlock(stage, mainCallId, mainCallBlock)

            SB3Builder.addBlock(stage, defId, defBlock)
            SB3Builder.addBlock(stage, protoId, protoBlock)
            SB3Builder.addBlock(stage, startArgId, startArgBlock)
            SB3Builder.addBlock(stage, endArgId, endArgBlock)

            SB3Builder.addBlock(stage, endMinusStartId, endMinusStartBlock)
            SB3Builder.addBlock(stage, continueCondId, continueCondBlock)
            SB3Builder.addBlock(stage, ifContinueId, ifContinueBlock)

            SB3Builder.addBlock(stage, setI0Id, setI0Block)
            SB3Builder.addBlock(stage, setJ1Id, setJ1Block)
            SB3Builder.addBlock(stage, randomIndexId, randomIndexBlock)
            SB3Builder.addBlock(stage, pivotValueId, pivotValueBlock)
            SB3Builder.addBlock(stage, setPivotId, setPivotBlock)
            SB3Builder.addBlock(stage, setAId, setABlock)
            SB3Builder.addBlock(stage, setBId, setBBlock)

            SB3Builder.addBlock(stage, iVarId, iVarBlock)
            SB3Builder.addBlock(stage, jVarId, jVarBlock)
            SB3Builder.addBlock(stage, mainLoopCondId, mainLoopCondBlock)
            SB3Builder.addBlock(stage, mainLoopId, mainLoopBlock)

            SB3Builder.addBlock(stage, aVar1Id, aVar1Block)
            SB3Builder.addBlock(stage, dataAId, dataABlock)
            SB3Builder.addBlock(stage, pivotVar1Id, pivotVar1Block)
            SB3Builder.addBlock(stage, leftScanCondId, leftScanCondBlock)
            SB3Builder.addBlock(stage, leftScanLoopId, leftScanLoopBlock)
            SB3Builder.addBlock(stage, incAId, incABlock)
            SB3Builder.addBlock(stage, aVar2Id, aVar2Block)
            SB3Builder.addBlock(stage, setIId, setIBlock)

            SB3Builder.addBlock(stage, bVar1Id, bVar1Block)
            SB3Builder.addBlock(stage, dataBId, dataBBlock)
            SB3Builder.addBlock(stage, pivotVar2Id, pivotVar2Block)
            SB3Builder.addBlock(stage, rightScanCondId, rightScanCondBlock)
            SB3Builder.addBlock(stage, rightScanLoopId, rightScanLoopBlock)
            SB3Builder.addBlock(stage, decBId, decBBlock)
            SB3Builder.addBlock(stage, bVar2Id, bVar2Block)
            SB3Builder.addBlock(stage, setJId, setJBlock)

            SB3Builder.addBlock(stage, iVar2Id, iVar2Block)
            SB3Builder.addBlock(stage, jVar2Id, jVar2Block)
            SB3Builder.addBlock(stage, swapCondId, swapCondBlock)
            SB3Builder.addBlock(stage, ifSwapId, ifSwapBlock)

            SB3Builder.addBlock(stage, iVar3Id, iVar3Block)
            SB3Builder.addBlock(stage, dataI1Id, dataI1Block)
            SB3Builder.addBlock(stage, setCId, setCBlock)
            SB3Builder.addBlock(stage, iVar4Id, iVar4Block)
            SB3Builder.addBlock(stage, jVar3Id, jVar3Block)
            SB3Builder.addBlock(stage, dataJ1Id, dataJ1Block)
            SB3Builder.addBlock(stage, replaceIId, replaceIBlock)
            SB3Builder.addBlock(stage, jVar4Id, jVar4Block)
            SB3Builder.addBlock(stage, cVarId, cVarBlock)
            SB3Builder.addBlock(stage, replaceJId, replaceJBlock)
            SB3Builder.addBlock(stage, incA2Id, incA2Block)
            SB3Builder.addBlock(stage, decB2Id, decB2Block)

            SB3Builder.addBlock(stage, iVar5Id, iVar5Block)
            SB3Builder.addBlock(stage, iMinus1Id, iMinus1Block)
            SB3Builder.addBlock(stage, leftRecId, leftRecBlock)
            SB3Builder.addBlock(stage, iVar6Id, iVar6Block)
            SB3Builder.addBlock(stage, rightRecId, rightRecBlock)

            SB3Builder.linkBlocks(stage, { hatId, mainCallId })

            SB3Builder.linkBlocks(stage, {
                defId, ifContinueId
            })

            local Core = require("tests.sb3_builder.core")
            ifContinueBlock.inputs.SUBSTACK = Core.substackInput(setI0Id)
            SB3Builder.linkBlocks(stage, {
                setI0Id, setJ1Id, setPivotId, setAId, setBId, mainLoopId,
                leftRecId, rightRecId
            })

            mainLoopBlock.inputs.SUBSTACK = Core.substackInput(leftScanLoopId)
            SB3Builder.linkBlocks(stage, {
                leftScanLoopId, setIId, rightScanLoopId, setJId, ifSwapId
            })

            leftScanLoopBlock.inputs.SUBSTACK = Core.substackInput(incAId)

            rightScanLoopBlock.inputs.SUBSTACK = Core.substackInput(decBId)

            ifSwapBlock.inputs.SUBSTACK = Core.substackInput(setCId)
            SB3Builder.linkBlocks(stage, { setCId, replaceIId, replaceJId, incA2Id, decB2Id })

            local projectJson = SB3Builder.createProject({ stage })
            local project = ProjectModel:new(projectJson, {})
            local runtime = Runtime:new(project)
            runtime:initialize()

            local dataList = runtime.stage:lookupVariableByNameAndType("Data", "list")

            local originalData = {}
            for i, v in ipairs(dataList.value) do
                originalData[i] = v
            end

            runtime:broadcastGreenFlag()
            local maxIterations = 10000
            local iterations = 0
            while #runtime:getActiveThreads() > 0 and iterations < maxIterations do
                runtime:update(1 / 60)
                iterations = iterations + 1
            end

            local isSorted = true
            for i = 1, #dataList.value - 1 do
                if dataList.value[i] > dataList.value[i + 1] then
                    isSorted = false
                    break
                end
            end

            local sortedCopy = {}
            for i, v in ipairs(dataList.value) do
                sortedCopy[i] = v
            end
            table.sort(originalData)

            local elementsMatch = true
            for i = 1, #originalData do
                if originalData[i] ~= sortedCopy[i] then
                    elementsMatch = false
                    break
                end
            end

            expect(#dataList.value).to.equal(100)
            expect(iterations < maxIterations).to.be.truthy()
            expect(isSorted).to.be.truthy()
            expect(elementsMatch).to.be.truthy()
        end)


        it("should implement corrected pseudocode quicksort algorithm", function()
            SB3Builder.resetCounter()
            local stage = SB3Builder.createStage()

            local testData = { 64, 34, 25, 12, 22, 11, 90 }

            local dataListId = SB3Builder.addList(stage, "Data", testData)

            local iId = SB3Builder.addVariable(stage, "i", 0)
            local jId = SB3Builder.addVariable(stage, "j", 0)
            local pivotId = SB3Builder.addVariable(stage, "pivot", 0)
            local cId = SB3Builder.addVariable(stage, "c", 0)

            local hatId, hatBlock = SB3Builder.Events.whenFlagClicked()
            local mainCallId, mainCallBlock = SB3Builder.Procedures.call(
                "quick_sort %n %n",
                { "start", "end" },
                { "arg_start", "arg_end" },
                { 1, 7 },
                { 1, 7 },
                false
            )

            local defId, defBlock, protoId, protoBlock = SB3Builder.Procedures.definition(
                "quick_sort %n %n",
                { "start", "end" },
                { "arg_start", "arg_end" },
                { 1, 7 },
                false
            )

            local startArgId, startArgBlock = SB3Builder.Procedures.argumentReporter("start")
            local endArgId, endArgBlock = SB3Builder.Procedures.argumentReporter("end")

            local endMinusStartId, endMinusStartBlock = SB3Builder.Operators.subtract(
                SB3Builder.blockInput(endArgId), SB3Builder.blockInput(startArgId))
            local exitCondId, exitCondBlock = SB3Builder.Operators.lessThan(
                SB3Builder.blockInput(endMinusStartId), 1)
            local ifExitId, ifExitBlock = SB3Builder.Control.if_(exitCondId, nil)
            local stopId, stopBlock = SB3Builder.Control.stopThisScript()

            local randomIndexId, randomIndexBlock = SB3Builder.Operators.random(
                SB3Builder.blockInput(startArgId), SB3Builder.blockInput(endArgId))
            local pivotValueId, pivotValueBlock = SB3Builder.Data.itemOfList(
                SB3Builder.blockInput(randomIndexId), "Data", dataListId)
            local setPivotId, setPivotBlock = SB3Builder.Data.setVariable("pivot",
                SB3Builder.blockInput(pivotValueId), pivotId)

            -- i ← start, j ← end
            local setIId, setIBlock = SB3Builder.Data.setVariable("i",
                SB3Builder.blockInput(startArgId), iId)
            local setJId, setJBlock = SB3Builder.Data.setVariable("j",
                SB3Builder.blockInput(endArgId), jId)

            local iVarId, iVarBlock = SB3Builder.Data.variable("i", iId)
            local jVarId, jVarBlock = SB3Builder.Data.variable("j", jId)
            local mainLoopCondId, mainLoopCondBlock = SB3Builder.Operators.greaterThan(
                SB3Builder.blockInput(iVarId), SB3Builder.blockInput(jVarId))
            local mainLoopId, mainLoopBlock = SB3Builder.Control.repeatUntil(mainLoopCondId, nil)

            local iVar1Id, iVar1Block = SB3Builder.Data.variable("i", iId)
            local dataIId, dataIBlock = SB3Builder.Data.itemOfList(SB3Builder.blockInput(iVar1Id), "Data", dataListId)
            local pivotVar1Id, pivotVar1Block = SB3Builder.Data.variable("pivot", pivotId)
            local leftScanCondId, leftScanCondBlock = SB3Builder.Operators.lessThan(
                SB3Builder.blockInput(dataIId), SB3Builder.blockInput(pivotVar1Id))
            local leftScanLoopId, leftScanLoopBlock = SB3Builder.Control.repeatWhile(leftScanCondId, nil)
            local incIId, incIBlock = SB3Builder.Data.changeVariable("i", 1, iId)

            local jVar1Id, jVar1Block = SB3Builder.Data.variable("j", jId)
            local dataJId, dataJBlock = SB3Builder.Data.itemOfList(SB3Builder.blockInput(jVar1Id), "Data", dataListId)
            local pivotVar2Id, pivotVar2Block = SB3Builder.Data.variable("pivot", pivotId)
            local rightScanCondId, rightScanCondBlock = SB3Builder.Operators.greaterThan(
                SB3Builder.blockInput(dataJId), SB3Builder.blockInput(pivotVar2Id))
            local rightScanLoopId, rightScanLoopBlock = SB3Builder.Control.repeatWhile(rightScanCondId, nil)
            local decJId, decJBlock = SB3Builder.Data.changeVariable("j", -1, jId)

            local iVar2Id, iVar2Block = SB3Builder.Data.variable("i", iId)
            local jVar2Id, jVar2Block = SB3Builder.Data.variable("j", jId)
            local lessOrSwapCondId, lessOrSwapCondBlock = SB3Builder.Operators.lessThan(
                SB3Builder.blockInput(iVar2Id), SB3Builder.blockInput(jVar2Id))
            local equalSwapCondId, equalSwapCondBlock = SB3Builder.Operators.equals(
                SB3Builder.blockInput(iVar2Id), SB3Builder.blockInput(jVar2Id))
            local swapCondId, swapCondBlock = SB3Builder.Operators.or_(
                SB3Builder.blockInput(lessOrSwapCondId), SB3Builder.blockInput(equalSwapCondId))
            local ifSwapId, ifSwapBlock = SB3Builder.Control.if_(swapCondId, nil)

            local iVar3Id, iVar3Block = SB3Builder.Data.variable("i", iId)
            local dataI2Id, dataI2Block = SB3Builder.Data.itemOfList(SB3Builder.blockInput(iVar3Id), "Data", dataListId)
            local setCId, setCBlock = SB3Builder.Data.setVariable("c", SB3Builder.blockInput(dataI2Id), cId)

            local iVar4Id, iVar4Block = SB3Builder.Data.variable("i", iId)
            local jVar3Id, jVar3Block = SB3Builder.Data.variable("j", jId)
            local dataJ2Id, dataJ2Block = SB3Builder.Data.itemOfList(SB3Builder.blockInput(jVar3Id), "Data", dataListId)
            local replaceIId, replaceIBlock = SB3Builder.Data.replaceItemOfList(
                SB3Builder.blockInput(iVar4Id), SB3Builder.blockInput(dataJ2Id), "Data", dataListId)

            local jVar4Id, jVar4Block = SB3Builder.Data.variable("j", jId)
            local cVarId, cVarBlock = SB3Builder.Data.variable("c", cId)
            local replaceJId, replaceJBlock = SB3Builder.Data.replaceItemOfList(
                SB3Builder.blockInput(jVar4Id), SB3Builder.blockInput(cVarId), "Data", dataListId)

            local incI2Id, incI2Block = SB3Builder.Data.changeVariable("i", 1, iId)
            local decJ2Id, decJ2Block = SB3Builder.Data.changeVariable("j", -1, jId)

            local jVar5Id, jVar5Block = SB3Builder.Data.variable("j", jId)
            local leftRecId, leftRecBlock = SB3Builder.Procedures.call(
                "quick_sort %n %n",
                { "start", "end" },
                { "arg_start", "arg_end" },
                { 1, 7 },
                { SB3Builder.blockInput(startArgId), SB3Builder.blockInput(jVar5Id) },
                false
            )

            local iVar5Id, iVar5Block = SB3Builder.Data.variable("i", iId)
            local rightRecId, rightRecBlock = SB3Builder.Procedures.call(
                "quick_sort %n %n",
                { "start", "end" },
                { "arg_start", "arg_end" },
                { 1, 7 },
                { SB3Builder.blockInput(iVar5Id), SB3Builder.blockInput(endArgId) },
                false
            )

            SB3Builder.addBlock(stage, hatId, hatBlock)
            SB3Builder.addBlock(stage, mainCallId, mainCallBlock)

            SB3Builder.addBlock(stage, defId, defBlock)
            SB3Builder.addBlock(stage, protoId, protoBlock)
            SB3Builder.addBlock(stage, startArgId, startArgBlock)
            SB3Builder.addBlock(stage, endArgId, endArgBlock)

            SB3Builder.addBlock(stage, endMinusStartId, endMinusStartBlock)
            SB3Builder.addBlock(stage, exitCondId, exitCondBlock)
            SB3Builder.addBlock(stage, ifExitId, ifExitBlock)
            SB3Builder.addBlock(stage, stopId, stopBlock)

            SB3Builder.addBlock(stage, randomIndexId, randomIndexBlock)
            SB3Builder.addBlock(stage, pivotValueId, pivotValueBlock)
            SB3Builder.addBlock(stage, setPivotId, setPivotBlock)
            SB3Builder.addBlock(stage, setIId, setIBlock)
            SB3Builder.addBlock(stage, setJId, setJBlock)

            SB3Builder.addBlock(stage, iVarId, iVarBlock)
            SB3Builder.addBlock(stage, jVarId, jVarBlock)
            SB3Builder.addBlock(stage, mainLoopCondId, mainLoopCondBlock)
            SB3Builder.addBlock(stage, mainLoopId, mainLoopBlock)

            SB3Builder.addBlock(stage, iVar1Id, iVar1Block)
            SB3Builder.addBlock(stage, dataIId, dataIBlock)
            SB3Builder.addBlock(stage, pivotVar1Id, pivotVar1Block)
            SB3Builder.addBlock(stage, leftScanCondId, leftScanCondBlock)
            SB3Builder.addBlock(stage, leftScanLoopId, leftScanLoopBlock)
            SB3Builder.addBlock(stage, incIId, incIBlock)

            SB3Builder.addBlock(stage, jVar1Id, jVar1Block)
            SB3Builder.addBlock(stage, dataJId, dataJBlock)
            SB3Builder.addBlock(stage, pivotVar2Id, pivotVar2Block)
            SB3Builder.addBlock(stage, rightScanCondId, rightScanCondBlock)
            SB3Builder.addBlock(stage, rightScanLoopId, rightScanLoopBlock)
            SB3Builder.addBlock(stage, decJId, decJBlock)

            SB3Builder.addBlock(stage, iVar2Id, iVar2Block)
            SB3Builder.addBlock(stage, jVar2Id, jVar2Block)
            SB3Builder.addBlock(stage, lessOrSwapCondId, lessOrSwapCondBlock)
            SB3Builder.addBlock(stage, equalSwapCondId, equalSwapCondBlock)
            SB3Builder.addBlock(stage, swapCondId, swapCondBlock)
            SB3Builder.addBlock(stage, ifSwapId, ifSwapBlock)
            SB3Builder.addBlock(stage, iVar3Id, iVar3Block)
            SB3Builder.addBlock(stage, dataI2Id, dataI2Block)
            SB3Builder.addBlock(stage, setCId, setCBlock)
            SB3Builder.addBlock(stage, iVar4Id, iVar4Block)
            SB3Builder.addBlock(stage, jVar3Id, jVar3Block)
            SB3Builder.addBlock(stage, dataJ2Id, dataJ2Block)
            SB3Builder.addBlock(stage, replaceIId, replaceIBlock)
            SB3Builder.addBlock(stage, jVar4Id, jVar4Block)
            SB3Builder.addBlock(stage, cVarId, cVarBlock)
            SB3Builder.addBlock(stage, replaceJId, replaceJBlock)
            SB3Builder.addBlock(stage, incI2Id, incI2Block)
            SB3Builder.addBlock(stage, decJ2Id, decJ2Block)

            SB3Builder.addBlock(stage, jVar5Id, jVar5Block)
            SB3Builder.addBlock(stage, leftRecId, leftRecBlock)
            SB3Builder.addBlock(stage, iVar5Id, iVar5Block)
            SB3Builder.addBlock(stage, rightRecId, rightRecBlock)

            SB3Builder.linkBlocks(stage, { hatId, mainCallId })

            SB3Builder.linkBlocks(stage, {
                defId, ifExitId, setPivotId, setIId, setJId, mainLoopId,
                leftRecId, rightRecId
            })

            local Core = require("tests.sb3_builder.core")

            ifExitBlock.inputs.SUBSTACK = Core.substackInput(stopId)

            mainLoopBlock.inputs.SUBSTACK = Core.substackInput(leftScanLoopId)
            SB3Builder.linkBlocks(stage, {
                leftScanLoopId, rightScanLoopId, ifSwapId
            })

            leftScanLoopBlock.inputs.SUBSTACK = Core.substackInput(incIId)

            rightScanLoopBlock.inputs.SUBSTACK = Core.substackInput(decJId)

            ifSwapBlock.inputs.SUBSTACK = Core.substackInput(setCId)
            SB3Builder.linkBlocks(stage, { setCId, replaceIId, replaceJId, incI2Id, decJ2Id })

            local projectJson = SB3Builder.createProject({ stage })
            local project = ProjectModel:new(projectJson, {})
            local runtime = Runtime:new(project)
            runtime:initialize()

            local dataList = runtime.stage:lookupVariableByNameAndType("Data", "list")

            local originalData = {}
            for i, v in ipairs(dataList.value) do
                originalData[i] = v
            end

            runtime:broadcastGreenFlag()
            local maxIterations = 1000
            local iterations = 0
            while #runtime:getActiveThreads() > 0 and iterations < maxIterations do
                runtime:update(1 / 60)
                iterations = iterations + 1
            end

            local isSorted = true
            for i = 1, #dataList.value - 1 do
                if dataList.value[i] > dataList.value[i + 1] then
                    isSorted = false
                    print("Sort failed at position:", i, "value:", dataList.value[i], ">", dataList.value[i + 1])
                    break
                end
            end

            local sortedCopy = {}
            for i, v in ipairs(dataList.value) do
                sortedCopy[i] = v
            end
            table.sort(originalData)

            local elementsMatch = true
            for i = 1, #originalData do
                if originalData[i] ~= sortedCopy[i] then
                    elementsMatch = false
                    print("Element mismatch at position:", i, "expected:", originalData[i], "actual:", sortedCopy[i])
                    break
                end
            end

            expect(#dataList.value).to.equal(7)
            expect(iterations < maxIterations).to.be.truthy()
            expect(isSorted).to.be.truthy()
            expect(elementsMatch).to.be.truthy()
        end)
    end)
end)


describe("WarpMode and Performance Testing", function()
    it("should execute all at once block immediately", function()
        SB3Builder.resetCounter()
        local stage = SB3Builder.createStage()
        local variableId = SB3Builder.addVariable(stage, "counter", 0)

        -- Create: all at once { repeat 10 times { change counter by 1 } }
        -- Note: "all at once" in Scratch 3.0 behaves like normal execution, not warp mode
        local hatId, hatBlock = SB3Builder.Events.whenFlagClicked(100, 100)
        local changeId, changeBlock = SB3Builder.Data.changeVariable("counter", 1, variableId)
        local repeatId, repeatBlock = SB3Builder.Control.repeat_(10, changeId)
        local allAtOnceId, allAtOnceBlock = SB3Builder.Control.allAtOnce(repeatId)

        SB3Builder.addBlock(stage, hatId, hatBlock)
        SB3Builder.addBlock(stage, allAtOnceId, allAtOnceBlock)
        SB3Builder.addBlock(stage, repeatId, repeatBlock)
        SB3Builder.addBlock(stage, changeId, changeBlock)
        SB3Builder.linkBlocks(stage, { hatId, allAtOnceId })

        local projectJson = SB3Builder.createProject({ stage })
        local project = ProjectModel:new(projectJson, {})
        local runtime = Runtime:new(project)
        runtime:initialize()

        runtime:broadcastGreenFlag()

        -- Execute normal amount of frames since all at once is not warp mode
        local maxIterations = 50
        local iterations = 0
        while #runtime:getActiveThreads() > 0 and iterations < maxIterations do
            runtime:update(1 / 60)
            iterations = iterations + 1
        end

        local counter = runtime.stage:lookupVariableByNameAndType("counter")
        expect(counter.value).to.equal(10)
    end)

    it("should execute custom procedure with warpMode enabled", function()
        SB3Builder.resetCounter()
        local stage = SB3Builder.createStage()
        local variableId = SB3Builder.addVariable(stage, "counter", 0)

        -- Define a procedure with warp mode enabled that increments counter 50 times
        local proccode = "increment %n times"
        local argumentNames = { "times" }
        local argumentIds = { "times_arg" }
        local argumentDefaults = { 10 }
        local warp = true

        local procDefId, procDefBlock, protoId, prototypeBlock = SB3Builder.Procedures.definition(
            proccode, argumentNames, argumentIds, argumentDefaults, warp, 100, 200
        )

        -- Procedure body: repeat (times) { change counter by 1 }
        local getTimesId, getTimesBlock = SB3Builder.Procedures.argumentReporter("times")
        local changeId, changeBlock = SB3Builder.Data.changeVariable("counter", 1, variableId)
        local repeatId, repeatBlock = SB3Builder.Control.repeat_(getTimesId, changeId)

        -- Main script: call procedure with 50
        local hatId, hatBlock = SB3Builder.Events.whenFlagClicked(100, 100)
        local callId, callBlock = SB3Builder.Procedures.call(
            proccode, argumentNames, argumentIds, argumentDefaults, { 50 }, warp
        )

        SB3Builder.addBlock(stage, hatId, hatBlock)
        SB3Builder.addBlock(stage, callId, callBlock)
        SB3Builder.addBlock(stage, procDefId, procDefBlock)
        SB3Builder.addBlock(stage, protoId, prototypeBlock)
        SB3Builder.addBlock(stage, repeatId, repeatBlock)
        SB3Builder.addBlock(stage, changeId, changeBlock)
        SB3Builder.addBlock(stage, getTimesId, getTimesBlock)
        SB3Builder.linkBlocks(stage, { hatId, callId })
        procDefBlock.next = repeatId

        local projectJson = SB3Builder.createProject({ stage })
        local project = ProjectModel:new(projectJson, {})
        local runtime = Runtime:new(project)
        runtime:initialize()

        runtime:broadcastGreenFlag()

        -- Should complete very quickly due to warp mode
        local maxIterations = 5
        local iterations = 0
        while #runtime:getActiveThreads() > 0 and iterations < maxIterations do
            runtime:update(1 / 60)
            iterations = iterations + 1
        end

        local counter = runtime.stage:lookupVariableByNameAndType("counter")
        expect(counter.value).to.equal(50)
        expect(iterations <= 3).to.be(true) -- Should complete in very few frames due to warp
    end)

    it("should execute custom procedure with warpMode disabled efficiently for data operations", function()
        SB3Builder.resetCounter()
        local stage = SB3Builder.createStage()
        local variableId = SB3Builder.addVariable(stage, "counter", 0)

        -- Define a procedure with warp mode disabled
        local proccode = "slow increment %n times"
        local argumentNames = { "times" }
        local argumentIds = { "times_arg" }
        local argumentDefaults = { 10 }
        local warp = false -- No warp mode

        local procDefId, procDefBlock, protoId, prototypeBlock = SB3Builder.Procedures.definition(
            proccode, argumentNames, argumentIds, argumentDefaults, warp, 100, 200
        )

        -- Procedure body: repeat (times) { change counter by 1 }
        local getTimesId, getTimesBlock = SB3Builder.Procedures.argumentReporter("times")
        local changeId, changeBlock = SB3Builder.Data.changeVariable("counter", 1, variableId)
        local repeatId, repeatBlock = SB3Builder.Control.repeat_(getTimesId, changeId)

        -- Main script: call procedure with 20
        local hatId, hatBlock = SB3Builder.Events.whenFlagClicked(100, 100)
        local callId, callBlock = SB3Builder.Procedures.call(
            proccode, argumentNames, argumentIds, argumentDefaults, { 20 }, warp
        )

        SB3Builder.addBlock(stage, hatId, hatBlock)
        SB3Builder.addBlock(stage, callId, callBlock)
        SB3Builder.addBlock(stage, procDefId, procDefBlock)
        SB3Builder.addBlock(stage, protoId, prototypeBlock)
        SB3Builder.addBlock(stage, repeatId, repeatBlock)
        SB3Builder.addBlock(stage, changeId, changeBlock)
        SB3Builder.addBlock(stage, getTimesId, getTimesBlock)
        SB3Builder.linkBlocks(stage, { hatId, callId })
        procDefBlock.next = repeatId

        local projectJson = SB3Builder.createProject({ stage })
        local project = ProjectModel:new(projectJson, {})
        local runtime = Runtime:new(project)
        runtime:initialize()

        runtime:broadcastGreenFlag()

        -- Without warp mode, should take more frames to complete
        local maxIterations = 30
        local iterations = 0
        while #runtime:getActiveThreads() > 0 and iterations < maxIterations do
            runtime:update(1 / 60)
            iterations = iterations + 1
        end

        local counter = runtime.stage:lookupVariableByNameAndType("counter")
        expect(counter.value).to.equal(20)
        expect(iterations <= 5).to.be(true) -- Pure data operations should be efficient even without warp mode
    end)

    it("should handle nested custom procedures with different warp modes", function()
        SB3Builder.resetCounter()
        local stage = SB3Builder.createStage()
        local variableId = SB3Builder.addVariable(stage, "counter", 0)

        -- Fast procedure (with warp)
        local fastProccode = "fast add %n"
        local fastProcDefId, fastProcDefBlock, fastProtoId, fastPrototypeBlock = SB3Builder.Procedures.definition(
            fastProccode, { "amount" }, { "amount_arg" }, { 1 }, true, 100, 200
        )
        local fastArgId, fastArgBlock = SB3Builder.Procedures.argumentReporter("amount")
        local fastChangeId, fastChangeBlock = SB3Builder.Data.changeVariable("counter", fastArgId, variableId)
        fastProcDefBlock.next = fastChangeId

        -- Slow procedure (without warp) that calls fast procedure
        local slowProccode = "slow process %n times"
        local slowProcDefId, slowProcDefBlock, slowProtoId, slowPrototypeBlock = SB3Builder.Procedures.definition(
            slowProccode, { "times" }, { "times_arg" }, { 1 }, false, 100, 300
        )
        local slowArgId, slowArgBlock = SB3Builder.Procedures.argumentReporter("times")
        local slowCallId, slowCallBlock = SB3Builder.Procedures.call(
            fastProccode, { "amount" }, { "amount_arg" }, { 1 }, { 5 }, true
        )
        local slowRepeatId, slowRepeatBlock = SB3Builder.Control.repeat_(slowArgId, slowCallId)
        slowProcDefBlock.next = slowRepeatId

        -- Main script
        local hatId, hatBlock = SB3Builder.Events.whenFlagClicked(100, 100)
        local mainCallId, mainCallBlock = SB3Builder.Procedures.call(
            slowProccode, { "times" }, { "times_arg" }, { 1 }, { 3 }, false
        )

        SB3Builder.addBlock(stage, hatId, hatBlock)
        SB3Builder.addBlock(stage, mainCallId, mainCallBlock)
        SB3Builder.addBlock(stage, fastProcDefId, fastProcDefBlock)
        SB3Builder.addBlock(stage, fastProtoId, fastPrototypeBlock)
        SB3Builder.addBlock(stage, fastChangeId, fastChangeBlock)
        SB3Builder.addBlock(stage, fastArgId, fastArgBlock)
        SB3Builder.addBlock(stage, slowProcDefId, slowProcDefBlock)
        SB3Builder.addBlock(stage, slowProtoId, slowPrototypeBlock)
        SB3Builder.addBlock(stage, slowRepeatId, slowRepeatBlock)
        SB3Builder.addBlock(stage, slowCallId, slowCallBlock)
        SB3Builder.addBlock(stage, slowArgId, slowArgBlock)
        SB3Builder.linkBlocks(stage, { hatId, mainCallId })

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
        expect(counter.value).to.equal(15) -- 3 times * 5 each = 15
    end)

    it("should handle nested all at once blocks", function()
        SB3Builder.resetCounter()
        local stage = SB3Builder.createStage()
        local variableId = SB3Builder.addVariable(stage, "counter", 0)

        -- Create: all at once { all at once { repeat 10 times { change counter by 1 } } }
        local hatId, hatBlock = SB3Builder.Events.whenFlagClicked(100, 100)
        local changeId, changeBlock = SB3Builder.Data.changeVariable("counter", 1, variableId)
        local repeatId, repeatBlock = SB3Builder.Control.repeat_(10, changeId)
        local innerAllAtOnceId, innerAllAtOnceBlock = SB3Builder.Control.allAtOnce(repeatId)
        local outerAllAtOnceId, outerAllAtOnceBlock = SB3Builder.Control.allAtOnce(innerAllAtOnceId)

        SB3Builder.addBlock(stage, hatId, hatBlock)
        SB3Builder.addBlock(stage, outerAllAtOnceId, outerAllAtOnceBlock)
        SB3Builder.addBlock(stage, innerAllAtOnceId, innerAllAtOnceBlock)
        SB3Builder.addBlock(stage, repeatId, repeatBlock)
        SB3Builder.addBlock(stage, changeId, changeBlock)
        SB3Builder.linkBlocks(stage, { hatId, outerAllAtOnceId })

        local projectJson = SB3Builder.createProject({ stage })
        local project = ProjectModel:new(projectJson, {})
        local runtime = Runtime:new(project)
        runtime:initialize()

        runtime:broadcastGreenFlag()

        local maxIterations = 10
        local iterations = 0
        while #runtime:getActiveThreads() > 0 and iterations < maxIterations do
            runtime:update(1 / 60)
            iterations = iterations + 1
        end

        local counter = runtime.stage:lookupVariableByNameAndType("counter")
        expect(counter.value).to.equal(10)
    end)
end)
