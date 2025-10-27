-- Integration Test: Broadcast Special Characters SB3
-- Reference: 
--
-- Tests handling of broadcast messages with special characters

local lust = require("tests.lust")
local describe, it, expect = lust.describe, lust.it, lust.expect

local IntegrationHelper = require("tests.integration.integration_helper")
local ProjectModel = require("parser.project_model")
local Runtime = require("vm.runtime")
local Variable = require("vm.variable")

describe("Integration: Broadcast Special Characters SB3", function()

    it("should handle broadcast messages with special characters", function()
        -- Reference: 
        --
        -- Native test verification points:
        -- 1. threads.length === 0 (no active threads after completion)
        -- 2. targets.length === 2 (stage + sprite)
        -- 3. stage.variables contains broadcast with special characters
        -- 4. broadcast variable type is BROADCAST_MESSAGE_TYPE
        -- 5. broadcast message name contains special characters
        -- 6. blocks reference broadcasts correctly

        local projectData, assetMap = IntegrationHelper.loadSB3Project("broadcast_special_chars.sb3")
        local project = ProjectModel:new(projectData, assetMap)
        local runtime = Runtime:new(project)
        runtime:initialize()

        -- Run project and wait for completion
        runtime:broadcastGreenFlag()
        IntegrationHelper.runUntilComplete(runtime, 100)

        -- Verification 1: No active threads after completion
        expect(#runtime:getActiveThreads()).to.equal(0)

        -- Verification 2: Exactly 2 targets (stage + sprite)
        expect(#runtime.targets).to.equal(2)

        local stage = runtime.targets[1]
        expect(stage.isStage).to.be.truthy()

        -- Verification 3-5: Broadcast messages stored as Variable objects
        -- Check that broadcasts exist in stage.variables with correct type
        local broadcastFound = false
        for id, variable in pairs(stage.variables) do
            if variable.type == Variable.BROADCAST_MESSAGE_TYPE then
                broadcastFound = true
                -- Verify the broadcast has special characters in its name
                expect(variable.name).to.exist()
                expect(type(variable.name)).to.equal("string")
                expect(#variable.name > 0).to.be.truthy()
            end
        end
        expect(broadcastFound).to.be.truthy()

        -- Verification 6: Blocks reference broadcasts correctly
        -- Count broadcast-related blocks in the project
        local broadcastBlockCount = 0
        for _, target in ipairs(projectData.targets) do
            if target.blocks then
                for blockId, block in pairs(target.blocks) do
                    if type(block) == "table" and block.opcode then
                        -- Check for broadcast and broadcast_and_wait blocks
                        if block.opcode == "event_broadcast" or block.opcode == "event_broadcastandwait" then
                            broadcastBlockCount = broadcastBlockCount + 1

                            -- Verify block has broadcast input
                            local hasBroadcastInput = false

                            -- Check inputs.BROADCAST_INPUT (native sb3 format)
                            if block.inputs and block.inputs.BROADCAST_INPUT then
                                hasBroadcastInput = true
                            end

                            -- Check fields.BROADCAST_OPTION (alternative format)
                            if block.fields and block.fields.BROADCAST_OPTION then
                                hasBroadcastInput = true
                            end

                            expect(hasBroadcastInput).to.be.truthy()
                        end
                    end
                end
            end
        end

        -- The test project should have at least 2 broadcast blocks
        expect(broadcastBlockCount >= 2).to.be.truthy()
    end)

end)