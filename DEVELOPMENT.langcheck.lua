--[[
    I remember you! -- localization parity check.

    Run from anywhere with Lua 5.1:
        lua5.1 DEVELOPMENT.langcheck.lua

    Compares lang/en.lua and lang/ru.lua key by key, compares the HELP block
    lengths, and verifies that every IRY.L.<KEY> referenced by the source has
    an entry in en.lua. Exit code is non-zero when something is missing.
]]

local script = (arg and arg[0]) or "DEVELOPMENT.langcheck.lua"
local dir = script:match("^(.*)[/\\][^/\\]+$") or "."
local root = dir .. "/"

IRY = {}
function ZO_CreateStringId() end
function GetCVar() return "ru" end

dofile(root .. "lang/en.lua")
local en = IRY.L
dofile(root .. "lang/ru.lua")
local ru = IRY.L

local function keys(t)
    local out = {}
    for k in pairs(t) do out[k] = true end
    return out
end

local ek, rk = keys(en), keys(ru)
local missingRu, missingEn = {}, {}
for k in pairs(ek) do if rk[k] == nil then missingRu[#missingRu + 1] = k end end
for k in pairs(rk) do if ek[k] == nil then missingEn[#missingEn + 1] = k end end
table.sort(missingRu)
table.sort(missingEn)

local problems = 0

if #missingRu > 0 then
    print("missing in ru: " .. table.concat(missingRu, ", "))
    problems = problems + #missingRu
end
if #missingEn > 0 then
    print("missing in en: " .. table.concat(missingEn, ", "))
    problems = problems + #missingEn
end

print("HELP en=" .. tostring(#en.HELP) .. " ru=" .. tostring(#ru.HELP))
if #en.HELP ~= #ru.HELP then
    problems = problems + 1
    for i = 1, math.max(#en.HELP, #ru.HELP) do
        if en.HELP[i] ~= nil and ru.HELP[i] == nil then
            print("ru HELP missing line " .. i .. ": " .. en.HELP[i])
        elseif en.HELP[i] == nil and ru.HELP[i] ~= nil then
            print("en HELP missing line " .. i .. ": " .. ru.HELP[i])
        end
    end
end

-- Every IRY.L.<KEY> used by the source must exist in en.lua.
local p = io.popen('findstr /S /I "IRY.L." "' .. root .. '*.lua"')
if p then
    local used = {}
    for line in p:lines() do
        for key in line:gmatch("IRY%.L%.([A-Za-z0-9_]+)") do
            used[key] = true
        end
    end
    p:close()

    local missing = {}
    for k in pairs(used) do
        if en[k] == nil then missing[#missing + 1] = k end
    end
    table.sort(missing)
    if #missing > 0 then
        print("referenced but not in en.lua: " .. table.concat(missing, ", "))
        problems = problems + #missing
    else
        print("all referenced keys exist")
    end
else
    print("findstr unavailable -- skipped the referenced-keys scan")
end

if problems > 0 then
    print("FAILED: " .. problems .. " problem(s)")
    os.exit(1)
end
print("OK")
