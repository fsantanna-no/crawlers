#!/usr/bin/env lua5.4
-- crawler.lua — fetch RSS/Atom feed, extract items as JSON lines
-- usage: lua5.4 crawler.lua <output-dir> <url>

local function run(cmd)
    local h = io.popen(cmd)
    local out = h:read("*a")
    h:close()
    return out
end

local function check_deps(cmds)
    for _, cmd in ipairs(cmds) do
        if os.execute("command -v " .. cmd
            .. " >/dev/null 2>&1") ~= true then
            io.stderr:write(
                "error: " .. cmd .. " not found\n")
            os.exit(1)
        end
    end
end

if #arg ~= 2 then
    io.stderr:write(
        "usage: crawler.lua <output-dir> <url>\n")
    os.exit(1)
end

local output_dir = arg[1]
local url = arg[2]

check_deps({"curl", "yq", "jq", "sha256sum"})

os.execute("mkdir -p " .. output_dir)

local tmp = os.tmpname()

local ok = os.execute(
    "curl -sL '" .. url .. "'"
    .. " | yq -p xml -o json > " .. tmp)
if not ok then
    io.stderr:write(
        "error: failed to fetch/parse "
        .. url .. "\n")
    os.execute("rm -f " .. tmp)
    os.exit(1)
end

local feed_type = run(
    "jq -r '"
    .. 'if .rss then "rss2"'
    .. ' elif .feed then "atom"'
    .. ' else "unknown"'
    .. " end' " .. tmp):gsub("%s+$", "")

if feed_type == "unknown" then
    io.stderr:write("error: unknown feed type\n")
    os.execute("rm -f " .. tmp)
    os.exit(1)
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

local jq_filter
if feed_type == "rss2" then
    jq_filter = JQ_RSS2
else
    jq_filter = JQ_ATOM
end

local items = run(
    "jq -c '" .. jq_filter .. "' " .. tmp)

os.execute("rm -f " .. tmp)

io.write(items)
