local ffi = require("ffi")

local source = debug.getinfo(1, "S").source
local root = assert(source:match("^@(.+)[/\\][^/\\]+$"), "install.lua must be loaded from a file")
local package_file = assert(loadfile(root .. "/package.lua"), "package.lua not found")
local package_info = package_file()
local version = assert(package_info.version, "package version not found")
assert(version:match("^[%w._%-]+$"), "invalid package version")

local assets = {
    Linux = "discord-bundle-linux-x64.tar.xz",
    Windows = "discord-bundle-windows-x64.zip",
}
local asset = assets[ffi.os]
if not asset or ffi.arch ~= "x64" then error("native bundle is only available for Linux x64 and Windows x64", 0) end

local url = "https://github.com/filispeen/discord.lua/releases/download/v" .. version .. "/" .. asset
if os.getenv("BUNDLE_INSTALL_DRY_RUN") == "1" then
    print(url)
    return
end

local function shell_quote(value)
    return "'" .. value:gsub("'", "'\\''") .. "'"
end

local function powershell_quote(value)
    return "'" .. value:gsub("'", "''") .. "'"
end

local function download(download_url, path)
    package.preload["coro-channel"] = package.preload["coro-channel"] or function()
        return require("./lib/utils")
    end
    local response, body = require("coro-http").request("GET", download_url)
    if not response or response.code ~= 200 then error("native bundle download failed: HTTP " .. tostring(response and response.code), 0) end
    local file = assert(io.open(path, "wb"), "could not write native bundle")
    assert(file:write(body), "could not write native bundle")
    file:close()
end

local command
if ffi.os == "Linux" then
    local archive = os.tmpname()
    download(url, archive)
    command = "mkdir -p " .. shell_quote(root .. "/lib/bundle") .. " && tar -xJf " .. shell_quote(archive)
        .. " -C " .. shell_quote(root .. "/lib/bundle") .. " && rm " .. shell_quote(archive)
else
    command = "powershell -NoProfile -Command \"$ErrorActionPreference = 'Stop'; $ProgressPreference = 'SilentlyContinue'; "
        .. "Set-Location -LiteralPath " .. powershell_quote(root) .. "; "
        .. "$archive = Join-Path $env:TEMP '" .. asset .. "'; "
        .. "Invoke-WebRequest -Uri " .. powershell_quote(url) .. " -OutFile $archive; "
        .. "New-Item -ItemType Directory -Force -Path \"lib\\bundle\" | Out-Null; "
        .. "Expand-Archive -LiteralPath $archive -DestinationPath \"lib\\bundle\" -Force; "
        .. "Remove-Item -LiteralPath $archive\""
end

local ok = os.execute(command)
if ok ~= true and ok ~= 0 then error("native bundle download failed", 0) end
print("Installed " .. asset)