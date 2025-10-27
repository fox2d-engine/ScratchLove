-- Integration Test: Variable Special Characters SB3
-- Reference: 
--
-- Tests handling of variables with special characters in names

local lust = require("tests.lust")
local describe, it, expect = lust.describe, lust.it, lust.expect

local IntegrationHelper = require("tests.integration.integration_helper")
local ProjectModel = require("parser.project_model")
local Runtime = require("vm.runtime")

describe("Integration: Variable Special Characters SB3", function()

    it("should handle variables with special characters", function()
        -- Reference: 
        --
        -- Native test verification points:
        -- 1. threads.length === 0 (no active threads after completion)
        -- 2. targets.length === 3 (stage + 2 sprites)
        -- 3. Variable "a&b" (list) exists with values ["thing", "thing'1"]
        -- 4. Variable ""foo" exists with value "foo"
        -- 5. Variable "< Perfect" exists with value "> perfect"
        -- 6. Variable "a&b" is referenced 3 times in blocks
        -- 7. Variable ""foo" is referenced 2 times in blocks
        -- 8. Variable "< Perfect" is referenced 1 time in blocks

        local projectData, assetMap = IntegrationHelper.loadSB3Project("variable_characters.sb3")
        local project = ProjectModel:new(projectData, assetMap)
        local runtime = Runtime:new(project)
        runtime:initialize()

        -- Run project to completion
        runtime:broadcastGreenFlag()
        IntegrationHelper.runUntilComplete(runtime, 100)

        -- Verification 1: No active threads
        expect(#runtime:getActiveThreads()).to.equal(0)

        -- Verification 2: Exactly 3 targets
        expect(#runtime.targets).to.equal(3)

        -- Get stage and sprites
        local stage = runtime.targets[1]
        local sprite1 = runtime.targets[2]
        local sprite2 = runtime.targets[3]

        -- Verification 3: Variable "a&b" (list) with correct values
        -- Find the list variable by name
        local listVar = nil
        for _, variable in pairs(stage.variables) do
            if variable.name == "a&b" then
                listVar = variable
                break
            end
        end

        expect(listVar).to.exist()
        expect(listVar.type).to.equal("list")
        -- The list should have at least 2 elements (project may add more during execution)
        expect(#listVar.value >= 2).to.be.truthy()
        expect(listVar.value[1]).to.equal("thing")
        expect(listVar.value[2]).to.equal("thing'1")

        -- Verification 4: Variable ""foo" with value "foo"
        local fooVar = nil
        for _, variable in pairs(stage.variables) do
            if variable.name == '"foo' then
                fooVar = variable
                break
            end
        end

        expect(fooVar).to.exist()
        expect(fooVar.value).to.equal("foo")

        -- Verification 5: Variable "< Perfect" with value "> perfect"
        local perfectVar = nil
        for _, variable in pairs(sprite2.variables) do
            if variable.name == "< Perfect" then
                perfectVar = variable
                break
            end
        end

        expect(perfectVar).to.exist()
        expect(perfectVar.value).to.equal("> perfect")

        -- Verification 6-8: Count variable references in blocks
        -- This validates that variables with special characters are correctly referenced

        -- Helper function to get field ID supporting both formats
        local function getFieldId(field)
            if not field then return nil end
            if type(field) == "table" then
                if field.id then
                    return field.id  -- Compiled format
                elseif field[2] then
                    return field[2]  -- Native sb3 format [name, id]
                end
            end
            return nil
        end

        -- Find list variable ID
        local listId = nil
        for id, variable in pairs(stage.variables) do
            if variable.name == "a&b" then
                listId = id
                break
            end
        end
        expect(listId).to.exist()

        -- Count references to "a&b" list
        local listRefCount = 0
        for _, target in ipairs(projectData.targets) do
            if target.blocks then
                for blockId, block in pairs(target.blocks) do
                    if type(block) == "table" and block.fields then
                        -- Check LIST field
                        if block.fields.LIST then
                            local fieldId = getFieldId(block.fields.LIST)
                            if fieldId == listId then
                                listRefCount = listRefCount + 1
                            end
                        end
                    end
                end
            end
        end
        expect(listRefCount).to.equal(3)

        -- Find "foo variable ID
        local fooId = nil
        for id, variable in pairs(stage.variables) do
            if variable.name == '"foo' then
                fooId = id
                break
            end
        end
        expect(fooId).to.exist()

        -- Count references to ""foo"
        local fooRefCount = 0
        for _, target in ipairs(projectData.targets) do
            if target.blocks then
                for blockId, block in pairs(target.blocks) do
                    if type(block) == "table" and block.fields then
                        -- Check VARIABLE field
                        if block.fields.VARIABLE then
                            local fieldId = getFieldId(block.fields.VARIABLE)
                            if fieldId == fooId then
                                fooRefCount = fooRefCount + 1
                            end
                        end
                    end
                end
            end
        end
        expect(fooRefCount).to.equal(2)

        -- Find "< Perfect" variable ID
        local perfectId = nil
        for id, variable in pairs(sprite2.variables) do
            if variable.name == "< Perfect" then
                perfectId = id
                break
            end
        end
        expect(perfectId).to.exist()

        -- Count references to "< Perfect"
        local perfectRefCount = 0
        for _, target in ipairs(projectData.targets) do
            if target.blocks then
                for blockId, block in pairs(target.blocks) do
                    if type(block) == "table" and block.fields then
                        -- Check VARIABLE field
                        if block.fields.VARIABLE then
                            local fieldId = getFieldId(block.fields.VARIABLE)
                            if fieldId == perfectId then
                                perfectRefCount = perfectRefCount + 1
                            end
                        end
                    end
                end
            end
        end
        expect(perfectRefCount).to.equal(1)
    end)

end)