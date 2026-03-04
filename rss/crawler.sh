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
