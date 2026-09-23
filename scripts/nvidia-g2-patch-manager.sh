#!/bin/bash
# Discover, audit, patch, rebuild, and deliver the NVIDIA open kernel module
# required by the Reverb G2.  No driver version or /dev/dri/card number is
# assumed.  All source changes are tested on a temporary mini-tree first.

set -euo pipefail

REPO="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
ACTION="${1:-status}"
REQUESTED_VERSION="${2:-}"
PATCH_DIR="$REPO/patches/nvidia"
KERNEL_VERSION="${KERNEL_VERSION:-$(uname -r)}"

usage() {
    printf 'usage: %s [status|validate|apply [NVIDIA-version]|initramfs-check]\n' "$0"
}

running_version() {
    local version
    version="$(grep -oE '[0-9]+([.][0-9]+){2,}' /proc/driver/nvidia/version 2>/dev/null | head -1)"
    [ -n "$version" ] && printf '%s\n' "$version"
}

installed_version() {
    modinfo -F version nvidia_modeset 2>/dev/null | head -1
}

resolve_source_tree() {
    local version="$1" candidate
    local -a candidates=()
    if [ -n "${NVIDIA_SOURCE_DIR:-}" ]; then
        [ -d "$NVIDIA_SOURCE_DIR/src/nvidia-modeset" ] || return 1
        printf '%s\n' "$NVIDIA_SOURCE_DIR"
        return 0
    fi
    for candidate in "/usr/src/nvidia-$version" "/usr/src/nvidia-open-$version" "/usr/src/nvidia/$version"; do
        [ -d "$candidate/src/nvidia-modeset" ] || continue
        printf '%s\n' "$candidate"
        return 0
    done
    while IFS= read -r candidate; do
        [ -d "$candidate/src/nvidia-modeset" ] || continue
        candidates+=("$candidate")
    done < <(find /usr/src -mindepth 1 -maxdepth 3 -type d -path '*/src/nvidia-modeset' \
        -printf '%h\n' 2>/dev/null | sed 's|/src$||' | LC_ALL=C sort -u)
    if [ "${#candidates[@]}" -eq 1 ]; then
        printf '%s\n' "${candidates[0]}"
        return 0
    fi
    return 1
}

patch_list_for_version() {
    local version="$1" major patch
    major="${version%%.*}"
    [[ "$major" =~ ^[0-9]+$ ]] || major=0
    case "$major" in
        595)
            for patch in "$PATCH_DIR"/000{1,2,3,4,5}-*.patch; do
                [ -f "$patch" ] && printf '%s\n' "$patch"
            done
            ;;
        610)
            # 610 already contains or supersedes the portions of 0001/0002.
            for patch in "$PATCH_DIR"/000{3,4,5}-*.patch; do
                [ -f "$patch" ] && printf '%s\n' "$patch"
            done
            ;;
        615)
            # 615 retains the max-link issue, but refactored the color-format
            # function. 0006 is the exact 615 port of the 0004/0005 behavior.
            for patch in "$PATCH_DIR"/000{3,6}-*.patch; do
                [ -f "$patch" ] && printf '%s\n' "$patch"
            done
            ;;
        *) return 2 ;;
    esac
}

dkms_module_for_version() {
    local version="$1" module
    if [ -n "${NVIDIA_DKMS_MODULE:-}" ]; then
        printf '%s\n' "$NVIDIA_DKMS_MODULE"
        return 0
    fi
    module="$(dkms status 2>/dev/null | awk -F'[,/]' -v wanted="$version" \
        '$2 == wanted { gsub(/^[[:space:]]+|[[:space:]]+$/, "", $1); print $1 "/" wanted; exit }')"
    printf '%s\n' "${module:-nvidia/$version}"
}

patch_state() {
    local tree="$1" patch_file="$2"
    if patch --directory "$tree" -p1 --dry-run --reverse --force < "$patch_file" >/dev/null 2>&1; then
        printf 'applied\n'
    elif patch --directory "$tree" -p1 --dry-run --forward --force < "$patch_file" >/dev/null 2>&1; then
        printf 'missing\n'
    else
        printf 'incompatible\n'
    fi
}

show_connector() {
    local connector prefix
    for connector in /sys/class/drm/card*-DP-*; do
        [ -r "$connector/edid" ] || continue
        prefix="$(od -An -tx1 -N12 "$connector/edid" 2>/dev/null | tr -d ' \n')"
        [ "$prefix" = 00ffffffffffff00220ec136 ] || continue
        printf '%s' "$connector"
        return 0
    done
    return 1
}

show_status() {
    local version running installed source connector state failures=0 patch_file dkms_module=""
    local disk_module relative cached_module boot_epoch disk_epoch
    local -a patch_files=()
    running="$(running_version || true)"
    installed="$(installed_version || true)"
    version="${REQUESTED_VERSION:-${installed:-$running}}"
    printf '=== NVIDIA Reverb G2 patch status ===\n'
    printf 'Running NVIDIA version: %s\n' "${running:-not detected}"
    printf 'Installed/on-disk version: %s\n' "${installed:-not detected}"
    printf 'Source version being audited: %s\n' "${version:-not detected}"
    if [ -n "$running" ] && [ -n "$installed" ] && [ "$running" != "$installed" ]; then
        printf 'NOTICE: an NVIDIA update is pending reboot; auditing the new on-disk version.\n'
    fi
    if [ -r /proc/driver/nvidia/version ]; then
        head -1 /proc/driver/nvidia/version
        if ! grep -q 'Open Kernel Module' /proc/driver/nvidia/version; then
            printf 'WARNING: this workflow is validated for NVIDIA open kernel modules.\n' >&2
        fi
    fi
    printf 'Running kernel: %s\n' "$KERNEL_VERSION"
    mapfile -t patch_files < <(patch_list_for_version "$version")
    if [ "${#patch_files[@]}" -eq 0 ]; then
        printf 'FAIL: NVIDIA %s is outside the supported patch series (595.x, 610.x and 615.x).\n' "$version" >&2
        printf 'Refusing to infer compatibility; port and physically retest the patches first.\n' >&2
        return 2
    fi
    source="$(resolve_source_tree "$version" 2>/dev/null || true)"
    if [ -z "$source" ]; then
        printf 'FAIL: no unique source tree matching NVIDIA %s under /usr/src.\n' "${version:-unknown}" >&2
        printf 'Installed source trees:\n' >&2
        printf '  %s\n' /usr/src/nvidia-* >&2
        return 2
    fi
    printf 'Matched source tree: %s\n' "$source"
    if [ ! -d "$source/kernel-open" ]; then
        printf 'FAIL: this is not a complete NVIDIA open-kernel-module source tree.\n' >&2
        return 2
    fi

    for patch_file in "${patch_files[@]}"; do
        state="$(patch_state "$source" "$patch_file")"
        printf '  %-12s %s\n' "$state" "$(basename "$patch_file")"
        [ "$state" = applied ] || failures=$((failures + 1))
    done

    if command -v dkms >/dev/null 2>&1; then
        dkms_module="$(dkms_module_for_version "$version")"
        printf 'DKMS: %s\n' "$(dkms status "$dkms_module" -k "$KERNEL_VERSION" 2>/dev/null || printf 'not installed for this kernel')"
    else
        printf 'FAIL: dkms is not installed.\n' >&2
        failures=$((failures + 1))
    fi
    disk_module="$(modinfo -k "$KERNEL_VERSION" -n nvidia_modeset 2>/dev/null || true)"
    if [ -f "$disk_module" ]; then
        boot_epoch="$(awk '$1 == "btime" { print $2; exit }' /proc/stat)"
        disk_epoch="$(stat -c %Y "$disk_module")"
        if [ -n "$running" ] && [ -n "$boot_epoch" ] && [ "$disk_epoch" -gt "$boot_epoch" ]; then
            printf 'NOTICE: nvidia-modeset was installed after this boot. Reboot before testing; matching version numbers do not confirm the loaded patch.\n'
        fi
        while IFS= read -r relative; do
            if [ "$source/$relative" -nt "$disk_module" ]; then
                printf 'FAIL: installed nvidia-modeset predates patched source %s; force a DKMS build before installing.\n' "$relative" >&2
                failures=$((failures + 1))
            fi
            for cached_module in /var/lib/dkms/"$dkms_module"/"$KERNEL_VERSION"/*/module/nvidia-modeset.ko*; do
                [ -f "$cached_module" ] || continue
                if [ "$source/$relative" -nt "$cached_module" ]; then
                    printf 'FAIL: cached DKMS nvidia-modeset predates patched source %s; reinstalling the cache is insufficient.\n' "$relative" >&2
                    failures=$((failures + 1))
                fi
            done
        done < <(for patch_file in "${patch_files[@]}"; do sed -n 's|^--- a/||p' "$patch_file"; done | sort -u)
    else
        printf 'FAIL: nvidia-modeset is not installed for kernel %s.\n' "$KERNEL_VERSION" >&2
        failures=$((failures + 1))
    fi
    connector="$(show_connector 2>/dev/null || true)"
    if [ -n "$connector" ]; then
        printf 'G2 connector (EDID-discovered): %s\n' "$connector"
        printf 'Modes: %s\n' "$(paste -sd, "$connector/modes" 2>/dev/null || printf unavailable)"
    else
        printf 'G2 connector: not currently present (no GPU port is assumed)\n'
    fi
    if [ "$failures" -eq 0 ]; then
        printf 'Result: source patches are ready. A driver/package update can replace this tree; rerun status afterward.\n'
        return 0
    fi
    printf 'Result: %d patch/build prerequisite(s) need attention.\n' "$failures" >&2
    return 2
}

copy_patch_files() {
    local source="$1" destination="$2" patch_file relative
    shift 2
    mkdir -p "$destination"
    for patch_file in "$@"; do
        while IFS= read -r relative; do
            [ "$relative" != /dev/null ] || continue
            [ -f "$source/$relative" ] || {
                printf 'Patch expects a source file that is absent: %s\n' "$source/$relative" >&2
                return 1
            }
            mkdir -p "$destination/$(dirname "$relative")"
            [ -e "$destination/$relative" ] || cp --preserve=all "$source/$relative" "$destination/$relative"
        done < <(sed -n 's|^--- a/||p' "$patch_file")
    done
}

plan_and_apply_series() {
    local tree="$1" mode="$2" patch_file state
    shift 2
    for patch_file in "$@"; do
        state="$(patch_state "$tree" "$patch_file")"
        case "$state" in
            applied)
                printf '  already applied  %s\n' "$(basename "$patch_file")"
                ;;
            missing)
                printf '  applying         %s\n' "$(basename "$patch_file")"
                patch --directory "$tree" -p1 --forward --batch < "$patch_file" >/dev/null
                [ "$mode" = real ] && APPLIED_ANY=true
                ;;
            incompatible)
                printf 'REFUSING: %s is neither cleanly applied nor cleanly applicable to %s.\n' \
                    "$(basename "$patch_file")" "$tree" >&2
                return 1
                ;;
        esac
    done
    return 0
}

refresh_initramfs() {
    if command -v mkinitcpio >/dev/null 2>&1 && [ -r /etc/mkinitcpio.conf ]; then
        printf '=== rebuilding initramfs with mkinitcpio ===\n'
        mkinitcpio -P
    elif command -v update-initramfs >/dev/null 2>&1; then
        printf '=== rebuilding initramfs with update-initramfs ===\n'
        update-initramfs -u -k "$KERNEL_VERSION"
    elif command -v dracut >/dev/null 2>&1; then
        printf '=== rebuilding initramfs with dracut ===\n'
        if command -v bootctl >/dev/null 2>&1 && command -v lsinitrd >/dev/null 2>&1 &&
           bootctl --print-boot-path >/dev/null 2>&1; then
            "$REPO/scripts/sync-nvidia-initramfs.sh" --rebuild
        else
            dracut --force --kver "$KERNEL_VERSION"
        fi
    else
        printf 'No supported initramfs tool found (mkinitcpio, update-initramfs, or dracut).\n' >&2
        return 1
    fi
}

validate_patches() {
    local version source work stage
    local -a patch_files=()
    version="${REQUESTED_VERSION:-$(installed_version || true)}"
    [ -n "$version" ] || version="$(running_version || true)"
    [ -n "$version" ] || { printf 'Could not detect the NVIDIA version.\n' >&2; return 1; }
    source="$(resolve_source_tree "$version")" || {
        printf 'No source tree exactly matching NVIDIA %s. Refusing to guess.\n' "$version" >&2
        return 1
    }
    mapfile -t patch_files < <(patch_list_for_version "$version")
    [ "${#patch_files[@]}" -gt 0 ] || {
        printf 'NVIDIA %s is outside the supported 595.x/610.x/615.x patch series.\n' "$version" >&2
        return 1
    }
    work="$(mktemp -d -t g2-nvidia-validate.XXXXXX)"
    stage="$work/tree"
    # shellcheck disable=SC2064 # capture this validated mktemp path before local scope ends
    trap "rm -rf -- '$work'" EXIT
    printf 'Validating NVIDIA %s patches against temporary copies from %s\n' "$version" "$source"
    copy_patch_files "$source" "$stage" "${patch_files[@]}"
    plan_and_apply_series "$stage" staging "${patch_files[@]}"
    printf 'Validation passed; the series produces a coherent final source tree.\n'
}

apply_patches() {
    local version source work stage backup_root relative patch_file dkms_module
    local -a patch_files=()
    version="${REQUESTED_VERSION:-$(installed_version || true)}"
    [ -n "$version" ] || version="$(running_version || true)"
    [ -n "$version" ] || { printf 'Could not detect the NVIDIA version.\n' >&2; return 1; }
    source="$(resolve_source_tree "$version")" || {
        printf 'No source tree exactly matching NVIDIA %s. Refusing to guess.\n' "$version" >&2
        return 1
    }
    [ -d "$source/kernel-open" ] || {
        printf '%s is not the complete NVIDIA open kernel source.\n' "$source" >&2
        return 1
    }
    mapfile -t patch_files < <(patch_list_for_version "$version")
    [ "${#patch_files[@]}" -gt 0 ] || {
        printf 'NVIDIA %s is outside the supported 595.x/610.x/615.x patch series.\n' "$version" >&2
        return 1
    }

    if [ "$EUID" -ne 0 ]; then
        printf 'Root is required to patch /usr/src, rebuild DKMS, and refresh the boot image.\n'
        exec sudo -- "$0" apply "$version"
    fi
    for command in patch dkms cp sed; do
        command -v "$command" >/dev/null 2>&1 || { printf 'Missing required command: %s\n' "$command" >&2; return 1; }
    done

    work="$(mktemp -d -t g2-nvidia-patch.XXXXXX)"
    # shellcheck disable=SC2064 # capture this validated mktemp path before local scope ends
    trap "rm -rf -- '$work'" EXIT
    stage="$work/tree"
    printf '=== validating the entire patch series on a temporary mini-tree ===\n'
    copy_patch_files "$source" "$stage" "${patch_files[@]}"
    plan_and_apply_series "$stage" staging "${patch_files[@]}"

    APPLIED_ANY=false
    backup_root="/var/backups/reverb-g2-nvidia/$version/$(date +%Y%m%d-%H%M%S)"
    mkdir -p "$backup_root"
    while IFS= read -r relative; do
        [ "$relative" != /dev/null ] || continue
        [ -f "$source/$relative" ] || continue
        mkdir -p "$backup_root/$(dirname "$relative")"
        [ -e "$backup_root/$relative" ] || cp --preserve=all "$source/$relative" "$backup_root/$relative"
    done < <(for patch_file in "${patch_files[@]}"; do sed -n 's|^--- a/||p' "$patch_file"; done | sort -u)
    printf 'Recovery copy: %s\n' "$backup_root"

    printf '=== applying to %s ===\n' "$source"
    plan_and_apply_series "$source" real "${patch_files[@]}"
    if [ "$APPLIED_ANY" != true ]; then
        printf 'Nothing changed; all selected source patches were already present.\n'
        printf 'Rebuilding anyway so DKMS and the boot image cannot retain an older binary.\n'
    fi

    printf '=== rebuilding NVIDIA %s for %s ===\n' "$version" "$KERNEL_VERSION"
    dkms_module="$(dkms_module_for_version "$version")"
    rebuild_dkms_module "$dkms_module"
    refresh_initramfs
    printf '\nPatched modules and boot image are ready. Reboot manually before testing the G2.\n'
    printf 'This script never reboots automatically.\n'
}

rebuild_dkms_module() {
    # install --force only reinstalls a cached build. Explicitly invalidate and
    # rebuild it so changes in /usr/src reach the installed kernel module.
    # Keep this error check explicit: never install the cached binary after a
    # failed build, including when the caller uses this function in a condition.
    dkms build --force "$1" -k "$KERNEL_VERSION" || return 1
    dkms install --force "$1" -k "$KERNEL_VERSION"
}

check_initramfs() {
    if [ "$EUID" -ne 0 ]; then
        exec sudo -- "$0" initramfs-check
    fi
    if command -v bootctl >/dev/null 2>&1 && command -v lsinitrd >/dev/null 2>&1 &&
       bootctl --print-boot-path >/dev/null 2>&1; then
        exec "$REPO/scripts/sync-nvidia-initramfs.sh" --check
    fi
    printf 'Exact embedded-module comparison is currently implemented for dracut/systemd-boot systems.\n' >&2
    printf 'The apply action still rebuilds mkinitcpio and update-initramfs systems correctly.\n' >&2
    return 2
}

if [[ "${BASH_SOURCE[0]}" == "$0" ]]; then
    case "$ACTION" in
        status) show_status ;;
        validate) validate_patches ;;
        apply) apply_patches ;;
        initramfs-check) check_initramfs ;;
        -h|--help) usage ;;
        *) usage >&2; exit 2 ;;
    esac
fi
