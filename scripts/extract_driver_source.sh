#!/usr/bin/env bash

set -euo pipefail

ROOT_DIR=$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)
MODULE_SRC_DIR="${MODULE_SRC_DIR:-$ROOT_DIR/build/module-src}"
SOURCE_TARBALL="${SOURCE_TARBALL:-$ROOT_DIR/hybrid-v35_64-nodebug-pcoem-6_30_223_271.tar.gz}"

if [[ ! -f "$SOURCE_TARBALL" ]]; then
    echo "[!] missing Broadcom source tarball: $SOURCE_TARBALL"
    exit 1
fi

rm -rf "$MODULE_SRC_DIR"
mkdir -p "$MODULE_SRC_DIR"

echo "[*] extracting Broadcom wl source"
tar -xf "$SOURCE_TARBALL" -C "$MODULE_SRC_DIR"

if [[ ! -f "$MODULE_SRC_DIR/Makefile" ]] || [[ ! -f "$MODULE_SRC_DIR/src/wl/sys/wl_linux.c" ]]; then
    echo "[!] extracted source tree does not look valid: $MODULE_SRC_DIR"
    exit 1
fi

echo "[*] module source ready at $MODULE_SRC_DIR"
