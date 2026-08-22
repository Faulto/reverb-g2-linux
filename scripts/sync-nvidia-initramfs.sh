#!/bin/bash
# Compare the nvidia-modeset module embedded in the current systemd-boot
# initramfs with the DKMS module on disk.  With dracut force_drivers, rebooting
# after a manual `dkms install` is not enough: the early boot image must also be
# rebuilt or the kernel loads the old embedded module.

set -euo pipefail

usage() {
    cat <<'EOF'
Usage:
  sudo ./scripts/sync-nvidia-initramfs.sh
  sudo ./scripts/sync-nvidia-initramfs.sh --rebuild

The default is read-only.  --rebuild replaces only the normal initramfs for
the running kernel, verifies its embedded nvidia-modeset module, and asks for
a reboot.  It does not reload the live graphics driver.
EOF
}

ACTION=check
case "${1:-}" in
    "") ;;
    --check) ;;
    --rebuild) ACTION=rebuild ;;
    -h|--help) usage; exit 0 ;;
    *) usage >&2; exit 2 ;;
esac

if [ "${EUID}" -ne 0 ]; then
    echo "This needs root to read and rebuild the boot image." >&2
    echo "Run: sudo $0${1:+ $1}" >&2
    exit 1
fi

for command in bootctl lsinitrd modinfo sha256sum; do
    if ! command -v "$command" >/dev/null 2>&1; then
        echo "Missing required command: $command" >&2
        exit 1
    fi
done

KERNEL_VERSION="$(uname -r)"
BOOT_ROOT="$(bootctl --print-boot-path)"
CMDLINE_INITRD="$(tr ' ' '\n' < /proc/cmdline | sed -n 's/^initrd=//p' | tail -n 1)"
if [ -n "$CMDLINE_INITRD" ]; then
    # shellcheck disable=SC1003 # tr receives one literal backslash character
    INITRD_RELATIVE="$(printf '%s' "$CMDLINE_INITRD" | tr '\\' '/')"
    INITRD="$BOOT_ROOT/${INITRD_RELATIVE#/}"
else
    if [ -s /etc/kernel/entry-token ]; then
        ENTRY_TOKEN="$(cat /etc/kernel/entry-token)"
    else
        ENTRY_TOKEN="$(cat /etc/machine-id)"
    fi
    INITRD="$BOOT_ROOT/$ENTRY_TOKEN/$KERNEL_VERSION/initrd"
fi
DISK_MODULE="$(modinfo -k "$KERNEL_VERSION" -n nvidia_modeset)"

if [ ! -f "$INITRD" ]; then
    echo "Could not find the active kernel's normal initramfs:" >&2
    echo "  $INITRD" >&2
    exit 1
fi
if [ ! -f "$DISK_MODULE" ]; then
    echo "Could not find the on-disk nvidia-modeset module:" >&2
    echo "  $DISK_MODULE" >&2
    exit 1
fi

WORK="$(mktemp -d -t g2-initramfs-check.XXXXXX)"
cleanup() {
    rm -rf -- "$WORK"
}
trap cleanup EXIT INT TERM

decompress_module() {
    local source="$1"
    local destination="$2"
    local format_name="${3:-$source}"

    case "$format_name" in
        *.zst) zstd -q -d -c -- "$source" > "$destination" ;;
        *.xz)  xz -d -c -- "$source" > "$destination" ;;
        *.gz)  gzip -d -c -- "$source" > "$destination" ;;
        *)     cp -- "$source" "$destination" ;;
    esac
}

find_embedded_module() {
    lsinitrd "$INITRD" | awk '
        !found && $NF ~ /(^|\/)nvidia-modeset\.ko(\.(zst|xz|gz))?$/ {
            found = $NF
        }
        END { if (found) print found }
    '
}

compare_modules() {
    local embedded_path
    local disk_sha
    local initrd_sha

    embedded_path="$(find_embedded_module)"
    if [ -z "$embedded_path" ]; then
        echo "The initramfs does not contain nvidia-modeset." >&2
        return 1
    fi

    if ! lsinitrd --file "$embedded_path" "$INITRD" \
            > "$WORK/initrd-module.packed"; then
        echo "Could not extract $embedded_path from the initramfs." >&2
        return 1
    fi
    if ! decompress_module "$DISK_MODULE" "$WORK/disk-module.ko"; then
        echo "Could not decompress the on-disk module." >&2
        return 1
    fi
    # The extracted file has a neutral name, so use the internal path only as
    # the compression-format hint.
    if ! decompress_module "$WORK/initrd-module.packed" \
            "$WORK/initrd-module.ko" "$embedded_path"; then
        echo "Could not decompress the initramfs module." >&2
        return 1
    fi

    disk_sha="$(sha256sum "$WORK/disk-module.ko" | awk '{print $1}')"
    initrd_sha="$(sha256sum "$WORK/initrd-module.ko" | awk '{print $1}')"

    echo "  kernel:          $KERNEL_VERSION"
    echo "  initramfs:       $INITRD"
    echo "  embedded module: $embedded_path"
    echo "  disk module:     $DISK_MODULE"
    echo "  initramfs SHA:   $initrd_sha"
    echo "  disk SHA:        $disk_sha"

    if cmp -s "$WORK/initrd-module.ko" "$WORK/disk-module.ko"; then
        echo "  result:           MATCH"
        return 0
    fi

    echo "  result:           STALE -- boot image contains a different module"
    return 2
}

image_was_built_after_boot() {
    local boot_epoch
    local initrd_epoch

    boot_epoch="$(awk '$1 == "btime" { print $2 }' /proc/stat)"
    initrd_epoch="$(stat -c %Y "$INITRD")"
    [ -n "$boot_epoch" ] && [ "$initrd_epoch" -gt "$boot_epoch" ]
}

echo "=== nvidia-modeset in the boot image versus DKMS on disk ==="
set +e
compare_modules
COMPARE_STATUS=$?
set -e

if [ "$ACTION" = check ]; then
    if [ "$COMPARE_STATUS" -eq 2 ]; then
        echo
        echo "Rebuild it with:"
        echo "  sudo $0 --rebuild"
        exit 2
    fi
    if [ "$COMPARE_STATUS" -eq 0 ]; then
        if image_was_built_after_boot; then
            echo
            echo "The boot image is current, but it was rebuilt after this boot."
            echo "The live NVIDIA module is still from the previous image; reboot first."
            exit 3
        fi
    fi
    exit "$COMPARE_STATUS"
fi

if [ "$COMPARE_STATUS" -eq 0 ]; then
    echo
    echo "The boot image already contains the current DKMS module; no rebuild needed."
    if image_was_built_after_boot; then
        echo "It was built after this boot, so reboot before another G2 test."
    fi
    exit 0
fi
if [ "$COMPARE_STATUS" -ne 2 ]; then
    exit "$COMPARE_STATUS"
fi

if ! command -v dracut >/dev/null 2>&1; then
    echo "Missing required command for --rebuild: dracut" >&2
    exit 1
fi

echo
echo "=== rebuilding the normal initramfs for $KERNEL_VERSION ==="
# These are the same options used by kernel-install-for-dracut's normal-image
# hook on this system.  The fallback image is intentionally left untouched.
dracut --force --hostonly --no-hostonly-cmdline "$INITRD" "$KERNEL_VERSION"

rm -f -- "$WORK/initrd-module.packed" "$WORK/initrd-module.ko"
echo
echo "=== verifying the rebuilt boot image ==="
compare_modules

echo
echo "The next boot will load the patched module. Reboot before another G2 test:"
echo "  sudo reboot"
