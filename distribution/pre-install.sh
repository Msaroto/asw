#!/usr/bin/env bash

# unofficial strict mode
set -euo pipefail
IFS=$'\n\t'

if [ -n "${DEBUG:-}" ]; then
    set -x
fi

function main() {
    mkdir -p /tmp/build/usr/local/lib/luarocks/rocks-5.1/
}

main
