-- Project Format Validator
-- Validates Scratch project format (sb2 vs sb3) based on native scratch-parser logic

local log = require("lib.log")

---@class ProjectValidator
local ProjectValidator = {}

---Check if project is valid SB3 format (strict validation)
---@param projectData table Parsed project JSON data
---@return boolean isValid True if valid SB3 format, false otherwise
---@return string|nil errorMessage Detailed error description if validation fails, nil if valid
function ProjectValidator.isSB3(projectData)
    -- SB3 MUST have meta object with semver field
    if not projectData.meta then
        log.debug("SB3 validation failed: Missing 'meta' field")
        return false, "Missing 'meta' field (required for SB3)"
    end

    if not projectData.meta.semver then
        log.debug("SB3 validation failed: Missing 'meta.semver' field")
        return false, "Missing 'meta.semver' field (required for SB3)"
    end

    -- Validate semver starts with "3."
    local semver = tostring(projectData.meta.semver)
    if not semver:match("^3%.") then
        log.debug("SB3 validation failed: Invalid semver version: " .. semver)
        return false, "Invalid semver version: " .. semver .. " (expected 3.x.x)"
    end

    -- SB3 MUST have targets array
    if not projectData.targets then
        log.debug("SB3 validation failed: Missing 'targets' field")
        return false, "Missing 'targets' field (required for SB3)"
    end

    if type(projectData.targets) ~= "table" then
        log.debug("SB3 validation failed: 'targets' is not a table")
        return false, "'targets' must be an array"
    end

    -- Targets array must have at least one element (stage)
    if #projectData.targets == 0 then
        log.debug("SB3 validation failed: 'targets' array is empty")
        return false, "'targets' array is empty (must contain at least stage)"
    end

    log.debug("SB3 validation passed")
    return true, nil
end

---Check if project is valid SB2 format (strict validation)
---@param projectData table Parsed project JSON data
---@return boolean isValid True if valid SB2 format, false otherwise
---@return string|nil errorMessage Detailed error description if validation fails, nil if valid
function ProjectValidator.isSB2(projectData)
    -- SB2 format is a direct stage object without meta/targets wrapper

    -- SB2 should NOT have meta or targets (those are SB3 fields)
    if projectData.meta then
        log.debug("SB2 validation failed: Has 'meta' field (this is SB3 format)")
        return false, "Has 'meta' field (this is SB3 format)"
    end

    if projectData.targets then
        log.debug("SB2 validation failed: Has 'targets' field (this is SB3 format)")
        return false, "Has 'targets' field (this is SB3 format)"
    end

    -- SB2 should have 'children' array (contains sprites)
    if not projectData.children then
        log.debug("SB2 validation failed: Missing 'children' field")
        return false, "Missing 'children' field (required for SB2)"
    end

    if type(projectData.children) ~= "table" then
        log.debug("SB2 validation failed: 'children' is not a table")
        return false, "'children' must be an array"
    end

    -- Optional: Check for other SB2 characteristics
    -- SB2 typically has objName, scripts, costumes, sounds, etc.
    if not projectData.objName then
        log.debug("SB2 validation failed: Missing 'objName' field")
        return false, "Missing 'objName' field (typical for SB2 stage)"
    end

    log.debug("SB2 validation passed")
    return true, nil
end

---Validate project format and return version or error
---This is the main entry point for project validation
---@param projectData table Parsed project JSON data from project.json
---@return number|nil version Project version number (2 for SB2, 3 for SB3), nil if invalid
---@return string|nil errorMessage User-friendly error description if validation fails, nil if valid
function ProjectValidator.validate(projectData)
    if not projectData then
        log.debug("Project validation failed: nil value")
        return nil, "Invalid project data: nil value"
    end

    if type(projectData) ~= "table" then
        log.debug("Project validation failed: expected table, got " .. type(projectData))
        return nil, "Invalid project data: expected table, got " .. type(projectData)
    end

    -- Check for at least some basic structure
    if next(projectData) == nil then
        log.debug("Project validation failed: empty table")
        return nil, "Invalid project data: empty table"
    end

    -- Try SB3 validation first (more common)
    local isSB3, sb3Error = ProjectValidator.isSB3(projectData)
    if isSB3 then
        return 3, nil
    end

    -- Try SB2 validation
    local isSB2, sb2Error = ProjectValidator.isSB2(projectData)
    if isSB2 then
        return 2, nil
    end

    -- Neither format is valid - log detailed error for debugging
    log.debug("Project validation failed:")
    log.debug("  SB3 check: " .. (sb3Error or "unknown error"))
    log.debug("  SB2 check: " .. (sb2Error or "unknown error"))

    -- Return user-friendly error message
    local errorMsg = "Invalid project format. Please ensure you're loading a valid Scratch 3.0 (.sb3) file."

    return nil, errorMsg
end

return ProjectValidator
