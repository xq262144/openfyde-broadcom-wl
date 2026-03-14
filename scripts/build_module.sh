#!/usr/bin/env bash

set -euo pipefail

ROOT_DIR=$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)
KERNEL_DIR="${KERNEL_DIR:-$ROOT_DIR/build/kernel-src}"
LOCALVERSION="${LOCALVERSION:--22664-gca5ac6161115}"
MODULE_SRC_DIR="${MODULE_SRC_DIR:-$ROOT_DIR/build/module-src}"
OUT_DIR="${OUT_DIR:-$ROOT_DIR/out/module}"
JOBS="${JOBS:-$(nproc)}"

if [[ ! -f "$KERNEL_DIR/Makefile" ]]; then
    echo "[!] missing kernel tree at $KERNEL_DIR"
    echo "    run ./scripts/prepare_kernel_tree.sh first"
    exit 1
fi

if [[ ! -f "$MODULE_SRC_DIR/Makefile" ]] && [[ ! -f "$MODULE_SRC_DIR/Kbuild" ]]; then
    echo "[!] module source does not look buildable: $MODULE_SRC_DIR"
    echo "    expected Makefile or Kbuild in the module directory"
    exit 1
fi

rm -rf "$OUT_DIR"
mkdir -p "$OUT_DIR"

echo "[*] building wl module from: $MODULE_SRC_DIR"
make -C "$KERNEL_DIR" \
    ARCH="${ARCH:-x86_64}" \
    LOCALVERSION="$LOCALVERSION" \
    M="$MODULE_SRC_DIR" \
    modules -j"$JOBS"

if ! find "$MODULE_SRC_DIR" -maxdepth 3 -name 'wl.ko' -print -quit | grep -q .; then
    echo "[!] build finished but wl.ko was not generated"
    exit 1
fi

echo "[*] collecting .ko files"
find "$MODULE_SRC_DIR" -maxdepth 3 -name '*.ko' -exec cp -f {} "$OUT_DIR/" \;

echo "[*] artifacts:"
find "$OUT_DIR" -maxdepth 1 -name '*.ko' -print | sort
