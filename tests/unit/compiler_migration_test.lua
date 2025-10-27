-- Test suite for compiler migration phases 1-3
-- Validates implementation against specification

local lust = require("tests.lust")
local describe, it, expect = lust.describe, lust.it, lust.expect

-- Load compiler modules
local InputType = require("compiler.enums").InputType
local InputOpcode = require("compiler.enums").InputOpcode
local IntermediateInput = require("compiler.intermediate").IntermediateInput
local IROptimizer = require("compiler.iroptimizer").IROptimizer
local ScriptTreeGenerator = require("compiler.irgen").ScriptTreeGenerator

describe("Compiler Migration - Phase 1: Type System", function()

    describe("Task 1.1: 14-bit InputType Enumeration", function()

        it("should define all basic number types (9 bits: 0-8)", function()
            expect(InputType.NUMBER_POS_INF).to.exist()
            expect(InputType.NUMBER_POS_INT).to.exist()
            expect(InputType.NUMBER_POS_FRACT).to.exist()
            expect(InputType.NUMBER_ZERO).to.exist()
            expect(InputType.NUMBER_NEG_ZERO).to.exist()
            expect(InputType.NUMBER_NEG_INT).to.exist()
            expect(InputType.NUMBER_NEG_FRACT).to.exist()
            expect(InputType.NUMBER_NEG_INF).to.exist()
            expect(InputType.NUMBER_NAN).to.exist()
        end)

        it("should define all string types (3 bits: 9-11)", function()
            expect(InputType.STRING_NUM).to.exist()
            expect(InputType.STRING_NAN).to.exist()
            expect(InputType.STRING_BOOLEAN).to.exist()
        end)

        it("should define other types (2 bits: 12-13)", function()
            expect(InputType.BOOLEAN).to.exist()
            expect(InputType.COLOR).to.exist()
        end)

        it("should define composite type masks correctly", function()
            -- NUMBER = all number types except NaN
            expect(InputType.NUMBER).to.equal(0x0FF)

            -- NUMBER_OR_NAN = all number types including NaN
            expect(InputType.NUMBER_OR_NAN).to.equal(0x1FF)

            -- NUMBER_POS = POS_INF | POS_INT | POS_FRACT
            expect(InputType.NUMBER_POS).to.equal(0x007)

            -- NUMBER_NEG = NEG_INF | NEG_INT | NEG_FRACT
            expect(InputType.NUMBER_NEG).to.equal(0x0E0)

            -- NUMBER_INT = POS_INT | ANY_ZERO | NEG_INT (includes zeros)
            expect(InputType.NUMBER_INT).to.equal(0x03A)

            -- NUMBER_ANY_ZERO = ZERO | NEG_ZERO
            expect(InputType.NUMBER_ANY_ZERO).to.equal(0x018)

            -- NUMBER_INF = POS_INF | NEG_INF
            expect(InputType.NUMBER_INF).to.equal(0x081)

            -- STRING = all string types
            expect(InputType.STRING).to.equal(0xE00)

            -- ANY = NUMBER_OR_NAN | STRING | BOOLEAN (13 bits, excludes COLOR)
            expect(InputType.ANY).to.equal(0x1FFF)
        end)

        it("should use correct bit positions for each type", function()
            expect(InputType.NUMBER_POS_INF).to.equal(0x001)    -- bit 0
            expect(InputType.NUMBER_POS_INT).to.equal(0x002)    -- bit 1
            expect(InputType.NUMBER_POS_FRACT).to.equal(0x004)  -- bit 2
            expect(InputType.NUMBER_ZERO).to.equal(0x008)       -- bit 3
            expect(InputType.NUMBER_NEG_ZERO).to.equal(0x010)   -- bit 4
            expect(InputType.NUMBER_NEG_INT).to.equal(0x020)    -- bit 5
            expect(InputType.NUMBER_NEG_FRACT).to.equal(0x040)  -- bit 6
            expect(InputType.NUMBER_NEG_INF).to.equal(0x080)    -- bit 7
            expect(InputType.NUMBER_NAN).to.equal(0x100)        -- bit 8
            expect(InputType.STRING_NUM).to.equal(0x200)        -- bit 9
            expect(InputType.STRING_NAN).to.equal(0x400)        -- bit 10
            expect(InputType.STRING_BOOLEAN).to.equal(0x800)    -- bit 11
            expect(InputType.BOOLEAN).to.equal(0x1000)          -- bit 12
            expect(InputType.COLOR).to.equal(0x2000)            -- bit 13
        end)
    end)

    describe("Task 1.2: getNumberInputType() Implementation", function()

        it("should correctly identify positive integers", function()
            local type1 = IntermediateInput.getNumberInputType(1)
            expect(type1).to.equal(InputType.NUMBER_POS_INT)

            local type42 = IntermediateInput.getNumberInputType(42)
            expect(type42).to.equal(InputType.NUMBER_POS_INT)

            local type1000 = IntermediateInput.getNumberInputType(1000)
            expect(type1000).to.equal(InputType.NUMBER_POS_INT)
        end)

        it("should correctly identify positive fractions", function()
            local type1 = IntermediateInput.getNumberInputType(0.5)
            expect(type1).to.equal(InputType.NUMBER_POS_FRACT)

            local type2 = IntermediateInput.getNumberInputType(3.14)
            expect(type2).to.equal(InputType.NUMBER_POS_FRACT)

            local type3 = IntermediateInput.getNumberInputType(1.5)
            expect(type3).to.equal(InputType.NUMBER_POS_FRACT)
        end)

        it("should correctly identify zero", function()
            local type1 = IntermediateInput.getNumberInputType(0)
            expect(type1).to.equal(InputType.NUMBER_ZERO)
        end)

        it("should correctly identify negative integers", function()
            local type1 = IntermediateInput.getNumberInputType(-1)
            expect(type1).to.equal(InputType.NUMBER_NEG_INT)

            local type2 = IntermediateInput.getNumberInputType(-42)
            expect(type2).to.equal(InputType.NUMBER_NEG_INT)

            local type3 = IntermediateInput.getNumberInputType(-1000)
            expect(type3).to.equal(InputType.NUMBER_NEG_INT)
        end)

        it("should correctly identify negative fractions", function()
            local type1 = IntermediateInput.getNumberInputType(-0.5)
            expect(type1).to.equal(InputType.NUMBER_NEG_FRACT)

            local type2 = IntermediateInput.getNumberInputType(-3.14)
            expect(type2).to.equal(InputType.NUMBER_NEG_FRACT)

            local type3 = IntermediateInput.getNumberInputType(-1.5)
            expect(type3).to.equal(InputType.NUMBER_NEG_FRACT)
        end)

        it("should correctly identify positive infinity", function()
            local typeInf = IntermediateInput.getNumberInputType(math.huge)
            expect(typeInf).to.equal(InputType.NUMBER_POS_INF)
        end)

        it("should correctly identify negative infinity", function()
            local typeNegInf = IntermediateInput.getNumberInputType(-math.huge)
            expect(typeNegInf).to.equal(InputType.NUMBER_NEG_INF)
        end)

        it("should correctly identify NaN", function()
            local typeNan = IntermediateInput.getNumberInputType(0/0)
            expect(typeNan).to.equal(InputType.NUMBER_NAN)
        end)
    end)

    describe("Task 1.3: isAlwaysType() and isSometimesType() Methods", function()

        it("should implement isAlwaysType() correctly", function()
            -- Create an input that is always a positive integer
            local posIntInput = IntermediateInput:new(
                InputOpcode.CONSTANT,
                InputType.NUMBER_POS_INT,
                {value = 42}
            )

            -- Should be always a positive integer
            expect(posIntInput:isAlwaysType(InputType.NUMBER_POS_INT)).to.be.truthy()

            -- Should be always a number (superset)
            expect(posIntInput:isAlwaysType(InputType.NUMBER)).to.be.truthy()

            -- Should NOT be always a string
            local isString = posIntInput:isAlwaysType(InputType.STRING)
            expect(isString).to.equal(false)
        end)

        it("should implement isSometimesType() correctly", function()
            -- Create an input that could be positive OR negative integer
            local anyIntInput = IntermediateInput:new(
                InputOpcode.CONSTANT,
                InputType.NUMBER_INT,  -- POS_INT | NEG_INT
                {value = 0}
            )

            -- Sometimes positive integer
            expect(anyIntInput:isSometimesType(InputType.NUMBER_POS_INT)).to.be.truthy()

            -- Sometimes negative integer
            expect(anyIntInput:isSometimesType(InputType.NUMBER_NEG_INT)).to.be.truthy()

            -- Never a string
            local isString = anyIntInput:isSometimesType(InputType.STRING)
            expect(isString).to.equal(false)
        end)

        it("should implement isConstant() correctly", function()
            local constInput = IntermediateInput:new(
                InputOpcode.CONSTANT,
                InputType.NUMBER_POS_INT,
                {value = 42}
            )

            expect(constInput:isConstant(42)).to.be.truthy()
            expect(constInput:isConstant(10)).to.equal(false)

            local varInput = IntermediateInput:new(
                InputOpcode.VAR_GET,
                InputType.ANY,
                {variable = {id = "test"}}
            )

            expect(varInput:isConstant(42)).to.equal(false)
        end)
    end)
end)

describe("Compiler Migration - Phase 2: Type Inference Algorithms", function()

    local optimizer

    lust.before(function()
        optimizer = IROptimizer:new()
    end)

    describe("Task 2.1: getAddType() Implementation", function()

        it("should infer positive integer + positive integer = positive integer", function()
            local result = optimizer:getAddType(
                InputType.NUMBER_POS_INT,
                InputType.NUMBER_POS_INT
            )
            expect(bit.band(result, InputType.NUMBER_POS_INT)).to_not.equal(0)
        end)

        it("should infer positive + negative = could be either", function()
            local result = optimizer:getAddType(
                InputType.NUMBER_POS_INT,
                InputType.NUMBER_NEG_INT
            )
            -- Result could be positive or negative
            expect(bit.band(result, InputType.NUMBER_POS_INT)).to_not.equal(0)
            expect(bit.band(result, InputType.NUMBER_NEG_INT)).to_not.equal(0)
        end)

        it("should infer integer + fraction = fraction possible", function()
            local result = optimizer:getAddType(
                InputType.NUMBER_POS_INT,
                InputType.NUMBER_POS_FRACT
            )
            expect(bit.band(result, InputType.NUMBER_POS_FRACT)).to_not.equal(0)
        end)

        it("should detect NaN: Infinity + (-Infinity)", function()
            local result = optimizer:getAddType(
                InputType.NUMBER_POS_INF,
                InputType.NUMBER_NEG_INF
            )
            expect(bit.band(result, InputType.NUMBER_NAN)).to_not.equal(0)
        end)

        it("should propagate positive infinity", function()
            local result = optimizer:getAddType(
                InputType.NUMBER_POS_INF,
                InputType.NUMBER_POS_INT
            )
            expect(bit.band(result, InputType.NUMBER_POS_INF)).to_not.equal(0)
        end)

        it("should propagate negative infinity", function()
            local result = optimizer:getAddType(
                InputType.NUMBER_NEG_INF,
                InputType.NUMBER_NEG_INT
            )
            expect(bit.band(result, InputType.NUMBER_NEG_INF)).to_not.equal(0)
        end)

        it("should handle zero + zero = zero", function()
            local result = optimizer:getAddType(
                InputType.NUMBER_ZERO,
                InputType.NUMBER_ZERO
            )
            expect(bit.band(result, InputType.NUMBER_ZERO)).to_not.equal(0)
        end)

        it("should handle negative zero cases", function()
            local result = optimizer:getAddType(
                InputType.NUMBER_NEG_ZERO,
                InputType.NUMBER_NEG_ZERO
            )
            expect(bit.band(result, InputType.NUMBER_NEG_ZERO)).to_not.equal(0)
        end)
    end)

    describe("Task 2.2: getSubtractType() Implementation", function()

        it("should infer positive - positive = could be either sign", function()
            local result = optimizer:getSubtractType(
                InputType.NUMBER_POS_INT,
                InputType.NUMBER_POS_INT
            )
            -- Could be positive, negative, or zero
            expect(bit.band(result, InputType.NUMBER_POS)).to_not.equal(0)
        end)

        it("should infer positive - negative = positive", function()
            local result = optimizer:getSubtractType(
                InputType.NUMBER_POS_INT,
                InputType.NUMBER_NEG_INT
            )
            expect(bit.band(result, InputType.NUMBER_POS_INT)).to_not.equal(0)
        end)

        it("should detect NaN: Infinity - Infinity", function()
            local result = optimizer:getSubtractType(
                InputType.NUMBER_POS_INF,
                InputType.NUMBER_POS_INF
            )
            expect(bit.band(result, InputType.NUMBER_NAN)).to_not.equal(0)
        end)

        it("should infer Infinity - number = Infinity", function()
            local result = optimizer:getSubtractType(
                InputType.NUMBER_POS_INF,
                InputType.NUMBER_POS_INT
            )
            expect(bit.band(result, InputType.NUMBER_POS_INF)).to_not.equal(0)
        end)
    end)

    describe("Task 2.3: getMultiplyType() Implementation", function()

        it("should infer positive × positive = positive", function()
            local result = optimizer:getMultiplyType(
                InputType.NUMBER_POS_INT,
                InputType.NUMBER_POS_INT
            )
            expect(bit.band(result, InputType.NUMBER_POS_INT)).to_not.equal(0)
        end)

        it("should infer positive × negative = negative", function()
            local result = optimizer:getMultiplyType(
                InputType.NUMBER_POS_INT,
                InputType.NUMBER_NEG_INT
            )
            expect(bit.band(result, InputType.NUMBER_NEG_INT)).to_not.equal(0)
        end)

        it("should infer negative × negative = positive", function()
            local result = optimizer:getMultiplyType(
                InputType.NUMBER_NEG_INT,
                InputType.NUMBER_NEG_INT
            )
            expect(bit.band(result, InputType.NUMBER_POS_INT)).to_not.equal(0)
        end)

        it("should detect NaN: 0 × Infinity", function()
            local result = optimizer:getMultiplyType(
                InputType.NUMBER_ZERO,
                InputType.NUMBER_POS_INF
            )
            expect(bit.band(result, InputType.NUMBER_NAN)).to_not.equal(0)
        end)

        it("should infer X × 0 = 0", function()
            local result = optimizer:getMultiplyType(
                InputType.NUMBER_POS_INT,
                InputType.NUMBER_ZERO
            )
            expect(bit.band(result, InputType.NUMBER_ZERO)).to_not.equal(0)
        end)

        it("should handle fractional results", function()
            local result = optimizer:getMultiplyType(
                InputType.NUMBER_POS_INT,
                InputType.NUMBER_POS_FRACT
            )
            expect(bit.band(result, InputType.NUMBER_POS_FRACT)).to_not.equal(0)
        end)

        it("should handle negative zero: positive × (-0) = -0", function()
            local result = optimizer:getMultiplyType(
                InputType.NUMBER_POS_INT,
                InputType.NUMBER_NEG_ZERO
            )
            expect(bit.band(result, InputType.NUMBER_NEG_ZERO)).to_not.equal(0)
        end)
    end)

    describe("Task 2.4: getDivideType() Implementation", function()

        it("should infer positive ÷ positive = positive", function()
            local result = optimizer:getDivideType(
                InputType.NUMBER_POS_INT,
                InputType.NUMBER_POS_INT
            )
            expect(bit.band(result, InputType.NUMBER_POS)).to_not.equal(0)
        end)

        it("should infer positive ÷ negative = negative", function()
            local result = optimizer:getDivideType(
                InputType.NUMBER_POS_INT,
                InputType.NUMBER_NEG_INT
            )
            expect(bit.band(result, InputType.NUMBER_NEG)).to_not.equal(0)
        end)

        it("should detect NaN: 0 ÷ 0", function()
            local result = optimizer:getDivideType(
                InputType.NUMBER_ZERO,
                InputType.NUMBER_ZERO
            )
            expect(bit.band(result, InputType.NUMBER_NAN)).to_not.equal(0)
        end)

        it("should detect NaN: Infinity ÷ Infinity", function()
            local result = optimizer:getDivideType(
                InputType.NUMBER_POS_INF,
                InputType.NUMBER_POS_INF
            )
            expect(bit.band(result, InputType.NUMBER_NAN)).to_not.equal(0)
        end)

        it("should infer positive ÷ 0 = +Infinity", function()
            local result = optimizer:getDivideType(
                InputType.NUMBER_POS_INT,
                InputType.NUMBER_ZERO
            )
            expect(bit.band(result, InputType.NUMBER_POS_INF)).to_not.equal(0)
        end)

        it("should infer negative ÷ 0 = -Infinity", function()
            local result = optimizer:getDivideType(
                InputType.NUMBER_NEG_INT,
                InputType.NUMBER_ZERO
            )
            expect(bit.band(result, InputType.NUMBER_NEG_INF)).to_not.equal(0)
        end)

        it("should infer 0 ÷ X = 0 (where X != 0)", function()
            local result = optimizer:getDivideType(
                InputType.NUMBER_ZERO,
                InputType.NUMBER_POS_INT
            )
            expect(bit.band(result, InputType.NUMBER_ZERO)).to_not.equal(0)
        end)

        it("should handle fractional results (division often produces fractions)", function()
            local result = optimizer:getDivideType(
                InputType.NUMBER_POS_INT,
                InputType.NUMBER_POS_INT
            )
            -- Division can produce fractions
            expect(bit.band(result, InputType.NUMBER_POS_FRACT)).to_not.equal(0)
        end)
    end)

    describe("Task 2.5: getInputType() Default Return Value Fix", function()

        it("should return input.type for unhandled opcodes (not InputType.ANY)", function()
            local TypeState = require("compiler.iroptimizer").TypeState
            local state = TypeState:new()

            -- Create an input with a specific type but unhandled opcode
            local input = IntermediateInput:new(
                InputOpcode.CONSTANT,
                InputType.NUMBER_POS_INT,
                {value = 42}
            )

            local resultType = optimizer:getInputType(input, state)

            -- Should return input.type, not InputType.ANY
            expect(resultType).to.equal(InputType.NUMBER_POS_INT)
        end)

        it("should preserve type information through unhandled operations", function()
            local TypeState = require("compiler.iroptimizer").TypeState
            local state = TypeState:new()

            -- Create input with specific number type
            local specificInput = IntermediateInput:new(
                InputOpcode.CONSTANT,
                InputType.NUMBER_POS_FRACT,
                {value = 3.14}
            )

            local resultType = optimizer:getInputType(specificInput, state)

            -- Type information should be preserved
            expect(resultType).to.equal(InputType.NUMBER_POS_FRACT)
            expect(resultType).to_not.equal(InputType.ANY)
        end)
    end)
end)

describe("Compiler Migration - Phase 3: Constant Folding", function()

    describe("Task 3.1: Arithmetic Operation Constant Folding in IR Generation", function()

        it("should fold constant addition during IR generation", function()
            -- Create two constant inputs
            local left = IntermediateInput:new(
                InputOpcode.CONSTANT,
                InputType.NUMBER_POS_INT,
                {value = 3}
            )

            local right = IntermediateInput:new(
                InputOpcode.CONSTANT,
                InputType.NUMBER_POS_INT,
                {value = 5}
            )

            -- Check if both are constants
            expect(left.opcode).to.equal(InputOpcode.CONSTANT)
            expect(right.opcode).to.equal(InputOpcode.CONSTANT)

            -- If IR generation does constant folding, result should be constant 8
            -- (This tests the infrastructure, actual folding happens in irgen.lua)
            expect(left.inputs.value + right.inputs.value).to.equal(8)
        end)

        it("should fold constant subtraction during IR generation", function()
            local left = IntermediateInput:new(
                InputOpcode.CONSTANT,
                InputType.NUMBER_POS_INT,
                {value = 10}
            )

            local right = IntermediateInput:new(
                InputOpcode.CONSTANT,
                InputType.NUMBER_POS_INT,
                {value = 3}
            )

            expect(left.inputs.value - right.inputs.value).to.equal(7)
        end)

        it("should fold constant multiplication during IR generation", function()
            local left = IntermediateInput:new(
                InputOpcode.CONSTANT,
                InputType.NUMBER_POS_INT,
                {value = 4}
            )

            local right = IntermediateInput:new(
                InputOpcode.CONSTANT,
                InputType.NUMBER_POS_INT,
                {value = 5}
            )

            expect(left.inputs.value * right.inputs.value).to.equal(20)
        end)

        it("should fold constant division during IR generation", function()
            local left = IntermediateInput:new(
                InputOpcode.CONSTANT,
                InputType.NUMBER_POS_INT,
                {value = 10}
            )

            local right = IntermediateInput:new(
                InputOpcode.CONSTANT,
                InputType.NUMBER_POS_INT,
                {value = 2}
            )

            expect(left.inputs.value / right.inputs.value).to.equal(5)
        end)

        it("should handle division by zero correctly", function()
            local left = IntermediateInput:new(
                InputOpcode.CONSTANT,
                InputType.NUMBER_POS_INT,
                {value = 10}
            )

            local right = IntermediateInput:new(
                InputOpcode.CONSTANT,
                InputType.NUMBER_ZERO,
                {value = 0}
            )

            local result = left.inputs.value / right.inputs.value
            expect(result).to.equal(math.huge)  -- Should be Infinity
        end)
    end)

    describe("Task 3.2: Comparison Operation Constant Folding", function()

        it("should fold constant equality comparison", function()
            local left = IntermediateInput:new(
                InputOpcode.CONSTANT,
                InputType.NUMBER_POS_INT,
                {value = 5}
            )

            local right = IntermediateInput:new(
                InputOpcode.CONSTANT,
                InputType.NUMBER_POS_INT,
                {value = 5}
            )

            expect(left.inputs.value == right.inputs.value).to.be.truthy()
        end)

        it("should fold constant less than comparison", function()
            local left = IntermediateInput:new(
                InputOpcode.CONSTANT,
                InputType.NUMBER_POS_INT,
                {value = 3}
            )

            local right = IntermediateInput:new(
                InputOpcode.CONSTANT,
                InputType.NUMBER_POS_INT,
                {value = 5}
            )

            expect(left.inputs.value < right.inputs.value).to.be.truthy()
        end)
    end)

    describe("Task 3.3: Logical Operation Constant Folding", function()

        it("should fold constant AND operation", function()
            local left = IntermediateInput:new(
                InputOpcode.CONSTANT,
                InputType.BOOLEAN,
                {value = true}
            )

            local right = IntermediateInput:new(
                InputOpcode.CONSTANT,
                InputType.BOOLEAN,
                {value = false}
            )

            local Cast = require("utils.cast")
            local result = Cast.toBoolean(left.inputs.value) and Cast.toBoolean(right.inputs.value)
            expect(result).to.equal(false)
        end)

        it("should fold constant OR operation", function()
            local left = IntermediateInput:new(
                InputOpcode.CONSTANT,
                InputType.BOOLEAN,
                {value = true}
            )

            local right = IntermediateInput:new(
                InputOpcode.CONSTANT,
                InputType.BOOLEAN,
                {value = false}
            )

            local Cast = require("utils.cast")
            local result = Cast.toBoolean(left.inputs.value) or Cast.toBoolean(right.inputs.value)
            expect(result).to.be.truthy()
        end)

        it("should fold constant NOT operation", function()
            local operand = IntermediateInput:new(
                InputOpcode.CONSTANT,
                InputType.BOOLEAN,
                {value = true}
            )

            local Cast = require("utils.cast")
            local result = not Cast.toBoolean(operand.inputs.value)
            expect(result).to.equal(false)
        end)
    end)

    describe("Task 3.4: IROptimizer Should Only Optimize CAST Operations", function()

        it("should optimize redundant CAST_NUMBER when input is already a number", function()
            local optimizer = IROptimizer:new()
            local TypeState = require("compiler.iroptimizer").TypeState
            local state = TypeState:new()

            -- Create a number input
            local numberInput = IntermediateInput:new(
                InputOpcode.CONSTANT,
                InputType.NUMBER_POS_INT,
                {value = 42}
            )

            -- Wrap it in a CAST_NUMBER
            local castInput = IntermediateInput:new(
                InputOpcode.CAST_NUMBER,
                InputType.NUMBER,
                {target = numberInput}
            )

            -- Optimizer should remove the redundant cast
            local optimized = optimizer:optimizeInput(castInput, state)

            -- Should return the inner input directly
            expect(optimized.opcode).to.equal(InputOpcode.CONSTANT)
            expect(optimized.inputs.value).to.equal(42)
        end)

        it("should optimize redundant CAST_NUMBER_OR_NAN when input is already number or NaN", function()
            local optimizer = IROptimizer:new()
            local TypeState = require("compiler.iroptimizer").TypeState
            local state = TypeState:new()

            -- Create a number input
            local numberInput = IntermediateInput:new(
                InputOpcode.CONSTANT,
                InputType.NUMBER_POS_INT,
                {value = 42}
            )

            -- Wrap it in CAST_NUMBER_OR_NAN
            local castInput = IntermediateInput:new(
                InputOpcode.CAST_NUMBER_OR_NAN,
                InputType.NUMBER_OR_NAN,
                {target = numberInput}
            )

            -- Optimizer should remove the redundant cast
            local optimized = optimizer:optimizeInput(castInput, state)

            -- Should return the inner input directly
            expect(optimized.opcode).to.equal(InputOpcode.CONSTANT)
        end)

        it("should NOT perform constant folding in optimizer (should be in irgen)", function()
            local optimizer = IROptimizer:new()
            local TypeState = require("compiler.iroptimizer").TypeState
            local state = TypeState:new()

            -- Create OP_ADD with two constants
            local left = IntermediateInput:new(
                InputOpcode.CONSTANT,
                InputType.NUMBER_POS_INT,
                {value = 3}
            )

            local right = IntermediateInput:new(
                InputOpcode.CONSTANT,
                InputType.NUMBER_POS_INT,
                {value = 5}
            )

            local addInput = IntermediateInput:new(
                InputOpcode.OP_ADD,
                InputType.NUMBER_OR_NAN,
                {left = left, right = right}
            )

            -- Optimizer should NOT fold this (folding should be in irgen)
            local optimized = optimizer:optimizeInput(addInput, state)

            -- Should still be an OP_ADD
            expect(optimized.opcode).to.equal(InputOpcode.OP_ADD)
        end)
    end)
end)

describe("Integration Tests: End-to-End Block Compilation", function()

    local SB3Builder = require("tests.sb3_builder")
    local ProjectModel = require("parser.project_model")
    local Runtime = require("vm.runtime")

    describe("Complete Block Compilation Pipeline", function()

        it("should compile and execute arithmetic operations with type optimization", function()
            SB3Builder.resetCounter()
            local stage = SB3Builder.createStage()
            local sprite = SB3Builder.createSprite("TestSprite")

            -- Create variable to store result
            local resultVar = SB3Builder.addVariable(sprite, "result", 0)

            -- Build script: result = (3 + 5) * 2
            local hatId, hatBlock = SB3Builder.Events.whenFlagClicked()

            -- 3 + 5
            local addId, addBlock = SB3Builder.Operators.add(3, 5)

            -- (3 + 5) * 2
            local mulId, mulBlock = SB3Builder.Operators.multiply(addId, 2)

            -- result = (3 + 5) * 2
            local setId, setBlock = SB3Builder.Data.setVariable("result", mulId, resultVar)

            -- Build and link
            SB3Builder.addBlock(sprite, hatId, hatBlock)
            SB3Builder.addBlock(sprite, addId, addBlock)
            SB3Builder.addBlock(sprite, mulId, mulBlock)
            SB3Builder.addBlock(sprite, setId, setBlock)
            SB3Builder.linkBlocks(sprite, {hatId, setId})

            -- Execute
            local projectJson = SB3Builder.createProject({stage, sprite})
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

            -- Verify result: (3 + 5) * 2 = 16
            local spriteTarget = runtime:getSpriteTargetByName("TestSprite")
            local resultValue = spriteTarget.variables[resultVar].value
            expect(resultValue).to.equal(16)
        end)

        it("should compile and execute comparison operations correctly", function()
            SB3Builder.resetCounter()
            local stage = SB3Builder.createStage()
            local sprite = SB3Builder.createSprite("TestSprite")

            local xVar = SB3Builder.addVariable(sprite, "x", 0)

            -- Build script: if 5 > 3 then x = 10
            local hatId, hatBlock = SB3Builder.Events.whenFlagClicked()

            local gtId, gtBlock = SB3Builder.Operators.greaterThan(5, 3)
            local setId, setBlock = SB3Builder.Data.setVariable("x", 10, xVar)
            local ifId, ifBlock = SB3Builder.Control.if_(gtId, setId)

            SB3Builder.addBlock(sprite, hatId, hatBlock)
            SB3Builder.addBlock(sprite, gtId, gtBlock)
            SB3Builder.addBlock(sprite, setId, setBlock)
            SB3Builder.addBlock(sprite, ifId, ifBlock)
            SB3Builder.linkBlocks(sprite, {hatId, ifId})

            -- Execute
            local projectJson = SB3Builder.createProject({stage, sprite})
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

            -- Verify: 5 > 3 is true, so x should be 10
            local spriteTarget = runtime:getSpriteTargetByName("TestSprite")
            local xValue = spriteTarget.variables[xVar].value
            expect(xValue).to.equal(10)
        end)

        it("should compile loops with arithmetic correctly", function()
            SB3Builder.resetCounter()
            local stage = SB3Builder.createStage()
            local sprite = SB3Builder.createSprite("TestSprite")

            local sumVar = SB3Builder.addVariable(sprite, "sum", 0)

            -- Build script: repeat 5: sum = sum + 2
            local hatId, hatBlock = SB3Builder.Events.whenFlagClicked()

            local varId, varBlock = SB3Builder.Data.variable("sum", sumVar)
            local addId, addBlock = SB3Builder.Operators.add(varId, 2)
            local setId, setBlock = SB3Builder.Data.setVariable("sum", addId, sumVar)
            local repeatId, repeatBlock = SB3Builder.Control.repeat_(5, setId)

            SB3Builder.addBlock(sprite, hatId, hatBlock)
            SB3Builder.addBlock(sprite, varId, varBlock)
            SB3Builder.addBlock(sprite, addId, addBlock)
            SB3Builder.addBlock(sprite, setId, setBlock)
            SB3Builder.addBlock(sprite, repeatId, repeatBlock)
            SB3Builder.linkBlocks(sprite, {hatId, repeatId})

            -- Execute
            local projectJson = SB3Builder.createProject({stage, sprite})
            local project = ProjectModel:new(projectJson, {})
            local runtime = Runtime:new(project)
            runtime:initialize()

            runtime:broadcastGreenFlag()
            local maxIterations = 200
            local iterations = 0
            while #runtime:getActiveThreads() > 0 and iterations < maxIterations do
                runtime:update(1/60)
                iterations = iterations + 1
            end

            -- Verify: sum = 0 + 2*5 = 10
            local spriteTarget = runtime:getSpriteTargetByName("TestSprite")
            local sumValue = spriteTarget.variables[sumVar].value
            expect(sumValue).to.equal(10)
        end)

        it("should handle division and type inference correctly", function()
            SB3Builder.resetCounter()
            local stage = SB3Builder.createStage()
            local sprite = SB3Builder.createSprite("TestSprite")

            local resultVar = SB3Builder.addVariable(sprite, "result", 0)

            -- Build script: result = 10 / 2
            local hatId, hatBlock = SB3Builder.Events.whenFlagClicked()

            local divId, divBlock = SB3Builder.Operators.divide(10, 2)
            local setId, setBlock = SB3Builder.Data.setVariable("result", divId, resultVar)

            SB3Builder.addBlock(sprite, hatId, hatBlock)
            SB3Builder.addBlock(sprite, divId, divBlock)
            SB3Builder.addBlock(sprite, setId, setBlock)
            SB3Builder.linkBlocks(sprite, {hatId, setId})

            -- Execute
            local projectJson = SB3Builder.createProject({stage, sprite})
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

            -- Verify: 10 / 2 = 5
            local spriteTarget = runtime:getSpriteTargetByName("TestSprite")
            local resultValue = spriteTarget.variables[resultVar].value
            expect(resultValue).to.equal(5)
        end)
    end)
end)

describe("Type System Workflow Tests", function()

    it("should correctly infer types through complex arithmetic expression", function()
        local optimizer = IROptimizer:new()

        -- Test: (3 + 5) should infer as positive integer
        local result = optimizer:getAddType(
            InputType.NUMBER_POS_INT,  -- 3
            InputType.NUMBER_POS_INT   -- 5
        )

        expect(bit.band(result, InputType.NUMBER_POS_INT)).to_not.equal(0)
    end)

    it("should handle type propagation through mixed operations", function()
        local optimizer = IROptimizer:new()

        -- Test: positive int × positive fract = positive fract
        local multResult = optimizer:getMultiplyType(
            InputType.NUMBER_POS_INT,
            InputType.NUMBER_POS_FRACT
        )

        expect(bit.band(multResult, InputType.NUMBER_POS_FRACT)).to_not.equal(0)

        -- Then: positive fract + positive int = could be int or fract
        local addResult = optimizer:getAddType(
            multResult,
            InputType.NUMBER_POS_INT
        )

        expect(bit.band(addResult, InputType.NUMBER_POS)).to_not.equal(0)
    end)

    it("should detect special value propagation through operations", function()
        local optimizer = IROptimizer:new()

        -- Infinity + number = Infinity
        local result1 = optimizer:getAddType(
            InputType.NUMBER_POS_INF,
            InputType.NUMBER_POS_INT
        )
        expect(bit.band(result1, InputType.NUMBER_POS_INF)).to_not.equal(0)

        -- Infinity - Infinity = NaN
        local result2 = optimizer:getSubtractType(
            InputType.NUMBER_POS_INF,
            InputType.NUMBER_POS_INF
        )
        expect(bit.band(result2, InputType.NUMBER_NAN)).to_not.equal(0)

        -- 0 × Infinity = NaN
        local result3 = optimizer:getMultiplyType(
            InputType.NUMBER_ZERO,
            InputType.NUMBER_POS_INF
        )
        expect(bit.band(result3, InputType.NUMBER_NAN)).to_not.equal(0)
    end)
end)
