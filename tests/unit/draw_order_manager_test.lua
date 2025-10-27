-- DrawOrderManager Tests
-- Tests for the draw order management system

local lust = require("tests.lust")
local describe, it, expect = lust.describe, lust.it, lust.expect

describe("DrawOrderManager", function()
    local DrawOrderManager = require("renderer.draw_order_manager")
    local StageLayering = require("renderer.stage_layering")

    describe("Basic Operations", function()
        it("should add drawable to sprite layer", function()
            local manager = DrawOrderManager:new()
            manager:addDrawable("sprite1", StageLayering.SPRITE_LAYER)

            local drawOrder = manager:getDrawOrder()
            expect(#drawOrder).to.equal(1)
            expect(drawOrder[1]).to.equal("sprite1")
        end)

        it("should add multiple drawables to same layer", function()
            local manager = DrawOrderManager:new()
            manager:addDrawable("sprite1", StageLayering.SPRITE_LAYER)
            manager:addDrawable("sprite2", StageLayering.SPRITE_LAYER)
            manager:addDrawable("sprite3", StageLayering.SPRITE_LAYER)

            local drawOrder = manager:getDrawOrder()
            expect(#drawOrder).to.equal(3)
        end)

        it("should remove drawable", function()
            local manager = DrawOrderManager:new()
            manager:addDrawable("sprite1", StageLayering.SPRITE_LAYER)
            manager:addDrawable("sprite2", StageLayering.SPRITE_LAYER)

            manager:removeDrawable("sprite1")

            local drawOrder = manager:getDrawOrder()
            expect(#drawOrder).to.equal(1)
            expect(drawOrder[1]).to.equal("sprite2")
        end)

        it("should handle removing non-existent drawable gracefully", function()
            local manager = DrawOrderManager:new()
            manager:addDrawable("sprite1", StageLayering.SPRITE_LAYER)

            -- Should not crash
            manager:removeDrawable("nonexistent")

            local drawOrder = manager:getDrawOrder()
            expect(#drawOrder).to.equal(1)
        end)

        it("should add drawables to different layers", function()
            local manager = DrawOrderManager:new()
            manager:addDrawable("bg", StageLayering.BACKGROUND_LAYER)
            manager:addDrawable("pen", StageLayering.PEN_LAYER)
            manager:addDrawable("sprite", StageLayering.SPRITE_LAYER)

            local drawOrder = manager:getDrawOrder()
            expect(#drawOrder).to.equal(3)
            -- Background should be first, sprite last
            expect(drawOrder[1]).to.equal("bg")
            expect(drawOrder[3]).to.equal("sprite")
        end)
    end)

    describe("Move Operations", function()
        it("should move drawable to front of layer", function()
            local manager = DrawOrderManager:new()
            manager:addDrawable("sprite1", StageLayering.SPRITE_LAYER)
            manager:addDrawable("sprite2", StageLayering.SPRITE_LAYER)
            manager:addDrawable("sprite3", StageLayering.SPRITE_LAYER)

            manager:moveDrawableToFront("sprite1")

            local drawOrder = manager:getDrawOrder()
            expect(drawOrder[3]).to.equal("sprite1") -- Should be at end (front in rendering)
        end)

        it("should move drawable to back of layer", function()
            local manager = DrawOrderManager:new()
            manager:addDrawable("sprite1", StageLayering.SPRITE_LAYER)
            manager:addDrawable("sprite2", StageLayering.SPRITE_LAYER)
            manager:addDrawable("sprite3", StageLayering.SPRITE_LAYER)

            manager:moveDrawableToBack("sprite3")

            local drawOrder = manager:getDrawOrder()
            expect(drawOrder[1]).to.equal("sprite3") -- Should be at start (back in rendering)
        end)

        it("should move drawable forward by positions", function()
            local manager = DrawOrderManager:new()
            manager:addDrawable("sprite1", StageLayering.SPRITE_LAYER)
            manager:addDrawable("sprite2", StageLayering.SPRITE_LAYER)
            manager:addDrawable("sprite3", StageLayering.SPRITE_LAYER)

            manager:moveDrawableForward("sprite1", 1)

            local drawOrder = manager:getDrawOrder()
            expect(drawOrder[2]).to.equal("sprite1")
        end)

        it("should move drawable backward by positions", function()
            local manager = DrawOrderManager:new()
            manager:addDrawable("sprite1", StageLayering.SPRITE_LAYER)
            manager:addDrawable("sprite2", StageLayering.SPRITE_LAYER)
            manager:addDrawable("sprite3", StageLayering.SPRITE_LAYER)

            manager:moveDrawableBackward("sprite3", 1)

            local drawOrder = manager:getDrawOrder()
            expect(drawOrder[2]).to.equal("sprite3")
        end)

        it("should clamp forward movement to layer bounds", function()
            local manager = DrawOrderManager:new()
            manager:addDrawable("sprite1", StageLayering.SPRITE_LAYER)
            manager:addDrawable("sprite2", StageLayering.SPRITE_LAYER)

            manager:moveDrawableForward("sprite1", 999)

            local drawOrder = manager:getDrawOrder()
            expect(drawOrder[2]).to.equal("sprite1") -- Should stop at end of layer
        end)

        it("should clamp backward movement to layer bounds", function()
            local manager = DrawOrderManager:new()
            manager:addDrawable("sprite1", StageLayering.SPRITE_LAYER)
            manager:addDrawable("sprite2", StageLayering.SPRITE_LAYER)

            manager:moveDrawableBackward("sprite2", 999)

            local drawOrder = manager:getDrawOrder()
            expect(drawOrder[1]).to.equal("sprite2") -- Should stop at start of layer
        end)
    end)

    describe("Move Behind Operations", function()
        it("should move drawable behind another drawable", function()
            local manager = DrawOrderManager:new()
            manager:addDrawable("sprite1", StageLayering.SPRITE_LAYER)
            manager:addDrawable("sprite2", StageLayering.SPRITE_LAYER)
            manager:addDrawable("sprite3", StageLayering.SPRITE_LAYER)

            manager:moveDrawableBehind("sprite3", "sprite1")

            local drawOrder = manager:getDrawOrder()
            -- sprite3 should now be at position 1 (behind sprite1)
            expect(drawOrder[1]).to.equal("sprite3")
            expect(drawOrder[2]).to.equal("sprite1")
        end)

        it("should handle moving behind non-existent target gracefully", function()
            local manager = DrawOrderManager:new()
            manager:addDrawable("sprite1", StageLayering.SPRITE_LAYER)
            manager:addDrawable("sprite2", StageLayering.SPRITE_LAYER)

            -- This is the bug scenario - should not crash
            manager:moveDrawableBehind("sprite1", "nonexistent")

            local drawOrder = manager:getDrawOrder()
            expect(#drawOrder).to.equal(2) -- Should still have both sprites
        end)

        it("should handle moving behind deleted target", function()
            local manager = DrawOrderManager:new()
            manager:addDrawable("sprite1", StageLayering.SPRITE_LAYER)
            manager:addDrawable("sprite2", StageLayering.SPRITE_LAYER)
            manager:addDrawable("sprite3", StageLayering.SPRITE_LAYER)

            -- Remove target
            manager:removeDrawable("sprite2")

            -- Try to move behind deleted target - should not crash
            manager:moveDrawableBehind("sprite3", "sprite2")

            local drawOrder = manager:getDrawOrder()
            expect(#drawOrder).to.equal(2)
        end)

        it("should warn when moving to different layer", function()
            local manager = DrawOrderManager:new()
            manager:addDrawable("pen", StageLayering.PEN_LAYER)
            manager:addDrawable("sprite", StageLayering.SPRITE_LAYER)

            -- Should warn but not crash
            manager:moveDrawableBehind("sprite", "pen")

            local drawOrder = manager:getDrawOrder()
            expect(#drawOrder).to.equal(2)
        end)

        it("should update target index after removal in moveDrawableBehind", function()
            local manager = DrawOrderManager:new()
            manager:addDrawable("sprite1", StageLayering.SPRITE_LAYER)
            manager:addDrawable("sprite2", StageLayering.SPRITE_LAYER)
            manager:addDrawable("sprite3", StageLayering.SPRITE_LAYER)

            -- Move sprite1 behind sprite3
            manager:moveDrawableBehind("sprite1", "sprite3")

            local drawOrder = manager:getDrawOrder()
            -- After removing sprite1 and re-inserting behind sprite3:
            -- Expected order: sprite2, sprite1, sprite3
            expect(drawOrder[1]).to.equal("sprite2")
            expect(drawOrder[2]).to.equal("sprite1")
            expect(drawOrder[3]).to.equal("sprite3")
        end)
    end)

    describe("Clone Creation Timing", function()
        it("should handle rapid add-remove-add sequence", function()
            local manager = DrawOrderManager:new()
            -- Simulate rapid clone creation/deletion
            manager:addDrawable("clone1", StageLayering.SPRITE_LAYER)
            manager:addDrawable("clone2", StageLayering.SPRITE_LAYER)

            -- Delete clone1
            manager:removeDrawable("clone1")

            -- Create clone3 and try to place behind clone1 (deleted)
            manager:addDrawable("clone3", StageLayering.SPRITE_LAYER)
            manager:moveDrawableBehind("clone3", "clone1") -- Should gracefully fail

            local drawOrder = manager:getDrawOrder()
            expect(#drawOrder).to.equal(2) -- clone2, clone3
        end)

        it("should handle add-behind sequence where target is added after", function()
            local manager = DrawOrderManager:new()
            manager:addDrawable("original", StageLayering.SPRITE_LAYER)

            -- Simulate: clone created, addTarget called (assigns ID)
            manager:addDrawable("clone1", StageLayering.SPRITE_LAYER)

            -- Then immediately try to move behind original
            manager:moveDrawableBehind("clone1", "original")

            local drawOrder = manager:getDrawOrder()
            expect(drawOrder[1]).to.equal("clone1")
            expect(drawOrder[2]).to.equal("original")
        end)

        it("should maintain consistency with concurrent operations", function()
            local manager = DrawOrderManager:new()
            -- Add multiple sprites
            for i = 1, 10 do
                manager:addDrawable("sprite" .. i, StageLayering.SPRITE_LAYER)
            end

            -- Simulate chaotic operations
            manager:removeDrawable("sprite5")
            manager:moveDrawableBehind("sprite8", "sprite3")
            manager:removeDrawable("sprite2")
            manager:moveDrawableToFront("sprite1")

            local drawOrder = manager:getDrawOrder()
            expect(#drawOrder).to.equal(8) -- Should have 8 sprites (removed 2)

            -- Verify no duplicates
            local seen = {}
            for _, id in ipairs(drawOrder) do
                expect(seen[id]).to_not.exist()
                seen[id] = true
            end
        end)
    end)

    describe("Layer Group Integrity", function()
        it("should maintain correct layer group counts", function()
            local manager = DrawOrderManager:new()
            manager:addDrawable("bg", StageLayering.BACKGROUND_LAYER)
            manager:addDrawable("pen", StageLayering.PEN_LAYER)
            manager:addDrawable("sprite1", StageLayering.SPRITE_LAYER)
            manager:addDrawable("sprite2", StageLayering.SPRITE_LAYER)

            local bgDrawables = manager:getDrawablesInLayer(StageLayering.BACKGROUND_LAYER)
            local penDrawables = manager:getDrawablesInLayer(StageLayering.PEN_LAYER)
            local spriteDrawables = manager:getDrawablesInLayer(StageLayering.SPRITE_LAYER)

            expect(#bgDrawables).to.equal(1)
            expect(#penDrawables).to.equal(1)
            expect(#spriteDrawables).to.equal(2)
        end)

        it("should update layer counts on removal", function()
            local manager = DrawOrderManager:new()
            manager:addDrawable("sprite1", StageLayering.SPRITE_LAYER)
            manager:addDrawable("sprite2", StageLayering.SPRITE_LAYER)
            manager:addDrawable("sprite3", StageLayering.SPRITE_LAYER)

            manager:removeDrawable("sprite2")

            local spriteDrawables = manager:getDrawablesInLayer(StageLayering.SPRITE_LAYER)
            expect(#spriteDrawables).to.equal(2)
        end)

        it("should get drawable layer", function()
            local manager = DrawOrderManager:new()
            manager:addDrawable("sprite1", StageLayering.SPRITE_LAYER)
            manager:addDrawable("pen", StageLayering.PEN_LAYER)

            expect(manager:getDrawableLayer("sprite1")).to.equal(StageLayering.SPRITE_LAYER)
            expect(manager:getDrawableLayer("pen")).to.equal(StageLayering.PEN_LAYER)
        end)
    end)

    describe("Edge Cases", function()
        it("should handle empty manager", function()
            local manager = DrawOrderManager:new()
            local drawOrder = manager:getDrawOrder()
            expect(#drawOrder).to.equal(0)
        end)

        it("should handle moving non-existent drawable", function()
            local manager = DrawOrderManager:new()
            manager:addDrawable("sprite1", StageLayering.SPRITE_LAYER)

            -- Should not crash
            manager:moveDrawableToFront("nonexistent")
            manager:moveDrawableToBack("nonexistent")
            manager:moveDrawableForward("nonexistent", 1)
            manager:moveDrawableBackward("nonexistent", 1)

            local drawOrder = manager:getDrawOrder()
            expect(#drawOrder).to.equal(1)
        end)

        it("should handle re-adding same drawable ID", function()
            local manager = DrawOrderManager:new()
            manager:addDrawable("sprite1", StageLayering.SPRITE_LAYER)
            manager:addDrawable("sprite2", StageLayering.SPRITE_LAYER)

            -- Re-adding should remove old and add new (per addDrawable implementation)
            manager:addDrawable("sprite1", StageLayering.SPRITE_LAYER)

            local drawOrder = manager:getDrawOrder()
            expect(#drawOrder).to.equal(2)
            -- sprite1 should be at the end now
            expect(drawOrder[2]).to.equal("sprite1")
        end)
    end)
end)
