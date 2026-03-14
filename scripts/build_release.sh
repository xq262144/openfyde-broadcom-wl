#!/usr/bin/env bash

set -euo pipefail

ROOT_DIR=$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)
KERNEL_DIR="${KERNEL_DIR:-$ROOT_DIR/build/kernel-src}"
MODULE_SRC_DIR="${MODULE_SRC_DIR:-$ROOT_DIR/build/module-src}"
BUILD_MODE="${BUILD_MODE:-release}"

resolve_config_file() {
    local candidate

    for candidate in \
        "$ROOT_DIR/config.gz" \
        "$ROOT_DIR/kernel.config" \
        "$ROOT_DIR/kernel.config.gz" \
        "$ROOT_DIR/../kernel.config" \
        "$ROOT_DIR/../config.gz"
    do
        if [[ -f "$candidate" ]]; then
            printf '%s\n' "$candidate"
            return 0
        fi
    done

    return 1
}

if [[ "$BUILD_MODE" == "smoke" ]]; then
    export CONFIG_FILE="${CONFIG_FILE:-$ROOT_DIR/smoke.config}"
else
    if [[ -z "${CONFIG_FILE:-}" ]]; then
        CONFIG_FILE=$(resolve_config_file || true)
    fi
    : "${CONFIG_FILE:=$ROOT_DIR/kernel.config}"
fi

KERNEL_DIR="$KERNEL_DIR" CONFIG_FILE="$CONFIG_FILE" \
    "$ROOT_DIR/scripts/prepare_kernel_tree.sh"

MODULE_SRC_DIR="$MODULE_SRC_DIR" "$ROOT_DIR/scripts/extract_driver_source.sh"
MODULE_SRC_DIR="$MODULE_SRC_DIR" "$ROOT_DIR/scripts/apply_patchset.sh"

MODULE_OUT_DIR="$ROOT_DIR/out/module"

KERNEL_DIR="$KERNEL_DIR" MODULE_SRC_DIR="$MODULE_SRC_DIR" OUT_DIR="$MODULE_OUT_DIR" \
    "$ROOT_DIR/scripts/build_module.sh"

BUILD_MODE="$BUILD_MODE" MODULE_OUT_DIR="$MODULE_OUT_DIR" CONFIG_FILE="$CONFIG_FILE" \
    "$ROOT_DIR/scripts/package_release.sh"
