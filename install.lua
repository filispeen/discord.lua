local ffi = require("ffi")

local source = debug.getinfo(1, "S").source
local root = assert(source:match("^@(.+)[/\\][^/\\]+$"), "install.lua must be loaded from a file")
local package_file = assert(loadfile(root .. "/package.lua"), "package.lua not found")
local package_info = package_file()
local version = assert(package_info.version, "package version not found")
assert(version:match("^[%w._%-]+$"), "invalid package version")
if version == "REPLACE_ME" then
    print("discord.lua: native bundle install skipped because package.lua version is REPLACE_ME")
    return
end

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
    local old_channel = package.loaded["coro-channel"]
    if not old_channel then package.loaded["coro-channel"] = require("./lib/utils") end
    local ok, http = pcall(require, "coro-http")
    if not old_channel then package.loaded["coro-channel"] = nil end
    if not ok then error(http, 0) end
    local response, body = http.request("GET", download_url)
    if not response or response.code ~= 200 then error("native bundle download failed: HTTP " .. tostring(response and response.code), 0) end
    local file = assert(io.open(path, "wb"), "could not write native bundle")
    assert(file:write(body), "could not write native bundle")
    file:close()
end

local checksum_file = assert(io.open(root .. "/bundle.sha256", "r"), "bundle.sha256 not found")
local expected
for line in checksum_file:lines() do
    local platform, digest = line:match("^(%w+)=(%x+)$")
    if platform == ffi.os then expected = digest:lower() end
end
checksum_file:close()
if not expected or #expected ~= 64 then error("bundle.sha256 has no trusted SHA-256 for " .. ffi.os, 0) end

local function file_sha256(path)
    local command
    if ffi.os == "Linux" then
        command = "sha256sum " .. shell_quote(path) .. " 2>/dev/null"
    else
        command = "powershell -NoProfile -Command \"(Get-FileHash -Algorithm SHA256 -LiteralPath "
            .. powershell_quote(path) .. ").Hash\""
    end
    local pipe = assert(io.popen(command, "r"), "could not calculate archive SHA-256")
    local digest = pipe:read("*l")
    pipe:close()
    if ffi.os == "Linux" and digest then digest = digest:match("^(%x+)") end
    return digest and digest:lower()
end

local archive = os.tmpname()
download(url, archive)
if file_sha256(archive) ~= expected then
    os.remove(archive)
    error("native bundle SHA-256 mismatch; archive was not extracted", 0)
end

local command
if ffi.os == "Linux" then
    command = "mkdir -p " .. shell_quote(root .. "/lib/bundle") .. " && tar -xJf " .. shell_quote(archive)
        .. " -C " .. shell_quote(root .. "/lib/bundle") .. " && rm " .. shell_quote(archive)
else
    command = "powershell -NoProfile -Command \"$ErrorActionPreference = 'Stop'; $ProgressPreference = 'SilentlyContinue'; "
        .. "Set-Location -LiteralPath " .. powershell_quote(root) .. "; "
        .. "New-Item -ItemType Directory -Force -Path \"lib\\bundle\" | Out-Null; "
        .. "Expand-Archive -LiteralPath " .. powershell_quote(archive) .. " -DestinationPath \"lib\\bundle\" -Force; "
        .. "Remove-Item -LiteralPath " .. powershell_quote(archive) .. "\""
end

local ok = os.execute(command)
if ok ~= true and ok ~= 0 then error("native bundle download failed", 0) end
print("Installed " .. asset)
