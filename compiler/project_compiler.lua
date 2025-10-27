-- Project-level compiler
-- Aggregates all top-level hat scripts into a single precompiled bundle

local log = require("lib.log")
local ScratchToLuaCompiler = require("compiler.init")

---@class CompiledScriptBundleEntry
---@field target any Runtime target object (stage or sprite)
---@field targetKey string Key used in bundle lookups
---@field blockId string Top-level block identifier
---@field blockContainer table<string, Block> Block container table used for caching
---@field executableHat boolean Whether the hat is executable
---@field entrySource string Generated Lua source for entry script
---@field procedureSources table<string, string> Generated Lua source per procedure variant

---@class CompiledBundleContext
---@field source string Generated aggregate Lua chunk source
---@field entries CompiledScriptBundleEntry[] Metadata for cache registration

---@class ProjectCompiler
local ProjectCompiler = {}

-- Simple hash function for generating stable identifiers
local function simpleHash(str)
    local hash = 0
    for i = 1, #str do
        local byte = string.byte(str, i)
        hash = (hash * 31 + byte) % 2147483647
    end
    return hash
end

-- Base32 encoding table (without confusing characters like 0, O, I, 1)
local base32Chars = "ABCDEFGHIJKLMNPQRSTUVWXYZ23456789"

local function toBase32(num)
    if num == 0 then return "A" end
    local result = ""
    while num > 0 do
        local remainder = num % 32
        result = base32Chars:sub(remainder + 1, remainder + 1) .. result
        num = math.floor(num / 32)
    end
    return result
end

local function sanitizeIdentifier(raw)
    -- First try to extract ASCII alphanumeric characters and underscores
    local ascii = raw:gsub("[^%w_]", "")

    -- If we have a clean ASCII identifier, use it (but ensure it starts with letter/underscore)
    if #ascii > 0 and ascii:match("^[%a_]") then
        return ascii
    end

    -- For names with Chinese characters or other Unicode, use hash-based approach
    local hash = simpleHash(raw)
    local base32Hash = toBase32(hash)

    -- Create a readable identifier: prefix + hash
    local prefix = "target"
    if #ascii > 0 then
        -- Use cleaned ASCII characters as prefix if available
        if ascii:match("^[^%a_]") then
            ascii = "_" .. ascii
        end
        prefix = ascii:sub(1, 8) -- Limit prefix length
    end

    return prefix .. "_" .. base32Hash
end

local function chunkToNamedFunction(source, functionName)
    local headerPattern = "^return%s+function%s*%((.-)%)"
    local params = source:match(headerPattern)
    if not params then
        error("Unexpected generated Lua chunk header while renaming function")
    end
    local named = source:gsub(headerPattern, "local function " .. functionName .. "(%1)", 1)
    return named
end

local function blockSorter(a, b)
    local ay = (a.block.y or 0)
    local by = (b.block.y or 0)
    if ay ~= by then
        return ay < by
    end
    local ax = (a.block.x or 0)
    local bx = (b.block.x or 0)
    if ax ~= bx then
        return ax < bx
    end
    return a.id < b.id
end

local function gatherHatBlocks(target)
    local hatBlockIds = {}
    local hatIndex = target.hatBlockIndex
    if not hatIndex and target.spriteTemplate then
        hatIndex = target.spriteTemplate.hatBlockIndex
    end
    if not hatIndex then
        return hatBlockIds
    end

    -- Get block container and order
    local blockContainer = target.blocks or (target.spriteTemplate and target.spriteTemplate.blocks) or {}
    local blockOrder = target.blockOrder or (target.spriteTemplate and target.spriteTemplate.blockOrder)

    if not blockOrder then
        error("ProjectCompiler:gatherHatBlocks: blockOrder is required for stable compilation order")
    end

    -- Empty blockOrder is valid (target has no blocks)

    -- Collect hat blocks in original JSON order (not by opcode grouping)
    for _, blockId in ipairs(blockOrder) do
        local block = blockContainer[blockId]
        if block and block.topLevel and hatIndex[block.opcode] then
            table.insert(hatBlockIds, {
                id = blockId,
                block = block
            })
        end
    end

    -- No need to sort - already in stable JSON order
    return hatBlockIds
end

local function getBlockContainer(target)
    if target.blocks then
        return target.blocks
    end
    if target.spriteTemplate and target.spriteTemplate.blocks then
        return target.spriteTemplate.blocks
    end
    return nil
end

local function compilerThreadForTarget(runtime, target, topBlock, blockContainer)
    return {
        target = {
            name = target.name,  -- Required for variable scope resolution
            isStage = target.isStage or false,  -- Required for script lookup
            runtime = runtime,
            variables = target.variables or {},
            lists = target.lists or {},
            blockOrder = target.blockOrder or {},  -- Required for stable procedure definition cache
            spriteTemplate = target.spriteTemplate,  -- May contain blockOrder if target is a clone
            sprite = {
                costumes = target.costumes or {},
                sounds = target.sounds or {}
            }
        },
        topBlock = topBlock,
        blockContainer = blockContainer
    }
end

---Generate closure-based compiled project for all hat blocks in the runtime.
---@param runtime Runtime
---@return CompiledBundleContext
function ProjectCompiler.generateClosureBundle(runtime)
    local compiler = ScratchToLuaCompiler:new()
    local entries = {}
    local orderedTargets = {}

    if runtime.stage then
        table.insert(orderedTargets, runtime.stage)
    end

    for _, template in ipairs(runtime.spriteTemplates or {}) do
        local baseSprite = nil
        for _, clone in ipairs(template.clones or {}) do
            if clone and not clone.isClone then
                baseSprite = clone
                break
            end
        end
        if not baseSprite and template.clones and #template.clones > 0 then
            baseSprite = template.clones[1]
        end
        if baseSprite then
            table.insert(orderedTargets, baseSprite)
        end
    end

    -- Phase 1: Collect all scripts and analyze module usage
    for _, target in ipairs(orderedTargets) do
        local blockContainer = getBlockContainer(target)
        if blockContainer then
            local hatBlocks = gatherHatBlocks(target)
            for _, hat in ipairs(hatBlocks) do
                local threadData = compilerThreadForTarget(runtime, target, hat.id, blockContainer)

                -- Get function body only (no wrapper) for closure compilation
                local success, result = pcall(function()
                    return compiler:compile(threadData, {
                        emitSourceOnly = true,
                        closureMode = true,
                        functionBodyOnly = true
                    })
                end)

                if not success then
                    -- Format detailed error for outer layer to display
                    local errorMessage = string.format(
                        "Failed to compile script in %s\nBlock ID: %s\n\nError:\n%s",
                        tostring(target.name or "Unknown"),
                        tostring(hat.id),
                        tostring(result)
                    )

                    error(errorMessage)
                end

                if not result or not result.entrySource then
                    error("Compiler returned incomplete result for block " .. tostring(hat.id))
                end

                local targetKey = target.name or (target.isStage and "Stage") or (target.spriteTemplate and target.spriteTemplate.name) or "Target"
                local procedureBodies = {}
                for variant, proc in pairs(result.procedures or {}) do
                    procedureBodies[variant] = proc.source or ""
                end

                table.insert(entries, {
                    target = target,
                    targetKey = targetKey,
                    blockId = hat.id,
                    blockContainer = blockContainer,
                    executableHat = result.executableHat and true or false,
                    entryBody = result.entrySource or "",
                    procedureBodies = procedureBodies,
                    procedures = result.procedures or {}
                })
            end
        end
    end

    -- Phase 2: Generate closure-based source
    local builder = {}
    table.insert(builder, "-- Auto-generated compiled Scratch closure bundle")
    table.insert(builder, "return function(runtime)")
    table.insert(builder, "    -- Shared dependencies loaded once")
    table.insert(builder, "    local Global = require('global')")

    -- Import all block modules (simplified - no dynamic detection)
    table.insert(builder, "    local cast = require('utils.cast')")
    table.insert(builder, "    local BlockHelpers = require('runtime.block_helpers')")

    table.insert(builder, "")
    table.insert(builder, "    -- Shared performance optimizations")
    table.insert(builder, "    local stage = runtime.stage")
    table.insert(builder, "    local toNumber = cast.toNumber")
    table.insert(builder, "    local toNumberOrNaN = cast.toNumberOrNaN")
    table.insert(builder, "    local toBoolean = cast.toBoolean")
    table.insert(builder, "    local toString = cast.toString")

    table.insert(builder, "")
    table.insert(builder, "    -- Script functions")
    local seenTargets = {}
    local orderedTargetKeys = {}  -- Maintain target order for stable output

    for _, entry in ipairs(entries) do
        local targetKey = entry.targetKey
        local blockId = entry.blockId
        local sanitizedTarget = sanitizeIdentifier(targetKey)
        local sanitizedBlock = sanitizeIdentifier(blockId)

        if not seenTargets[targetKey] then
            table.insert(builder, string.format("    local %s_scripts = {}", sanitizedTarget))
            seenTargets[targetKey] = true
            table.insert(orderedTargetKeys, targetKey)  -- Record order
        end

        -- Create script entry with inline function definitions (avoid local variables)
        table.insert(builder, string.format("    %s_scripts[%q] = {", sanitizedTarget, blockId))
        table.insert(builder, string.format("        executableHat = %s,", entry.executableHat and "true" or "false"))

        -- Generate entry function inline
        table.insert(builder, "        entry = function(runtime, target, thread)")
        for line in entry.entryBody:gmatch("[^\r\n]+") do
            if line:match("^%s*$") then
                table.insert(builder, "")
            else
                table.insert(builder, "        " .. line)
            end
        end
        table.insert(builder, "        end,")

        -- Generate procedure functions inline
        table.insert(builder, "        procedures = {")

        -- Sort procedure variants for stable output
        local procedureVariants = {}
        for variant in pairs(entry.procedureBodies) do
            table.insert(procedureVariants, variant)
        end
        table.sort(procedureVariants)

        local firstProc = true
        for _, variant in ipairs(procedureVariants) do
            local procBody = entry.procedureBodies[variant]
            if not firstProc then
                table.insert(builder, ",")
            end
            firstProc = false
            table.insert(builder, string.format("            [%q] = function(runtime, target, thread, ...)", variant))
            for line in procBody:gmatch("[^\r\n]+") do
                if line:match("^%s*$") then
                    table.insert(builder, "")
                else
                    table.insert(builder, "            " .. line)
                end
            end
            table.insert(builder, "            end")
        end
        table.insert(builder, "        }")
        table.insert(builder, "    }")
        table.insert(builder, "")
    end

    table.insert(builder, "    -- Return script collection")
    table.insert(builder, "    return {")
    -- Use ordered target keys for stable output
    for _, targetKey in ipairs(orderedTargetKeys) do
        local sanitizedTarget = sanitizeIdentifier(targetKey)
        table.insert(builder, string.format("        [%q] = %s_scripts,", targetKey, sanitizedTarget))
    end
    table.insert(builder, "    }")
    table.insert(builder, "end")

    local source = table.concat(builder, "\n")

    return {
        source = source,
        entries = entries
    }
end

---Generate aggregated Lua script and metadata for all hat blocks in the runtime (legacy).
---@param runtime Runtime
---@return CompiledBundleContext
function ProjectCompiler.generateBundle(runtime)
    local compiler = ScratchToLuaCompiler:new()
    local entries = {}
    local orderedTargets = {}

    if runtime.stage then
        table.insert(orderedTargets, runtime.stage)
    end

    for _, template in ipairs(runtime.spriteTemplates or {}) do
        local baseSprite = nil
        for _, clone in ipairs(template.clones or {}) do
            if clone and not clone.isClone then
                baseSprite = clone
                break
            end
        end
        if not baseSprite and template.clones and #template.clones > 0 then
            baseSprite = template.clones[1]
        end
        if baseSprite then
            table.insert(orderedTargets, baseSprite)
        end
    end

    local compileOrder = {}

    for _, target in ipairs(orderedTargets) do
        local blockContainer = getBlockContainer(target)
        if blockContainer then
            local hatBlocks = gatherHatBlocks(target)
            for _, hat in ipairs(hatBlocks) do
                local threadData = compilerThreadForTarget(runtime, target, hat.id, blockContainer)
                local success, result = pcall(function()
                    return compiler:compile(threadData, { emitSourceOnly = true })
                end)

                if not success then
                    -- Format detailed error for outer layer to display
                    local errorMessage = string.format(
                        "Failed to compile script in %s\nBlock ID: %s\n\nError:\n%s",
                        tostring(target.name or "Unknown"),
                        tostring(hat.id),
                        tostring(result)
                    )

                    error(errorMessage)
                end

                if not result or not result.entrySource then
                    error("Compiler returned incomplete result for block " .. tostring(hat.id))
                end

                local targetKey = target.name or (target.isStage and "Stage") or (target.spriteTemplate and target.spriteTemplate.name) or "Target"
                local procedureSources = {}
                for variant, proc in pairs(result.procedures or {}) do
                    procedureSources[variant] = proc.source or ""
                end

                table.insert(entries, {
                    target = target,
                    targetKey = targetKey,
                    blockId = hat.id,
                    blockContainer = blockContainer,
                    executableHat = result.executableHat and true or false,
                    entrySource = result.entrySource or "",
                    procedureSources = procedureSources,
                    procedures = result.procedures or {}
                })

                table.insert(compileOrder, entries[#entries])
            end
        end
    end

    local builder = {}
    table.insert(builder, "-- Auto-generated compiled Scratch bundle")
    table.insert(builder, "local bundle = { scripts = {} }")
    table.insert(builder, "")

    local seenTargets = {}

    for _, entry in ipairs(compileOrder) do
        local targetKey = entry.targetKey
        local blockId = entry.blockId
        local sanitizedTarget = sanitizeIdentifier(targetKey)
        local sanitizedBlock = sanitizeIdentifier(blockId)

        if not seenTargets[targetKey] then
            table.insert(builder, string.format("bundle.scripts[%q] = {}", targetKey))
            seenTargets[targetKey] = true
        end

        if not entry.entrySource or entry.entrySource == "" then
            error("Missing generated source for block " .. tostring(blockId))
        end

        local header = string.format(
            "bundle.scripts[%q][%q] = { executableHat = %s, entrySource = %s, procedures = {} }",
            targetKey,
            blockId,
            entry.executableHat and "true" or "false",
            string.format("%q", entry.entrySource or "")
        )
        table.insert(builder, header)

        local entryFunctionName = string.format("__compiled_%s_%s_entry", sanitizedTarget, sanitizedBlock)
        local entryFunctionDef = chunkToNamedFunction(entry.entrySource or "", entryFunctionName)
        table.insert(builder, entryFunctionDef)
        table.insert(builder, string.format(
            "bundle.scripts[%q][%q].entry = %s",
            targetKey,
            blockId,
            entryFunctionName
        ))

        local procedureVariants = {}
        for variant in pairs(entry.procedures or {}) do
            table.insert(procedureVariants, variant)
        end
        table.sort(procedureVariants)

        for _, variant in ipairs(procedureVariants) do
            local proc = entry.procedures and entry.procedures[variant]
            local procSource = proc.source or ""
            if procSource == "" then
                error("Missing procedure source for variant " .. tostring(variant) .. " in block " .. tostring(blockId))
            end
            local sanitizedVariant = sanitizeIdentifier(variant)
            local procFunctionName = string.format("__compiled_%s_%s_proc_%s", sanitizedTarget, sanitizedBlock, sanitizedVariant)
            table.insert(builder, string.format(
                "bundle.scripts[%q][%q].procedures[%q] = { source = %s }",
                targetKey,
                blockId,
                variant,
                string.format("%q", procSource)
            ))
            local procFunctionDef = chunkToNamedFunction(procSource, procFunctionName)
            table.insert(builder, procFunctionDef)
            table.insert(builder, string.format(
                "bundle.scripts[%q][%q].procedures[%q].func = %s",
                targetKey,
                blockId,
                variant,
                procFunctionName
            ))
        end

        table.insert(builder, "")
    end

    table.insert(builder, "return bundle")

    local source = table.concat(builder, "\n")

    return {
        source = source,
        entries = entries
    }
end

---Prepare variables for all targets by scanning blocks and creating missing variables.
---This ensures variables referenced in compiled code exist at runtime.
---@param runtime Runtime
function ProjectCompiler.prepareVariables(runtime)
    log.debug("Preparing variables for runtime (pre-compilation scan)")

    local function ensureVariable(target, id, name, variableType)
        -- Look for by ID in target
        if target.variables and target.variables[id] then
            return
        end

        -- Look for by ID in stage (if target is not stage)
        if not target.isStage and runtime.stage and runtime.stage.variables and runtime.stage.variables[id] then
            return
        end

        -- Look for by name and type in target
        if target.variables then
            for varId, currVar in pairs(target.variables) do
                local varType = currVar.type or ""
                if currVar.name == name and varType == variableType then
                    return
                end
            end
        end

        -- Look for by name and type in stage (if target is not stage)
        if not target.isStage and runtime.stage and runtime.stage.variables then
            for varId, currVar in pairs(runtime.stage.variables) do
                local varType = currVar.type or ""
                if currVar.name == name and varType == variableType then
                    return
                end
            end
        end

        log.debug("[ProjectCompiler] Auto-creating variable (Scratch compatibility): " ..
            tostring(name) .. " (ID: " .. tostring(id) .. ") in " .. tostring(target.name))

        local newVariable = {
            id = id,
            name = name,
            type = variableType,
            value = (variableType == "list") and {} or 0,
            cloud = false,
            isCloud = false
        }

        target.variables[tostring(id)] = newVariable

        -- Create in all clones if this is a sprite
        if target.spriteTemplate then
            local clones = target.spriteTemplate.clones
            if clones then
                for _, clone in ipairs(clones) do
                    if not clone.variables[id] then
                        clone.variables[tostring(id)] = {
                            id = id,
                            name = name,
                            type = variableType,
                            value = (variableType == "list") and {} or 0,
                            cloud = false,
                            isCloud = false
                        }
                    end
                end
            end
        end
    end

    local function scanBlockForVariables(target, blockId, blocks)
        local block = blocks[blockId]
        if not block then return end

        -- Scan inputs for variable/list references (primitiveType 12 and 13)
        if block.inputs then
            for inputName, input in pairs(block.inputs) do
                local value = nil

                -- Handle ProjectModel's parsed format {shadowType, value, obscuredShadow}
                if type(input) == "table" and input.value ~= nil then
                    value = input.value
                end

                if type(value) == "table" and #value >= 3 then
                    local primitiveType = value[1]

                    -- primitiveType 12: Variable reference {12, "variableName", variableId}
                    if primitiveType == 12 then
                        local variableName = value[2]
                        local variableId = value[3]
                        ensureVariable(target, variableId, variableName, "")
                    end

                    -- primitiveType 13: List reference {13, "listName", listId}
                    if primitiveType == 13 then
                        local listName = value[2]
                        local listId = value[3]
                        ensureVariable(target, listId, listName, "list")
                    end
                end
            end
        end

        -- Scan fields for variable/list references (used by data blocks)
        if block.fields then
            for fieldName, field in pairs(block.fields) do
                if type(field) == "table" and field.id and field.value then
                    -- Determine variable type based on block opcode
                    local variableType = ""
                    if block.opcode and block.opcode:match("^data_list") then
                        variableType = "list"
                    end
                    ensureVariable(target, field.id, field.value, variableType)
                end
            end
        end
    end

    -- Scan all targets
    local orderedTargets = {}
    if runtime.stage then
        table.insert(orderedTargets, runtime.stage)
    end

    for _, template in ipairs(runtime.spriteTemplates or {}) do
        local baseSprite = nil
        for _, clone in ipairs(template.clones or {}) do
            if clone and not clone.isClone then
                baseSprite = clone
                break
            end
        end
        if not baseSprite and template.clones and #template.clones > 0 then
            baseSprite = template.clones[1]
        end
        if baseSprite then
            table.insert(orderedTargets, baseSprite)
        end
    end

    for _, target in ipairs(orderedTargets) do
        local blockContainer = getBlockContainer(target)
        if blockContainer then
            local blockOrder = target.blockOrder or (target.spriteTemplate and target.spriteTemplate.blockOrder)
            if blockOrder then
                for _, blockId in ipairs(blockOrder) do
                    scanBlockForVariables(target, blockId, blockContainer)
                end
            end
        end
    end

    log.debug("Variable preparation complete")
end

---Compile the entire runtime project using closure mode and register compiled scripts.
---@param runtime Runtime
---@return string compiledSource Aggregated compiled Lua source
function ProjectCompiler.compileRuntimeWithClosure(runtime)
    -- Check if SKIP_COMPILE is set and project.lua exists
    local skipCompile = os.getenv("SKIP_COMPILE")
    if skipCompile and runtime.project and runtime.project.projectPath then
        local projectLuaPath = runtime.project.projectPath .. "/project.lua"

        -- Check if file exists using love.filesystem
        local info = love.filesystem.getInfo(projectLuaPath)
        if info and info.type == "file" then
            -- Normal compilation already creates variables via _descendVariable in irgen.lua
            -- But SKIP_COMPILE bypasses compilation, so we need to ensure variables exist
            ProjectCompiler.prepareVariables(runtime)

            local fullPath = love.filesystem.getSaveDirectory() .. "/" .. projectLuaPath
            log.info("SKIP_COMPILE enabled - loading existing project.lua from: " .. fullPath)

            -- Read the existing compiled source using love.filesystem
            local existingSource, err = love.filesystem.read(projectLuaPath)
            if not existingSource then
                log.warn("Failed to read existing project.lua: " .. tostring(err) .. ", falling back to recompilation")
                -- Fall through to normal compilation
            else
                -- Try to load and execute the existing compiled bundle
                local loadSuccess, loadError = pcall(function()
                    -- Load the compiled bundle
                    local chunk, err = load(existingSource, "compiled_closure_bundle", "t")
                    if not chunk then
                        error("Failed to load compiled bundle: " .. tostring(err))
                    end

                    local success, bundleFactory = pcall(chunk)
                    if not success then
                        error("Failed to execute compiled bundle: " .. tostring(bundleFactory))
                    end

                    if type(bundleFactory) ~= "function" then
                        error("Compiled bundle should return a factory function")
                    end

                    -- Execute the factory function to get the script collection
                    local success2, scripts = pcall(bundleFactory, runtime)
                    if not success2 then
                        error("Failed to execute closure factory: " .. tostring(scripts))
                    end

                    if type(scripts) ~= "table" then
                        error("Closure factory returned unexpected structure")
                    end

                    -- Register all compiled scripts in the compiler cache
                    runtime.compilerCache = runtime.compilerCache or {}

                    for targetKey, targetScripts in pairs(scripts) do
                        if type(targetScripts) == "table" then
                            for blockId, scriptData in pairs(targetScripts) do
                                if type(scriptData) == "table" and scriptData.entry then
                                    -- Find the target and its block container
                                    local target = nil
                                    if targetKey == "Stage" and runtime.stage then
                                        target = runtime.stage
                                    else
                                        for _, t in ipairs(runtime.targets or {}) do
                                            if t.name == targetKey or (t.spriteTemplate and t.spriteTemplate.name == targetKey) then
                                                target = t
                                                break
                                            end
                                        end
                                    end

                                    if target then
                                        local blockContainer = target.blocks or (target.spriteTemplate and target.spriteTemplate.blocks)
                                        if blockContainer then
                                            runtime.compilerCache[blockContainer] = runtime.compilerCache[blockContainer] or {}
                                            runtime.compilerCache[blockContainer][blockId] = {
                                                entryFunction = scriptData.entry,
                                                procedures = scriptData.procedures or {},
                                                executableHat = scriptData.executableHat
                                            }
                                        end
                                    end
                                end
                            end
                        end
                    end

                    runtime.compiledBundle = {
                        source = existingSource,
                        scripts = scripts,
                        factory = bundleFactory
                    }

                    log.info("Successfully loaded existing compiled project from project.lua")
                end)

                if loadSuccess then
                    return existingSource
                else
                    log.warn("Failed to load project.lua: " .. tostring(loadError) .. ", falling back to recompilation")
                    -- Fall through to normal compilation
                end
            end
        else
            log.info("SKIP_COMPILE enabled but project.lua not found at: " .. projectLuaPath .. ", will compile and save")
        end
    end

    local context = ProjectCompiler.generateClosureBundle(runtime)
    local chunk, err = load(context.source, "compiled_closure_bundle", "t")
    if not chunk then
        log.error("Failed to load compiled closure bundle: " .. tostring(err))
        error(err)
    end

    local success, bundleFactory = pcall(chunk)
    if not success then
        log.error("Executing compiled closure bundle failed: " .. tostring(bundleFactory))
        error(bundleFactory)
    end

    if type(bundleFactory) ~= "function" then
        error("Compiled closure bundle should return a factory function")
    end

    -- Execute the factory function to get the script collection
    local success2, scripts = pcall(bundleFactory, runtime)
    if not success2 then
        log.error("Executing closure factory function failed: " .. tostring(scripts))
        error(scripts)
    end

    if type(scripts) ~= "table" then
        error("Closure factory function returned unexpected structure")
    end

    runtime.compilerCache = runtime.compilerCache or {}

    for _, entry in ipairs(context.entries) do
        local targetScripts = scripts[entry.targetKey]
        if not targetScripts then
            error("Missing compiled scripts for target " .. tostring(entry.targetKey))
        end

        local scriptData = targetScripts[entry.blockId]
        if not scriptData then
            error("Missing compiled script data for block " .. tostring(entry.blockId))
        end

        local blockContainer = entry.blockContainer
        if blockContainer then
            runtime.compilerCache[blockContainer] = runtime.compilerCache[blockContainer] or {}
            runtime.compilerCache[blockContainer][entry.blockId] = {
                entryFunction = scriptData.entry,
                procedures = scriptData.procedures or {},
                executableHat = scriptData.executableHat
            }
        end
    end

    runtime.compiledBundle = {
        source = context.source,
        scripts = scripts,
        factory = bundleFactory
    }

    log.info("Project-wide closure compilation completed: " .. tostring(#context.entries) .. " scripts compiled")

    return context.source
end

---Compile the entire runtime project and register compiled scripts (legacy).
---@param runtime Runtime
---@return string compiledSource Aggregated compiled Lua source
function ProjectCompiler.compileRuntime(runtime)
    local context = ProjectCompiler.generateBundle(runtime)
    local chunk, err = load(context.source, "compiled_project_bundle", "t")
    if not chunk then
        log.error("Failed to load compiled project bundle: " .. tostring(err))
        error(err)
    end

    local success, bundle = pcall(chunk)
    if not success then
        log.error("Executing compiled project bundle failed: " .. tostring(bundle))
        error(bundle)
    end

    if type(bundle) ~= "table" or type(bundle.scripts) ~= "table" then
        error("Compiled project bundle returned unexpected structure")
    end

    runtime.compilerCache = runtime.compilerCache or {}

    for _, entry in ipairs(context.entries) do
        local targetScripts = bundle.scripts[entry.targetKey]
        if not targetScripts then
            error("Missing compiled scripts for target " .. tostring(entry.targetKey))
        end

        local scriptData = targetScripts[entry.blockId]
        if not scriptData then
            error("Missing compiled script data for block " .. tostring(entry.blockId))
        end

        local procedures = {}
        local procedureSources = {}
        for variant, proc in pairs(scriptData.procedures or {}) do
            procedures[variant] = proc.func
            procedureSources[variant] = proc.source
        end

        local blockContainer = entry.blockContainer
        if blockContainer then
            runtime.compilerCache[blockContainer] = runtime.compilerCache[blockContainer] or {}
            runtime.compilerCache[blockContainer][entry.blockId] = {
                entryFunction = scriptData.entry,
                entrySource = scriptData.entrySource,
                procedures = procedures,
                procedureSources = procedureSources,
                executableHat = scriptData.executableHat
            }
        end
    end

    runtime.compiledBundle = {
        source = context.source,
        bundle = bundle
    }

    log.info("Project-wide compilation completed: " .. tostring(#context.entries) .. " scripts compiled")

    return context.source
end

return ProjectCompiler
