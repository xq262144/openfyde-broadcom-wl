#!/usr/bin/env bash

set -euo pipefail

ROOT_DIR=$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)
MODULE_SRC_DIR="${MODULE_SRC_DIR:-$ROOT_DIR/build/module-src}"
PATCH_DIR="${PATCH_DIR:-$ROOT_DIR/patches}"
SERIES_FILE="${SERIES_FILE:-$PATCH_DIR/series}"

if [[ ! -f "$MODULE_SRC_DIR/Makefile" ]]; then
    echo "[!] missing module source tree at $MODULE_SRC_DIR"
    exit 1
fi

if [[ ! -f "$SERIES_FILE" ]]; then
    echo "[!] missing patch series file: $SERIES_FILE"
    exit 1
fi

while IFS= read -r patch_name; do
    [[ -z "$patch_name" ]] && continue
    [[ "$patch_name" =~ ^# ]] && continue

    patch_path="$PATCH_DIR/$patch_name"
    if [[ ! -f "$patch_path" ]]; then
        echo "[!] missing patch file: $patch_path"
        exit 1
    fi

    echo "[*] applying $patch_name"
    patch -d "$MODULE_SRC_DIR" -p1 < "$patch_path"
done < "$SERIES_FILE"
