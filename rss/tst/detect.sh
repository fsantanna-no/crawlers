# detect.sh — test feed type detection
# 1.1-1.4: yq XML→JSON produces valid JSON
# 2.1-2.2: detect RSS 2.0 vs Atom feed type

#!/usr/bin/env bash
set -euo pipefail
DIR="${1:-.}"
FIX="$DIR/fixtures"

ALL="akita hn lobster github"
RSS2="akita hn lobster"
ATOM="github"

# 1.1-1.4: yq XML to JSON produces valid JSON
for xml in $ALL; do
    cat "$FIX/$xml.xml" | yq -p xml -o json | jq empty || {
        echo "FAIL: $xml.xml not valid JSON"; exit 1
    }
done

# 2.1: detect RSS 2.0 feed type
for xml in $RSS2; do
    type=$(cat "$FIX/$xml.xml" | yq -p xml -o json \
        | jq -r 'if .rss then "rss2"
                  elif .feed then "atom"
                  else "unknown"
                  end')
    [ "$type" = "rss2" ] || {
        echo "FAIL: $xml.xml type=$type, expected rss2"
        exit 1
    }
done

# 2.2: detect Atom feed type
for xml in $ATOM; do
    type=$(cat "$FIX/$xml.xml" | yq -p xml -o json \
        | jq -r 'if .rss then "rss2"
                  elif .feed then "atom"
                  else "unknown"
                  end')
    [ "$type" = "atom" ] || {
        echo "FAIL: $xml.xml type=$type, expected atom"
        exit 1
    }
done

echo "PASS: detect"
