--[[
    I remember you! -- icon manifest check.

    Run from anywhere with Lua 5.1:
        lua5.1 DEVELOPMENT.pathcheck.lua

    Reproduces Icons:AllPaths() without the game: loads the manifest, verifies
    that every path passes IRY.IsIconPath, and that no path is listed twice.
    Also feeds a few malformed paths through the validator to prove they are
    rejected. Exit code is non-zero on any failure.
]]

local script = (arg and arg[0]) or "DEVELOPMENT.pathcheck.lua"
local dir = script:match("^(.*)[/\\][^/\\]+$") or "."
local root = dir .. "/"

IRY = {}
ADDON_TITLE = "IRememberYou"

dofile(root .. "core/constants.lua")
dofile(root .. "core/iconpacks.lua")

local problems = 0
local total = 0
local seen = {}

for _, pack in ipairs(IRY.IconPacks or {}) do
    local count = 0
    for _, path in ipairs(pack.icons or {}) do
        count = count + 1
        total = total + 1
        if not IRY.IsIconPath(path) then
            print("bad path in pack '" .. tostring(pack.id) .. "': " .. tostring(path))
            problems = problems + 1
        end
        if seen[path] then
            print("duplicate path: " .. tostring(path))
            problems = problems + 1
        end
        seen[path] = true
    end
    print(string.format("pack %-6s %3d icons", tostring(pack.id), count))
end

local shouldReject = {
    "",
    "ESOUI/art/x.dds",
    "esoui/art/x.png",
    "/esoui/art/x.dds",
    "esoui/art/../x.dds",
    "esoui/art/x y.dds",
    "esoui/art//x.dds",
    "esoui/art/x.dds/",
    "esoui/art/Sub/x.dds",
    "IRememberYou/icons/base/X.dds",
    "IRememberYou/icons/a/b/x.dds",
    "some/other/addon/x.dds",
}
for _, path in ipairs(shouldReject) do
    if IRY.IsIconPath(path) then
        print("validator accepted a bad path: " .. tostring(path))
        problems = problems + 1
    end
end
if IRY.IsIconPath(nil) then
    print("validator accepted nil")
    problems = problems + 1
end

print(string.format("packs=%d paths=%d problems=%d", #IRY.IconPacks, total, problems))
if problems > 0 then
    print("FAILED")
    os.exit(1)
end
print("OK")
