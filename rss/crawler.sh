#!/usr/bin/env bash
set -euo pipefail

usage() {
    echo "usage: crawler.sh <root-dir> <url>" >&2
    exit 1
}

if [ $# -ne 2 ]; then
    usage
fi

root_dir="$1"
url="$2"
