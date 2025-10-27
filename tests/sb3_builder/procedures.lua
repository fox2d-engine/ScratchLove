-- Procedures Blocks Module
-- Implements blocks for custom procedures (custom blocks)

local Core = require("tests.sb3_builder.core")
local json = require("lib.json")

local Procedures = {}

---Create a procedure definition block and its prototype
---@param proccode string The procedure code (e.g., "my block %s %b")
---@param argNames string[] Names of arguments
---@param argIds string[] IDs of arguments
---@param argDefaults any[] Default values for arguments
---@param warp boolean Whether the procedure runs without screen refresh
---@param x number|nil X position
---@param y number|nil Y position
---@return string procDefId, table procDefBlock, string protoId, table prototypeBlock
function Procedures.definition(proccode, argNames, argIds, argDefaults, warp, x, y)
    local mutation = {
        tagName = "mutation",
        children = {},
        proccode = proccode,
        argumentids = json.encode(argIds),
        argumentnames = json.encode(argNames),
        argumentdefaults = json.encode(argDefaults),
        warp = tostring(warp or false)
    }

    local protoId, prototypeBlock = Core.createBlock("procedures_prototype", {}, {}, { shadow = true }, mutation)

    local procDefId, procDefBlock = Core.createBlock("procedures_definition", {
        custom_block = Core.blockInput(protoId)
    }, {}, { topLevel = true, x = x, y = y })

    return procDefId, procDefBlock, protoId, prototypeBlock
end

---Create a procedure call block
---@param proccode string The procedure code
---@param argNames string[] Names of arguments
---@param argIds string[] IDs of arguments
---@param argDefaults any[] Default values for arguments
---@param argValues table Values for the arguments for this call
---@param warp boolean Whether the procedure runs without screen refresh
---@return string id, table block
function Procedures.call(proccode, argNames, argIds, argDefaults, argValues, warp)
    local mutation = {
        tagName = "mutation",
        children = {},
        proccode = proccode,
        argumentids = json.encode(argIds),
        warp = tostring(warp or false)
    }
    local inputs = {}
    for i, argId in ipairs(argIds) do
        inputs[argId] = argValues[i]
    end

    return Core.createBlock("procedures_call", inputs, {}, {}, mutation)
end

---Create an argument reporter
---@param name string The name of the argument
---@return string id, table block
function Procedures.argumentReporter(name)
    return Core.createBlock("argument_reporter_string_number", {}, {
        VALUE = Core.field(name)
    })
end

return Procedures
