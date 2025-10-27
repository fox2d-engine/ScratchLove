local utf8 = require("utf8")

local M = {}

M.utf8sub = function(s, i, j)
    local si = utf8.offset(s, i)
    local sj = j and utf8.offset(s, j + 1) or nil
    if not si then return "" end
    if not sj then
        return s:sub(si)
    else
        return s:sub(si, sj - 1)
    end
end

M.utf8len = function(s)
    return utf8.len(s)
end

--- Truncate a UTF-8 string to a specific length
---@param s string
---@param n number
---@return string
M.utf8truncate = function(s, n)
    local pos = utf8.offset(s, n + 1)
    if pos then
        return s:sub(1, pos - 1)
    else
        return s
    end
end

return M
