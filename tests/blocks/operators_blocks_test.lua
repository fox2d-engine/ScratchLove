-- Operators Blocks Tests
-- Tests for operator block implementations based on native Scratch tests
-- This file replicates all test cases from blocks_operators.js and blocks_operators_infinity.js

-- Import testing framework
local lust = require("tests.lust")
local describe, it, expect = lust.describe, lust.it, lust.expect

-- Import project components
local SB3Builder = require("tests.sb3_builder")
local ProjectModel = require("parser.project_model")
local Runtime = require("vm.runtime")

-- Helper function to execute a single operator block and get result
local function executeOperatorBlock(opcode, inputs, fields)
    SB3Builder.resetCounter()
    local stage = SB3Builder.createStage()
    local resultId = SB3Builder.addVariable(stage, "result", "UNSET")

    -- Create the operator block using SB3Builder.createBlock
    local operatorId, operatorBlock = SB3Builder.createBlock(opcode, inputs, fields)

    -- Create script: when flag clicked -> set result to operator result
    local hatId, hatBlock = SB3Builder.Events.whenFlagClicked()
    local setId, setBlock = SB3Builder.createBlock("data_setvariableto", {
        VALUE = SB3Builder.blockInput(operatorId)
    }, {
        VARIABLE = SB3Builder.field("result", resultId)
    })

    SB3Builder.addBlock(stage, hatId, hatBlock)
    SB3Builder.addBlock(stage, operatorId, operatorBlock)
    SB3Builder.addBlock(stage, setId, setBlock)
    SB3Builder.linkBlocks(stage, {hatId, setId})

    local projectJson = SB3Builder.createProject({stage})
    local project = ProjectModel:new(projectJson, {})
    local runtime = Runtime:new(project)
    runtime:initialize()

    runtime:broadcastGreenFlag()
    local iterations = 0
    while #runtime:getActiveThreads() > 0 and iterations < 100 do
        runtime:update(1/60)
        iterations = iterations + 1
    end

    local result = runtime.stage:lookupVariableByNameAndType("result")
    return result and result.value
end

-- Helper function to create primitive input
local function primitiveInput(value, primitiveType)
    return SB3Builder.primitiveInput(value, primitiveType or 10) -- TEXT_PRIMITIVE = 10
end

-- Helper function to create math number input
local function mathInput(value)
    return SB3Builder.primitiveInput(value, 5) -- MATH_NUM_PRIMITIVE = 5
end

describe("Operator Blocks", function()
    describe("Basic Math Operations", function()
        it("should add two numbers correctly", function()
            local result = executeOperatorBlock("operator_add", {
                NUM1 = mathInput('1'),
                NUM2 = mathInput('1')
            })
            expect(result).to.equal(2)
        end)

        it("should handle string addition", function()
            local result = executeOperatorBlock("operator_add", {
                NUM1 = mathInput('foo'),
                NUM2 = mathInput('bar')
            })
            expect(result).to.equal(0)
        end)

        it("should subtract two numbers correctly", function()
            local result = executeOperatorBlock("operator_subtract", {
                NUM1 = mathInput('1'),
                NUM2 = mathInput('1')
            })
            expect(result).to.equal(0)
        end)

        it("should handle string subtraction", function()
            local result = executeOperatorBlock("operator_subtract", {
                NUM1 = mathInput('foo'),
                NUM2 = mathInput('bar')
            })
            expect(result).to.equal(0)
        end)

        it("should multiply two numbers correctly", function()
            local result = executeOperatorBlock("operator_multiply", {
                NUM1 = mathInput('2'),
                NUM2 = mathInput('2')
            })
            expect(result).to.equal(4)
        end)

        it("should handle string multiplication", function()
            local result = executeOperatorBlock("operator_multiply", {
                NUM1 = mathInput('foo'),
                NUM2 = mathInput('bar')
            })
            expect(result).to.equal(0)
        end)

        it("should divide two numbers correctly", function()
            local result = executeOperatorBlock("operator_divide", {
                NUM1 = mathInput('2'),
                NUM2 = mathInput('2')
            })
            expect(result).to.equal(1)
        end)

        it("should handle string division", function()
            local result = executeOperatorBlock("operator_divide", {
                NUM1 = mathInput('foo'),
                NUM2 = mathInput('bar')
            })
            expect(tostring(result)).to.equal("nan")
        end)

        it("should handle division by zero: (1) / (0) = Infinity", function()
            local result = executeOperatorBlock("operator_divide", {
                NUM1 = mathInput('1'),
                NUM2 = mathInput('0')
            })
            expect(result).to.equal(math.huge)
        end)
    end)

    describe("Infinity Division Tests", function()
        it("should handle division with Infinity", function()
            -- "Infinity" / 111 = Infinity
            local result1 = executeOperatorBlock("operator_divide", {
                NUM1 = mathInput('Infinity'),
                NUM2 = mathInput(111)
            })
            expect(result1).to.equal(math.huge)

            -- "INFINITY" / 222 = 0 (treated as non-numeric string)
            local result2 = executeOperatorBlock("operator_divide", {
                NUM1 = mathInput('INFINITY'),
                NUM2 = mathInput(222)
            })
            expect(result2).to.equal(0)

            -- Infinity / 333 = Infinity (use string representation since JSON can't handle math.huge)
            local result3 = executeOperatorBlock("operator_divide", {
                NUM1 = mathInput('Infinity'),
                NUM2 = mathInput(333)
            })
            expect(result3).to.equal(math.huge)

            -- 111 / "Infinity" = 0
            local result4 = executeOperatorBlock("operator_divide", {
                NUM1 = mathInput(111),
                NUM2 = mathInput('Infinity')
            })
            expect(result4).to.equal(0)

            -- 222 / "INFINITY" = Infinity (string treated as non-numeric, becomes 0, so 222/0)
            local result5 = executeOperatorBlock("operator_divide", {
                NUM1 = mathInput(222),
                NUM2 = mathInput('INFINITY')
            })
            expect(result5).to.equal(math.huge)

                        -- 333 / Infinity = 0
            local result4 = executeOperatorBlock("operator_divide", {
                NUM1 = mathInput(333),
                NUM2 = mathInput('Infinity')
            })
            expect(result4).to.equal(0)
        end)

        it("should handle negative infinity division", function()
            -- "-Infinity" / 111 = -Infinity
            local result1 = executeOperatorBlock("operator_divide", {
                NUM1 = mathInput('-Infinity'),
                NUM2 = mathInput(111)
            })
            expect(result1).to.equal(-math.huge)

            -- "-INFINITY" / 222 = 0
            local result2 = executeOperatorBlock("operator_divide", {
                NUM1 = mathInput('-INFINITY'),
                NUM2 = mathInput(222)
            })
            expect(result2).to.equal(0)

            -- -Infinity / 333 = -Infinity
            local result3 = executeOperatorBlock("operator_divide", {
                NUM1 = mathInput('-Infinity'),
                NUM2 = mathInput(333)
            })
            expect(result3).to.equal(-math.huge)

            -- 111 / "-Infinity" = 0
            local result4 = executeOperatorBlock("operator_divide", {
                NUM1 = mathInput(111),
                NUM2 = mathInput('-Infinity')
            })
            expect(result4).to.equal(0)

            -- 222 / "-INFINITY" = Infinity (string becomes 0, so 222/0)
            local result5 = executeOperatorBlock("operator_divide", {
                NUM1 = mathInput(222),
                NUM2 = mathInput('-INFINITY')
            })
            expect(result5).to.equal(math.huge)

            -- 333 / -Infinity = 0
            local result6 = executeOperatorBlock("operator_divide", {
                NUM1 = mathInput(333),
                NUM2 = mathInput('-Infinity')
            })
            expect(result6).to.equal(0)
        end)
    end)

    describe("Infinity Multiplication Tests", function()
        it("should multiply Infinity with numbers", function()
            -- "Infinity" * 111 = Infinity
            local result1 = executeOperatorBlock("operator_multiply", {
                NUM1 = mathInput('Infinity'),
                NUM2 = mathInput(111)
            })
            expect(result1).to.equal(math.huge)

            -- "INFINITY" * 222 = 0
            local result2 = executeOperatorBlock("operator_multiply", {
                NUM1 = mathInput('INFINITY'),
                NUM2 = mathInput(222)
            })
            expect(result2).to.equal(0)

            -- Infinity * 333 = Infinity
            local result3 = executeOperatorBlock("operator_multiply", {
                NUM1 = mathInput(math.huge),
                NUM2 = mathInput(333)
            })
            expect(result3).to.equal(math.huge)

            -- "-Infinity" * 111 = -Infinity
            local result4 = executeOperatorBlock("operator_multiply", {
                NUM1 = mathInput('-Infinity'),
                NUM2 = mathInput(111)
            })
            expect(result4).to.equal(-math.huge)

            -- "-INFINITY" * 222 = 0
            local result5 = executeOperatorBlock("operator_multiply", {
                NUM1 = mathInput('-INFINITY'),
                NUM2 = mathInput(222)
            })
            expect(result5).to.equal(0)

            -- -Infinity * 333 = -Infinity
            local result6 = executeOperatorBlock("operator_multiply", {
                NUM1 = mathInput(-math.huge),
                NUM2 = mathInput(333)
            })
            expect(result6).to.equal(-math.huge)

            -- -Infinity * Infinity = -Infinity
            local result7 = executeOperatorBlock("operator_multiply", {
                NUM1 = mathInput(-math.huge),
                NUM2 = mathInput(math.huge)
            })
            expect(result7).to.equal(-math.huge)

            -- Infinity * 0 = NaN
            local result8 = executeOperatorBlock("operator_multiply", {
                NUM1 = mathInput(math.huge),
                NUM2 = mathInput(0)
            })
            expect(tostring(result8)).to.equal("nan")
        end)
    end)

    describe("Infinity Addition Tests", function()
        it("should add Infinity to a number", function()
            -- "Infinity" + 111 = Infinity
            local result1 = executeOperatorBlock("operator_add", {
                NUM1 = mathInput('Infinity'),
                NUM2 = mathInput(111)
            })
            expect(result1).to.equal(math.huge)

            -- "INFINITY" + 222 = 222
            local result2 = executeOperatorBlock("operator_add", {
                NUM1 = mathInput('INFINITY'),
                NUM2 = mathInput(222)
            })
            expect(result2).to.equal(222)

            -- Infinity + 333 = Infinity
            local result3 = executeOperatorBlock("operator_add", {
                NUM1 = mathInput(math.huge),
                NUM2 = mathInput(333)
            })
            expect(result3).to.equal(math.huge)

            -- "-Infinity" + 111 = -Infinity
            local result4 = executeOperatorBlock("operator_add", {
                NUM1 = mathInput('-Infinity'),
                NUM2 = mathInput(111)
            })
            expect(result4).to.equal(-math.huge)

            -- "-INFINITY" + 222 = 222
            local result5 = executeOperatorBlock("operator_add", {
                NUM1 = mathInput('-INFINITY'),
                NUM2 = mathInput(222)
            })
            expect(result5).to.equal(222)

            -- -Infinity + 333 = -Infinity
            local result6 = executeOperatorBlock("operator_add", {
                NUM1 = mathInput(-math.huge),
                NUM2 = mathInput(333)
            })
            expect(result6).to.equal(-math.huge)

            -- -Infinity + Infinity = NaN
            local result7 = executeOperatorBlock("operator_add", {
                NUM1 = mathInput(-math.huge),
                NUM2 = mathInput(math.huge)
            })
            expect(tostring(result7)).to.equal("nan")
        end)
    end)

    describe("Infinity Subtraction Tests", function()
        it("should subtract Infinity with a number", function()
            -- "Infinity" - 111 = Infinity
            local result1 = executeOperatorBlock("operator_subtract", {
                NUM1 = mathInput('Infinity'),
                NUM2 = mathInput(111)
            })
            expect(result1).to.equal(math.huge)

            -- "INFINITY" - 222 = -222
            local result2 = executeOperatorBlock("operator_subtract", {
                NUM1 = mathInput('INFINITY'),
                NUM2 = mathInput(222)
            })
            expect(result2).to.equal(-222)

            -- Infinity - 333 = Infinity
            local result3 = executeOperatorBlock("operator_subtract", {
                NUM1 = mathInput(math.huge),
                NUM2 = mathInput(333)
            })
            expect(result3).to.equal(math.huge)

            -- 111 - "Infinity" = -Infinity
            local result4 = executeOperatorBlock("operator_subtract", {
                NUM1 = mathInput(111),
                NUM2 = mathInput('Infinity')
            })
            expect(result4).to.equal(-math.huge)

            -- 222 - "INFINITY" = 222
            local result5 = executeOperatorBlock("operator_subtract", {
                NUM1 = mathInput(222),
                NUM2 = mathInput('INFINITY')
            })
            expect(result5).to.equal(222)

            -- 333 - Infinity = -Infinity
            local result6 = executeOperatorBlock("operator_subtract", {
                NUM1 = mathInput(333),
                NUM2 = mathInput(math.huge)
            })
            expect(result6).to.equal(-math.huge)

            -- Infinity - Infinity = NaN
            local result7 = executeOperatorBlock("operator_subtract", {
                NUM1 = mathInput(math.huge),
                NUM2 = mathInput(math.huge)
            })
            expect(tostring(result7)).to.equal("nan")
        end)
    end)

    describe("Comparison Operations", function()
        it("should handle less than comparisons", function()
            local result1 = executeOperatorBlock("operator_lt", {
                OPERAND1 = primitiveInput('1'),
                OPERAND2 = primitiveInput('2')
            })
            expect(result1).to.equal(true)

            local result2 = executeOperatorBlock("operator_lt", {
                OPERAND1 = primitiveInput('2'),
                OPERAND2 = primitiveInput('1')
            })
            expect(result2).to.equal(false)

            local result3 = executeOperatorBlock("operator_lt", {
                OPERAND1 = primitiveInput('1'),
                OPERAND2 = primitiveInput('1')
            })
            expect(result3).to.equal(false)

            local result4 = executeOperatorBlock("operator_lt", {
                OPERAND1 = primitiveInput('10'),
                OPERAND2 = primitiveInput('2')
            })
            expect(result4).to.equal(false)

            local result5 = executeOperatorBlock("operator_lt", {
                OPERAND1 = primitiveInput('a'),
                OPERAND2 = primitiveInput('z')
            })
            expect(result5).to.equal(true)
        end)

        it("should handle equals comparisons", function()
            local result1 = executeOperatorBlock("operator_equals", {
                OPERAND1 = primitiveInput('1'),
                OPERAND2 = primitiveInput('2')
            })
            expect(result1).to.equal(false)

            local result2 = executeOperatorBlock("operator_equals", {
                OPERAND1 = primitiveInput('2'),
                OPERAND2 = primitiveInput('1')
            })
            expect(result2).to.equal(false)

            local result3 = executeOperatorBlock("operator_equals", {
                OPERAND1 = primitiveInput('1'),
                OPERAND2 = primitiveInput('1')
            })
            expect(result3).to.equal(true)

            local result4 = executeOperatorBlock("operator_equals", {
                OPERAND1 = primitiveInput('あ'),
                OPERAND2 = primitiveInput('ア')
            })
            expect(result4).to.equal(false)
        end)

        it("should handle greater than comparisons", function()
            local result1 = executeOperatorBlock("operator_gt", {
                OPERAND1 = primitiveInput('1'),
                OPERAND2 = primitiveInput('2')
            })
            expect(result1).to.equal(false)

            local result2 = executeOperatorBlock("operator_gt", {
                OPERAND1 = primitiveInput('2'),
                OPERAND2 = primitiveInput('1')
            })
            expect(result2).to.equal(true)

            local result3 = executeOperatorBlock("operator_gt", {
                OPERAND1 = primitiveInput('1'),
                OPERAND2 = primitiveInput('1')
            })
            expect(result3).to.equal(false)
        end)
    end)

    describe("Infinity Comparison Tests", function()
        it("should compare string infinity and numeric Infinity for equality", function()
            -- "Infinity" = "INFINITY"
            local result1 = executeOperatorBlock("operator_equals", {
                OPERAND1 = primitiveInput('Infinity'),
                OPERAND2 = primitiveInput('INFINITY')
            })
            expect(result1).to.equal(true)

            -- "INFINITY" = "Infinity"
            local result2 = executeOperatorBlock("operator_equals", {
                OPERAND1 = primitiveInput('INFINITY'),
                OPERAND2 = primitiveInput('Infinity')
            })
            expect(result2).to.equal(true)

            -- "Infinity" = "Infinity"
            local result3 = executeOperatorBlock("operator_equals", {
                OPERAND1 = primitiveInput('Infinity'),
                OPERAND2 = primitiveInput('Infinity')
            })
            expect(result3).to.equal(true)

            -- "INFINITY" = "INFINITY"
            local result4 = executeOperatorBlock("operator_equals", {
                OPERAND1 = primitiveInput('INFINITY'),
                OPERAND2 = primitiveInput('INFINITY')
            })
            expect(result4).to.equal(true)

            -- "INFINITY" = "infinity"
            local result5 = executeOperatorBlock("operator_equals", {
                OPERAND1 = primitiveInput('INFINITY'),
                OPERAND2 = primitiveInput('infinity')
            })
            expect(result5).to.equal(true)

            -- Infinity = Infinity
            local result6 = executeOperatorBlock("operator_equals", {
                OPERAND1 = primitiveInput('Infinity'),
                OPERAND2 = primitiveInput('Infinity')
            })
            expect(result6).to.equal(true)

            -- "Infinity" = Infinity
            local result7 = executeOperatorBlock("operator_equals", {
                OPERAND1 = primitiveInput('Infinity'),
                OPERAND2 = primitiveInput('Infinity')
            })
            expect(result7).to.equal(true)

            -- "INFINITY" = Infinity
            local result8 = executeOperatorBlock("operator_equals", {
                OPERAND1 = primitiveInput('INFINITY'),
                OPERAND2 = primitiveInput('Infinity')
            })
            expect(result8).to.equal(true)

            -- Infinity = "Infinity"
            local result9 = executeOperatorBlock("operator_equals", {
                OPERAND1 = primitiveInput('Infinity'),
                OPERAND2 = primitiveInput('Infinity')
            })
            expect(result9).to.equal(true)

            -- Infinity = "INFINITY"
            local result10 = executeOperatorBlock("operator_equals", {
                OPERAND1 = primitiveInput('Infinity'),
                OPERAND2 = primitiveInput('INFINITY')
            })
            expect(result10).to.equal(true)
        end)

        it("should compare string negative infinity and numeric negative Infinity for equality", function()
            -- "-Infinity" = "-INFINITY"
            local result1 = executeOperatorBlock("operator_equals", {
                OPERAND1 = primitiveInput('-Infinity'),
                OPERAND2 = primitiveInput('-INFINITY')
            })
            expect(result1).to.equal(true)

            -- "-INFINITY" = "-Infinity"
            local result2 = executeOperatorBlock("operator_equals", {
                OPERAND1 = primitiveInput('-INFINITY'),
                OPERAND2 = primitiveInput('-Infinity')
            })
            expect(result2).to.equal(true)

            -- "-Infinity" = "-Infinity"
            local result3 = executeOperatorBlock("operator_equals", {
                OPERAND1 = primitiveInput('-Infinity'),
                OPERAND2 = primitiveInput('-Infinity')
            })
            expect(result3).to.equal(true)

            -- "-INFINITY" = "-INFINITY"
            local result4 = executeOperatorBlock("operator_equals", {
                OPERAND1 = primitiveInput('-INFINITY'),
                OPERAND2 = primitiveInput('-INFINITY')
            })
            expect(result4).to.equal(true)

            -- "-INFINITY" = "-infinity"
            local result5 = executeOperatorBlock("operator_equals", {
                OPERAND1 = primitiveInput('-INFINITY'),
                OPERAND2 = primitiveInput('-infinity')
            })
            expect(result5).to.equal(true)

            -- -Infinity = -Infinity
            local result6 = executeOperatorBlock("operator_equals", {
                OPERAND1 = primitiveInput('-Infinity'),
                OPERAND2 = primitiveInput('-Infinity')
            })
            expect(result6).to.equal(true)

            -- "-Infinity" = -Infinity
            local result7 = executeOperatorBlock("operator_equals", {
                OPERAND1 = primitiveInput('-Infinity'),
                OPERAND2 = primitiveInput('-Infinity')
            })
            expect(result7).to.equal(true)

            -- "-INFINITY" = -Infinity
            local result8 = executeOperatorBlock("operator_equals", {
                OPERAND1 = primitiveInput('-INFINITY'),
                OPERAND2 = primitiveInput('-Infinity')
            })
            expect(result8).to.equal(true)

            -- -Infinity = "-Infinity"
            local result9 = executeOperatorBlock("operator_equals", {
                OPERAND1 = primitiveInput('-Infinity'),
                OPERAND2 = primitiveInput('-Infinity')
            })
            expect(result9).to.equal(true)

            -- -Infinity = "-INFINITY"
            local result10 = executeOperatorBlock("operator_equals", {
                OPERAND1 = primitiveInput('-Infinity'),
                OPERAND2 = primitiveInput('-INFINITY')
            })
            expect(result10).to.equal(true)
        end)

        it("should compare negative to positive string and numeric Infinity", function()
            -- "-Infinity" != "Infinity"
            local result1 = executeOperatorBlock("operator_equals", {
                OPERAND1 = primitiveInput('-Infinity'),
                OPERAND2 = primitiveInput('Infinity')
            })
            expect(result1).to.equal(false)

            -- "-Infinity" != "INFINITY"
            local result2 = executeOperatorBlock("operator_equals", {
                OPERAND1 = primitiveInput('-Infinity'),
                OPERAND2 = primitiveInput('INFINITY')
            })
            expect(result2).to.equal(false)

            -- "-INFINITY" != "Infinity"
            local result3 = executeOperatorBlock("operator_equals", {
                OPERAND1 = primitiveInput('-INFINITY'),
                OPERAND2 = primitiveInput('Infinity')
            })
            expect(result3).to.equal(false)

            -- "-INFINITY" != "INFINITY"
            local result4 = executeOperatorBlock("operator_equals", {
                OPERAND1 = primitiveInput('-INFINITY'),
                OPERAND2 = primitiveInput('INFINITY')
            })
            expect(result4).to.equal(false)

            -- "-Infinity" != Infinity
            local result5 = executeOperatorBlock("operator_equals", {
                OPERAND1 = primitiveInput('-Infinity'),
                OPERAND2 = primitiveInput('Infinity')
            })
            expect(result5).to.equal(false)

            -- "-INFINITY" != Infinity
            local result6 = executeOperatorBlock("operator_equals", {
                OPERAND1 = primitiveInput('-INFINITY'),
                OPERAND2 = primitiveInput('Infinity')
            })
            expect(result6).to.equal(false)

            -- "Infinity" != -Infinity
            local result7 = executeOperatorBlock("operator_equals", {
                OPERAND1 = primitiveInput('Infinity'),
                OPERAND2 = primitiveInput('-Infinity')
            })
            expect(result7).to.equal(false)

            -- "INFINITY" != -Infinity
            local result8 = executeOperatorBlock("operator_equals", {
                OPERAND1 = primitiveInput('INFINITY'),
                OPERAND2 = primitiveInput('-Infinity')
            })
            expect(result8).to.equal(false)

            -- Infinity != -Infinity
            local result9 = executeOperatorBlock("operator_equals", {
                OPERAND1 = primitiveInput('Infinity'),
                OPERAND2 = primitiveInput('-Infinity')
            })
            expect(result9).to.equal(false)
        end)

        it("should compare string infinity and numeric Infinity for less than", function()
            -- "Infinity" !< "INFINITY"
            local result1 = executeOperatorBlock("operator_lt", {
                OPERAND1 = primitiveInput('Infinity'),
                OPERAND2 = primitiveInput('INFINITY')
            })
            expect(result1).to.equal(false)

            -- "INFINITY" !< Infinity
            local result2 = executeOperatorBlock("operator_lt", {
                OPERAND1 = primitiveInput('INFINITY'),
                OPERAND2 = primitiveInput('Infinity')
            })
            expect(result2).to.equal(false)

            -- "-INFINITY" < "INFINITY"
            local result3 = executeOperatorBlock("operator_lt", {
                OPERAND1 = primitiveInput('-INFINITY'),
                OPERAND2 = primitiveInput('INFINITY')
            })
            expect(result3).to.equal(true)

            -- -Infinity < "INFINITY"
            local result4 = executeOperatorBlock("operator_lt", {
                OPERAND1 = primitiveInput('-Infinity'),
                OPERAND2 = primitiveInput('INFINITY')
            })
            expect(result4).to.equal(true)

            -- "Infinity" !< 111
            local result5 = executeOperatorBlock("operator_lt", {
                OPERAND1 = primitiveInput('Infinity'),
                OPERAND2 = primitiveInput(111)
            })
            expect(result5).to.equal(false)

            -- "INFINITY" !< 222
            local result6 = executeOperatorBlock("operator_lt", {
                OPERAND1 = primitiveInput('INFINITY'),
                OPERAND2 = primitiveInput(222)
            })
            expect(result6).to.equal(false)

            -- Infinity !< 333
            local result7 = executeOperatorBlock("operator_lt", {
                OPERAND1 = primitiveInput('Infinity'),
                OPERAND2 = primitiveInput(333)
            })
            expect(result7).to.equal(false)

            -- 111 < "Infinity"
            local result8 = executeOperatorBlock("operator_lt", {
                OPERAND1 = primitiveInput(111),
                OPERAND2 = primitiveInput('Infinity')
            })
            expect(result8).to.equal(true)

            -- 222 < "INFINITY"
            local result9 = executeOperatorBlock("operator_lt", {
                OPERAND1 = primitiveInput(222),
                OPERAND2 = primitiveInput('INFINITY')
            })
            expect(result9).to.equal(true)

            -- 333 < Infinity
            local result10 = executeOperatorBlock("operator_lt", {
                OPERAND1 = primitiveInput(333),
                OPERAND2 = primitiveInput('Infinity')
            })
            expect(result10).to.equal(true)
        end)

        it("should compare string infinity and numeric Infinity for greater than", function()
            -- "Infinity" !> "INFINITY"
            local result1 = executeOperatorBlock("operator_gt", {
                OPERAND1 = primitiveInput('Infinity'),
                OPERAND2 = primitiveInput('INFINITY')
            })
            expect(result1).to.equal(false)

            -- "INFINITY" !> Infinity
            local result2 = executeOperatorBlock("operator_gt", {
                OPERAND1 = primitiveInput('INFINITY'),
                OPERAND2 = primitiveInput('Infinity')
            })
            expect(result2).to.equal(false)

            -- "INFINITY" > "-INFINITY"
            local result3 = executeOperatorBlock("operator_gt", {
                OPERAND1 = primitiveInput('INFINITY'),
                OPERAND2 = primitiveInput('-INFINITY')
            })
            expect(result3).to.equal(true)

            -- Infinity > "-INFINITY"
            local result4 = executeOperatorBlock("operator_gt", {
                OPERAND1 = primitiveInput('Infinity'),
                OPERAND2 = primitiveInput('-INFINITY')
            })
            expect(result4).to.equal(true)

            -- "Infinity" > 111
            local result5 = executeOperatorBlock("operator_gt", {
                OPERAND1 = primitiveInput('Infinity'),
                OPERAND2 = primitiveInput(111)
            })
            expect(result5).to.equal(true)

            -- "INFINITY" > 222
            local result6 = executeOperatorBlock("operator_gt", {
                OPERAND1 = primitiveInput('INFINITY'),
                OPERAND2 = primitiveInput(222)
            })
            expect(result6).to.equal(true)

            -- Infinity > 333
            local result7 = executeOperatorBlock("operator_gt", {
                OPERAND1 = primitiveInput('Infinity'),
                OPERAND2 = primitiveInput(333)
            })
            expect(result7).to.equal(true)

            -- 111 !> "Infinity"
            local result8 = executeOperatorBlock("operator_gt", {
                OPERAND1 = primitiveInput(111),
                OPERAND2 = primitiveInput('Infinity')
            })
            expect(result8).to.equal(false)

            -- 222 !> "INFINITY"
            local result9 = executeOperatorBlock("operator_gt", {
                OPERAND1 = primitiveInput(222),
                OPERAND2 = primitiveInput('INFINITY')
            })
            expect(result9).to.equal(false)

            -- 333 !> Infinity
            local result10 = executeOperatorBlock("operator_gt", {
                OPERAND1 = primitiveInput(333),
                OPERAND2 = primitiveInput('Infinity')
            })
            expect(result10).to.equal(false)
        end)
    end)

    describe("Boolean Operations", function()
        it("should handle 'and' operator", function()
            SB3Builder.resetCounter()
            local stage = SB3Builder.createStage()
            local resultId = SB3Builder.addVariable(stage, "result", false)

            local hatId, hatBlock = SB3Builder.Events.whenFlagClicked()
            local true1Id, true1Block = SB3Builder.createBlock("operator_equals", {
                OPERAND1 = primitiveInput("1"),
                OPERAND2 = primitiveInput("1")
            })
            local true2Id, true2Block = SB3Builder.createBlock("operator_equals", {
                OPERAND1 = primitiveInput("2"),
                OPERAND2 = primitiveInput("2")
            })
            local andId, andBlock = SB3Builder.Operators.and_(true1Id, true2Id)
            local setId, setBlock = SB3Builder.createBlock("data_setvariableto", {
                VALUE = SB3Builder.blockInput(andId)
            }, {
                VARIABLE = SB3Builder.field("result", resultId)
            })

            SB3Builder.addBlock(stage, hatId, hatBlock)
            SB3Builder.addBlock(stage, true1Id, true1Block)
            SB3Builder.addBlock(stage, true2Id, true2Block)
            SB3Builder.addBlock(stage, andId, andBlock)
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
            expect(result).to.exist()
            expect(result.value).to.equal(true)

            -- Test true and false
            SB3Builder.resetCounter()
            stage = SB3Builder.createStage()
            resultId = SB3Builder.addVariable(stage, "result", false)

            hatId, hatBlock = SB3Builder.Events.whenFlagClicked()
            true1Id, true1Block = SB3Builder.createBlock("operator_equals", {
                OPERAND1 = primitiveInput("1"),
                OPERAND2 = primitiveInput("1")
            })
            local false1Id, false1Block = SB3Builder.createBlock("operator_equals", {
                OPERAND1 = primitiveInput("1"),
                OPERAND2 = primitiveInput("2")
            })
            andId, andBlock = SB3Builder.Operators.and_(true1Id, false1Id)
            setId, setBlock = SB3Builder.createBlock("data_setvariableto", {
                VALUE = SB3Builder.blockInput(andId)
            }, {
                VARIABLE = SB3Builder.field("result", resultId)
            })

            SB3Builder.addBlock(stage, hatId, hatBlock)
            SB3Builder.addBlock(stage, true1Id, true1Block)
            SB3Builder.addBlock(stage, false1Id, false1Block)
            SB3Builder.addBlock(stage, andId, andBlock)
            SB3Builder.addBlock(stage, setId, setBlock)
            SB3Builder.linkBlocks(stage, {hatId, setId})

            projectJson = SB3Builder.createProject({stage})
            project = ProjectModel:new(projectJson, {})
            runtime = Runtime:new(project)
            runtime:initialize()

            runtime:broadcastGreenFlag()
            -- Safe execution with iteration limit to prevent infinite loops
            local maxIterations = 100
            local iterations = 0
            while #runtime:getActiveThreads() > 0 and iterations < maxIterations do
                runtime:update(1/60)
                iterations = iterations + 1
            end

            result = runtime.stage:lookupVariableByNameAndType("result")
            expect(result.value).to.equal(false)

            -- Test false and false
            SB3Builder.resetCounter()
            stage = SB3Builder.createStage()
            resultId = SB3Builder.addVariable(stage, "result", true)

            hatId, hatBlock = SB3Builder.Events.whenFlagClicked()
            false1Id, false1Block = SB3Builder.createBlock("operator_equals", {
                OPERAND1 = primitiveInput("1"),
                OPERAND2 = primitiveInput("2")
            })
            local false2Id, false2Block = SB3Builder.createBlock("operator_equals", {
                OPERAND1 = primitiveInput("3"),
                OPERAND2 = primitiveInput("4")
            })
            andId, andBlock = SB3Builder.Operators.and_(false1Id, false2Id)
            setId, setBlock = SB3Builder.createBlock("data_setvariableto", {
                VALUE = SB3Builder.blockInput(andId)
            }, {
                VARIABLE = SB3Builder.field("result", resultId)
            })

            SB3Builder.addBlock(stage, hatId, hatBlock)
            SB3Builder.addBlock(stage, false1Id, false1Block)
            SB3Builder.addBlock(stage, false2Id, false2Block)
            SB3Builder.addBlock(stage, andId, andBlock)
            SB3Builder.addBlock(stage, setId, setBlock)
            SB3Builder.linkBlocks(stage, {hatId, setId})

            projectJson = SB3Builder.createProject({stage})
            project = ProjectModel:new(projectJson, {})
            runtime = Runtime:new(project)
            runtime:initialize()

            runtime:broadcastGreenFlag()
            -- Safe execution with iteration limit to prevent infinite loops
            local maxIterations = 100
            local iterations = 0
            while #runtime:getActiveThreads() > 0 and iterations < maxIterations do
                runtime:update(1/60)
                iterations = iterations + 1
            end

            result = runtime.stage:lookupVariableByNameAndType("result")
            expect(result.value).to.equal(false)
        end)

        it("should handle 'or' operator", function()
            SB3Builder.resetCounter()
            local stage = SB3Builder.createStage()
            local resultId = SB3Builder.addVariable(stage, "result", false)

            local hatId, hatBlock = SB3Builder.Events.whenFlagClicked()
            local true1Id, true1Block = SB3Builder.createBlock("operator_equals", {
                OPERAND1 = primitiveInput("1"),
                OPERAND2 = primitiveInput("1")
            })
            local true2Id, true2Block = SB3Builder.createBlock("operator_equals", {
                OPERAND1 = primitiveInput("2"),
                OPERAND2 = primitiveInput("2")
            })
            local orId, orBlock = SB3Builder.Operators.or_(true1Id, true2Id)
            local setId, setBlock = SB3Builder.createBlock("data_setvariableto", {
                VALUE = SB3Builder.blockInput(orId)
            }, {
                VARIABLE = SB3Builder.field("result", resultId)
            })

            SB3Builder.addBlock(stage, hatId, hatBlock)
            SB3Builder.addBlock(stage, true1Id, true1Block)
            SB3Builder.addBlock(stage, true2Id, true2Block)
            SB3Builder.addBlock(stage, orId, orBlock)
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
            expect(result.value).to.equal(true)

            -- Test true or false
            SB3Builder.resetCounter()
            stage = SB3Builder.createStage()
            resultId = SB3Builder.addVariable(stage, "result", false)

            hatId, hatBlock = SB3Builder.Events.whenFlagClicked()
            true1Id, true1Block = SB3Builder.createBlock("operator_equals", {
                OPERAND1 = primitiveInput("1"),
                OPERAND2 = primitiveInput("1")
            })
            local false1Id, false1Block = SB3Builder.createBlock("operator_equals", {
                OPERAND1 = primitiveInput("1"),
                OPERAND2 = primitiveInput("2")
            })
            orId, orBlock = SB3Builder.Operators.or_(true1Id, false1Id)
            setId, setBlock = SB3Builder.createBlock("data_setvariableto", {
                VALUE = SB3Builder.blockInput(orId)
            }, {
                VARIABLE = SB3Builder.field("result", resultId)
            })

            SB3Builder.addBlock(stage, hatId, hatBlock)
            SB3Builder.addBlock(stage, true1Id, true1Block)
            SB3Builder.addBlock(stage, false1Id, false1Block)
            SB3Builder.addBlock(stage, orId, orBlock)
            SB3Builder.addBlock(stage, setId, setBlock)
            SB3Builder.linkBlocks(stage, {hatId, setId})

            projectJson = SB3Builder.createProject({stage})
            project = ProjectModel:new(projectJson, {})
            runtime = Runtime:new(project)
            runtime:initialize()

            runtime:broadcastGreenFlag()
            -- Safe execution with iteration limit to prevent infinite loops
            local maxIterations = 100
            local iterations = 0
            while #runtime:getActiveThreads() > 0 and iterations < maxIterations do
                runtime:update(1/60)
                iterations = iterations + 1
            end

            result = runtime.stage:lookupVariableByNameAndType("result")
            expect(result.value).to.equal(true)

            -- Test false or false
            SB3Builder.resetCounter()
            stage = SB3Builder.createStage()
            resultId = SB3Builder.addVariable(stage, "result", true)

            hatId, hatBlock = SB3Builder.Events.whenFlagClicked()
            false1Id, false1Block = SB3Builder.createBlock("operator_equals", {
                OPERAND1 = primitiveInput("1"),
                OPERAND2 = primitiveInput("2")
            })
            local false2Id, false2Block = SB3Builder.createBlock("operator_equals", {
                OPERAND1 = primitiveInput("3"),
                OPERAND2 = primitiveInput("4")
            })
            orId, orBlock = SB3Builder.Operators.or_(false1Id, false2Id)
            setId, setBlock = SB3Builder.createBlock("data_setvariableto", {
                VALUE = SB3Builder.blockInput(orId)
            }, {
                VARIABLE = SB3Builder.field("result", resultId)
            })

            SB3Builder.addBlock(stage, hatId, hatBlock)
            SB3Builder.addBlock(stage, false1Id, false1Block)
            SB3Builder.addBlock(stage, false2Id, false2Block)
            SB3Builder.addBlock(stage, orId, orBlock)
            SB3Builder.addBlock(stage, setId, setBlock)
            SB3Builder.linkBlocks(stage, {hatId, setId})

            projectJson = SB3Builder.createProject({stage})
            project = ProjectModel:new(projectJson, {})
            runtime = Runtime:new(project)
            runtime:initialize()

            runtime:broadcastGreenFlag()
            -- Safe execution with iteration limit to prevent infinite loops
            local maxIterations = 100
            local iterations = 0
            while #runtime:getActiveThreads() > 0 and iterations < maxIterations do
                runtime:update(1/60)
                iterations = iterations + 1
            end

            result = runtime.stage:lookupVariableByNameAndType("result")
            expect(result.value).to.equal(false)
        end)

        it("should handle 'not' operator", function()
            SB3Builder.resetCounter()
            local stage = SB3Builder.createStage()
            local resultId = SB3Builder.addVariable(stage, "result", false)

            local hatId, hatBlock = SB3Builder.Events.whenFlagClicked()
            local trueId, trueBlock = SB3Builder.createBlock("operator_equals", {
                OPERAND1 = primitiveInput("1"),
                OPERAND2 = primitiveInput("1")
            })
            local notId, notBlock = SB3Builder.Operators.not_(trueId)
            local setId, setBlock = SB3Builder.createBlock("data_setvariableto", {
                VALUE = SB3Builder.blockInput(notId)
            }, {
                VARIABLE = SB3Builder.field("result", resultId)
            })

            SB3Builder.addBlock(stage, hatId, hatBlock)
            SB3Builder.addBlock(stage, trueId, trueBlock)
            SB3Builder.addBlock(stage, notId, notBlock)
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
            expect(result.value).to.equal(false)

            -- Test not false
            SB3Builder.resetCounter()
            stage = SB3Builder.createStage()
            resultId = SB3Builder.addVariable(stage, "result", true)

            hatId, hatBlock = SB3Builder.Events.whenFlagClicked()
            local falseId, falseBlock = SB3Builder.createBlock("operator_equals", {
                OPERAND1 = primitiveInput("1"),
                OPERAND2 = primitiveInput("2")
            })
            notId, notBlock = SB3Builder.Operators.not_(falseId)
            setId, setBlock = SB3Builder.createBlock("data_setvariableto", {
                VALUE = SB3Builder.blockInput(notId)
            }, {
                VARIABLE = SB3Builder.field("result", resultId)
            })

            SB3Builder.addBlock(stage, hatId, hatBlock)
            SB3Builder.addBlock(stage, falseId, falseBlock)
            SB3Builder.addBlock(stage, notId, notBlock)
            SB3Builder.addBlock(stage, setId, setBlock)
            SB3Builder.linkBlocks(stage, {hatId, setId})

            projectJson = SB3Builder.createProject({stage})
            project = ProjectModel:new(projectJson, {})
            runtime = Runtime:new(project)
            runtime:initialize()

            runtime:broadcastGreenFlag()
            -- Safe execution with iteration limit to prevent infinite loops
            local maxIterations = 100
            local iterations = 0
            while #runtime:getActiveThreads() > 0 and iterations < maxIterations do
                runtime:update(1/60)
                iterations = iterations + 1
            end

            result = runtime.stage:lookupVariableByNameAndType("result")
            expect(result.value).to.equal(true)
        end)
    end)

    describe("Random Operations", function()
        it("should generate random numbers within range", function()
            local min = 0
            local max = 100
            local result = executeOperatorBlock("operator_random", {
                FROM = mathInput(min),
                TO = mathInput(max)
            })
            expect(result >= min).to.equal(true)
            expect(result <= max).to.equal(true)
        end)

        it("should handle equal min and max", function()
            local value = 1
            local result = executeOperatorBlock("operator_random", {
                FROM = mathInput(value),
                TO = mathInput(value)
            })
            expect(result).to.equal(value)
        end)

        it("should generate random decimals", function()
            local min = 0.1
            local max = 10
            local result = executeOperatorBlock("operator_random", {
                FROM = mathInput(min),
                TO = mathInput(max)
            })
            expect(result >= min).to.equal(true)
            expect(result <= max).to.equal(true)
        end)

        it("should generate random integers", function()
            local min = 0
            local max = 10
            local result = executeOperatorBlock("operator_random", {
                FROM = mathInput(min),
                TO = mathInput(max)
            })
            expect(result >= min).to.equal(true)
            expect(result <= max).to.equal(true)
        end)

        it("should handle reversed range", function()
            local min = 0
            local max = 10
            local result = executeOperatorBlock("operator_random", {
                FROM = mathInput(max),
                TO = mathInput(min)
            })
            expect(result >= min).to.equal(true)
            expect(result <= max).to.equal(true)
        end)
    end)

    describe("String Operations", function()
        it("should join strings", function()
            local result = executeOperatorBlock("operator_join", {
                STRING1 = primitiveInput('foo'),
                STRING2 = primitiveInput('bar')
            })
            expect(result).to.equal('foobar')

            local result2 = executeOperatorBlock("operator_join", {
                STRING1 = primitiveInput('1'),
                STRING2 = primitiveInput('2')
            })
            expect(result2).to.equal('12')
        end)

        it("should extract letters correctly", function()
            local result1 = executeOperatorBlock("operator_letter_of", {
                STRING = primitiveInput('foo'),
                LETTER = SB3Builder.primitiveInput(0, 6) -- WHOLE_NUM_PRIMITIVE = 6
            })
            expect(result1).to.equal('')

            local result2 = executeOperatorBlock("operator_letter_of", {
                STRING = primitiveInput('foo'),
                LETTER = SB3Builder.primitiveInput(1, 6)
            })
            expect(result2).to.equal('f')

            local result3 = executeOperatorBlock("operator_letter_of", {
                STRING = primitiveInput('foo'),
                LETTER = SB3Builder.primitiveInput(2, 6)
            })
            expect(result3).to.equal('o')

            local result4 = executeOperatorBlock("operator_letter_of", {
                STRING = primitiveInput('foo'),
                LETTER = SB3Builder.primitiveInput(3, 6)
            })
            expect(result4).to.equal('o')

            local result5 = executeOperatorBlock("operator_letter_of", {
                STRING = primitiveInput('foo'),
                LETTER = SB3Builder.primitiveInput(4, 6)
            })
            expect(result5).to.equal('')

            local result6 = executeOperatorBlock("operator_letter_of", {
                STRING = primitiveInput('foo'),
                LETTER = primitiveInput('bar')
            })
            expect(result6).to.equal('')
        end)

        it("should calculate string length", function()
            local result1 = executeOperatorBlock("operator_length", {
                STRING = primitiveInput('')
            })
            expect(result1).to.equal(0)

            local result2 = executeOperatorBlock("operator_length", {
                STRING = primitiveInput('foo')
            })
            expect(result2).to.equal(3)

            local result3 = executeOperatorBlock("operator_length", {
                STRING = primitiveInput('1')
            })
            expect(result3).to.equal(1)

            local result4 = executeOperatorBlock("operator_length", {
                STRING = primitiveInput('100')
            })
            expect(result4).to.equal(3)
        end)

        it("should check string contains", function()
            local result1 = executeOperatorBlock("operator_contains", {
                STRING1 = primitiveInput('hello world'),
                STRING2 = primitiveInput('hello')
            })
            expect(result1).to.equal(true)

            local result2 = executeOperatorBlock("operator_contains", {
                STRING1 = primitiveInput('foo'),
                STRING2 = primitiveInput('bar')
            })
            expect(result2).to.equal(false)

            local result3 = executeOperatorBlock("operator_contains", {
                STRING1 = primitiveInput('HeLLo world'),
                STRING2 = primitiveInput('hello')
            })
            expect(result3).to.equal(true)
        end)
    end)

    describe("Math Functions", function()
        it("should calculate modulo", function()
            local result1 = executeOperatorBlock("operator_mod", {
                NUM1 = mathInput(1),
                NUM2 = mathInput(1)
            })
            expect(result1).to.equal(0)

            local result2 = executeOperatorBlock("operator_mod", {
                NUM1 = mathInput(3),
                NUM2 = mathInput(6)
            })
            expect(result2).to.equal(3)

            local result3 = executeOperatorBlock("operator_mod", {
                NUM1 = mathInput(-3),
                NUM2 = mathInput(6)
            })
            expect(result3).to.equal(3)
        end)

        it("should round numbers", function()
            local result1 = executeOperatorBlock("operator_round", {
                NUM = mathInput(1)
            })
            expect(result1).to.equal(1)

            local result2 = executeOperatorBlock("operator_round", {
                NUM = mathInput(1.1)
            })
            expect(result2).to.equal(1)

            local result3 = executeOperatorBlock("operator_round", {
                NUM = mathInput(1.5)
            })
            expect(result3).to.equal(2)
        end)

        it("should handle math operations", function()
            local result1 = executeOperatorBlock("operator_mathop", {
                NUM = mathInput(-1)
            }, {
                OPERATOR = SB3Builder.field('abs')
            })
            expect(result1).to.equal(1)

            local result2 = executeOperatorBlock("operator_mathop", {
                NUM = mathInput(1.5)
            }, {
                OPERATOR = SB3Builder.field('floor')
            })
            expect(result2).to.equal(1)

            local result3 = executeOperatorBlock("operator_mathop", {
                NUM = mathInput(0.1)
            }, {
                OPERATOR = SB3Builder.field('ceiling')
            })
            expect(result3).to.equal(1)

            local result4 = executeOperatorBlock("operator_mathop", {
                NUM = mathInput(1)
            }, {
                OPERATOR = SB3Builder.field('sqrt')
            })
            expect(result4).to.equal(1)

            -- Test trigonometric functions with some tolerance
            local result5 = executeOperatorBlock("operator_mathop", {
                NUM = mathInput(90)
            }, {
                OPERATOR = SB3Builder.field('sin')
            })
            expect(math.abs(result5 - 1) < 0.001).to.equal(true)

            local result6 = executeOperatorBlock("operator_mathop", {
                NUM = mathInput(180)
            }, {
                OPERATOR = SB3Builder.field('cos')
            })
            expect(math.abs(result6 - (-1)) < 0.001).to.equal(true)

            local result7 = executeOperatorBlock("operator_mathop", {
                NUM = mathInput(90)
            }, {
                OPERATOR = SB3Builder.field('tan')
            })
            expect(result7).to.equal(math.huge)

            local result8 = executeOperatorBlock("operator_mathop", {
                NUM = mathInput(180)
            }, {
                OPERATOR = SB3Builder.field('tan')
            })
            expect(type(result8) == "number" and math.abs(result8) < 0.001).to.equal(true)

            local result9 = executeOperatorBlock("operator_mathop", {
                NUM = mathInput(1)
            }, {
                OPERATOR = SB3Builder.field('asin')
            })
            expect(result9).to.equal(90)

            local result10 = executeOperatorBlock("operator_mathop", {
                NUM = mathInput(1)
            }, {
                OPERATOR = SB3Builder.field('acos')
            })
            expect(result10).to.equal(0)

            local result11 = executeOperatorBlock("operator_mathop", {
                NUM = mathInput(1)
            }, {
                OPERATOR = SB3Builder.field('atan')
            })
            expect(result11).to.equal(45)

            local result12 = executeOperatorBlock("operator_mathop", {
                NUM = mathInput(1)
            }, {
                OPERATOR = SB3Builder.field('ln')
            })
            expect(result12).to.equal(0)

            local result13 = executeOperatorBlock("operator_mathop", {
                NUM = mathInput(1)
            }, {
                OPERATOR = SB3Builder.field('log')
            })
            expect(result13).to.equal(0)

            local result14 = executeOperatorBlock("operator_mathop", {
                NUM = mathInput(1)
            }, {
                OPERATOR = SB3Builder.field('e ^')
            })
            expect(math.abs(result14 - 2.718281828459045) < 0.001).to.equal(true)

            local result15 = executeOperatorBlock("operator_mathop", {
                NUM = mathInput(1)
            }, {
                OPERATOR = SB3Builder.field('10 ^')
            })
            expect(result15).to.equal(10)

            local result16 = executeOperatorBlock("operator_mathop", {
                NUM = mathInput(1)
            }, {
                OPERATOR = SB3Builder.field('undefined')
            })
            expect(result16).to.equal(0)
        end)
    end)

    -- Test list equality comparison
    describe("List equals comparison", function()
        it("should return true when comparing identical single-letter lists", function()
            SB3Builder.resetCounter()
            local stage = SB3Builder.createStage()
            local list1Id = SB3Builder.addList(stage, "list1", {"a", "b", "c"})
            local list2Id = SB3Builder.addList(stage, "list2", {"a", "b", "c"})
            local resultId = SB3Builder.addVariable(stage, "result", "UNSET")

            -- Create blocks: when flag clicked -> set result to (list1 contents = list2 contents)
            local hatId, hatBlock = SB3Builder.Events.whenFlagClicked()
            local list1Id_block, list1Block = SB3Builder.Data.listContents("list1", list1Id)
            local list2Id_block, list2Block = SB3Builder.Data.listContents("list2", list2Id)
            local equalsId, equalsBlock = SB3Builder.Operators.equals(
                SB3Builder.blockInput(list1Id_block),
                SB3Builder.blockInput(list2Id_block)
            )
            local setId, setBlock = SB3Builder.Data.setVariable("result", SB3Builder.blockInput(equalsId), resultId)

            SB3Builder.addBlock(stage, hatId, hatBlock)
            SB3Builder.addBlock(stage, list1Id_block, list1Block)
            SB3Builder.addBlock(stage, list2Id_block, list2Block)
            SB3Builder.addBlock(stage, equalsId, equalsBlock)
            SB3Builder.addBlock(stage, setId, setBlock)
            SB3Builder.linkBlocks(stage, {hatId, setId})

            local projectJson = SB3Builder.createProject({stage})
            local project = ProjectModel:new(projectJson, {})
            local runtime = Runtime:new(project)
            runtime:initialize()

            runtime:broadcastGreenFlag()
            local iterations = 0
            while #runtime:getActiveThreads() > 0 and iterations < 100 do
                runtime:update(1/60)
                iterations = iterations + 1
            end

            local result = runtime.stage:lookupVariableByNameAndType("result")
            expect(result.value).to.equal(true)
        end)

        it("should return true when comparing identical multi-character lists", function()
            SB3Builder.resetCounter()
            local stage = SB3Builder.createStage()
            local list1Id = SB3Builder.addList(stage, "list1", {"hello", "world"})
            local list2Id = SB3Builder.addList(stage, "list2", {"hello", "world"})
            local resultId = SB3Builder.addVariable(stage, "result", "UNSET")

            -- Create blocks: when flag clicked -> set result to (list1 contents = list2 contents)
            local hatId, hatBlock = SB3Builder.Events.whenFlagClicked()
            local list1Id_block, list1Block = SB3Builder.Data.listContents("list1", list1Id)
            local list2Id_block, list2Block = SB3Builder.Data.listContents("list2", list2Id)
            local equalsId, equalsBlock = SB3Builder.Operators.equals(
                SB3Builder.blockInput(list1Id_block),
                SB3Builder.blockInput(list2Id_block)
            )
            local setId, setBlock = SB3Builder.Data.setVariable("result", SB3Builder.blockInput(equalsId), resultId)

            SB3Builder.addBlock(stage, hatId, hatBlock)
            SB3Builder.addBlock(stage, list1Id_block, list1Block)
            SB3Builder.addBlock(stage, list2Id_block, list2Block)
            SB3Builder.addBlock(stage, equalsId, equalsBlock)
            SB3Builder.addBlock(stage, setId, setBlock)
            SB3Builder.linkBlocks(stage, {hatId, setId})

            local projectJson = SB3Builder.createProject({stage})
            local project = ProjectModel:new(projectJson, {})
            local runtime = Runtime:new(project)
            runtime:initialize()

            runtime:broadcastGreenFlag()
            local iterations = 0
            while #runtime:getActiveThreads() > 0 and iterations < 100 do
                runtime:update(1/60)
                iterations = iterations + 1
            end

            local result = runtime.stage:lookupVariableByNameAndType("result")
            expect(result.value).to.equal(true)
        end)

        it("should return false when comparing different lists", function()
            SB3Builder.resetCounter()
            local stage = SB3Builder.createStage()
            local list1Id = SB3Builder.addList(stage, "list1", {"1", "2", "3"})
            local list2Id = SB3Builder.addList(stage, "list2", {"4", "5", "6"})
            local resultId = SB3Builder.addVariable(stage, "result", "UNSET")

            -- Create blocks: when flag clicked -> set result to (list1 contents = list2 contents)
            local hatId, hatBlock = SB3Builder.Events.whenFlagClicked()
            local list1Id_block, list1Block = SB3Builder.Data.listContents("list1", list1Id)
            local list2Id_block, list2Block = SB3Builder.Data.listContents("list2", list2Id)
            local equalsId, equalsBlock = SB3Builder.Operators.equals(
                SB3Builder.blockInput(list1Id_block),
                SB3Builder.blockInput(list2Id_block)
            )
            local setId, setBlock = SB3Builder.Data.setVariable("result", SB3Builder.blockInput(equalsId), resultId)

            SB3Builder.addBlock(stage, hatId, hatBlock)
            SB3Builder.addBlock(stage, list1Id_block, list1Block)
            SB3Builder.addBlock(stage, list2Id_block, list2Block)
            SB3Builder.addBlock(stage, equalsId, equalsBlock)
            SB3Builder.addBlock(stage, setId, setBlock)
            SB3Builder.linkBlocks(stage, {hatId, setId})

            local projectJson = SB3Builder.createProject({stage})
            local project = ProjectModel:new(projectJson, {})
            local runtime = Runtime:new(project)
            runtime:initialize()

            runtime:broadcastGreenFlag()
            local iterations = 0
            while #runtime:getActiveThreads() > 0 and iterations < 100 do
                runtime:update(1/60)
                iterations = iterations + 1
            end

            local result = runtime.stage:lookupVariableByNameAndType("result")
            expect(result.value).to.equal(false)
        end)

        it("should return true when comparing number and string lists with same content", function()
            SB3Builder.resetCounter()
            local stage = SB3Builder.createStage()
            local list1Id = SB3Builder.addList(stage, "list1", {1, 2, 3})
            local list2Id = SB3Builder.addList(stage, "list2", {"1", "2", "3"})
            local resultId = SB3Builder.addVariable(stage, "result", "UNSET")

            -- Create blocks: when flag clicked -> set result to (list1 contents = list2 contents)
            local hatId, hatBlock = SB3Builder.Events.whenFlagClicked()
            local list1Id_block, list1Block = SB3Builder.Data.listContents("list1", list1Id)
            local list2Id_block, list2Block = SB3Builder.Data.listContents("list2", list2Id)
            local equalsId, equalsBlock = SB3Builder.Operators.equals(
                SB3Builder.blockInput(list1Id_block),
                SB3Builder.blockInput(list2Id_block)
            )
            local setId, setBlock = SB3Builder.Data.setVariable("result", SB3Builder.blockInput(equalsId), resultId)

            SB3Builder.addBlock(stage, hatId, hatBlock)
            SB3Builder.addBlock(stage, list1Id_block, list1Block)
            SB3Builder.addBlock(stage, list2Id_block, list2Block)
            SB3Builder.addBlock(stage, equalsId, equalsBlock)
            SB3Builder.addBlock(stage, setId, setBlock)
            SB3Builder.linkBlocks(stage, {hatId, setId})

            local projectJson = SB3Builder.createProject({stage})
            local project = ProjectModel:new(projectJson, {})
            local runtime = Runtime:new(project)
            runtime:initialize()

            runtime:broadcastGreenFlag()
            local iterations = 0
            while #runtime:getActiveThreads() > 0 and iterations < 100 do
                runtime:update(1/60)
                iterations = iterations + 1
            end

            local result = runtime.stage:lookupVariableByNameAndType("result")
            expect(result.value).to.equal(true)
        end)

        it("should return true when comparing empty lists", function()
            SB3Builder.resetCounter()
            local stage = SB3Builder.createStage()
            local list1Id = SB3Builder.addList(stage, "list1", {})
            local list2Id = SB3Builder.addList(stage, "list2", {})
            local resultId = SB3Builder.addVariable(stage, "result", "UNSET")

            -- Create blocks: when flag clicked -> set result to (list1 contents = list2 contents)
            local hatId, hatBlock = SB3Builder.Events.whenFlagClicked()
            local list1Id_block, list1Block = SB3Builder.Data.listContents("list1", list1Id)
            local list2Id_block, list2Block = SB3Builder.Data.listContents("list2", list2Id)
            local equalsId, equalsBlock = SB3Builder.Operators.equals(
                SB3Builder.blockInput(list1Id_block),
                SB3Builder.blockInput(list2Id_block)
            )
            local setId, setBlock = SB3Builder.Data.setVariable("result", SB3Builder.blockInput(equalsId), resultId)

            SB3Builder.addBlock(stage, hatId, hatBlock)
            SB3Builder.addBlock(stage, list1Id_block, list1Block)
            SB3Builder.addBlock(stage, list2Id_block, list2Block)
            SB3Builder.addBlock(stage, equalsId, equalsBlock)
            SB3Builder.addBlock(stage, setId, setBlock)
            SB3Builder.linkBlocks(stage, {hatId, setId})

            local projectJson = SB3Builder.createProject({stage})
            local project = ProjectModel:new(projectJson, {})
            local runtime = Runtime:new(project)
            runtime:initialize()

            runtime:broadcastGreenFlag()
            local iterations = 0
            while #runtime:getActiveThreads() > 0 and iterations < 100 do
                runtime:update(1/60)
                iterations = iterations + 1
            end

            local result = runtime.stage:lookupVariableByNameAndType("result")
            expect(result.value).to.equal(true)
        end)

        it("should handle direct list reference in operator (problematic case)", function()
            SB3Builder.resetCounter()
            local stage = SB3Builder.createStage()
            local listId = SB3Builder.addList(stage, "test list", {"a", "b", "c"})
            local resultId = SB3Builder.addVariable(stage, "result", "UNSET")

            -- Create an operator_join block with direct list reference as input
            -- This mimics the problematic structure: STRING2 = [3, [13, "list", "id"], [10, "fallback"]]
            local joinBlockData = {
                opcode = "operator_join",
                topLevel = false,
                parent = nil,
                inputs = {
                    STRING1 = {1, {10, "|"}},  -- literal text "|"
                    STRING2 = {3, {13, "test list", listId}, {10, "fallback"}}  -- direct list reference
                },
                shadow = false,
                fields = {}
            }

            -- Add the join block using SB3Builder to maintain __keyOrder
            local joinBlockId = "direct_list_test_block"
            SB3Builder.addBlock(stage, joinBlockId, joinBlockData)

            -- Create script to execute this
            local hatId, hatBlock = SB3Builder.Events.whenFlagClicked()
            local setId, setBlock = SB3Builder.Data.setVariable("result", SB3Builder.blockInput(joinBlockId), resultId)

            SB3Builder.addBlock(stage, hatId, hatBlock)
            SB3Builder.addBlock(stage, setId, setBlock)
            SB3Builder.linkBlocks(stage, {hatId, setId})

            local projectJson = SB3Builder.createProject({stage})
            local project = ProjectModel:new(projectJson, {})
            local runtime = Runtime:new(project)
            runtime:initialize()

            runtime:broadcastGreenFlag()
            local iterations = 0
            while #runtime:getActiveThreads() > 0 and iterations < 100 do
                runtime:update(1/60)
                iterations = iterations + 1
            end

            local result = runtime.stage:lookupVariableByNameAndType("result")
            -- This should be "|abc" if list contents are properly converted to string
            -- But currently it might be "|[object Object]" because we return the array directly
            print("DEBUG: Direct list reference result:", result and result.value or "NIL")
            expect(result.value).to.equal("|abc")
        end)
    end)
end)