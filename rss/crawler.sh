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
