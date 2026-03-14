#!/usr/bin/env bash

set -euo pipefail

ROOT_DIR=$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)
PARENT_DIR=$(dirname "$ROOT_DIR")
ROOT_BASENAME=$(basename "$ROOT_DIR")
IMAGE_TAG="${IMAGE_TAG:-openfyde-broadcom-wl-builder}"
BUILD_MODE="${BUILD_MODE:-release}"

docker build --pull=false --platform linux/amd64 -t "$IMAGE_TAG" -f "$ROOT_DIR/Dockerfile" "$ROOT_DIR"

docker run --rm --platform linux/amd64 \
    -e BUILD_MODE="$BUILD_MODE" \
    -e LOCALVERSION \
    -e TARGET_KERNEL_RELEASE \
    -e KERNEL_VERSION_BASE \
    -e KERNEL_BRANCH \
    -e KERNEL_COMMIT \
    -e KERNEL_URL_BASE \
    -e CONFIG_FILE \
    -e ROOT_DIR_IN_CONTAINER="/src/$ROOT_BASENAME" \
    -v "$PARENT_DIR:/src" \
    "$IMAGE_TAG" \
    bash -lc 'cd "$ROOT_DIR_IN_CONTAINER" && ./scripts/build_release.sh'
