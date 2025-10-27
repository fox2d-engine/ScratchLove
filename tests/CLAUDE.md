# Testing Framework & SB3Builder API Reference

## Overview

The project uses the **lust testing framework** with a modular **SB3Builder** API for creating test scenarios. This document provides comprehensive documentation for writing tests in this codebase.

## Testing Framework Architecture

**Core Framework** (`tests/lust/`)
- Lust testing framework with colorized output
- BDD-style describe/it syntax for organizing tests
- Built-in expectation assertions
- Test lifecycle management and reporting

**Test Entry Point** (`tests/run.lua`)
- Main test runner that loads all test suites
- Sets up mock Love2D environment
- Provides unified test execution and reporting

**Test Utilities**
- `tests/sb3_builder/`: Modular SB3 project builder with category-based API
- `tests/mocks/love_mock.lua`: Love2D API mocking for headless test execution

## SB3Builder Modular API Reference

The SB3Builder uses a modular, category-based API for better organization and type safety. **Never use any backward compatibility aliases** - always use the full modular path.

### Core Functions

```lua
-- Project setup
SB3Builder.resetCounter()
local stage = SB3Builder.createStage()
local sprite = SB3Builder.createSprite("SpriteName")

-- Variable/list management
local variableId = SB3Builder.addVariable(stage, "varName", initialValue)
local listId = SB3Builder.addList(stage, "listName", initialValues)
local broadcastId = SB3Builder.addBroadcast(stage, "message")

-- Block management
SB3Builder.addBlock(target, blockId, blockData)
SB3Builder.linkBlocks(target, {blockId1, blockId2, blockId3})

-- Project creation
local projectJson = SB3Builder.createProject({stage, sprite1, sprite2})
```

### Events (Hat Blocks)

```lua
-- Event triggers
local hatId, hatBlock = SB3Builder.Events.whenFlagClicked(x, y)
local hatId, hatBlock = SB3Builder.Events.whenIReceive(message, broadcastId)
local broadcastId, broadcastBlock = SB3Builder.Events.broadcast(message, broadcastId)
local broadcastId, broadcastBlock = SB3Builder.Events.broadcastAndWait(message, broadcastId)
local hatId, hatBlock = SB3Builder.Events.whenKeyPressed(key)
local hatId, hatBlock = SB3Builder.Events.whenThisSpriteClicked()
```

### Motion Blocks

```lua
-- Basic movement
local moveId, moveBlock = SB3Builder.Motion.moveSteps(steps)
local turnId, turnBlock = SB3Builder.Motion.turnRight(degrees)
local turnId, turnBlock = SB3Builder.Motion.turnLeft(degrees)

-- Positioning
local gotoId, gotoBlock = SB3Builder.Motion.goToXY(x, y)
local gotoId, gotoBlock = SB3Builder.Motion.goTo(target)  -- "_mouse_", "_random_", or sprite name
local pointId, pointBlock = SB3Builder.Motion.pointInDirection(direction)
local pointId, pointBlock = SB3Builder.Motion.pointTowards(towards)

-- Coordinate changes
local setId, setBlock = SB3Builder.Motion.setX(x)
local setId, setBlock = SB3Builder.Motion.setY(y)
local changeId, changeBlock = SB3Builder.Motion.changeXBy(dx)
local changeId, changeBlock = SB3Builder.Motion.changeYBy(dy)

-- Animation
local glideId, glideBlock = SB3Builder.Motion.glideToXY(secs, x, y)
local glideId, glideBlock = SB3Builder.Motion.glideTo(secs, target)

-- Rotation and boundaries
local styleId, styleBlock = SB3Builder.Motion.setRotationStyle(style)  -- "all around", "left-right", "don't rotate"
local bounceId, bounceBlock = SB3Builder.Motion.ifOnEdgeBounce()

-- Reporters
local xId, xBlock = SB3Builder.Motion.xPosition()
local yId, yBlock = SB3Builder.Motion.yPosition()
local dirId, dirBlock = SB3Builder.Motion.direction()
```

### Control Flow Blocks

```lua
-- Loops
local repeatId, repeatBlock = SB3Builder.Control.repeat_(times, substackId)
local foreverIds, foreverBlock = SB3Builder.Control.forever(substackId)
local untilId, untilBlock = SB3Builder.Control.repeatUntil(conditionId, substackId)
local whileId, whileBlock = SB3Builder.Control.repeatWhile(conditionId, substackId)
local forEachId, forEachBlock = SB3Builder.Control.forEach(varName, value, substackId)

-- Conditionals
local ifId, ifBlock = SB3Builder.Control.if_(conditionId, substackId)
local ifElseId, ifElseBlock = SB3Builder.Control.ifElse(conditionId, substackId, substack2Id)

-- Timing
local waitId, waitBlock = SB3Builder.Control.wait(duration)
local waitUntilId, waitUntilBlock = SB3Builder.Control.waitUntil(conditionId)

-- Script control
local stopId, stopBlock = SB3Builder.Control.stop(stopOption)  -- "all", "this script", "other scripts in sprite"
local stopId, stopBlock = SB3Builder.Control.stopAll()
local stopId, stopBlock = SB3Builder.Control.stopThisScript()
local stopId, stopBlock = SB3Builder.Control.stopOtherScriptsInSprite()

-- Clones
local hatId, hatBlock = SB3Builder.Control.whenStartAsClone(x, y)
local cloneId, cloneBlock, menuId, menuBlock = SB3Builder.Control.createCloneOf(target)
local deleteId, deleteBlock = SB3Builder.Control.deleteThisClone()

-- Performance
local allAtOnceId, allAtOnceBlock = SB3Builder.Control.allAtOnce(substackId)
```

### Data Blocks

```lua
-- Variables
local setId, setBlock = SB3Builder.Data.setVariable(name, value, variableId)
local changeId, changeBlock = SB3Builder.Data.changeVariable(name, amount, variableId)
local varId, varBlock = SB3Builder.Data.variable(name, variableId)

-- Lists
local addId, addBlock = SB3Builder.Data.addToList(item, listName, listId)
local deleteId, deleteBlock = SB3Builder.Data.deleteFromList(index, listName, listId)
local deleteAllId, deleteAllBlock = SB3Builder.Data.deleteAllOfList(listName, listId)
local insertId, insertBlock = SB3Builder.Data.insertAtList(index, item, listName, listId)
local replaceId, replaceBlock = SB3Builder.Data.replaceItemOfList(index, item, listName, listId)
local itemId, itemBlock = SB3Builder.Data.itemOfList(index, listName, listId)
local indexId, indexBlock = SB3Builder.Data.itemNumOfList(item, listName, listId)
local lengthId, lengthBlock = SB3Builder.Data.lengthOfList(listName, listId)
local contentsId, contentsBlock = SB3Builder.Data.listContents(listName, listId)
local containsId, containsBlock = SB3Builder.Data.listContainsItem(item, listName, listId)
```

### Operators

```lua
-- Arithmetic
local addId, addBlock = SB3Builder.Operators.add(num1, num2)
local subId, subBlock = SB3Builder.Operators.subtract(num1, num2)
local mulId, mulBlock = SB3Builder.Operators.multiply(num1, num2)
local divId, divBlock = SB3Builder.Operators.divide(num1, num2)
local modId, modBlock = SB3Builder.Operators.mod(num1, num2)

-- Comparisons
local eqId, eqBlock = SB3Builder.Operators.equals(operand1, operand2)
local ltId, ltBlock = SB3Builder.Operators.lessThan(operand1, operand2)
local gtId, gtBlock = SB3Builder.Operators.greaterThan(operand1, operand2)

-- Logic
local andId, andBlock = SB3Builder.Operators.and_(operand1, operand2)
local orId, orBlock = SB3Builder.Operators.or_(operand1, operand2)
local notId, notBlock = SB3Builder.Operators.not_(operand)

-- Text
local joinId, joinBlock = SB3Builder.Operators.join(string1, string2)
local letterId, letterBlock = SB3Builder.Operators.letterOf(letter, string)
local lengthId, lengthBlock = SB3Builder.Operators.lengthOf(string)
local containsId, containsBlock = SB3Builder.Operators.contains(string1, string2)

-- Math functions
local roundId, roundBlock = SB3Builder.Operators.round(num)
local randomId, randomBlock = SB3Builder.Operators.random(from, to)
local absId, absBlock = SB3Builder.Operators.abs(num)
local floorId, floorBlock = SB3Builder.Operators.floor(num)
local ceilId, ceilBlock = SB3Builder.Operators.ceiling(num)
local sqrtId, sqrtBlock = SB3Builder.Operators.sqrt(num)
local sinId, sinBlock = SB3Builder.Operators.sin(num)
local cosId, cosBlock = SB3Builder.Operators.cos(num)
local tanId, tanBlock = SB3Builder.Operators.tan(num)
```

### Custom Procedures

```lua
-- Procedure definition
local procDefId, procDefBlock, protoId, prototypeBlock = SB3Builder.Procedures.definition(proccode, argNames, argIds, argDefaults, warp, x, y)

-- Procedure call
local callId, callBlock = SB3Builder.Procedures.call(proccode, argNames, argIds, argDefaults, argValues, warp)

-- Argument reporters
local argId, argBlock = SB3Builder.Procedures.argumentReporter(name)
```

## Writing Tests

### Basic Test Structure

```lua
local lust = require("tests.lust")
local describe, it, expect = lust.describe, lust.it, lust.expect

local SB3Builder = require("tests.sb3_builder")
local ProjectModel = require("parser.project_model")
local Runtime = require("vm.runtime")

describe("Feature Name", function()
    describe("Sub-feature", function()
        it("should perform specific behavior", function()
            SB3Builder.resetCounter()
            local stage = SB3Builder.createStage()
            local sprite = SB3Builder.createSprite("TestSprite")

            -- Create blocks using modular API
            local hatId, hatBlock = SB3Builder.Events.whenFlagClicked()
            local moveId, moveBlock = SB3Builder.Motion.moveSteps(10)

            -- Build project structure
            SB3Builder.addBlock(sprite, hatId, hatBlock)
            SB3Builder.addBlock(sprite, moveId, moveBlock)
            SB3Builder.linkBlocks(sprite, {hatId, moveId})

            -- Execute through full runtime pipeline
            local projectJson = SB3Builder.createProject({stage, sprite})
            local project = ProjectModel:new(projectJson, {})
            local runtime = Runtime:new(project)
            runtime:initialize()

            -- Execute with safe iteration
            runtime:broadcastGreenFlag()
            local maxIterations = 100
            local iterations = 0
            while #runtime:getActiveThreads() > 0 and iterations < maxIterations do
                runtime:update(1/60)
                iterations = iterations + 1
            end

            -- Verify results
            local spriteTarget = runtime:getSpriteTargetByName("TestSprite")
            expect(spriteTarget.x).to.equal(10)
        end)
    end)
end)
```

### Available Assertions

```lua
-- Basic assertions
expect(value).to.exist()            -- not nil
expect(value).to.equal(expected)    -- strict equality
expect(value).to.be(expected)       -- == comparison
expect(value).to.be.truthy()        -- not nil or false
expect(value).to.be.a("string")     -- type checking

-- Negated assertions
expect(value).to_not.equal(expected)
expect(value).to_not.be.truthy()

-- Function testing
expect(fn).to.fail()                -- function should throw error
expect(fn).to.fail.with("pattern") -- error should match pattern
```

### **CRITICAL: Test Execution Safety**

**NEVER use infinite loops in tests - always include iteration limits to prevent deadlocks**

```lua
-- ❌ WRONG - This can cause infinite loops and test hangs
while #runtime:getActiveThreads() > 0 do
    runtime:update(1/60)
end

-- ✅ CORRECT - Always use iteration limits for safety
local maxIterations = 100
local iterations = 0
while #runtime:getActiveThreads() > 0 and iterations < maxIterations do
    runtime:update(1/60)
    iterations = iterations + 1
end
```

## Test Organization

### Test File Structure

**CRITICAL: All test files MUST be organized in subdirectories, NOT at the root level of tests/**

```
tests/
├── run.lua                    # Main test runner (only non-test file at root)
├── CLAUDE.md                  # Test framework documentation
├── lust/                      # Testing framework
├── sb3_builder/               # Modular SB3 project builder
├── fixtures/                  # Test data and fixtures
├── mocks/                     # Test mocks
│   ├── love_mock.lua          # Love2D API mocking
│   └── audio_mock.lua         # Audio source mocking
├── blocks/                    # Block-specific tests
│   ├── data_blocks_test.lua
│   ├── control_blocks_test.lua
│   ├── motion_blocks_test.lua
│   ├── operators_blocks_test.lua
│   ├── procedures_blocks_test.lua
│   ├── loop_efficiency_test.lua
│   └── compiler_optimization_test.lua
├── unit/                      # Unit tests
│   ├── cast_test.lua
│   └── pen_renderer_test.lua
├── audio/                     # Audio-related tests
│   └── audio_manager_test.lua
└── integration/               # Integration tests
    ├── default_test.lua
    ├── broadcast_special_chars_sb3_test.lua
    └── execute_order_library_test.lua
```

### File Organization Rules

1. **NO test files at root level**: All `*_test.lua` files MUST be in subdirectories
2. **Use category-based subdirectories**: Group related tests together
3. **Register in run.lua**: All new test files must be added to the `testSuites` array in `run.lua`
4. **Naming convention**: All test files must end with `_test.lua`

### Running Tests

```bash
# Run all tests
luajit tests/run.lua

# Run tests matching wildcard pattern (case-insensitive)
luajit tests/run.lua data                 # Matches "*data*" -> data_blocks_test
luajit tests/run.lua control              # Matches "*control*" -> control_blocks_test
luajit tests/run.lua data_blocks_test     # Exact match -> data_blocks_test
luajit tests/run.lua blocks               # Matches all "*blocks*" tests
```

## Test Quality Standards

- **Descriptive Names**: Use clear, behavior-describing test names
- **Single Focus**: Each test should verify one specific behavior
- **Deterministic**: Tests must produce consistent results
- **Complete Setup**: Use SB3Builder to create realistic test scenarios
- **Clear Assertions**: Use specific expectations with meaningful error messages
- **Safe Execution**: Always use iteration limits to prevent hangs

## Debugging Failed Tests

- Use `print()` statements within tests for debugging
- Modify `tests/run.lua` to load only specific test files for isolation
- Check SB3Builder output to verify correct project structure
- Examine runtime state during test execution
- Verify that mocked Love2D environment doesn't interfere with test logic
- All tests must run through `tests/run.lua` for proper environment setup