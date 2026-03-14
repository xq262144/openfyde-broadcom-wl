#!/usr/bin/env bash

set -euo pipefail

ROOT_DIR=$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)
KERNEL_DIR="${KERNEL_DIR:-$ROOT_DIR/kernel-src}"
KERNEL_URL_BASE="${KERNEL_URL_BASE:-https://chromium.googlesource.com/chromiumos/third_party/kernel}"
KERNEL_COMMIT="${KERNEL_COMMIT:-ca5ac6161115cf185683715bc945e8c55bc6a402}"

archive_url="${KERNEL_URL_BASE}/+archive/${KERNEL_COMMIT}.tar.gz"

rm -rf "$KERNEL_DIR"
mkdir -p "$KERNEL_DIR"

echo "[*] downloading kernel tree ${KERNEL_COMMIT}"
curl -fL "$archive_url" | tar -xz -C "$KERNEL_DIR"

if [[ ! -f "$KERNEL_DIR/Makefile" ]]; then
    echo "[!] kernel tree fetch failed: missing Makefile in $KERNEL_DIR"
    exit 1
fi

echo "[*] kernel tree fetched into $KERNEL_DIR"
