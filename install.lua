local ffi = require("ffi")

local source = debug.getinfo(1, "S").source
local root = assert(source:match("^@(.+)[/\\][^/\\]+$"), "install.lua must be loaded from a file")
local package_file = assert(io.open(root .. "/package.lua", "r"), "package version not found")
local package_text = package_file:read("*a")
package_file:close()

local version = assert(package_text:match('version%s*=%s*"([^"]+)"'), "package version not found")
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

local command
if ffi.os == "Linux" then
    command = "cd " .. shell_quote(root) .. " && mkdir -p lib/bundle && curl -fL " .. shell_quote(url)
        .. " -o /tmp/" .. asset .. " && tar -xJf /tmp/" .. asset .. " -C lib/bundle && rm /tmp/" .. asset
else
    command = "powershell -NoProfile -Command \"$ErrorActionPreference = 'Stop'; Set-Location -LiteralPath "
        .. powershell_quote(root) .. "; $archive = Join-Path $env:TEMP '" .. asset .. "'; Invoke-WebRequest -Uri "
        .. powershell_quote(url) .. " -OutFile $archive; New-Item -ItemType Directory -Force -Path 'lib/bundle' | Out-Null; "
        .. "Expand-Archive -LiteralPath $archive -DestinationPath 'lib/bundle' -Force; Remove-Item $archive\""
end

local ok = os.execute(command)
if ok ~= true and ok ~= 0 then error("native bundle download failed", 0) end
print("Installed " .. asset)
