# extract.sh — test jq item extraction
# 3.1: akita items (all fields, guid as object)
# 3.2: HN items (no guid, fallback to link)
# 3.3: lobster items (guid + author)
# 3.4: GitHub Atom entries (id, link as object)
# 3.5: single item wrapped as array

#!/usr/bin/env bash
set -euo pipefail
DIR="${1:-.}"
FIX="$DIR/fixtures"

ALL="akita hn lobster github"
RSS2="akita hn lobster"
ATOM="github"

JQ_RSS2='
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
        body: (."content:encoded" // .description // ""),
        author: (.author // "")
    }
'

JQ_ATOM='
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
'

# 3.1: akita — 20 items, all have guid and title
json=$(cat "$FIX/akita.xml" | yq -p xml -o json)
n=$(echo "$json" | jq -c "$JQ_RSS2" | wc -l)
[ "$n" -eq 20 ] || {
    echo "FAIL: akita count=$n, expected 20"; exit 1
}
echo "$json" | jq -e "$JQ_RSS2" \
    | jq -e 'select(.guid != null and .title != null)' \
    > /dev/null || {
    echo "FAIL: akita missing guid or title"; exit 1
}

# 3.2: HN — 30 items, guid is null, link is set
json=$(cat "$FIX/hn.xml" | yq -p xml -o json)
n=$(echo "$json" | jq -c "$JQ_RSS2" | wc -l)
[ "$n" -eq 30 ] || {
    echo "FAIL: hn count=$n, expected 30"; exit 1
}
nulls=$(echo "$json" | jq -c "$JQ_RSS2" \
    | jq -r 'select(.guid == null) | .link' | wc -l)
[ "$nulls" -eq 30 ] || {
    echo "FAIL: hn expected all guids null"; exit 1
}

# 3.3: lobster — 25 items, all have guid and author
json=$(cat "$FIX/lobster.xml" | yq -p xml -o json)
n=$(echo "$json" | jq -c "$JQ_RSS2" | wc -l)
[ "$n" -eq 25 ] || {
    echo "FAIL: lobster count=$n, expected 25"; exit 1
}
echo "$json" | jq -e "$JQ_RSS2" \
    | jq -e 'select(.guid != null and .author != "")' \
    > /dev/null || {
    echo "FAIL: lobster missing guid or author"; exit 1
}

# 3.4: github — 10 entries, all have guid and link
json=$(cat "$FIX/github.xml" | yq -p xml -o json)
n=$(echo "$json" | jq -c "$JQ_ATOM" | wc -l)
[ "$n" -eq 10 ] || {
    echo "FAIL: github count=$n, expected 10"; exit 1
}
echo "$json" | jq -e "$JQ_ATOM" \
    | jq -e 'select(.guid != null and .link != null)' \
    > /dev/null || {
    echo "FAIL: github missing guid or link"; exit 1
}

# 3.5: single item wrapped as array
single=$(cat "$FIX/akita.xml" | yq -p xml -o json \
    | jq '.rss.channel.item = .rss.channel.item[0]')
n=$(echo "$single" | jq -c "$JQ_RSS2" | wc -l)
[ "$n" -eq 1 ] || {
    echo "FAIL: single item count=$n, expected 1"; exit 1
}

echo "PASS: extract"
