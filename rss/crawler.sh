# crawler.sh — fetch RSS/Atom feed, save items as RFC 2822
# usage: crawler.sh <output-dir> <url>

#!/usr/bin/env bash
set -euo pipefail

usage() {
    echo "usage: crawler.sh <output-dir> <url>" >&2
    exit 1
}

if [ $# -ne 2 ]; then
    usage
fi

output_dir="$1"
url="$2"

for cmd in curl yq jq sha256sum; do
    command -v "$cmd" >/dev/null 2>&1 || {
        echo "error: $cmd not found" >&2; exit 1
    }
done

mkdir -p "$output_dir"

tmp=$(mktemp)
trap 'rm -f "$tmp"' EXIT

curl -sL "$url" | yq -p xml -o json > "$tmp" || {
    echo "error: failed to fetch/parse $url" >&2; exit 1
}

# detect feed type
feed_type=$(jq -r \
    'if .rss then "rss2"
     elif .feed then "atom"
     else "unknown"
     end' "$tmp")

if [ "$feed_type" = "unknown" ]; then
    echo "error: unknown feed type" >&2
    exit 1
fi

# extract feed title
feed_title=$(jq -r \
    'if .rss then .rss.channel.title
     else
         if .feed.title | type == "object"
         then .feed.title["+content"]
         else .feed.title
         end
     end // "Untitled"' "$tmp")

# jq filter: normalize items to JSON lines
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

if [ "$feed_type" = "rss2" ]; then
    jq_filter="$JQ_RSS2"
else
    jq_filter="$JQ_ATOM"
fi

# extract items as JSON lines
jq -c "$jq_filter" "$tmp"
