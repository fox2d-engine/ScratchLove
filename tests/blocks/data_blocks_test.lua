-- Data Blocks Tests
-- Tests for data (variables and lists) block implementations

-- Import testing framework
local lust = require("tests.lust")
local describe, it, expect = lust.describe, lust.it, lust.expect

-- Import project components
local SB3Builder = require("tests.sb3_builder")
local ProjectModel = require("parser.project_model")
local Runtime = require("vm.runtime")

describe("Data Blocks", function()
    describe("Basic Variable Operations", function()
        it("should execute a simple set variable script", function()
            -- Reset builder counter for clean test
            SB3Builder.resetCounter()

            -- Create stage and add variable
            local stage = SB3Builder.createStage()
            local variableId = SB3Builder.addVariable(stage, "counter", 0)

            -- Create simple script: when flag clicked -> set counter to 5
            local hatId, hatBlock = SB3Builder.Events.whenFlagClicked(100, 100)
            local setId, setBlock = SB3Builder.Data.setVariable("counter", 5, variableId)

            -- Add blocks to stage
            SB3Builder.addBlock(stage, hatId, hatBlock)
            SB3Builder.addBlock(stage, setId, setBlock)

            -- Link blocks
            SB3Builder.linkBlocks(stage, {hatId, setId})

            -- Create complete SB3 project
            local projectJson = SB3Builder.createProject({stage})

            -- Parse through ProjectModel (just like real SB3 loading)
            local project = ProjectModel:new(projectJson, {})
            local runtime = Runtime:new(project)
            runtime:initialize()

            -- Execute green flag script
            runtime:broadcastGreenFlag()
            -- Safe execution with iteration limit to prevent infinite loops
            local maxIterations = 100
            local iterations = 0
            while #runtime:getActiveThreads() > 0 and iterations < maxIterations do
                runtime:update(1/60)
                iterations = iterations + 1
            end

            -- Verify result
            local counter = runtime.stage:lookupVariableByNameAndType("counter")
            expect(counter).to.exist()
            expect(counter.value).to.equal(5)
        end)

        it("should execute change variable by operations", function()
            SB3Builder.resetCounter()
            local stage = SB3Builder.createStage()
            local variableId = SB3Builder.addVariable(stage, "counter", 10)

            -- Create script: when flag clicked -> change counter by 5 -> change counter by -3
            local hatId, hatBlock = SB3Builder.Events.whenFlagClicked()
            local change1Id, change1Block = SB3Builder.Data.changeVariable("counter", 5, variableId)
            local change2Id, change2Block = SB3Builder.Data.changeVariable("counter", -3, variableId)

            SB3Builder.addBlock(stage, hatId, hatBlock)
            SB3Builder.addBlock(stage, change1Id, change1Block)
            SB3Builder.addBlock(stage, change2Id, change2Block)
            SB3Builder.linkBlocks(stage, {hatId, change1Id, change2Id})

            local projectJson = SB3Builder.createProject({stage})
            local project = ProjectModel:new(projectJson, {})
            local runtime = Runtime:new(project)
            runtime:initialize()

            runtime:broadcastGreenFlag()
            -- Safe execution with iteration limit to prevent infinite loops
            local maxIterations = 100
            local iterations = 0
            while #runtime:getActiveThreads() > 0 and iterations < maxIterations do
                runtime:update(1/60)
                iterations = iterations + 1
            end

            local counter = runtime.stage:lookupVariableByNameAndType("counter")
            expect(counter.value).to.equal(12) -- 10 + 5 - 3 = 12
        end)

        it("should handle type casting in variable change operations", function()
            SB3Builder.resetCounter()
            local stage = SB3Builder.createStage()
            local variableId = SB3Builder.addVariable(stage, "var", "10") -- String

            -- Change by number
            local hatId, hatBlock = SB3Builder.Events.whenFlagClicked()
            local changeId, changeBlock = SB3Builder.Data.changeVariable("var", 5, variableId)

            SB3Builder.addBlock(stage, hatId, hatBlock)
            SB3Builder.addBlock(stage, changeId, changeBlock)
            SB3Builder.linkBlocks(stage, {hatId, changeId})

            local projectJson = SB3Builder.createProject({stage})
            local project = ProjectModel:new(projectJson, {})
            local runtime = Runtime:new(project)
            runtime:initialize()

            runtime:broadcastGreenFlag()
            -- Safe execution with iteration limit to prevent infinite loops
            local maxIterations = 100
            local iterations = 0
            while #runtime:getActiveThreads() > 0 and iterations < maxIterations do
                runtime:update(1/60)
                iterations = iterations + 1
            end

            local var = runtime.stage:lookupVariableByNameAndType("var")
            expect(var.value).to.equal(15) -- "10" + 5 = 15 (string to number conversion)
        end)
    end)

    describe("Edge Cases and Boundary Conditions", function()
        it("should handle invalid list indices gracefully", function()
            SB3Builder.resetCounter()
            local stage = SB3Builder.createStage()
            local listId = SB3Builder.addList(stage, "test", {"a", "b", "c"})
            local resultId = SB3Builder.addVariable(stage, "result", "init")

            local hatId, hatBlock = SB3Builder.Events.whenFlagClicked()
            local itemId, itemBlock = SB3Builder.Data.itemOfList(10, "test", listId) -- Invalid index
            local setId, setBlock = SB3Builder.createBlock("data_setvariableto", {
                VALUE = SB3Builder.blockInput(itemId)
            }, {
                VARIABLE = SB3Builder.field("result", resultId)
            })

            SB3Builder.addBlock(stage, hatId, hatBlock)
            SB3Builder.addBlock(stage, itemId, itemBlock)
            SB3Builder.addBlock(stage, setId, setBlock)
            SB3Builder.linkBlocks(stage, {hatId, setId})

            local projectJson = SB3Builder.createProject({stage})
            local project = ProjectModel:new(projectJson, {})
            local runtime = Runtime:new(project)
            runtime:initialize()

            runtime:broadcastGreenFlag()
            -- Safe execution with iteration limit to prevent infinite loops
            local maxIterations = 100
            local iterations = 0
            while #runtime:getActiveThreads() > 0 and iterations < maxIterations do
                runtime:update(1/60)
                iterations = iterations + 1
            end

            local result = runtime.stage:lookupVariableByNameAndType("result")
            expect(result.value).to.equal("") -- Should return empty string for invalid index
        end)

        it("should handle negative list indices", function()
            SB3Builder.resetCounter()
            local stage = SB3Builder.createStage()
            local listId = SB3Builder.addList(stage, "test", {"x", "y", "z"})
            local resultId = SB3Builder.addVariable(stage, "result", "init")

            local hatId, hatBlock = SB3Builder.Events.whenFlagClicked()
            local itemId, itemBlock = SB3Builder.Data.itemOfList(-1, "test", listId) -- Negative index
            local setId, setBlock = SB3Builder.createBlock("data_setvariableto", {
                VALUE = SB3Builder.blockInput(itemId)
            }, {
                VARIABLE = SB3Builder.field("result", resultId)
            })

            SB3Builder.addBlock(stage, hatId, hatBlock)
            SB3Builder.addBlock(stage, itemId, itemBlock)
            SB3Builder.addBlock(stage, setId, setBlock)
            SB3Builder.linkBlocks(stage, {hatId, setId})

            local projectJson = SB3Builder.createProject({stage})
            local project = ProjectModel:new(projectJson, {})
            local runtime = Runtime:new(project)
            runtime:initialize()

            runtime:broadcastGreenFlag()
            -- Safe execution with iteration limit to prevent infinite loops
            local maxIterations = 100
            local iterations = 0
            while #runtime:getActiveThreads() > 0 and iterations < maxIterations do
                runtime:update(1/60)
                iterations = iterations + 1
            end

            local result = runtime.stage:lookupVariableByNameAndType("result")
            expect(result.value).to.equal("") -- Should return empty string for invalid index
        end)

        it("should handle zero as list index", function()
            SB3Builder.resetCounter()
            local stage = SB3Builder.createStage()
            local listId = SB3Builder.addList(stage, "test", {"first", "second"})
            local resultId = SB3Builder.addVariable(stage, "result", "init")

            local hatId, hatBlock = SB3Builder.Events.whenFlagClicked()
            local itemId, itemBlock = SB3Builder.Data.itemOfList(0, "test", listId) -- Zero index
            local setId, setBlock = SB3Builder.createBlock("data_setvariableto", {
                VALUE = SB3Builder.blockInput(itemId)
            }, {
                VARIABLE = SB3Builder.field("result", resultId)
            })

            SB3Builder.addBlock(stage, hatId, hatBlock)
            SB3Builder.addBlock(stage, itemId, itemBlock)
            SB3Builder.addBlock(stage, setId, setBlock)
            SB3Builder.linkBlocks(stage, {hatId, setId})

            local projectJson = SB3Builder.createProject({stage})
            local project = ProjectModel:new(projectJson, {})
            local runtime = Runtime:new(project)
            runtime:initialize()

            runtime:broadcastGreenFlag()
            -- Safe execution with iteration limit to prevent infinite loops
            local maxIterations = 100
            local iterations = 0
            while #runtime:getActiveThreads() > 0 and iterations < maxIterations do
                runtime:update(1/60)
                iterations = iterations + 1
            end

            local result = runtime.stage:lookupVariableByNameAndType("result")
            expect(result.value).to.equal("") -- Should return empty string for invalid index
        end)

        it("should handle empty lists", function()
            SB3Builder.resetCounter()
            local stage = SB3Builder.createStage()
            local listId = SB3Builder.addList(stage, "empty", {})
            local lengthId = SB3Builder.addVariable(stage, "length", -1)
            local hasItemId = SB3Builder.addVariable(stage, "hasItem", true)

            local hatId, hatBlock = SB3Builder.Events.whenFlagClicked()
            local lenId, lenBlock = SB3Builder.Data.lengthOfList("empty", listId)
            local setLenId, setLenBlock = SB3Builder.createBlock("data_setvariableto", {
                VALUE = SB3Builder.blockInput(lenId)
            }, {
                VARIABLE = SB3Builder.field("length", lengthId)
            })
            local containsId, containsBlock = SB3Builder.Data.listContainsItem("anything", "empty", listId)
            local setContainsId, setContainsBlock = SB3Builder.createBlock("data_setvariableto", {
                VALUE = SB3Builder.blockInput(containsId)
            }, {
                VARIABLE = SB3Builder.field("hasItem", hasItemId)
            })

            SB3Builder.addBlock(stage, hatId, hatBlock)
            SB3Builder.addBlock(stage, lenId, lenBlock)
            SB3Builder.addBlock(stage, setLenId, setLenBlock)
            SB3Builder.addBlock(stage, containsId, containsBlock)
            SB3Builder.addBlock(stage, setContainsId, setContainsBlock)
            SB3Builder.linkBlocks(stage, {hatId, setLenId, setContainsId})

            local projectJson = SB3Builder.createProject({stage})
            local project = ProjectModel:new(projectJson, {})
            local runtime = Runtime:new(project)
            runtime:initialize()

            runtime:broadcastGreenFlag()
            -- Safe execution with iteration limit to prevent infinite loops
            local maxIterations = 100
            local iterations = 0
            while #runtime:getActiveThreads() > 0 and iterations < maxIterations do
                runtime:update(1/60)
                iterations = iterations + 1
            end

            local length = runtime.stage:lookupVariableByNameAndType("length")
            local hasItem = runtime.stage:lookupVariableByNameAndType("hasItem")
            expect(length.value).to.equal(0)
            expect(hasItem.value).to.equal(false)
        end)

        it("should handle variable operations with different data types", function()
            SB3Builder.resetCounter()
            local stage = SB3Builder.createStage()
            local var1Id = SB3Builder.addVariable(stage, "var1", 0)
            local var2Id = SB3Builder.addVariable(stage, "var2", 0)
            local var3Id = SB3Builder.addVariable(stage, "var3", 0)

            local hatId, hatBlock = SB3Builder.Events.whenFlagClicked()
            -- Set to string
            local set1Id, set1Block = SB3Builder.Data.setVariable("var1", "hello", var1Id)
            -- Set to boolean (true becomes 1, false becomes 0 in Scratch)
            local set2Id, set2Block = SB3Builder.Data.setVariable("var2", true, var2Id)
            -- Set to float
            local set3Id, set3Block = SB3Builder.Data.setVariable("var3", 3.14, var3Id)

            SB3Builder.addBlock(stage, hatId, hatBlock)
            SB3Builder.addBlock(stage, set1Id, set1Block)
            SB3Builder.addBlock(stage, set2Id, set2Block)
            SB3Builder.addBlock(stage, set3Id, set3Block)
            SB3Builder.linkBlocks(stage, {hatId, set1Id, set2Id, set3Id})

            local projectJson = SB3Builder.createProject({stage})
            local project = ProjectModel:new(projectJson, {})
            local runtime = Runtime:new(project)
            runtime:initialize()

            runtime:broadcastGreenFlag()
            -- Safe execution with iteration limit to prevent infinite loops
            local maxIterations = 100
            local iterations = 0
            while #runtime:getActiveThreads() > 0 and iterations < maxIterations do
                runtime:update(1/60)
                iterations = iterations + 1
            end

            local var1 = runtime.stage:lookupVariableByNameAndType("var1")
            local var2 = runtime.stage:lookupVariableByNameAndType("var2")
            local var3 = runtime.stage:lookupVariableByNameAndType("var3")
            expect(var1.value).to.equal("hello")
            expect(var2.value).to.equal("true")
            expect(var3.value).to.equal(3.14)
        end)

        it("should find item position with cross-type comparison", function()
            SB3Builder.resetCounter()
            local stage = SB3Builder.createStage()
            local listId = SB3Builder.addList(stage, "mixed", {1, "2", 3.0, "4"})
            local pos1Id = SB3Builder.addVariable(stage, "pos1", 0)
            local pos2Id = SB3Builder.addVariable(stage, "pos2", 0)

            local hatId, hatBlock = SB3Builder.Events.whenFlagClicked()
            -- Find string "1" (should match number 1 at position 1)
            local itemNum1Id, itemNum1Block = SB3Builder.Data.itemNumOfList("1", "mixed", listId)
            local set1Id, set1Block = SB3Builder.createBlock("data_setvariableto", {
                VALUE = SB3Builder.blockInput(itemNum1Id)
            }, {
                VARIABLE = SB3Builder.field("pos1", pos1Id)
            })
            -- Find number 3 (should match 3.0 at position 3)
            local itemNum2Id, itemNum2Block = SB3Builder.Data.itemNumOfList(3, "mixed", listId)
            local set2Id, set2Block = SB3Builder.createBlock("data_setvariableto", {
                VALUE = SB3Builder.blockInput(itemNum2Id)
            }, {
                VARIABLE = SB3Builder.field("pos2", pos2Id)
            })

            SB3Builder.addBlock(stage, hatId, hatBlock)
            SB3Builder.addBlock(stage, itemNum1Id, itemNum1Block)
            SB3Builder.addBlock(stage, set1Id, set1Block)
            SB3Builder.addBlock(stage, itemNum2Id, itemNum2Block)
            SB3Builder.addBlock(stage, set2Id, set2Block)
            SB3Builder.linkBlocks(stage, {hatId, set1Id, set2Id})

            local projectJson = SB3Builder.createProject({stage})
            local project = ProjectModel:new(projectJson, {})
            local runtime = Runtime:new(project)
            runtime:initialize()

            runtime:broadcastGreenFlag()
            -- Safe execution with iteration limit to prevent infinite loops
            local maxIterations = 100
            local iterations = 0
            while #runtime:getActiveThreads() > 0 and iterations < maxIterations do
                runtime:update(1/60)
                iterations = iterations + 1
            end

            local pos1 = runtime.stage:lookupVariableByNameAndType("pos1")
            local pos2 = runtime.stage:lookupVariableByNameAndType("pos2")
            expect(pos1.value).to.equal(1) -- Found "1" at position 1
            expect(pos2.value).to.equal(3) -- Found 3 (matching 3.0) at position 3
        end)

        it("should return 0 when searching for non-existent item", function()
            SB3Builder.resetCounter()
            local stage = SB3Builder.createStage()
            local listId = SB3Builder.addList(stage, "test", {"a", "b", "c"})
            local positionId = SB3Builder.addVariable(stage, "position", -1)

            local hatId, hatBlock = SB3Builder.Events.whenFlagClicked()
            local itemNumId, itemNumBlock = SB3Builder.Data.itemNumOfList("z", "test", listId)
            local setId, setBlock = SB3Builder.createBlock("data_setvariableto", {
                VALUE = SB3Builder.blockInput(itemNumId)
            }, {
                VARIABLE = SB3Builder.field("position", positionId)
            })

            SB3Builder.addBlock(stage, hatId, hatBlock)
            SB3Builder.addBlock(stage, itemNumId, itemNumBlock)
            SB3Builder.addBlock(stage, setId, setBlock)
            SB3Builder.linkBlocks(stage, {hatId, setId})

            local projectJson = SB3Builder.createProject({stage})
            local project = ProjectModel:new(projectJson, {})
            local runtime = Runtime:new(project)
            runtime:initialize()

            runtime:broadcastGreenFlag()
            -- Safe execution with iteration limit to prevent infinite loops
            local maxIterations = 100
            local iterations = 0
            while #runtime:getActiveThreads() > 0 and iterations < maxIterations do
                runtime:update(1/60)
                iterations = iterations + 1
            end

            local position = runtime.stage:lookupVariableByNameAndType("position")
            expect(position.value).to.equal(0) -- Should return 0 for non-existent item
        end)

        it("should use Scratch comparison semantics for case-insensitive matching", function()
            SB3Builder.resetCounter()
            local stage = SB3Builder.createStage()
            local listId = SB3Builder.addList(stage, "test", {"jump", "Jump", "JUMP"})
            local pos1Id = SB3Builder.addVariable(stage, "pos1", 0)
            local pos2Id = SB3Builder.addVariable(stage, "pos2", 0)
            local pos3Id = SB3Builder.addVariable(stage, "pos3", 0)

            local hatId, hatBlock = SB3Builder.Events.whenFlagClicked()

            -- Search for "Jump" (should find first occurrence "jump" at position 1)
            local itemNum1Id, itemNum1Block = SB3Builder.Data.itemNumOfList("Jump", "test", listId)
            local set1Id, set1Block = SB3Builder.createBlock("data_setvariableto", {
                VALUE = SB3Builder.blockInput(itemNum1Id)
            }, {
                VARIABLE = SB3Builder.field("pos1", pos1Id)
            })

            -- Search for "jump" (should find first occurrence at position 1)
            local itemNum2Id, itemNum2Block = SB3Builder.Data.itemNumOfList("jump", "test", listId)
            local set2Id, set2Block = SB3Builder.createBlock("data_setvariableto", {
                VALUE = SB3Builder.blockInput(itemNum2Id)
            }, {
                VARIABLE = SB3Builder.field("pos2", pos2Id)
            })

            -- Search for "JUMP" (should find first occurrence at position 1)
            local itemNum3Id, itemNum3Block = SB3Builder.Data.itemNumOfList("JUMP", "test", listId)
            local set3Id, set3Block = SB3Builder.createBlock("data_setvariableto", {
                VALUE = SB3Builder.blockInput(itemNum3Id)
            }, {
                VARIABLE = SB3Builder.field("pos3", pos3Id)
            })

            SB3Builder.addBlock(stage, hatId, hatBlock)
            SB3Builder.addBlock(stage, itemNum1Id, itemNum1Block)
            SB3Builder.addBlock(stage, set1Id, set1Block)
            SB3Builder.addBlock(stage, itemNum2Id, itemNum2Block)
            SB3Builder.addBlock(stage, set2Id, set2Block)
            SB3Builder.addBlock(stage, itemNum3Id, itemNum3Block)
            SB3Builder.addBlock(stage, set3Id, set3Block)
            SB3Builder.linkBlocks(stage, {hatId, set1Id, set2Id, set3Id})

            local projectJson = SB3Builder.createProject({stage})
            local project = ProjectModel:new(projectJson, {})
            local runtime = Runtime:new(project)
            runtime:initialize()

            runtime:broadcastGreenFlag()
            -- Safe execution with iteration limit to prevent infinite loops
            local maxIterations = 100
            local iterations = 0
            while #runtime:getActiveThreads() > 0 and iterations < maxIterations do
                runtime:update(1/60)
                iterations = iterations + 1
            end

            local pos1 = runtime.stage:lookupVariableByNameAndType("pos1")
            local pos2 = runtime.stage:lookupVariableByNameAndType("pos2")
            local pos3 = runtime.stage:lookupVariableByNameAndType("pos3")

            -- All should find the first occurrence (case-insensitive)
            expect(pos1.value).to.equal(1)
            expect(pos2.value).to.equal(1)
            expect(pos3.value).to.equal(1)
        end)

        it("should use Scratch comparison semantics for type-insensitive matching", function()
            SB3Builder.resetCounter()
            local stage = SB3Builder.createStage()
            local listId = SB3Builder.addList(stage, "test", {"123", 123, 800, "800"})
            local pos1Id = SB3Builder.addVariable(stage, "pos1", 0)
            local pos2Id = SB3Builder.addVariable(stage, "pos2", 0)
            local pos3Id = SB3Builder.addVariable(stage, "pos3", 0)

            local hatId, hatBlock = SB3Builder.Events.whenFlagClicked()

            -- Search for number 123 (should find string "123" at position 1)
            local itemNum1Id, itemNum1Block = SB3Builder.Data.itemNumOfList(123, "test", listId)
            local set1Id, set1Block = SB3Builder.createBlock("data_setvariableto", {
                VALUE = SB3Builder.blockInput(itemNum1Id)
            }, {
                VARIABLE = SB3Builder.field("pos1", pos1Id)
            })

            -- Search for string "123" (should find first occurrence at position 1)
            local itemNum2Id, itemNum2Block = SB3Builder.Data.itemNumOfList("123", "test", listId)
            local set2Id, set2Block = SB3Builder.createBlock("data_setvariableto", {
                VALUE = SB3Builder.blockInput(itemNum2Id)
            }, {
                VARIABLE = SB3Builder.field("pos2", pos2Id)
            })

            -- Search for string "800" (should find number 800 at position 3)
            local itemNum3Id, itemNum3Block = SB3Builder.Data.itemNumOfList("800", "test", listId)
            local set3Id, set3Block = SB3Builder.createBlock("data_setvariableto", {
                VALUE = SB3Builder.blockInput(itemNum3Id)
            }, {
                VARIABLE = SB3Builder.field("pos3", pos3Id)
            })

            SB3Builder.addBlock(stage, hatId, hatBlock)
            SB3Builder.addBlock(stage, itemNum1Id, itemNum1Block)
            SB3Builder.addBlock(stage, set1Id, set1Block)
            SB3Builder.addBlock(stage, itemNum2Id, itemNum2Block)
            SB3Builder.addBlock(stage, set2Id, set2Block)
            SB3Builder.addBlock(stage, itemNum3Id, itemNum3Block)
            SB3Builder.addBlock(stage, set3Id, set3Block)
            SB3Builder.linkBlocks(stage, {hatId, set1Id, set2Id, set3Id})

            local projectJson = SB3Builder.createProject({stage})
            local project = ProjectModel:new(projectJson, {})
            local runtime = Runtime:new(project)
            runtime:initialize()

            runtime:broadcastGreenFlag()
            -- Safe execution with iteration limit to prevent infinite loops
            local maxIterations = 100
            local iterations = 0
            while #runtime:getActiveThreads() > 0 and iterations < maxIterations do
                runtime:update(1/60)
                iterations = iterations + 1
            end

            local pos1 = runtime.stage:lookupVariableByNameAndType("pos1")
            local pos2 = runtime.stage:lookupVariableByNameAndType("pos2")
            local pos3 = runtime.stage:lookupVariableByNameAndType("pos3")

            -- Should find based on type-insensitive comparison
            expect(pos1.value).to.equal(1) -- 123 finds "123"
            expect(pos2.value).to.equal(1) -- "123" finds "123"
            expect(pos3.value).to.equal(3) -- "800" finds 800
        end)
    end)

    describe("List Contents Display", function()
        it("should join single characters without spaces", function()
            SB3Builder.resetCounter()
            local stage = SB3Builder.createStage()
            local listId = SB3Builder.addList(stage, "chars", {"a", "b", "c"})
            local resultId = SB3Builder.addVariable(stage, "result", "")

            local hatId, hatBlock = SB3Builder.Events.whenFlagClicked()
            local contentsId, contentsBlock = SB3Builder.Data.listContents("chars", listId)
            local setId, setBlock = SB3Builder.createBlock("data_setvariableto", {
                VALUE = SB3Builder.blockInput(contentsId)
            }, {
                VARIABLE = SB3Builder.field("result", resultId)
            })

            SB3Builder.addBlock(stage, hatId, hatBlock)
            SB3Builder.addBlock(stage, contentsId, contentsBlock)
            SB3Builder.addBlock(stage, setId, setBlock)
            SB3Builder.linkBlocks(stage, {hatId, setId})

            local projectJson = SB3Builder.createProject({stage})
            local project = ProjectModel:new(projectJson, {})
            local runtime = Runtime:new(project)
            runtime:initialize()

            runtime:broadcastGreenFlag()
            -- Safe execution with iteration limit to prevent infinite loops
            local maxIterations = 100
            local iterations = 0
            while #runtime:getActiveThreads() > 0 and iterations < maxIterations do
                runtime:update(1/60)
                iterations = iterations + 1
            end

            local result = runtime.stage:lookupVariableByNameAndType("result")
            expect(result.value).to.equal("abc")
        end)

        it("should join multi-character strings with spaces", function()
            SB3Builder.resetCounter()
            local stage = SB3Builder.createStage()
            local listId = SB3Builder.addList(stage, "words", {"hello", "world", "test"})
            local resultId = SB3Builder.addVariable(stage, "result", "")

            local hatId, hatBlock = SB3Builder.Events.whenFlagClicked()
            local contentsId, contentsBlock = SB3Builder.Data.listContents("words", listId)
            local setId, setBlock = SB3Builder.createBlock("data_setvariableto", {
                VALUE = SB3Builder.blockInput(contentsId)
            }, {
                VARIABLE = SB3Builder.field("result", resultId)
            })

            SB3Builder.addBlock(stage, hatId, hatBlock)
            SB3Builder.addBlock(stage, contentsId, contentsBlock)
            SB3Builder.addBlock(stage, setId, setBlock)
            SB3Builder.linkBlocks(stage, {hatId, setId})

            local projectJson = SB3Builder.createProject({stage})
            local project = ProjectModel:new(projectJson, {})
            local runtime = Runtime:new(project)
            runtime:initialize()

            runtime:broadcastGreenFlag()
            -- Safe execution with iteration limit to prevent infinite loops
            local maxIterations = 100
            local iterations = 0
            while #runtime:getActiveThreads() > 0 and iterations < maxIterations do
                runtime:update(1/60)
                iterations = iterations + 1
            end

            local result = runtime.stage:lookupVariableByNameAndType("result")
            expect(result.value).to.equal("hello world test")
        end)

        it("should handle mixed single chars and multi-char strings with spaces", function()
            SB3Builder.resetCounter()
            local stage = SB3Builder.createStage()
            local listId = SB3Builder.addList(stage, "mixed", {"a", "hello", "b"})
            local resultId = SB3Builder.addVariable(stage, "result", "")

            local hatId, hatBlock = SB3Builder.Events.whenFlagClicked()
            local contentsId, contentsBlock = SB3Builder.Data.listContents("mixed", listId)
            local setId, setBlock = SB3Builder.createBlock("data_setvariableto", {
                VALUE = SB3Builder.blockInput(contentsId)
            }, {
                VARIABLE = SB3Builder.field("result", resultId)
            })

            SB3Builder.addBlock(stage, hatId, hatBlock)
            SB3Builder.addBlock(stage, contentsId, contentsBlock)
            SB3Builder.addBlock(stage, setId, setBlock)
            SB3Builder.linkBlocks(stage, {hatId, setId})

            local projectJson = SB3Builder.createProject({stage})
            local project = ProjectModel:new(projectJson, {})
            local runtime = Runtime:new(project)
            runtime:initialize()

            runtime:broadcastGreenFlag()
            -- Safe execution with iteration limit to prevent infinite loops
            local maxIterations = 100
            local iterations = 0
            while #runtime:getActiveThreads() > 0 and iterations < maxIterations do
                runtime:update(1/60)
                iterations = iterations + 1
            end

            local result = runtime.stage:lookupVariableByNameAndType("result")
            expect(result.value).to.equal("a hello b") -- Uses spaces because not all are single chars
        end)
    end)

    describe("List Modification Operations", function()
        it("should add items to list correctly", function()
            SB3Builder.resetCounter()
            local stage = SB3Builder.createStage()
            local listId = SB3Builder.addList(stage, "testList", {})

            local hatId, hatBlock = SB3Builder.Events.whenFlagClicked()
            local add1Id, add1Block = SB3Builder.Data.addToList("first", "testList", listId)
            local add2Id, add2Block = SB3Builder.Data.addToList("second", "testList", listId)
            local lenId, lenBlock = SB3Builder.Data.lengthOfList("testList", listId)
            local resultId = SB3Builder.addVariable(stage, "length", 0)
            local setId, setBlock = SB3Builder.createBlock("data_setvariableto", {
                VALUE = SB3Builder.blockInput(lenId)
            }, {
                VARIABLE = SB3Builder.field("length", resultId)
            })

            SB3Builder.addBlock(stage, hatId, hatBlock)
            SB3Builder.addBlock(stage, add1Id, add1Block)
            SB3Builder.addBlock(stage, add2Id, add2Block)
            SB3Builder.addBlock(stage, lenId, lenBlock)
            SB3Builder.addBlock(stage, setId, setBlock)
            SB3Builder.linkBlocks(stage, {hatId, add1Id, add2Id, setId})

            local projectJson = SB3Builder.createProject({stage})
            local project = ProjectModel:new(projectJson, {})
            local runtime = Runtime:new(project)
            runtime:initialize()

            runtime:broadcastGreenFlag()
            -- Safe execution with iteration limit to prevent infinite loops
            local maxIterations = 100
            local iterations = 0
            while #runtime:getActiveThreads() > 0 and iterations < maxIterations do
                runtime:update(1/60)
                iterations = iterations + 1
            end

            local length = runtime.stage:lookupVariableByNameAndType("length")
            expect(length.value).to.equal(2)
        end)

        it("should delete specific list items correctly", function()
            SB3Builder.resetCounter()
            local stage = SB3Builder.createStage()
            local listId = SB3Builder.addList(stage, "testList", {"a", "b", "c", "d"})
            local resultId = SB3Builder.addVariable(stage, "result", "")

            local hatId, hatBlock = SB3Builder.Events.whenFlagClicked()
            -- Delete item at position 2 (should remove "b")
            local delId, delBlock = SB3Builder.Data.deleteFromList(2, "testList", listId)
            -- Get item at position 2 (should now be "c")
            local itemId, itemBlock = SB3Builder.Data.itemOfList(2, "testList", listId)
            local setId, setBlock = SB3Builder.createBlock("data_setvariableto", {
                VALUE = SB3Builder.blockInput(itemId)
            }, {
                VARIABLE = SB3Builder.field("result", resultId)
            })

            SB3Builder.addBlock(stage, hatId, hatBlock)
            SB3Builder.addBlock(stage, delId, delBlock)
            SB3Builder.addBlock(stage, itemId, itemBlock)
            SB3Builder.addBlock(stage, setId, setBlock)
            SB3Builder.linkBlocks(stage, {hatId, delId, setId})

            local projectJson = SB3Builder.createProject({stage})
            local project = ProjectModel:new(projectJson, {})
            local runtime = Runtime:new(project)
            runtime:initialize()

            runtime:broadcastGreenFlag()
            -- Safe execution with iteration limit to prevent infinite loops
            local maxIterations = 100
            local iterations = 0
            while #runtime:getActiveThreads() > 0 and iterations < maxIterations do
                runtime:update(1/60)
                iterations = iterations + 1
            end

            local result = runtime.stage:lookupVariableByNameAndType("result")
            expect(result.value).to.equal("c") -- Position 2 should now be "c" after deleting "b"
        end)

        it("should delete all list items correctly", function()
            SB3Builder.resetCounter()
            local stage = SB3Builder.createStage()
            local listId = SB3Builder.addList(stage, "testList", {"x", "y", "z"})
            local resultId = SB3Builder.addVariable(stage, "length", -1)

            local hatId, hatBlock = SB3Builder.Events.whenFlagClicked()
            local delAllId, delAllBlock = SB3Builder.Data.deleteAllOfList("testList", listId)
            local lenId, lenBlock = SB3Builder.Data.lengthOfList("testList", listId)
            local setId, setBlock = SB3Builder.createBlock("data_setvariableto", {
                VALUE = SB3Builder.blockInput(lenId)
            }, {
                VARIABLE = SB3Builder.field("length", resultId)
            })

            SB3Builder.addBlock(stage, hatId, hatBlock)
            SB3Builder.addBlock(stage, delAllId, delAllBlock)
            SB3Builder.addBlock(stage, lenId, lenBlock)
            SB3Builder.addBlock(stage, setId, setBlock)
            SB3Builder.linkBlocks(stage, {hatId, delAllId, setId})

            local projectJson = SB3Builder.createProject({stage})
            local project = ProjectModel:new(projectJson, {})
            local runtime = Runtime:new(project)
            runtime:initialize()

            runtime:broadcastGreenFlag()
            -- Safe execution with iteration limit to prevent infinite loops
            local maxIterations = 100
            local iterations = 0
            while #runtime:getActiveThreads() > 0 and iterations < maxIterations do
                runtime:update(1/60)
                iterations = iterations + 1
            end

            local length = runtime.stage:lookupVariableByNameAndType("length")
            expect(length.value).to.equal(0)
        end)

        it("should insert items at specific positions correctly", function()
            SB3Builder.resetCounter()
            local stage = SB3Builder.createStage()
            local listId = SB3Builder.addList(stage, "testList", {"a", "c"})
            local resultId = SB3Builder.addVariable(stage, "result", "")

            local hatId, hatBlock = SB3Builder.Events.whenFlagClicked()
            -- Insert "b" at position 2 (between "a" and "c")
            local insertId, insertBlock = SB3Builder.Data.insertAtList(2, "b", "testList", listId)
            -- Get item at position 2 (should be "b")
            local itemId, itemBlock = SB3Builder.Data.itemOfList(2, "testList", listId)
            local setId, setBlock = SB3Builder.createBlock("data_setvariableto", {
                VALUE = SB3Builder.blockInput(itemId)
            }, {
                VARIABLE = SB3Builder.field("result", resultId)
            })

            SB3Builder.addBlock(stage, hatId, hatBlock)
            SB3Builder.addBlock(stage, insertId, insertBlock)
            SB3Builder.addBlock(stage, itemId, itemBlock)
            SB3Builder.addBlock(stage, setId, setBlock)
            SB3Builder.linkBlocks(stage, {hatId, insertId, setId})

            local projectJson = SB3Builder.createProject({stage})
            local project = ProjectModel:new(projectJson, {})
            local runtime = Runtime:new(project)
            runtime:initialize()

            runtime:broadcastGreenFlag()
            -- Safe execution with iteration limit to prevent infinite loops
            local maxIterations = 100
            local iterations = 0
            while #runtime:getActiveThreads() > 0 and iterations < maxIterations do
                runtime:update(1/60)
                iterations = iterations + 1
            end

            local result = runtime.stage:lookupVariableByNameAndType("result")
            expect(result.value).to.equal("b")
        end)

        it("should replace list items correctly", function()
            SB3Builder.resetCounter()
            local stage = SB3Builder.createStage()
            local listId = SB3Builder.addList(stage, "testList", {"old", "keep", "old"})
            local resultId = SB3Builder.addVariable(stage, "result", "")

            local hatId, hatBlock = SB3Builder.Events.whenFlagClicked()
            -- Replace item at position 1 with "new"
            local replaceId, replaceBlock = SB3Builder.Data.replaceItemOfList(1, "new", "testList", listId)
            -- Get item at position 1 (should be "new")
            local itemId, itemBlock = SB3Builder.Data.itemOfList(1, "testList", listId)
            local setId, setBlock = SB3Builder.createBlock("data_setvariableto", {
                VALUE = SB3Builder.blockInput(itemId)
            }, {
                VARIABLE = SB3Builder.field("result", resultId)
            })

            SB3Builder.addBlock(stage, hatId, hatBlock)
            SB3Builder.addBlock(stage, replaceId, replaceBlock)
            SB3Builder.addBlock(stage, itemId, itemBlock)
            SB3Builder.addBlock(stage, setId, setBlock)
            SB3Builder.linkBlocks(stage, {hatId, replaceId, setId})

            local projectJson = SB3Builder.createProject({stage})
            local project = ProjectModel:new(projectJson, {})
            local runtime = Runtime:new(project)
            runtime:initialize()

            runtime:broadcastGreenFlag()
            -- Safe execution with iteration limit to prevent infinite loops
            local maxIterations = 100
            local iterations = 0
            while #runtime:getActiveThreads() > 0 and iterations < maxIterations do
                runtime:update(1/60)
                iterations = iterations + 1
            end

            local result = runtime.stage:lookupVariableByNameAndType("result")
            expect(result.value).to.equal("new")
        end)
    end)

    describe("Variable and List Scope", function()
        it("should handle stage variables accessible to sprites", function()
            SB3Builder.resetCounter()
            local stage = SB3Builder.createStage()
            local sprite = SB3Builder.createSprite("TestSprite")
            local stageVarId = SB3Builder.addVariable(stage, "globalVar", "stage value")

            -- Sprite reads stage variable
            local hatId, hatBlock = SB3Builder.Events.whenFlagClicked()
            local spriteVarId = SB3Builder.addVariable(sprite, "spriteVar", "")
            local varId, varBlock = SB3Builder.Data.variable("globalVar", stageVarId)
            local setId, setBlock = SB3Builder.createBlock("data_setvariableto", {
                VALUE = SB3Builder.blockInput(varId)
            }, {
                VARIABLE = SB3Builder.field("spriteVar", spriteVarId)
            })

            SB3Builder.addBlock(sprite, hatId, hatBlock)
            SB3Builder.addBlock(sprite, varId, varBlock)
            SB3Builder.addBlock(sprite, setId, setBlock)
            SB3Builder.linkBlocks(sprite, {hatId, setId})

            local projectJson = SB3Builder.createProject({stage, sprite})
            local project = ProjectModel:new(projectJson, {})
            local runtime = Runtime:new(project)
            runtime:initialize()

            runtime:broadcastGreenFlag()
            -- Safe execution with iteration limit to prevent infinite loops
            local maxIterations = 100
            local iterations = 0
            while #runtime:getActiveThreads() > 0 and iterations < maxIterations do
                runtime:update(1/60)
                iterations = iterations + 1
            end

            local spriteTarget = runtime:getSpriteTargetByName("TestSprite")
            local spriteVar = spriteTarget:lookupVariableByNameAndType("spriteVar")
            expect(spriteVar.value).to.equal("stage value")
        end)

        it("should handle sprite-local variables", function()
            SB3Builder.resetCounter()
            local stage = SB3Builder.createStage()
            local sprite1 = SB3Builder.createSprite("Sprite1")
            local sprite2 = SB3Builder.createSprite("Sprite2")

            local sprite1VarId = SB3Builder.addVariable(sprite1, "localVar", "sprite1 value")
            local sprite2VarId = SB3Builder.addVariable(sprite2, "localVar", "sprite2 value")
            local resultId = SB3Builder.addVariable(stage, "result", "")

            -- Sprite1 sets stage result to its local variable
            local hat1Id, hat1Block = SB3Builder.Events.whenFlagClicked()
            local var1Id, var1Block = SB3Builder.Data.variable("localVar", sprite1VarId)
            local set1Id, set1Block = SB3Builder.createBlock("data_setvariableto", {
                VALUE = SB3Builder.blockInput(var1Id)
            }, {
                VARIABLE = SB3Builder.field("result", resultId)
            })

            SB3Builder.addBlock(sprite1, hat1Id, hat1Block)
            SB3Builder.addBlock(sprite1, var1Id, var1Block)
            SB3Builder.addBlock(sprite1, set1Id, set1Block)
            SB3Builder.linkBlocks(sprite1, {hat1Id, set1Id})

            local projectJson = SB3Builder.createProject({stage, sprite1, sprite2})
            local project = ProjectModel:new(projectJson, {})
            local runtime = Runtime:new(project)
            runtime:initialize()

            runtime:broadcastGreenFlag()
            -- Safe execution with iteration limit to prevent infinite loops
            local maxIterations = 100
            local iterations = 0
            while #runtime:getActiveThreads() > 0 and iterations < maxIterations do
                runtime:update(1/60)
                iterations = iterations + 1
            end

            local result = runtime.stage:lookupVariableByNameAndType("result")
            expect(result.value).to.equal("sprite1 value")
        end)

        it("should handle list operations with large datasets", function()
            SB3Builder.resetCounter()
            local stage = SB3Builder.createStage()
            local listId = SB3Builder.addList(stage, "bigList", {})
            local countId = SB3Builder.addVariable(stage, "count", 0)

            -- Add 50 items to list then check length
            local hatId, hatBlock = SB3Builder.Events.whenFlagClicked()
            local blocks = {hatId}

            -- Create a chain of add operations
            for i = 1, 50 do
                local addId, addBlock = SB3Builder.Data.addToList(tostring(i), "bigList", listId)
                SB3Builder.addBlock(stage, addId, addBlock)
                table.insert(blocks, addId)
            end

            -- Check final length
            local lenId, lenBlock = SB3Builder.Data.lengthOfList("bigList", listId)
            local setId, setBlock = SB3Builder.createBlock("data_setvariableto", {
                VALUE = SB3Builder.blockInput(lenId)
            }, {
                VARIABLE = SB3Builder.field("count", countId)
            })

            SB3Builder.addBlock(stage, hatId, hatBlock)
            SB3Builder.addBlock(stage, lenId, lenBlock)
            SB3Builder.addBlock(stage, setId, setBlock)
            table.insert(blocks, setId)
            SB3Builder.linkBlocks(stage, blocks)

            local projectJson = SB3Builder.createProject({stage})
            local project = ProjectModel:new(projectJson, {})
            local runtime = Runtime:new(project)
            runtime:initialize()

            runtime:broadcastGreenFlag()
            -- Safe execution with iteration limit to prevent infinite loops
            local maxIterations = 100
            local iterations = 0
            while #runtime:getActiveThreads() > 0 and iterations < maxIterations do
                runtime:update(1/60)
                iterations = iterations + 1
            end

            local count = runtime.stage:lookupVariableByNameAndType("count")
            expect(count.value).to.equal(50)
        end)

        it("should handle basic list index edge cases correctly", function()
            SB3Builder.resetCounter()
            local stage = SB3Builder.createStage()
            local listId = SB3Builder.addList(stage, "testList", {"first", "middle", "last"})
            local resultId = SB3Builder.addVariable(stage, "result", "")

            local hatId, hatBlock = SB3Builder.Events.whenFlagClicked()

            -- Get last item using numeric index 3
            local itemId, itemBlock = SB3Builder.Data.itemOfList(3, "testList", listId)
            local setId, setBlock = SB3Builder.createBlock("data_setvariableto", {
                VALUE = SB3Builder.blockInput(itemId)
            }, {
                VARIABLE = SB3Builder.field("result", resultId)
            })

            SB3Builder.addBlock(stage, hatId, hatBlock)
            SB3Builder.addBlock(stage, itemId, itemBlock)
            SB3Builder.addBlock(stage, setId, setBlock)
            SB3Builder.linkBlocks(stage, {hatId, setId})

            local projectJson = SB3Builder.createProject({stage})
            local project = ProjectModel:new(projectJson, {})
            local runtime = Runtime:new(project)
            runtime:initialize()

            runtime:broadcastGreenFlag()
            -- Safe execution with iteration limit to prevent infinite loops
            local maxIterations = 100
            local iterations = 0
            while #runtime:getActiveThreads() > 0 and iterations < maxIterations do
                runtime:update(1/60)
                iterations = iterations + 1
            end

            local result = runtime.stage:lookupVariableByNameAndType("result")
            expect(result.value).to.equal("last") -- Should get the third item "last"
        end)
    end)

    describe("Algorithm Implementation Tests", function()
        it("should implement bubble sort algorithm for 10 random numbers", function()
            SB3Builder.resetCounter()
            local stage = SB3Builder.createStage()

            local randomNumbers = {}
            for i = 1, 10 do
                randomNumbers[i] = math.random(1, 50)
            end

            local listId = SB3Builder.addList(stage, "numbers", randomNumbers)
            local tempId = SB3Builder.addVariable(stage, "temp", 0)
            local iId = SB3Builder.addVariable(stage, "i", 1)
            local jId = SB3Builder.addVariable(stage, "j", 1)

            local hatId, hatBlock = SB3Builder.Events.whenFlagClicked()

            local outerRepeatId, outerRepeatBlock = SB3Builder.Control.repeat_(10, nil)

            local setJId, setJBlock = SB3Builder.Data.setVariable("j", 1, jId)

            local innerRepeatId, innerRepeatBlock = SB3Builder.Control.repeat_(9, nil)

            local jVarId, jVarBlock = SB3Builder.Data.variable("j", jId)
            local itemJId, itemJBlock = SB3Builder.Data.itemOfList(SB3Builder.blockInput(jVarId), "numbers", listId)

            local jPlus1Id, jPlus1Block = SB3Builder.Operators.add(SB3Builder.blockInput(jVarId), 1)
            local itemJPlus1Id, itemJPlus1Block = SB3Builder.Data.itemOfList(SB3Builder.blockInput(jPlus1Id), "numbers", listId)

            local compareId, compareBlock = SB3Builder.Operators.greaterThan(SB3Builder.blockInput(itemJId), SB3Builder.blockInput(itemJPlus1Id))

            local setTempId, setTempBlock = SB3Builder.Data.setVariable("temp", SB3Builder.blockInput(itemJId), tempId)
            local replaceJId, replaceJBlock = SB3Builder.Data.replaceItemOfList(SB3Builder.blockInput(jVarId), SB3Builder.blockInput(itemJPlus1Id), "numbers", listId)
            local tempVarId, tempVarBlock = SB3Builder.Data.variable("temp", tempId)
            local replaceJPlus1Id, replaceJPlus1Block = SB3Builder.Data.replaceItemOfList(SB3Builder.blockInput(jPlus1Id), SB3Builder.blockInput(tempVarId), "numbers", listId)

            local ifId, ifBlock = SB3Builder.Control.if_(compareId, setTempId)

            -- j = j + 1
            local incJId, incJBlock = SB3Builder.Data.changeVariable("j", 1, jId)

            SB3Builder.addBlock(stage, hatId, hatBlock)
            SB3Builder.addBlock(stage, outerRepeatId, outerRepeatBlock)
            SB3Builder.addBlock(stage, setJId, setJBlock)
            SB3Builder.addBlock(stage, innerRepeatId, innerRepeatBlock)
            SB3Builder.addBlock(stage, jVarId, jVarBlock)
            SB3Builder.addBlock(stage, itemJId, itemJBlock)
            SB3Builder.addBlock(stage, jPlus1Id, jPlus1Block)
            SB3Builder.addBlock(stage, itemJPlus1Id, itemJPlus1Block)
            SB3Builder.addBlock(stage, compareId, compareBlock)
            SB3Builder.addBlock(stage, ifId, ifBlock)
            SB3Builder.addBlock(stage, setTempId, setTempBlock)
            SB3Builder.addBlock(stage, replaceJId, replaceJBlock)
            SB3Builder.addBlock(stage, tempVarId, tempVarBlock)
            SB3Builder.addBlock(stage, replaceJPlus1Id, replaceJPlus1Block)
            SB3Builder.addBlock(stage, incJId, incJBlock)

            SB3Builder.linkBlocks(stage, {hatId, outerRepeatId})

            SB3Builder.linkBlocks(stage, {setJId, innerRepeatId})

            SB3Builder.linkBlocks(stage, {ifId, incJId})

            SB3Builder.linkBlocks(stage, {setTempId, replaceJId, replaceJPlus1Id})

            local Core = require("tests.sb3_builder.core")
            outerRepeatBlock.inputs.SUBSTACK = Core.substackInput(setJId)
            innerRepeatBlock.inputs.SUBSTACK = Core.substackInput(ifId)
            ifBlock.inputs.SUBSTACK = Core.substackInput(setTempId)

            local projectJson = SB3Builder.createProject({stage})
            local project = ProjectModel:new(projectJson, {})
            local runtime = Runtime:new(project)
            runtime:initialize()

            runtime:broadcastGreenFlag()
            local maxIterations = 2000
            local iterations = 0
            while #runtime:getActiveThreads() > 0 and iterations < maxIterations do
                runtime:update(1/60)
                iterations = iterations + 1
            end

            local numbers = runtime.stage:lookupVariableByNameAndType("numbers", "list")
            expect(numbers).to.exist()
            expect(numbers.value).to.exist()
            expect(#numbers.value).to.equal(10)

            local isSorted = true
            for i = 1, 9 do
                local current = tonumber(numbers.value[i])
                local next = tonumber(numbers.value[i + 1])
                if current > next then
                    isSorted = false
                    break
                end
            end

            expect(isSorted).to.be.truthy()

            local originalSorted = {}
            for i, v in ipairs(randomNumbers) do
                originalSorted[i] = v
            end
            table.sort(originalSorted)

            local resultSorted = {}
            for i, v in ipairs(numbers.value) do
                resultSorted[i] = tonumber(v)
            end

            for i = 1, 10 do
                expect(resultSorted[i]).to.equal(originalSorted[i])
            end
        end)
    end)
end)