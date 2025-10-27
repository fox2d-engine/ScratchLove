-- Integration Test: Comments SB3
-- Reference: 
--
-- Tests loading and preserving comments in sb3 projects

local lust = require("tests.lust")
local describe, it, expect = lust.describe, lust.it, lust.expect

local IntegrationHelper = require("tests.integration.integration_helper")
local ProjectModel = require("parser.project_model")
local Runtime = require("vm.runtime")

describe("Integration: Comments SB3", function()

    it("should load and preserve comments", function()
        -- Reference: 
        --
        -- Native test verification points:
        -- 1. threads.length === 0 (no active threads after completion)
        -- 2. Stage has 1 comment
        -- 3. Stage comment is minimized
        -- 4. Stage comment text is "A minimized stage comment."
        -- 5. Stage comment is workspace comment (blockId === null)
        -- 6. Sprite has 6 comments total
        -- 7. Sprite has 1 workspace comment
        -- 8. Workspace comment is not minimized
        -- 9. Workspace comment text is "This is a workspace comment."
        -- 10. Sprite has 5 block comments
        -- 11-15. Each block comment: minimized state, text, blockId, block.comment, opcode

        local projectData, assetMap = IntegrationHelper.loadSB3Project("comments.sb3")
        local project = ProjectModel:new(projectData, assetMap)
        local runtime = Runtime:new(project)
        runtime:initialize()

        runtime:broadcastGreenFlag()

        -- Run until all threads complete
        IntegrationHelper.runUntilComplete(runtime, 100)

        -- Verification 1: No active threads after completion
        expect(#runtime:getActiveThreads()).to.equal(0)

        -- Get stage and sprite targets
        expect(#runtime.targets).to.equal(2)
        local stage = runtime.targets[1]  -- Stage is first target
        local target = runtime.targets[2]  -- Sprite1 is second target

        -- Get comments from original project data
        local stageData = projectData.targets[1]
        local spriteData = projectData.targets[2]

        expect(stageData.isStage).to.be.truthy()
        expect(stageData.comments).to.exist()
        expect(spriteData.comments).to.exist()

        -- Convert comments object to array
        local stageComments = IntegrationHelper.tableToArray(stageData.comments)

        -- Verification 2-5: Stage comment properties
        expect(#stageComments).to.equal(1)
        expect(stageComments[1].minimized).to.equal(true)
        expect(stageComments[1].text).to.equal("A minimized stage comment.")
        expect(stageComments[1].blockId).to_not.exist()

        -- Verification 6: Sprite has 6 comments
        local targetComments = IntegrationHelper.tableToArray(spriteData.comments)
        expect(#targetComments).to.equal(6)

        -- Verification 7-9: Workspace comment
        local spriteWorkspaceComments = IntegrationHelper.filter(targetComments, function(comment)
            return not comment.blockId
        end)
        expect(#spriteWorkspaceComments).to.equal(1)
        expect(spriteWorkspaceComments[1].minimized).to.equal(false)
        expect(spriteWorkspaceComments[1].text).to.equal("This is a workspace comment.")

        -- Verification 10: Block comments
        local blockComments = IntegrationHelper.filter(targetComments, function(comment)
            return comment.blockId ~= nil
        end)
        expect(#blockComments).to.equal(5)

        -- Sort block comments by text to ensure consistent ordering
        IntegrationHelper.sort(blockComments, function(a, b) return a.text < b.text end)

        -- Verification 11: Comment 1 - Green Flag Comment
        expect(blockComments[1].minimized).to.equal(true)
        expect(blockComments[1].text).to.equal("1. Green Flag Comment.")
        local greenFlagBlock = spriteData.blocks[blockComments[1].blockId]
        expect(greenFlagBlock).to.exist()
        expect(greenFlagBlock.comment).to.equal(blockComments[1].id)
        expect(greenFlagBlock.opcode).to.equal("event_whenflagclicked")

        -- Verification 12: Comment 2 - Turn 15 Degrees Comment
        expect(blockComments[2].minimized).to.equal(true)
        expect(blockComments[2].text).to.equal("2. Turn 15 Degrees Comment.")
        local turnRightBlock = spriteData.blocks[blockComments[2].blockId]
        expect(turnRightBlock).to.exist()
        expect(turnRightBlock.comment).to.equal(blockComments[2].id)
        expect(turnRightBlock.opcode).to.equal("motion_turnright")

        -- Verification 13: Comment 3 - Comment for a loop
        expect(blockComments[3].minimized).to.equal(false)
        expect(blockComments[3].text).to.equal("3. Comment for a loop.")
        local repeatBlock = spriteData.blocks[blockComments[3].blockId]
        expect(repeatBlock).to.exist()
        expect(repeatBlock.comment).to.equal(blockComments[3].id)
        expect(repeatBlock.opcode).to.equal("control_repeat")

        -- Verification 14: Comment 4 - Comment for a block nested in a loop
        expect(blockComments[4].minimized).to.equal(false)
        expect(blockComments[4].text).to.equal("4. Comment for a block nested in a loop.")
        local changeColorBlock = spriteData.blocks[blockComments[4].blockId]
        expect(changeColorBlock).to.exist()
        expect(changeColorBlock.comment).to.equal(blockComments[4].id)
        expect(changeColorBlock.opcode).to.equal("looks_changeeffectby")

        -- Verification 15: Comment 5 - Comment for a block outside of a loop
        expect(blockComments[5].minimized).to.equal(false)
        expect(blockComments[5].text).to.equal("5. Comment for a block outside of a loop.")
        local stopAllBlock = spriteData.blocks[blockComments[5].blockId]
        expect(stopAllBlock).to.exist()
        expect(stopAllBlock.comment).to.equal(blockComments[5].id)
        expect(stopAllBlock.opcode).to.equal("control_stop")
    end)

end)