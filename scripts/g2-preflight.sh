#!/bin/bash
# Explain whether the host, Lighthouse receivers, and every G2 USB function are
# ready.  The G2 cable has separate USB 2 and USB 3 paths, so "it is in lsusb"
# is not a sufficient health check.

set -uo pipefail

REPO="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
NVIDIA_MANAGER="$REPO/scripts/nvidia-g2-patch-manager.sh"
stage="${1:-all}"
controller_mode="${G2_CONTROLLER_MODE:-index}"
failures=0
warnings=0

ok()   { printf '  OK    %s\n' "$*"; }
info() { printf '  INFO  %s\n' "$*"; }
warn() { printf '  WARN  %s\n' "$*" >&2; warnings=$((warnings + 1)); }
fail() { printf '  FAIL  %s\n' "$*" >&2; failures=$((failures + 1)); }

watchman_stats() {
    local uevent node detected=0 accessible=0
    for uevent in /sys/class/hidraw/hidraw*/device/uevent; do
        [ -r "$uevent" ] || continue
        if grep -Eq '^HID_ID=0003:000028DE:0000210[12]$' "$uevent"; then
            detected=$((detected + 1))
            node="/dev/$(basename "$(dirname "$(dirname "$uevent")")")"
            if [ -r "$node" ] && [ -w "$node" ]; then
                accessible=$((accessible + 1))
            fi
        fi
    done
    printf '%s %s\n' "$detected" "$accessible"
}

check_host() {
    local radios detected_radios nvrm nvidia_audit gpu_summary
    printf '=== host preflight (controllers: %s) ===\n' "$controller_mode"
    if command -v python3 >/dev/null 2>&1; then ok 'python3 is installed'; else fail 'python3 is missing'; fi
    if command -v steam >/dev/null 2>&1; then ok 'Steam command is installed'; else fail 'Steam command is missing'; fi
    if command -v rg >/dev/null 2>&1; then ok 'ripgrep is installed'; else fail 'ripgrep is missing (runtime log checks use rg)'; fi
    if command -v g++ >/dev/null 2>&1; then ok 'C++ compiler is installed'; else fail 'g++ is missing (runtime pose tools cannot build)'; fi
    if command -v pactl >/dev/null 2>&1; then ok 'PipeWire/Pulse control is installed'; else warn 'pactl is missing; headset volume integration will not work'; fi

    if [ -r /proc/driver/nvidia/version ]; then
        nvrm="$(head -1 /proc/driver/nvidia/version)"
        case "$nvrm" in
            *'Open Kernel Module'*) ok "$nvrm" ;;
            *) warn "$nvrm (this setup was tested with NVIDIA's open kernel module)" ;;
        esac
        if [ -d /sys/module/nvidia_modeset ]; then
            ok 'nvidia_modeset is loaded'
        else
            warn 'NVIDIA is loaded without nvidia_modeset (acceptable only when another GPU drives the G2)'
        fi
        if [ -x "$NVIDIA_MANAGER" ]; then
            if nvidia_audit="$($NVIDIA_MANAGER status 2>&1)"; then
                ok 'NVIDIA source/DKMS G2 patch audit passes for the installed driver version'
            else
                fail "NVIDIA patch audit needs attention; use the control panel's NVIDIA patch status"
                printf '%s\n' "$nvidia_audit" | sed 's/^/          /' >&2
            fi
        else
            fail 'NVIDIA G2 patch manager is missing from this checkout'
        fi
    else
        gpu_summary="$(lspci -nnk 2>/dev/null | awk '
            /VGA compatible controller|3D controller|Display controller/ { gpu=$0 }
            /Kernel driver in use:/ && gpu != "" { print gpu " — " $0; gpu="" }
        ' | paste -sd ';' -)"
        info "no NVIDIA kernel driver loaded; NVKMS patches are not applicable${gpu_summary:+ ($gpu_summary)}"
    fi

    read -r detected_radios radios < <(watchman_stats)
    case "$controller_mode" in
        index)
            if [ "$radios" -ge 2 ]; then
                ok "$radios Watchman receiver radios are detected and accessible"
            elif [ "$detected_radios" -ge 2 ]; then
                fail "$detected_radios Watchman radios were detected but only $radios/2 are readable and writable (install the distribution's Steam/Valve udev rules, then reconnect the dongles)"
            else
                fail "only $detected_radios/2 Watchman receiver radios were detected (Index mode needs one radio per controller)"
            fi
            ;;
        wmr)
            info "G2-controller mode selected; Watchman radios are not required ($detected_radios detected)"
            ;;
        none)
            info "headset-only mode selected; controller radios are not required ($detected_radios Watchman detected)"
            ;;
        *)
            fail "invalid G2_CONTROLLER_MODE=$controller_mode (use index, wmr, or none)"
            ;;
    esac

    if [ -r /etc/udev/rules.d/70-wmr-reverb.rules ] || [ -r /usr/lib/udev/rules.d/70-wmr-reverb.rules ]; then
        ok 'Reverb G2 udev permissions rule is installed'
    else
        warn '70-wmr-reverb.rules is not installed; camera/sensor permissions may fail'
    fi
}

find_usb_device() {
    local vendor="$1" product="$2" dev
    for dev in /sys/bus/usb/devices/*; do
        if [ ! -r "$dev/idVendor" ] || [ ! -r "$dev/idProduct" ]; then
            continue
        fi
        [ "$(cat "$dev/idVendor")" = "$vendor" ] || continue
        [ "$(cat "$dev/idProduct")" = "$product" ] || continue
        printf '%s\n' "$dev"
        return 0
    done
    return 1
}

usb_detail() {
    local dev="$1" label="$2" minimum_speed="$3" raw_access="${4:-true}"
    local speed authorized busnum devnum node controller power
    speed="$(cat "$dev/speed" 2>/dev/null || printf unknown)"
    authorized="$(cat "$dev/authorized" 2>/dev/null || printf unknown)"
    busnum="$(cat "$dev/busnum" 2>/dev/null || printf 0)"
    devnum="$(cat "$dev/devnum" 2>/dev/null || printf 0)"
    power="$(cat "$dev/power/control" 2>/dev/null || printf unknown)"
    controller="$(readlink -f "$dev" | grep -oE '[0-9a-f]{4}:[0-9a-f]{2}:[0-9a-f]{2}\.[0-9]' | tail -1)"
    node="/dev/bus/usb/$(printf '%03d' "$((10#$busnum))")/$(printf '%03d' "$((10#$devnum))")"

    if [ "$authorized" != 1 ]; then
        fail "$label is present but USB authorization is $authorized ($dev)"
    elif [ "$speed" != unknown ] && awk -v got="$speed" -v need="$minimum_speed" 'BEGIN { exit !(got < need) }'; then
        fail "$label negotiated only ${speed} Mb/s; it needs at least ${minimum_speed} Mb/s (cable/hub/port problem)"
    elif [ "$raw_access" = true ] && { [ ! -r "$node" ] || [ ! -w "$node" ]; }; then
        fail "$label is ${speed} Mb/s but $node is not readable and writable by this user"
    else
        ok "$label: ${speed} Mb/s, authorized, power=$power, xHCI=${controller:-unknown}, $(basename "$dev")"
    fi
}

check_usb() {
    local dev
    printf '=== Reverb G2 split-USB preflight ===\n'

    if dev="$(find_usb_device 04b4 6504)"; then
        usb_detail "$dev" 'Cypress cable SuperSpeed half' 5000
    else
        info 'Cypress v1-cable SuperSpeed hub (04b4:6504) is absent; continuing with functional endpoint checks (this may be a rev2 cable)'
    fi
    if dev="$(find_usb_device 04b4 6506)"; then
        usb_detail "$dev" 'Cypress cable USB 2 companion half' 480
    else
        info 'Cypress v1-cable USB 2 hub (04b4:6506) is absent; continuing with functional endpoint checks (this may be a rev2 cable)'
    fi
    if dev="$(find_usb_device 045e 0659)"; then
        usb_detail "$dev" 'HoloLens tracking cameras/sensors' 5000
    else
        fail 'HoloLens tracking cameras/sensors (045e:0659) are missing'
    fi
    if dev="$(find_usb_device 03f0 0580)"; then
        usb_detail "$dev" 'HP Reverb G2 control interface' 12
    else
        fail 'HP Reverb G2 control interface (03f0:0580) is missing'
    fi
    if dev="$(find_usb_device 0bda 4c15)"; then
        usb_detail "$dev" 'Reverb G2 USB audio' 480 false
    else
        warn 'Reverb G2 audio (0bda:4c15) is missing; display/tracking can run but headset audio will not'
    fi

    if command -v journalctl >/dev/null 2>&1; then
        local recent recent_disconnects
        recent="$(journalctl -k -b --since '-3 minutes' --no-pager 2>/dev/null | grep -Ei 'usb .* (error|reset|device descriptor|not responding|over-current)' | tail -8 || true)"
        if [ -n "$recent" ]; then
            warn 'recent kernel USB errors were found:'
            printf '%s\n' "$recent" | sed 's/^/          /'
        fi
        recent_disconnects="$(journalctl -k -b --since '-3 minutes' --no-pager 2>/dev/null | grep -Eic 'usb .* disconnect' || true)"
        if [ "$recent_disconnects" -gt 0 ]; then
            info "$recent_disconnects recent disconnect event(s) recorded (expected after a manual replug; all required devices are present now)"
        fi
    fi
}

case "$stage" in
    host) check_host ;;
    usb) check_usb ;;
    all) check_host; printf '\n'; check_usb ;;
    *) printf 'usage: %s [host|usb|all]\n' "$0" >&2; exit 2 ;;
esac

printf '\n=== preflight summary: %d failure(s), %d warning(s) ===\n' "$failures" "$warnings"
[ "$failures" -eq 0 ]
