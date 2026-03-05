#!/usr/bin/env lua5.4
-- extract.lua — test jq item extraction
-- 3.1: akita items (all fields, guid as object)
-- 3.2: HN items (no guid, fallback to link)
-- 3.3: lobster items (guid + author)
-- 3.4: GitHub Atom entries (id, link as object)
-- 3.5: single item wrapped as array

local DIR = arg[1] or "."
local FIX = DIR .. "/fixtures"

local function run(cmd)
    local h = io.popen(cmd)
    local out = h:read("*a")
    h:close()
    return out
end

local function count_lines(s)
    local n = 0
    for _ in s:gmatch("[^\n]+") do
        n = n + 1
    end
    return n
end

local function write_tmp(content)
    local path = os.tmpname()
    local f = io.open(path, "w")
    f:write(content)
    f:close()
    return path
end

local JQ_RSS2 = [=[
    .rss.channel.item
    | if type == "array" then .[] else . end
    | {
        guid: (if .guid | type == "object"
               then .guid["+content"]
               elif .guid then .guid
               else null end),
        link: .link,
        title: (.title // "(untitled)"),
        date: .pubDate,
        body: (."content:encoded"
               // .description // ""),
        author: (.author // "")
    }
]=]

local JQ_ATOM = [=[
    .feed.entry
    | if type == "array" then .[] else . end
    | {
        guid: .id,
        link: (if .link | type == "object"
               then .link["+@href"]
               else .link end),
        title: (if .title | type == "object"
                then .title["+content"]
                else .title // "(untitled)" end),
        date: (.published // .updated),
        body: (if .content | type == "object"
               then .content["+content"]
               elif .content then .content
               elif .summary | type == "object"
               then .summary["+content"]
               else .summary // "" end),
        author: (if .author | type == "object"
                 then .author.name
                 elif .author then .author
                 else "" end)
    }
]=]

-- 3.1: akita — 20 items, all have guid and title
local json = run(
    "cat '" .. FIX .. "/akita.xml'"
    .. " | yq -p xml -o json")
local tmp = write_tmp(json)
local n = count_lines(run(
    "jq -c '" .. JQ_RSS2 .. "' " .. tmp))
assert(n == 20,
    "FAIL: akita count=" .. n .. ", expected 20")
local ok = os.execute(
    "jq -e '" .. JQ_RSS2 .. "' " .. tmp
    .. " | jq -e '"
    .. "select(.guid != null and .title != null)'"
    .. " > /dev/null")
assert(ok, "FAIL: akita missing guid or title")
os.execute("rm -f " .. tmp)

-- 3.2: HN — 30 items, guid is null, link is set
json = run(
    "cat '" .. FIX .. "/hn.xml'"
    .. " | yq -p xml -o json")
tmp = write_tmp(json)
n = count_lines(run(
    "jq -c '" .. JQ_RSS2 .. "' " .. tmp))
assert(n == 30,
    "FAIL: hn count=" .. n .. ", expected 30")
local nulls = count_lines(run(
    "jq -c '" .. JQ_RSS2 .. "' " .. tmp
    .. " | jq -r 'select(.guid == null) | .link'"))
assert(nulls == 30,
    "FAIL: hn expected all guids null")
os.execute("rm -f " .. tmp)

-- 3.3: lobster — 25 items, all have guid and author
json = run(
    "cat '" .. FIX .. "/lobster.xml'"
    .. " | yq -p xml -o json")
tmp = write_tmp(json)
n = count_lines(run(
    "jq -c '" .. JQ_RSS2 .. "' " .. tmp))
assert(n == 25,
    "FAIL: lobster count=" .. n .. ", expected 25")
ok = os.execute(
    "jq -e '" .. JQ_RSS2 .. "' " .. tmp
    .. " | jq -e '"
    .. "select(.guid != null and .author != \"\")'"
    .. " > /dev/null")
assert(ok, "FAIL: lobster missing guid or author")
os.execute("rm -f " .. tmp)

-- 3.4: github — 10 entries, all have guid and link
json = run(
    "cat '" .. FIX .. "/github.xml'"
    .. " | yq -p xml -o json")
tmp = write_tmp(json)
n = count_lines(run(
    "jq -c '" .. JQ_ATOM .. "' " .. tmp))
assert(n == 10,
    "FAIL: github count=" .. n .. ", expected 10")
ok = os.execute(
    "jq -e '" .. JQ_ATOM .. "' " .. tmp
    .. " | jq -e '"
    .. "select(.guid != null and .link != null)'"
    .. " > /dev/null")
assert(ok, "FAIL: github missing guid or link")
os.execute("rm -f " .. tmp)

-- 3.5: single item wrapped as array
local single = run(
    "cat '" .. FIX .. "/akita.xml'"
    .. " | yq -p xml -o json"
    .. " | jq '.rss.channel.item"
    .. " = .rss.channel.item[0]'")
tmp = write_tmp(single)
n = count_lines(run(
    "jq -c '" .. JQ_RSS2 .. "' " .. tmp))
assert(n == 1,
    "FAIL: single item count=" .. n
    .. ", expected 1")
os.execute("rm -f " .. tmp)

print("PASS: extract")
