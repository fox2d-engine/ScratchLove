--- Resvg Lua binding utility functions
--- @module 'utils'

local ffi = require("ffi")

local M = {}

--- Error code to string mapping
--- @table error_messages
M.error_messages = {
    [0] = "OK",
    [1] = "NOT_AN_UTF8_STR",
    [2] = "FILE_OPEN_FAILED",
    [3] = "MALFORMED_GZIP",
    [4] = "ELEMENTS_LIMIT_REACHED",
    [5] = "INVALID_SIZE",
    [6] = "PARSING_FAILED",
}

--- Get error message from error code
--- @param code number Error code from resvg
--- @return string Error message
--- @function get_error_message
function M.get_error_message(code)
    return M.error_messages[code] or "UNKNOWN_ERROR"
end

--- Check error code and return result
--- @param code number Error code from resvg
--- @return boolean|nil true on success, nil on error
--- @return string|nil Error message if failed
--- @function check_error
function M.check_error(code)
    if code ~= 0 then
        return nil, M.get_error_message(code)
    end
    return true
end

--- Convert Transform struct to Lua table
--- @param transform userdata Transform struct
--- @return table Table with a,b,c,d,e,f fields
--- @function transform_to_table
function M.transform_to_table(transform)
    return {
        a = transform.a,
        b = transform.b,
        c = transform.c,
        d = transform.d,
        e = transform.e,
        f = transform.f,
    }
end

--- Convert Lua table to Transform struct
--- @param t table Table with a,b,c,d,e,f fields or array of 6 values
--- @return userdata Transform struct
--- @function table_to_transform
function M.table_to_transform(t)
    local transform = ffi.new("resvg_transform")
    transform.a = t.a or t[1] or 1 --- Horizontal scaling (default: 1)
    transform.b = t.b or t[2] or 0 --- Vertical skewing (default: 0)
    transform.c = t.c or t[3] or 0 --- Horizontal skewing (default: 0)
    transform.d = t.d or t[4] or 1 --- Vertical scaling (default: 1)
    transform.e = t.e or t[5] or 0 --- Horizontal translation (default: 0)
    transform.f = t.f or t[6] or 0 --- Vertical translation (default: 0)
    return transform
end

--- Convert Size struct to Lua table
--- @param size userdata Size struct
--- @return table Table with width and height fields
--- @function size_to_table
function M.size_to_table(size)
    return {
        width = size.width,
        height = size.height,
    }
end

--- Convert Lua table to Size struct
--- @param t table Table with width,height fields or array of 2 values
--- @return userdata Size struct
--- @function table_to_size
function M.table_to_size(t)
    local size = ffi.new("resvg_size")
    size.width = t.width or t[1] or 0   --- Width (default: 0)
    size.height = t.height or t[2] or 0 --- Height (default: 0)
    return size
end

--- Convert Rect struct to Lua table
--- @param rect userdata Rect struct
--- @return table Table with x,y,width,height fields
--- @function rect_to_table
function M.rect_to_table(rect)
    return {
        x = rect.x,
        y = rect.y,
        width = rect.width,
        height = rect.height,
    }
end

--- Convert Lua table to Rect struct
--- @param t table Table with x,y,width,height fields or array of 4 values
--- @return userdata Rect struct
--- @function table_to_rect
function M.table_to_rect(t)
    local rect = ffi.new("resvg_rect")
    rect.x = t.x or t[1] or 0           --- X coordinate (default: 0)
    rect.y = t.y or t[2] or 0           --- Y coordinate (default: 0)
    rect.width = t.width or t[3] or 0   --- Width (default: 0)
    rect.height = t.height or t[4] or 0 --- Height (default: 0)
    return rect
end

--- Rendering mode string to enum value mappings
--- @table shape_rendering_modes
--- @table text_rendering_modes
--- @table image_rendering_modes
M.shape_rendering_modes = {
    optimize_speed = 0,
    crisp_edges = 1,
    geometric_precision = 2,
}

M.text_rendering_modes = {
    optimize_speed = 0,
    optimize_legibility = 1,
    geometric_precision = 2,
}

M.image_rendering_modes = {
    optimize_quality = 0,
    optimize_speed = 1,
}

--- Get shape rendering mode enum value
--- @param mode string|number Mode name or enum value
--- @return number Enum value for shape rendering mode
--- @function get_shape_rendering_mode
function M.get_shape_rendering_mode(mode)
    if type(mode) == "string" then
        return M.shape_rendering_modes[mode:lower():gsub("-", "_")] or 2
    end
    return mode or 2
end

--- Get text rendering mode enum value
--- @param mode string|number Mode name or enum value
--- @return number Enum value for text rendering mode (default: optimize_legibility)
--- @function get_text_rendering_mode
function M.get_text_rendering_mode(mode)
    if type(mode) == "string" then
        return M.text_rendering_modes[mode:lower():gsub("-", "_")] or 1
    end
    return mode or 1
end

--- Get image rendering mode enum value
--- @param mode string|number Mode name or enum value
--- @return number Enum value for image rendering mode (default: optimize_quality)
--- @function get_image_rendering_mode
function M.get_image_rendering_mode(mode)
    if type(mode) == "string" then
        return M.image_rendering_modes[mode:lower():gsub("-", "_")] or 0
    end
    return mode or 0
end

local function load_system_library(os_name, arch)
    local ok, result = pcall(ffi.load, "resvg")
    if ok and result then
        print(string.format("Loaded resvg library from system path (OS: %s, Arch: %s)", os_name, arch))
        return result
    end
    error("Failed to load resvg library")
end

--- Load the resvg dynamic library
--- Tries multiple paths to find the library
--- @return ffi.namespace* FFI library handle
--- @function load_library
function M.load_library()
    local os_name = love.system.getOS() or "unknown"
    local jit = rawget(_G, "jit") --- Safely get jit global variable
    local arch = (jit and jit.arch) or "unknown"

    --- Map jit.os and jit.arch to prebuilt directory names
    local platform_map = {
        --- OS mappings
        ["OS X"] = "apple-darwin",
        ["Linux"] = "unknown-linux-gnu",
        ["Windows"] = "pc-windows-msvc",
        ["Android"] = "linux-android",

        --- Architecture mappings
        ["x64"] = "x86_64",
        ["x86"] = "i686",
        ["arm64"] = "aarch64",
        ["arm"] = "armv7",
    }

    --- Determine platform string
    local os_suffix = platform_map[os_name] or "unknown-linux-gnu"
    local arch_prefix = platform_map[arch] or arch

    --- Special handling for Android
    if os_name == "Android" then
        return load_system_library(os_name, arch) --- Use system paths on Android
    end

    local platform_dir = arch_prefix .. "-" .. os_suffix

    --- Determine library file extension
    local lib_name
    if os_name == "Windows" then
        lib_name = "resvg.dll"
    elseif os_name == "OS X" or os_name == "Darwin" then
        lib_name = "libresvg.dylib"
    else
        lib_name = "libresvg.so"
    end

    --- Build path to prebuilt library
    local prebuilt_path = "resvg/prebuilt/" .. platform_dir .. "/" .. lib_name

    --- Try loading from prebuilt directory first
    local ok, result = pcall(ffi.load, prebuilt_path)
    if ok and result then
        print(string.format("Loaded resvg library from prebuilt: %s (OS: %s, Arch: %s)",
            prebuilt_path, os_name, arch))
        return result
    end

    --- Fallback: try other possible paths
    local fallback_paths = {
        "resvg/prebuilt/" .. platform_dir .. "/" .. lib_name, --- Alternative prebuilt location
        "resvg/" .. lib_name,                                 --- Current directory
        package.searchpath and
        package.searchpath("resvg", package.cpath)            --- Lua package path
    }

    for _, path in ipairs(fallback_paths) do
        if path then
            ok, result = pcall(ffi.load, path)
            if ok and result then
                print(string.format("Loaded resvg library from fallback: %s (OS: %s, Arch: %s)",
                    path, os_name, arch))
                return result
            end
        end
    end

    --- Last resort: let FFI use system paths
    print(string.format("Warning: Could not find prebuilt library for %s, trying system paths", platform_dir))
    return load_system_library(os_name, arch)
end

--- Create identity transform
--- @return userdata Identity transform matrix
--- @function create_identity_transform
function M.create_identity_transform()
    return M.table_to_transform({ 1, 0, 0, 1, 0, 0 })
end

--- Create translation transform
--- @param x number|nil Horizontal translation (default: 0)
--- @param y number|nil Vertical translation (default: 0)
--- @return userdata Translation transform matrix
--- @function create_translate_transform
function M.create_translate_transform(x, y)
    return M.table_to_transform({ 1, 0, 0, 1, x or 0, y or 0 })
end

--- Create scale transform
--- @param sx number Horizontal scaling factor
--- @param sy number|nil Vertical scaling factor (defaults to sx)
--- @return userdata Scale transform matrix
--- @function create_scale_transform
function M.create_scale_transform(sx, sy)
    sy = sy or sx
    return M.table_to_transform({ sx, 0, 0, sy, 0, 0 })
end

--- Create rotation transform
--- @param angle number Rotation angle in degrees
--- @param cx number|nil Center X coordinate (default: 0)
--- @param cy number|nil Center Y coordinate (default: 0)
--- @return userdata Rotation transform matrix
--- @function create_rotate_transform
function M.create_rotate_transform(angle, cx, cy)
    cx = cx or 0
    cy = cy or 0
    local rad = math.rad(angle)
    local cos = math.cos(rad)
    local sin = math.sin(rad)

    if cx == 0 and cy == 0 then
        return M.table_to_transform({ cos, sin, -sin, cos, 0, 0 })
    else
        --- Rotation with center point
        return M.table_to_transform({
            cos, sin, -sin, cos,
            cx * (1 - cos) + cy * sin,
            cy * (1 - cos) - cx * sin
        })
    end
end

--- Matrix multiplication for transforms
--- @param t1 userdata First transform
--- @param t2 userdata Second transform
--- @return userdata Result of matrix multiplication
--- @function multiply_transforms
function M.multiply_transforms(t1, t2)
    local a1, b1, c1, d1, e1, f1 = t1.a, t1.b, t1.c, t1.d, t1.e, t1.f
    local a2, b2, c2, d2, e2, f2 = t2.a, t2.b, t2.c, t2.d, t2.e, t2.f

    return M.table_to_transform({
        a1 * a2 + c1 * b2,
        b1 * a2 + d1 * b2,
        a1 * c2 + c1 * d2,
        b1 * c2 + d1 * d2,
        a1 * e2 + c1 * f2 + e1,
        b1 * e2 + d1 * f2 + f1
    })
end

return M
