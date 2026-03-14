#!/usr/bin/env bash

set -euo pipefail

ROOT_DIR=$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)
KERNEL_DIR="${KERNEL_DIR:-$ROOT_DIR/kernel-src}"
KERNEL_URL_BASE="${KERNEL_URL_BASE:-https://chromium.googlesource.com/chromiumos/third_party/kernel}"
KERNEL_COMMIT="${KERNEL_COMMIT:-ca5ac6161115cf185683715bc945e8c55bc6a402}"
LOCALVERSION="${LOCALVERSION:--22664-gca5ac6161115}"
CONFIG_FILE="${CONFIG_FILE:-$ROOT_DIR/kernel.config}"
JOBS="${JOBS:-$(nproc)}"

install_kernel_config() {
    echo "[*] installing kernel config from $CONFIG_FILE"

    if gzip -t "$CONFIG_FILE" >/dev/null 2>&1; then
        gzip -cd "$CONFIG_FILE" > "$KERNEL_DIR/.config"
    else
        cp "$CONFIG_FILE" "$KERNEL_DIR/.config"
    fi
}

fetch_kernel_tree() {
    local archive_url

    archive_url="${KERNEL_URL_BASE}/+archive/${KERNEL_COMMIT}.tar.gz"

    rm -rf "$KERNEL_DIR"
    mkdir -p "$KERNEL_DIR"

    echo "[*] downloading kernel tree ${KERNEL_COMMIT}"
    curl -fL "$archive_url" | tar -xz -C "$KERNEL_DIR"
}

if [[ ! -d "$KERNEL_DIR" ]] || [[ ! -f "$KERNEL_DIR/Makefile" ]]; then
    fetch_kernel_tree
else
    echo "[*] using existing kernel tree: $KERNEL_DIR"
fi

if [[ ! -f "$CONFIG_FILE" ]]; then
    cat <<EOF
[!] missing kernel config: $CONFIG_FILE

Export it from the openFyde machine first:
  zcat /proc/config.gz > kernel.config
EOF
    exit 1
fi

install_kernel_config

echo "[*] normalizing config"
make -C "$KERNEL_DIR" ARCH="${ARCH:-x86_64}" LOCALVERSION="$LOCALVERSION" olddefconfig

echo "[*] preparing kernel tree"
make -C "$KERNEL_DIR" ARCH="${ARCH:-x86_64}" LOCALVERSION="$LOCALVERSION" prepare modules_prepare -j"$JOBS"

if grep -q '^CONFIG_MODVERSIONS=y$' "$KERNEL_DIR/.config" && [[ ! -f "$KERNEL_DIR/Module.symvers" ]]; then
    cat <<EOF
[!] CONFIG_MODVERSIONS=y but Module.symvers is not present.
    In-tree module rebuilds may still work for experiments.
    For out-of-tree modules, you should ideally provide the exact Module.symvers
    from a full build of the same kernel tree and config.
EOF
fi

echo "[*] kernel tree ready at $KERNEL_DIR"
