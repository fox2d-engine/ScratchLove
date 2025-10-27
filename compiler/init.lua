-- Compiles Scratch blocks to optimized Lua coroutines

local log = require("lib.log")

---@class ScratchToLuaCompiler
---@field private irgen IRGenerator
---@field private optimizer IROptimizer
---@field private luagen LuaGenerator
local ScratchToLuaCompiler = {}
ScratchToLuaCompiler.__index = ScratchToLuaCompiler

---Create a new Scratch to Lua compiler instance
---@return ScratchToLuaCompiler
function ScratchToLuaCompiler:new()
    local compiler = setmetatable({}, ScratchToLuaCompiler)

    -- Load compiler components
    local IRGenerator = require("compiler.irgen")
    local IROptimizer = require("compiler.iroptimizer")
    local LuaGenerator = require("compiler.luagen")

    compiler.irgen = IRGenerator
    compiler.optimizer = IROptimizer
    compiler.luagen = LuaGenerator

    return compiler
end

---Compile a thread's script and its dependencies to Lua
---@param thread Thread The thread to compile
---@return CompileResult result Compilation result with entry function and procedures
function ScratchToLuaCompiler:compile(thread, options)
    options = options or {}

    if options.emitSourceOnly then
        log.info("Scratch to Lua source generation started for thread: " .. tostring(thread.topBlock))
    else
        log.info("Scratch to Lua compilation started for thread: " .. tostring(thread.topBlock))
    end

    -- Stage 1: Generate intermediate representation
    log.debug("Stage 1: Generating IR...")
    local irGenerator = self.irgen.IRGenerator:new(thread)
    local ir = irGenerator:generate()

    -- Stage 2: Optimize intermediate representation
    log.debug("Stage 2: Optimizing IR...")
    local irOptimizer = self.optimizer.IROptimizer:new(ir)
    irOptimizer:optimize()

    -- Stage 3: Generate Lua code
    log.debug("Stage 3: Generating Lua code...")
    local procedures = {}
    local target = thread.target

    local function compileScript(script)
        if script.cachedCompileResult then
            return script.cachedCompileResult
        end

        local luaGenerator = self.luagen.LuaGenerator:new(script, ir, target)
        local chunk, source = luaGenerator:compile(options)
        local packaged = {
            chunk = chunk,
            source = source,
            usedModules = luaGenerator.usedModules or {}
        }
        script.cachedCompileResult = packaged
        return packaged
    end

    -- Compile main script
    local entryResult = compileScript(ir.entry)

    -- Compile all dependency procedures
    for procedureVariant, procedureScript in pairs(ir.procedures) do
        local procedureResult = compileScript(procedureScript)
        procedures[procedureVariant] = {
            chunk = procedureResult.chunk,
            source = procedureResult.source,
            usedModules = procedureResult.usedModules
        }
    end

    if options.emitSourceOnly then
        log.info("Scratch to Lua source generation completed successfully")
    else
        log.info("Scratch to Lua compilation completed successfully")
    end

    ---@class CompileResult
    return {
        entryChunk = entryResult.chunk,           -- Main script chunk (returns executable)
        entrySource = entryResult.source,         -- Generated Lua source for the entry script
        procedures = procedures,                  -- Procedure chunk/source map
        executableHat = ir.entry.executableHat,   -- Hat block info
        usedModules = entryResult.usedModules     -- Modules used by entry script
    }
end

return ScratchToLuaCompiler
