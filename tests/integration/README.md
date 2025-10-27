# Integration Tests

This directory contains integration tests migrated from the TurboWarp Scratch VM.

## Directory Structure

```
tests/integration/
├── README.md                                    # This document
├── integration_helper.lua                       # Shared utility functions
├── default_test.lua                            # Basic project loading test
├── broadcast_special_chars_sb3_test.lua        # Special character broadcast test
├── variable_special_chars_sb3_test.lua         # Special character variable test
├── comments_sb3_test.lua                       # Comment loading test
└── [more test files...]
```

## File Organization Principles

- **One-to-one mapping**: Each native test file corresponds to an independent Lua test file
- **Naming convention**: `[native_test_name]_test.lua`
  - Example: `comments_sb3.js` → `comments_sb3_test.lua`
  - Example: `control.js` → `control_test.lua`
- **Shared utilities**: `integration_helper.lua` provides common utility functions for all tests

## Running Tests

```bash
# Run all integration tests
luajit tests/run.lua integration

# Run specific test
luajit tests/run.lua comments_sb3

# Run all tests
luajit tests/run.lua
```

## Adding New Tests

1. **Create test file**: `tests/integration/[test_name]_test.lua`

2. **Use standard template**:

```lua
-- Integration Test: [Test Name]
--
-- [Brief description]

local lust = require("tests.lust")
local describe, it, expect = lust.describe, lust.it, lust.expect

local IntegrationHelper = require("tests.integration.integration_helper")
local ProjectModel = require("parser.project_model")
local Runtime = require("vm.runtime")

describe("Integration: [Test Name]", function()

    it("should [behavior]", function()
        -- Native test verification points:
        -- 1. [point 1]
        -- 2. [point 2]

        local projectData, assetMap = IntegrationHelper.loadSB3Project("fixture.sb3")
        local project = ProjectModel:new(projectData, assetMap)
        local runtime = Runtime:new(project)
        runtime:initialize()

        runtime:broadcastGreenFlag()
        IntegrationHelper.runUntilComplete(runtime, 100)

        -- Verifications
        expect(...).to.equal(...)
    end)

end)
```

3. **Register test**: Add to the `testSuites` array in `tests/run.lua`:

```lua
local testSuites = {
    -- ... existing tests ...
    "tests.integration.[test_name]_test",
}
```

## Shared Utility Functions

`integration_helper.lua` provides the following utilities:

### Project Loading

```lua
-- Load sb3 project file
local projectData, assetMap = IntegrationHelper.loadSB3Project("fixture.sb3")
```

### Execution Control

```lua
-- Run until all threads complete (with timeout protection)
IntegrationHelper.runUntilComplete(runtime, maxIterations)
```

### Data Processing

```lua
-- Count table elements
local count = IntegrationHelper.tableCount(tbl)

-- Convert table to array
local array = IntegrationHelper.tableToArray(tbl)

-- Filter array
local filtered = IntegrationHelper.filter(array, function(item)
    return item.property == "value"
end)

-- Sort array
IntegrationHelper.sort(array, function(a, b)
    return a.name < b.name
end)
```

## Test Writing Guidelines

### Core Principles

1. **100% verification point coverage**: Every assertion in the native test must have a corresponding verification
2. **API adaptation, not skipping**: APIs can differ, but verification logic must be the same
3. **No simplified verification**: Don't lower verification standards due to implementation difficulty
4. **Goal is finding issues**: Test failures indicate incompatibilities that need fixing in project code

### Verification Point Checklist

Each test must list all verification points in comments:

```lua
it("should test something", function()
    -- Native test verification points:
    -- 1. threads.length === 0
    -- 2. targets.length === 2
    -- 3. stage.variables contains expected values
    -- ... [list all verification points]

    -- Implement all verifications
end)
```

### Handling Test Failures

- ✅ **Test passes**: Feature works correctly, compatible with Scratch
- ❌ **Test fails**:
  1. Don't modify tests to make them pass
  2. Analyze failure reason (missing feature/implementation error/edge case)
  3. Fix project code
  4. Document discovered issues

## Reference Documentation

- Complete migration plan: `INTEGRATION_TESTS_MIGRATION_PLAN.md`
- Native test source: `../scratchfoundation/turbowarp-scratch-vm/test/integration/`
- Test framework docs: `tests/CLAUDE.md`

## Completed Tests

| Test File | Native Test | Description |
|---------|---------|------|
| `default_test.lua` | (default project) | Basic project loading |
| `broadcast_special_chars_sb3_test.lua` | `broadcast_special_chars_sb3.js` | Special character broadcast |
| `variable_special_chars_sb3_test.lua` | `variable_special_chars_sb3.js` | Special character variables |
| `comments_sb3_test.lua` | `comments_sb3.js` | Comment loading and saving |

## Tests To Be Migrated

See `INTEGRATION_TESTS_MIGRATION_PLAN.md` for the complete list and priority planning.
