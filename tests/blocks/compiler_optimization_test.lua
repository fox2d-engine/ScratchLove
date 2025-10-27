-- Compiler Optimization Test
-- Tests to verify that compiler optimizations work correctly

local lust = require("tests.lust")
local describe, it, expect = lust.describe, lust.it, lust.expect

local SB3Builder = require("tests.sb3_builder")
local ProjectModel = require("parser.project_model")
local luagenModule = require("compiler.luagen")
local LuaGenerator = luagenModule.LuaGenerator
local enums = require("compiler.enums")

describe("Compiler Optimizations", function()
    describe("Block Function Call Optimization", function()
        it("should eliminate anonymous function wrappers for sensing blocks", function()
            -- Create a minimal script, IR, and target for the generator
            local script = {}
            local ir = {}
            local target = {}
            local generator = LuaGenerator:new(script, ir, target)

            -- Test SENSING_KEY_DOWN input with proper structure
            local keyInput = {
                opcode = enums.InputOpcode.CONSTANT,
                inputs = {
                    value = "space"
                }
            }

            local code = generator:generateInput({
                opcode = enums.InputOpcode.SENSING_KEY_DOWN,
                inputs = {
                    key = keyInput
                }
            })

            -- Should not contain anonymous function wrapper
            expect(code:match("function%(%)[^%)]*local BlockHelpers = require")).to_not.exist()

            -- Should use direct BlockHelpers function call
            expect(code:match("BlockHelpers%.Sensing%.keyPressed")).to.exist()

            -- Should generate clean optimized code
            expect(code).to.be.a("string")

            -- Should inline arguments - BlockHelpers uses cleaner argument passing
            expect(code:match('"space"')).to.exist()
        end)

        it("should optimize mouse position sensing blocks", function()
            local script = {}
            local ir = {}
            local target = {}
            local generator = LuaGenerator:new(script, ir, target)

            local mouseXCode = generator:generateInput({
                opcode = enums.InputOpcode.SENSING_MOUSE_X,
                inputs = {}
            })

            local mouseYCode = generator:generateInput({
                opcode = enums.InputOpcode.SENSING_MOUSE_Y,
                inputs = {}
            })

            -- Both should use direct function calls, no wrappers
            expect(mouseXCode:match("function%(%)[^%)]*local BlockHelpers = require")).to_not.exist()
            expect(mouseYCode:match("function%(%)[^%)]*local BlockHelpers = require")).to_not.exist()

            expect(mouseXCode:match("BlockHelpers%.Sensing%.mouseX")).to.exist()
            expect(mouseYCode:match("BlockHelpers%.Sensing%.mouseY")).to.exist()

            -- Should generate clean optimized code
            expect(mouseXCode).to.be.a("string")
            expect(mouseYCode).to.be.a("string")
        end)

        it("should optimize looks blocks", function()
            local script = {}
            local ir = {}
            local target = {}
            local generator = LuaGenerator:new(script, ir, target)

            local costumeNumCode = generator:generateInput({
                opcode = enums.InputOpcode.LOOKS_COSTUME_NUMBER,
                inputs = {}
            })

            local sizeCode = generator:generateInput({
                opcode = enums.InputOpcode.LOOKS_SIZE,
                inputs = {}
            })

            -- Should not contain anonymous function wrapper
            expect(costumeNumCode:match("function%(%)[^%)]*local BlockHelpers = require")).to_not.exist()
            expect(sizeCode:match("function%(%)[^%)]*local BlockHelpers = require")).to_not.exist()

            -- costumeNumber should be inlined (optimization)
            expect(costumeNumCode:match("target%.currentCostume")).to.exist()
            -- size still uses BlockHelpers function call
            expect(sizeCode:match("BlockHelpers%.Looks%.getSize")).to.exist()

            -- Should generate clean optimized code
            expect(costumeNumCode).to.be.a("string")
            expect(sizeCode).to.be.a("string")
        end)

        it("should optimize sound blocks", function()
            local script = {}
            local ir = {}
            local target = {}
            local generator = LuaGenerator:new(script, ir, target)

            local volumeCode = generator:generateInput({
                opcode = enums.InputOpcode.SOUND_VOLUME,
                inputs = {}
            })

            -- Should not contain anonymous function wrapper
            expect(volumeCode:match("function%(%)[^%)]*local BlockHelpers = require")).to_not.exist()

            -- Should use direct BlockHelpers function call
            expect(volumeCode:match("BlockHelpers%.Sound%.getVolume")).to.exist()

            -- Should generate clean optimized code
            expect(volumeCode).to.be.a("string")
        end)

        it("should optimize blocks with minimal test case", function()
            -- Just test that optimization basics work
            local script = {}
            local ir = {}
            local target = {}
            local generator = LuaGenerator:new(script, ir, target)

            -- Test basic optimization with proper structure
            local keyInput = {
                opcode = enums.InputOpcode.CONSTANT,
                inputs = {
                    value = "space"
                }
            }

            local code = generator:generateInput({
                opcode = enums.InputOpcode.SENSING_KEY_DOWN,
                inputs = {
                    key = keyInput
                }
            })

            -- Should generate optimized code with BlockHelpers
            expect(code).to.exist()
            expect(code:match("BlockHelpers%.Sensing%.keyPressed")).to.exist()
            expect(code:match('"space"')).to.exist()
        end)
    end)
end)