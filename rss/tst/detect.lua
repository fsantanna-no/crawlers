#!/usr/bin/env lua5.4
-- detect.lua — test feed type detection
-- 1.1-1.4: yq XML->JSON produces valid JSON
-- 2.1-2.2: detect RSS 2.0 vs Atom feed type

local DIR = arg[1] or "."
local FIX = DIR .. "/fixtures"

local ALL  = {"akita", "hn", "lobster", "github"}
local RSS2 = {"akita", "hn", "lobster"}
local ATOM = {"github"}

local function run(cmd)
    local h = io.popen(cmd)
    local out = h:read("*a")
    h:close()
    return out
end

-- 1.1-1.4: yq XML to JSON produces valid JSON
for _, xml in ipairs(ALL) do
    local ok = os.execute(
        "cat '" .. FIX .. "/" .. xml .. ".xml'"
        .. " | yq -p xml -o json | jq empty")
    assert(ok,
        "FAIL: " .. xml .. ".xml not valid JSON")
end

-- 2.1: detect RSS 2.0 feed type
for _, xml in ipairs(RSS2) do
    local t = run(
        "cat '" .. FIX .. "/" .. xml .. ".xml'"
        .. " | yq -p xml -o json"
        .. " | jq -r '"
        .. 'if .rss then "rss2"'
        .. ' elif .feed then "atom"'
        .. ' else "unknown"'
        .. " end'"):gsub("%s+$", "")
    assert(t == "rss2",
        "FAIL: " .. xml .. ".xml type="
        .. t .. ", expected rss2")
end

-- 2.2: detect Atom feed type
for _, xml in ipairs(ATOM) do
    local t = run(
        "cat '" .. FIX .. "/" .. xml .. ".xml'"
        .. " | yq -p xml -o json"
        .. " | jq -r '"
        .. 'if .rss then "rss2"'
        .. ' elif .feed then "atom"'
        .. ' else "unknown"'
        .. " end'"):gsub("%s+$", "")
    assert(t == "atom",
        "FAIL: " .. xml .. ".xml type="
        .. t .. ", expected atom")
end

print("PASS: detect")
