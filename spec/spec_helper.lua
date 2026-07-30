local function file_exists(path)
    local f = io.open(path, "r")
    if f then
        f:close()
        return true
    end
    return false
end

local function normalize(path)
    local parts = {}
    for segment in path:gmatch("[^/]+") do
        if segment == ".." then
            if #parts > 0 and parts[#parts] ~= ".." then
                table.remove(parts)
            else
                table.insert(parts, segment)
            end
        elseif segment ~= "." then
            table.insert(parts, segment)
        end
    end
    return table.concat(parts, "/")
end

local function dirname(path)
    local dir = path:match("^(.*)/[^/]+$")
    return dir or ""
end

local function caller_path()
    local level = 2
    while true do
        local info = debug.getinfo(level, "S")
        if not info then
            return nil
        end
        local source = info.source
        if source:sub(1, 1) == "@" then
            local path = source:sub(2)
            if path:match("%.lua$") and not path:match("/busted/") and not path:match("^busted") and not path:match("spec_helper%.lua$") then
                return path
            end
        end
        level = level + 1
    end
end

local function relative_searcher(name)
    if not (name:sub(1, 2) == "./" or name:sub(1, 3) == "../") then
        return nil
    end

    local caller = caller_path()
    local base
    if caller and caller:match("^lib/") then
        base = dirname(caller)
    else
        base = "lib"
    end

    local resolved = normalize(base .. "/" .. name)
    local candidates = {
        resolved .. ".lua",
        resolved .. "/init.lua",
    }

    for _, candidate in ipairs(candidates) do
        if file_exists(candidate) then
            return function()
                local chunk = assert(loadfile(candidate))
                return chunk()
            end
        end
    end

    return "\n\tno file '" .. candidates[1] .. "'\n\tno file '" .. candidates[2] .. "'"
end

if not _G.__discord_lua_spec_helper_installed then
    table.insert(package.searchers or package.loaders, 1, relative_searcher)
    package.path = "lib/?.lua;lib/?/?.lua;" .. package.path
    _G.__discord_lua_spec_helper_installed = true
end

return true
