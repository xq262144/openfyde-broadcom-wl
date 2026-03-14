#!/usr/bin/env bash

set -euo pipefail

ROOT_DIR=$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)
PATCH_DIR="${PATCH_DIR:-$ROOT_DIR/patches}"
MODULE_OUT_DIR="${MODULE_OUT_DIR:-$ROOT_DIR/out/module}"
DIST_DIR="${DIST_DIR:-$ROOT_DIR/dist}"
HELPER_SRC_DIR="${HELPER_SRC_DIR:-$ROOT_DIR/helpers}"
KERNEL_VERSION_BASE="${KERNEL_VERSION_BASE:-5.4.275}"
LOCALVERSION="${LOCALVERSION:--22664-gca5ac6161115}"
KERNEL_BRANCH="${KERNEL_BRANCH:-release-R126-15886.B-chromeos-5.4}"
KERNEL_COMMIT="${KERNEL_COMMIT:-ca5ac6161115cf185683715bc945e8c55bc6a402}"
BUILD_MODE="${BUILD_MODE:-release}"
TARGET_KERNEL_RELEASE="${TARGET_KERNEL_RELEASE:-${KERNEL_VERSION_BASE}${LOCALVERSION}}"
SOURCE_TARBALL="${SOURCE_TARBALL:-$ROOT_DIR/hybrid-v35_64-nodebug-pcoem-6_30_223_271.tar.gz}"
CONFIG_FILE="${CONFIG_FILE:-}"

timestamp=$(date -u +%Y%m%dT%H%M%SZ)
release_name="broadcom-wl-${TARGET_KERNEL_RELEASE}-${BUILD_MODE}-${timestamp}"
stage_dir="$DIST_DIR/$release_name"

if [[ ! -f "$MODULE_OUT_DIR/wl.ko" ]]; then
    echo "[!] missing built module: $MODULE_OUT_DIR/wl.ko"
    exit 1
fi

rm -rf "$stage_dir"
mkdir -p "$stage_dir/modules" "$stage_dir/patches" "$stage_dir/configs" "$stage_dir/helpers"

find "$MODULE_OUT_DIR" -maxdepth 1 -name '*.ko' -exec cp -f {} "$stage_dir/modules/" \;
cp -f "$PATCH_DIR"/series "$stage_dir/patches/"
cp -f "$ROOT_DIR/broadcom-wl-dkms.conf" "$stage_dir/configs/"
for extra_config in broadcom-wl-openfyde-autoconnect.conf broadcom-wl-openfyde.conf.example; do
    if [[ -f "$ROOT_DIR/configs/$extra_config" ]]; then
        cp -f "$ROOT_DIR/configs/$extra_config" "$stage_dir/configs/"
    fi
done
if [[ -n "$CONFIG_FILE" ]] && [[ -f "$CONFIG_FILE" ]]; then
    if gzip -t "$CONFIG_FILE" >/dev/null 2>&1; then
        gzip -cd "$CONFIG_FILE" > "$stage_dir/configs/kernel.config"
    else
        cp -f "$CONFIG_FILE" "$stage_dir/configs/kernel.config"
    fi
fi
while IFS= read -r patch_name; do
    [[ -z "$patch_name" ]] && continue
    [[ "$patch_name" =~ ^# ]] && continue
    cp -f "$PATCH_DIR/$patch_name" "$stage_dir/patches/"
done < "$PATCH_DIR/series"

cat > "$stage_dir/helpers/broadcom-wl-openfyde-post-up" <<'EOF'
#!/usr/bin/env bash
set -euo pipefail

PATH=/usr/local/sbin:/usr/local/bin:/usr/sbin:/usr/bin:/sbin:/bin

collect_ifaces() {
    if [[ "$#" -gt 0 ]]; then
        printf '%s\n' "$@"
        return 0
    fi

    if command -v iw >/dev/null 2>&1; then
        iw dev | awk '$1 == "Interface" { print $2 }'
        return 0
    fi

    local dev
    for dev in /sys/class/net/wlan*; do
        [[ -e "$dev" ]] || continue
        basename "$dev"
    done
}

iwconfig_bin=$(command -v iwconfig || true)
[[ -n "$iwconfig_bin" ]] || exit 0

status=0
while IFS= read -r iface; do
    [[ -n "$iface" ]] || continue
    "$iwconfig_bin" "$iface" power off >/dev/null 2>&1 || status=1
done < <(collect_ifaces "$@")

exit "$status"
EOF
chmod +x "$stage_dir/helpers/broadcom-wl-openfyde-post-up"

if [[ -d "$HELPER_SRC_DIR" ]]; then
    find "$HELPER_SRC_DIR" -maxdepth 1 -type f -exec cp -f {} "$stage_dir/helpers/" \;
    find "$stage_dir/helpers" -maxdepth 1 -type f -exec chmod +x {} \;
fi

cat > "$stage_dir/configs/99-broadcom-wl-openfyde.rules" <<'EOF'
ACTION=="add|change", SUBSYSTEM=="net", KERNEL=="wlan*", RUN+="/usr/local/sbin/broadcom-wl-openfyde-post-up %k"
EOF

cat > "$stage_dir/install-module.sh" <<EOF
#!/usr/bin/env bash
set -euo pipefail

KERNEL_RELEASE="\${KERNEL_RELEASE:-$TARGET_KERNEL_RELEASE}"
SKIP_LIVE_RELOAD="\${SKIP_LIVE_RELOAD:-0}"
PACKAGE_ROOT=\$(cd "\$(dirname "\${BASH_SOURCE[0]}")" && pwd)
MODULE_DIR="/lib/modules/\${KERNEL_RELEASE}/extra/broadcom-wl"
MODPROBE_CONF="/etc/modprobe.d/broadcom-wl-openfyde.conf"
MODULES_LOAD_CONF="/etc/modules-load.d/wl.conf"
POST_UP_HELPER="/usr/local/sbin/broadcom-wl-openfyde-post-up"
WEXT_CONNECT_HELPER="/usr/local/sbin/broadcom-wl-openfyde-wext-connect"
WEXT_DISCONNECT_HELPER="/usr/local/sbin/broadcom-wl-openfyde-wext-disconnect"
AUTOCONNECT_HELPER="/usr/local/sbin/broadcom-wl-openfyde-autoconnect"
DHCLIENT_HOOK="/usr/local/sbin/broadcom-wl-openfyde-dhclient-script"
AUTOCONNECT_CONF="/usr/local/etc/broadcom-wl-openfyde.conf"
AUTOCONNECT_CONF_EXAMPLE="/usr/local/etc/broadcom-wl-openfyde.conf.example"
AUTOCONNECT_JOB="/etc/init/broadcom-wl-openfyde-autoconnect.conf"
UDEV_RULE="/etc/udev/rules.d/99-broadcom-wl-openfyde.rules"
DRIVER_NAME="wl"
PCI_SYSFS_ROOT="/sys/bus/pci/devices"
root_was_ro=0

run_root() {
    if [[ "\${EUID:-\$(id -u)}" -eq 0 ]]; then
        "\$@"
    elif command -v sudo >/dev/null 2>&1; then
        sudo "\$@"
    else
        echo "[!] need root privileges to install the module" >&2
        exit 1
    fi
}

run_root_bash() {
    if [[ "\${EUID:-\$(id -u)}" -eq 0 ]]; then
        bash -lc "\$1"
    elif command -v sudo >/dev/null 2>&1; then
        sudo bash -lc "\$1"
    else
        echo "[!] need root privileges to install the module" >&2
        exit 1
    fi
}

ensure_root_rw() {
    if mount | awk '\$3 == "/" { print \$0 }' | grep -q ' on / .* (ro,'; then
        run_root mount -o remount,rw /
        root_was_ro=1
    fi
}

restore_root_ro() {
    if [[ "\$root_was_ro" -eq 1 ]]; then
        run_root sync
        run_root mount -o remount,ro /
    fi
}

find_broadcom_wifi_bdfs() {
    local dev vendor class
    for dev in "\$PCI_SYSFS_ROOT"/*; do
        [[ -r "\$dev/vendor" ]] || continue
        [[ -r "\$dev/class" ]] || continue
        vendor=\$(<"\$dev/vendor")
        class=\$(<"\$dev/class")
        if [[ "\$vendor" == "0x14e4" && "\$class" == 0x0280* ]]; then
            basename "\$dev"
        fi
    done
}

current_driver_for_bdf() {
    local bdf=\$1
    local link="\$PCI_SYSFS_ROOT/\$bdf/driver"

    if [[ -L "\$link" ]]; then
        basename "\$(readlink -f "\$link")"
    fi
}

rebind_broadcom_wifi() {
    local bdf current_driver devdir

    while IFS= read -r bdf; do
        [[ -n "\$bdf" ]] || continue
        devdir="\$PCI_SYSFS_ROOT/\$bdf"
        current_driver=\$(current_driver_for_bdf "\$bdf" || true)

        if [[ -n "\$current_driver" && "\$current_driver" != "\$DRIVER_NAME" ]]; then
            run_root_bash "echo '\$bdf' > '\$devdir/driver/unbind'"
        fi

        run_root_bash "printf '%s\n' '\$DRIVER_NAME' > '\$devdir/driver_override'"

        if command -v timeout >/dev/null 2>&1; then
            run_root_bash "timeout 20 sh -c \"echo '\$bdf' > /sys/bus/pci/drivers_probe\""
        else
            run_root_bash "echo '\$bdf' > /sys/bus/pci/drivers_probe"
        fi

        if [[ "\$(current_driver_for_bdf "\$bdf" || true)" == "\$DRIVER_NAME" ]]; then
            run_root_bash ": > '\$devdir/driver_override'"
            echo "[*] bound \$bdf to \$DRIVER_NAME"
        else
            echo "[!] \$bdf did not bind to \$DRIVER_NAME immediately" >&2
        fi
    done < <(find_broadcom_wifi_bdfs)
}

if [[ "\$(uname -r)" != "\$KERNEL_RELEASE" ]]; then
    cat <<MSG
[!] running kernel is \$(uname -r), but this package targets \${KERNEL_RELEASE}
    installation will continue, but module loading may fail if the releases differ
MSG
fi

ensure_root_rw
trap restore_root_ro EXIT

run_root mkdir -p "\$MODULE_DIR"
run_root install -m 0644 "\$PACKAGE_ROOT/modules/wl.ko" "\$MODULE_DIR/wl.ko"
run_root install -D -m 0644 "\$PACKAGE_ROOT/configs/broadcom-wl-dkms.conf" "\$MODPROBE_CONF"
run_root install -D -m 0755 "\$PACKAGE_ROOT/helpers/broadcom-wl-openfyde-post-up" "\$POST_UP_HELPER"
run_root install -D -m 0755 "\$PACKAGE_ROOT/helpers/broadcom-wl-openfyde-wext-connect" "\$WEXT_CONNECT_HELPER"
run_root install -D -m 0755 "\$PACKAGE_ROOT/helpers/broadcom-wl-openfyde-wext-disconnect" "\$WEXT_DISCONNECT_HELPER"
run_root install -D -m 0755 "\$PACKAGE_ROOT/helpers/broadcom-wl-openfyde-autoconnect" "\$AUTOCONNECT_HELPER"
run_root install -D -m 0755 "\$PACKAGE_ROOT/helpers/broadcom-wl-openfyde-dhclient-script" "\$DHCLIENT_HOOK"
run_root install -D -m 0644 "\$PACKAGE_ROOT/configs/99-broadcom-wl-openfyde.rules" "\$UDEV_RULE"
run_root install -D -m 0644 "\$PACKAGE_ROOT/configs/broadcom-wl-openfyde-autoconnect.conf" "\$AUTOCONNECT_JOB"
run_root install -D -m 0644 "\$PACKAGE_ROOT/configs/broadcom-wl-openfyde.conf.example" "\$AUTOCONNECT_CONF_EXAMPLE"
if [[ ! -f "\$AUTOCONNECT_CONF" ]]; then
    run_root install -D -m 0644 "\$PACKAGE_ROOT/configs/broadcom-wl-openfyde.conf.example" "\$AUTOCONNECT_CONF"
fi

modules_load_tmp=\$(mktemp)
printf 'wl\n' > "\$modules_load_tmp"
run_root install -D -m 0644 "\$modules_load_tmp" "\$MODULES_LOAD_CONF"
rm -f "\$modules_load_tmp"

run_root udevadm control --reload >/dev/null 2>&1 || true
run_root initctl reload-configuration >/dev/null 2>&1 || true
run_root depmod -a "\$KERNEL_RELEASE"
if [[ "\$SKIP_LIVE_RELOAD" != "1" ]]; then
    run_root modprobe -r brcmfmac brcmutil bcma ssb b43 b43legacy bcm43xx brcmsmac 2>/dev/null || true
    run_root modprobe -r wl 2>/dev/null || true
    run_root modprobe wl nompc=1 2>/dev/null || true
    rebind_broadcom_wifi
    run_root "\$POST_UP_HELPER" || true
fi

cat <<'MSG'
Installed Broadcom wl module package.

Notes:
- The modprobe blacklist now disables bcma/brcmfmac/ssb and related drivers.
- The installer enables 'wl nompc=1' and installs a udev helper that forces 'iwconfig <iface> power off'.
- The installer also installs a one-shot Upstart job plus WEXT helpers for boot-time autoconnect.
- Unless SKIP_LIVE_RELOAD=1 is set, the installer also clears stale PCI driver overrides and tries to bind Broadcom Wi-Fi devices to wl immediately.
- If the module still did not bind, check 'lspci -nnk -d 14e4:43a0' and 'dmesg | grep -i wl'.
MSG
EOF
chmod +x "$stage_dir/install-module.sh"

cat > "$stage_dir/uninstall-module.sh" <<EOF
#!/usr/bin/env bash
set -euo pipefail

KERNEL_RELEASE="\${KERNEL_RELEASE:-$TARGET_KERNEL_RELEASE}"
MODULE_DIR="/lib/modules/\${KERNEL_RELEASE}/extra/broadcom-wl"
MODPROBE_CONF="/etc/modprobe.d/broadcom-wl-openfyde.conf"
MODULES_LOAD_CONF="/etc/modules-load.d/wl.conf"
POST_UP_HELPER="/usr/local/sbin/broadcom-wl-openfyde-post-up"
WEXT_CONNECT_HELPER="/usr/local/sbin/broadcom-wl-openfyde-wext-connect"
WEXT_DISCONNECT_HELPER="/usr/local/sbin/broadcom-wl-openfyde-wext-disconnect"
AUTOCONNECT_HELPER="/usr/local/sbin/broadcom-wl-openfyde-autoconnect"
DHCLIENT_HOOK="/usr/local/sbin/broadcom-wl-openfyde-dhclient-script"
AUTOCONNECT_CONF_EXAMPLE="/usr/local/etc/broadcom-wl-openfyde.conf.example"
AUTOCONNECT_JOB="/etc/init/broadcom-wl-openfyde-autoconnect.conf"
UDEV_RULE="/etc/udev/rules.d/99-broadcom-wl-openfyde.rules"
PCI_SYSFS_ROOT="/sys/bus/pci/devices"
root_was_ro=0

run_root() {
    if [[ "\${EUID:-\$(id -u)}" -eq 0 ]]; then
        "\$@"
    elif command -v sudo >/dev/null 2>&1; then
        sudo "\$@"
    else
        echo "[!] need root privileges to uninstall the module" >&2
        exit 1
    fi
}

run_root_bash() {
    if [[ "\${EUID:-\$(id -u)}" -eq 0 ]]; then
        bash -lc "\$1"
    elif command -v sudo >/dev/null 2>&1; then
        sudo bash -lc "\$1"
    else
        echo "[!] need root privileges to uninstall the module" >&2
        exit 1
    fi
}

ensure_root_rw() {
    if mount | awk '\$3 == "/" { print \$0 }' | grep -q ' on / .* (ro,'; then
        run_root mount -o remount,rw /
        root_was_ro=1
    fi
}

restore_root_ro() {
    if [[ "\$root_was_ro" -eq 1 ]]; then
        run_root sync
        run_root mount -o remount,ro /
    fi
}

ensure_root_rw
trap restore_root_ro EXIT

for dev in "\$PCI_SYSFS_ROOT"/*; do
    [[ -r "\$dev/vendor" ]] || continue
    if [[ "\$(<"\$dev/vendor")" == "0x14e4" ]]; then
        run_root_bash ": > '\$dev/driver_override'" || true
    fi
done

run_root initctl stop broadcom-wl-openfyde-autoconnect 2>/dev/null || true
run_root modprobe -r wl 2>/dev/null || true
run_root rm -f "\$MODULE_DIR/wl.ko"
run_root rmdir "\$MODULE_DIR" 2>/dev/null || true
run_root rm -f "\$MODPROBE_CONF" "\$MODULES_LOAD_CONF" "\$POST_UP_HELPER" "\$WEXT_CONNECT_HELPER" \
    "\$WEXT_DISCONNECT_HELPER" "\$AUTOCONNECT_HELPER" "\$DHCLIENT_HOOK" "\$AUTOCONNECT_CONF_EXAMPLE" \
    "\$AUTOCONNECT_JOB" "\$UDEV_RULE"
run_root udevadm control --reload >/dev/null 2>&1 || true
run_root initctl reload-configuration >/dev/null 2>&1 || true
run_root depmod -a "\$KERNEL_RELEASE"

cat <<'MSG'
Removed Broadcom wl module package.

Notes:
- Any transient PCI driver_override state for Broadcom devices was cleared.
- After removal, the stock bcma/brcmfmac path may bind again on next boot.
MSG
EOF
chmod +x "$stage_dir/uninstall-module.sh"

{
    echo "release_name=${release_name}"
    echo "build_mode=${BUILD_MODE}"
    echo "target_kernel_release=${TARGET_KERNEL_RELEASE}"
    echo "kernel_branch=${KERNEL_BRANCH}"
    echo "kernel_commit=${KERNEL_COMMIT}"
    echo "localversion=${LOCALVERSION}"
    echo "source_tarball=$(basename "$SOURCE_TARBALL")"
    if [[ -n "$CONFIG_FILE" ]] && [[ -f "$CONFIG_FILE" ]]; then
        echo "config_file=$(basename "$CONFIG_FILE")"
    fi
    echo
    echo "[modules]"
    find "$stage_dir/modules" -maxdepth 1 -name '*.ko' -exec sha256sum {} \; | sort
    echo
    echo "[patches]"
    find "$stage_dir/patches" -maxdepth 1 -type f -exec sha256sum {} \; | sort
    echo
    echo "[configs]"
    find "$stage_dir/configs" -maxdepth 1 -type f -exec sha256sum {} \; | sort
} > "$stage_dir/manifest.txt"

(cd "$DIST_DIR" && tar -czf "${release_name}.tar.gz" "$release_name")

echo "[*] packaged release:"
echo "    $DIST_DIR/${release_name}.tar.gz"
