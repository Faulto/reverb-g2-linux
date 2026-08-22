#!/bin/bash
# Run the G2 HMD through Monado's SteamVR driver and Index controllers through
# Valve's lighthouse driver. Space Calibrator aligns the two tracking spaces.

set -euo pipefail

REPO="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"

find_steam_root() {
    local candidate
    for candidate in \
        "${STEAM_ROOT:-}" \
        "${XDG_DATA_HOME:-$HOME/.local/share}/Steam" \
        "$HOME/.local/share/Steam" \
        "$HOME/.steam/steam" \
        "$HOME/.steam/root"; do
        [ -n "$candidate" ] || continue
        if [ -x "$candidate/ubuntu12_32/steam" ]; then
            readlink -f "$candidate"
            return 0
        fi
    done
    return 1
}

steam_library_for_app() {
    local app_id="$1" root vdf library
    root="$(find_steam_root 2>/dev/null || true)"
    [ -n "$root" ] || return 1
    if [ -f "$root/steamapps/appmanifest_${app_id}.acf" ]; then
        printf '%s\n' "$root"
        return 0
    fi
    vdf="$root/config/libraryfolders.vdf"
    [ -r "$vdf" ] || return 1
    while IFS= read -r library; do
        # Steam escapes backslashes in VDF paths; Linux paths normally need no conversion.
        library="${library//\\\\/\\}"
        if [ -f "$library/steamapps/appmanifest_${app_id}.acf" ]; then
            readlink -f "$library"
            return 0
        fi
    done < <(awk -F'"' '/^[[:space:]]*"path"/ { print $4 }' "$vdf")
    return 1
}

steam_common_for_app() {
    local app_id="$1" install_dir="$2" library
    library="$(steam_library_for_app "$app_id")" || return 1
    printf '%s/steamapps/common/%s\n' "$library" "$install_dir"
}

openvr_registered_path() {
    local kind="$1" name="${2:-}" vrpathreg="$3"
    [ -x "$vrpathreg" ] || return 1
    case "$kind" in
        driver)
            "$vrpathreg" show 2>/dev/null | awk -v wanted="$name" '$1 == wanted && $2 == ":" { print $3; exit }'
            ;;
        log)
            "$vrpathreg" show 2>/dev/null | sed -n 's/^Log path = //p' | head -1
            ;;
    esac
}

DETECTED_STEAM_ROOT="$(find_steam_root 2>/dev/null || true)"
STEAM_ROOT_RESOLVED="${DETECTED_STEAM_ROOT:-$HOME/.local/share/Steam}"
DETECTED_STEAMVR="$(steam_common_for_app 250820 SteamVR 2>/dev/null || true)"
DETECTED_BEAT_SABER="$(steam_common_for_app 620980 'Beat Saber' 2>/dev/null || true)"
STEAMVR="${STEAMVR_DIR:-${DETECTED_STEAMVR:-$HOME/.local/share/Steam/steamapps/common/SteamVR}}"
BEAT_SABER_DIR="${BEAT_SABER_DIR:-${DETECTED_BEAT_SABER:-}}"
DETECTED_MONADO_DRIVER="$(openvr_registered_path driver monado "$STEAMVR/bin/vrpathreg.sh" 2>/dev/null || true)"
DETECTED_SPACECAL_DRIVER="$(openvr_registered_path driver 01spacecalibrator "$STEAMVR/bin/vrpathreg.sh" 2>/dev/null || true)"
DETECTED_OPENVR_LOG="$(openvr_registered_path log '' "$STEAMVR/bin/vrpathreg.sh" 2>/dev/null || true)"
if [[ "$DETECTED_MONADO_DRIVER" = */build/steamvr-monado ]]; then
    DETECTED_MONADO_DIR="${DETECTED_MONADO_DRIVER%/build/steamvr-monado}"
else
    DETECTED_MONADO_DIR=""
fi
if [[ "$DETECTED_MONADO_DIR" = */monado-wmr ]]; then
    DETECTED_VR_ROOT="${DETECTED_MONADO_DIR%/monado-wmr}"
else
    DETECTED_VR_ROOT=""
fi
VR_ROOT="${G2_VR_ROOT:-${DETECTED_VR_ROOT:-$HOME/vr}}"
if [ -n "${MONADO_DIR:-}" ]; then
    MONADO="$MONADO_DIR"
elif [ -n "${G2_VR_ROOT:-}" ]; then
    MONADO="$VR_ROOT/monado-wmr"
else
    MONADO="${DETECTED_MONADO_DIR:-$VR_ROOT/monado-wmr}"
fi
SPACECAL_DRIVER="${SPACECAL_DRIVER_DIR:-${DETECTED_SPACECAL_DRIVER:-${XDG_DATA_HOME:-$HOME/.local/share}/SteamVR/drivers/01spacecalibrator}}"
BASALT_LIB="${VIT_SYSTEM_LIBRARY_PATH:-${BASALT_DIR:-$VR_ROOT/basalt-wmr}/build/libbasalt.so}"
MONADO_DRIVER="$MONADO/build/steamvr-monado"
SPACECAL="$SPACECAL_DRIVER/bin/linux64/space-calibrator"
VRPATHREG="$STEAMVR/bin/vrpathreg.sh"
STEAMVR_RUNTIME="$STEAMVR/steamxr_linux64.json"
MONADO_RUNTIME="$MONADO/build/openxr_monado-dev.json"
ACTIVE_RUNTIME="${XDG_CONFIG_HOME:-$HOME/.config}/openxr/1/active_runtime.json"
OPENVR_LOG_DIR="${STEAM_LOG_DIR:-${DETECTED_OPENVR_LOG:-$STEAM_ROOT_RESOLVED/logs}}"
COMPOSITOR_LOG="$OPENVR_LOG_DIR/vrcompositor.txt"
SERVER_LOG="$OPENVR_LOG_DIR/vrserver.txt"
CACHE_DIR="${XDG_CACHE_HOME:-$HOME/.cache}/reverb-g2"
STARTUP_LOG="${G2_STEAMVR_STARTUP_LOG:-$CACHE_DIR/steamvr-startup.log}"
SPACECAL_LOG="${G2_SPACECAL_LOG:-$CACHE_DIR/space-calibrator.log}"
STEAM_CLIENT_LOG="${G2_STEAM_CLIENT_LOG:-$CACHE_DIR/steam-client.log}"
MODDED_GAME_LOG="${G2_MODDED_GAME_LOG:-$CACHE_DIR/beat-saber-modded.log}"
SPACECAL_UNIT=reverb-g2-space-calibrator.service
STEAM_UNIT=reverb-g2-steam.service
MODDED_GAME_UNIT=reverb-g2-beat-saber-modded.service
TRACKING_SOURCE="$REPO/scripts/openvr-tracking.cpp"
TRACKING_BINARY="${XDG_CACHE_HOME:-$HOME/.cache}/reverb-g2/openvr-tracking"
TIMING_SOURCE="$REPO/scripts/openvr-frame-timing.cpp"
TIMING_BINARY="${XDG_CACHE_HOME:-$HOME/.cache}/reverb-g2/openvr-frame-timing"
ORIGIN_SOURCE="$REPO/scripts/openvr-standing-origin.cpp"
ORIGIN_BINARY="${XDG_CACHE_HOME:-$HOME/.cache}/reverb-g2/openvr-standing-origin"
JITTER_SOURCE="$REPO/scripts/openvr-pose-jitter.cpp"
JITTER_BINARY="${XDG_CACHE_HOME:-$HOME/.cache}/reverb-g2/openvr-pose-jitter"
STEAM_CLIENT="${STEAM_CLIENT:-$STEAM_ROOT_RESOLVED/ubuntu12_32/steam}"
STEAMVR_SETTINGS="${STEAMVR_SETTINGS:-$STEAM_ROOT_RESOLVED/config/steamvr.vrsettings}"
G2_AUDIO_SINK="${G2_AUDIO_SINK:-}"
G2_AUDIO_SOURCE="${G2_AUDIO_SOURCE:-}"
PREFLIGHT="$REPO/scripts/g2-preflight.sh"
SETTINGS_DIR="${XDG_CONFIG_HOME:-$HOME/.config}/reverb-g2"
SETTINGS_FILE="$SETTINGS_DIR/session.conf"
if [ -z "${BSMANAGER:-}" ]; then
    if command -v bs-manager >/dev/null 2>&1; then
        BSMANAGER="$(command -v bs-manager)"
    else
        BSMANAGER="$HOME/.local/opt/bs-manager/bs-manager"
    fi
fi
BSMANAGER_CONFIG="${BSMANAGER_CONFIG:-${XDG_CONFIG_HOME:-$HOME/.config}/bs-manager/config.json}"
NVIDIA_MANAGER="$REPO/scripts/nvidia-g2-patch-manager.sh"
APP_ID=620980

mkdir -p "$CACHE_DIR"

# Defaults from the physically tested Beat Saber profile. A saved session.conf
# still takes priority, so upgrades do not overwrite the user's settings.
G2_EYE_HEIGHT=1.77
G2_SMOOTHING=off
G2_PREDICTION_MODE=dead-reckoning
G2_ANGULAR_PREDICTION=true
G2_ANGULAR_PREDICTION_STRENGTH=100
G2_FEATURE_RECALL=front
G2_CAMERA_AUTOEXPOSURE=true
G2_CAMERA_UNIFY_EXPOSURE=false
G2_HEIGHT_RECOVERY=true
G2_HEIGHT_RECOVERY_DELAY=8
G2_AUDIO_VOLUME=65
G2_START_DELAY=10

load_settings() {
    local key value
    [ -r "$SETTINGS_FILE" ] || return 0
    while IFS='=' read -r key value; do
        case "$key" in
            G2_EYE_HEIGHT)
                [[ "$value" =~ ^[0-9]+([.][0-9]+)?$ ]] && G2_EYE_HEIGHT="$value"
                ;;
            G2_SMOOTHING)
                [[ "$value" =~ ^(off|position-light|position|full)$ ]] && G2_SMOOTHING="$value"
                ;;
            G2_PREDICTION_MODE)
                [[ "$value" =~ ^(none|pose-only|gyro|accel-gyro|dead-reckoning)$ ]] && G2_PREDICTION_MODE="$value"
                ;;
            G2_ANGULAR_PREDICTION)
                [[ "$value" =~ ^(true|false)$ ]] && G2_ANGULAR_PREDICTION="$value"
                ;;
            G2_ANGULAR_PREDICTION_STRENGTH)
                [[ "$value" =~ ^[0-9]+$ ]] && [ "$value" -le 150 ] && G2_ANGULAR_PREDICTION_STRENGTH="$value"
                ;;
            G2_FEATURE_RECALL)
                [[ "$value" =~ ^(off|front|all)$ ]] && G2_FEATURE_RECALL="$value"
                ;;
            G2_CAMERA_AUTOEXPOSURE)
                [[ "$value" =~ ^(true|false)$ ]] && G2_CAMERA_AUTOEXPOSURE="$value"
                ;;
            G2_CAMERA_UNIFY_EXPOSURE)
                [[ "$value" =~ ^(true|false)$ ]] && G2_CAMERA_UNIFY_EXPOSURE="$value"
                ;;
            G2_HEIGHT_RECOVERY)
                [[ "$value" =~ ^(true|false)$ ]] && G2_HEIGHT_RECOVERY="$value"
                ;;
            G2_HEIGHT_RECOVERY_DELAY)
                [[ "$value" =~ ^[0-9]+$ ]] && [ "$value" -ge 3 ] && [ "$value" -le 30 ] && G2_HEIGHT_RECOVERY_DELAY="$value"
                ;;
            G2_AUDIO_VOLUME)
                [[ "$value" =~ ^[0-9]+$ ]] && [ "$value" -le 100 ] && G2_AUDIO_VOLUME="$value"
                ;;
            G2_START_DELAY)
                [[ "$value" =~ ^[0-9]+$ ]] && [ "$value" -le 60 ] && G2_START_DELAY="$value"
                ;;
        esac
    done < "$SETTINGS_FILE"
}

save_settings() {
    local height="$1" smoothing="$2" angular="$3" volume="$4" start_delay="${5:-10}"
    local prediction="${6:-$G2_PREDICTION_MODE}" strength="${7:-$G2_ANGULAR_PREDICTION_STRENGTH}"
    local recall="${8:-$G2_FEATURE_RECALL}" autoexposure="${9:-$G2_CAMERA_AUTOEXPOSURE}"
    local unify_exposure="${10:-$G2_CAMERA_UNIFY_EXPOSURE}"
    local height_recovery="${11:-$G2_HEIGHT_RECOVERY}" recovery_delay="${12:-$G2_HEIGHT_RECOVERY_DELAY}" tmp
    [[ "$height" =~ ^[0-9]+([.][0-9]+)?$ ]] || die 'Eye height must be a number in metres.'
    awk -v h="$height" 'BEGIN { exit !(h >= 1.0 && h <= 2.5) }' || die 'Eye height must be between 1.0 and 2.5 metres.'
    [[ "$smoothing" =~ ^(off|position-light|position|full)$ ]] || die 'Smoothing must be off, position-light, position, or full.'
    [[ "$prediction" =~ ^(none|pose-only|gyro|accel-gyro|dead-reckoning)$ ]] || die 'Invalid SLAM prediction mode.'
    [[ "$angular" =~ ^(true|false)$ ]] || die 'Angular prediction must be true or false.'
    [[ "$strength" =~ ^[0-9]+$ ]] && [ "$strength" -le 150 ] || die 'Angular prediction strength must be 0..150 percent.'
    [[ "$recall" =~ ^(off|front|all)$ ]] || die 'Feature recall must be off, front, or all.'
    [[ "$autoexposure" =~ ^(true|false)$ ]] || die 'Camera auto-exposure must be true or false.'
    [[ "$unify_exposure" =~ ^(true|false)$ ]] || die 'Unified camera exposure must be true or false.'
    [[ "$height_recovery" =~ ^(true|false)$ ]] || die 'Upright height recovery must be true or false.'
    [[ "$recovery_delay" =~ ^[0-9]+$ ]] && [ "$recovery_delay" -ge 3 ] && [ "$recovery_delay" -le 30 ] || die 'Upright height recovery delay must be 3..30 seconds.'
    [[ "$volume" =~ ^[0-9]+$ ]] && [ "$volume" -le 100 ] || die 'Volume must be 0..100.'
    [[ "$start_delay" =~ ^[0-9]+$ ]] && [ "$start_delay" -le 60 ] || die 'Startup positioning delay must be 0..60 seconds.'
    mkdir -p "$SETTINGS_DIR"
    tmp="$(mktemp "$SETTINGS_DIR/session.conf.XXXXXX")"
    printf 'G2_EYE_HEIGHT=%s\nG2_SMOOTHING=%s\nG2_PREDICTION_MODE=%s\nG2_ANGULAR_PREDICTION=%s\nG2_ANGULAR_PREDICTION_STRENGTH=%s\nG2_FEATURE_RECALL=%s\nG2_CAMERA_AUTOEXPOSURE=%s\nG2_CAMERA_UNIFY_EXPOSURE=%s\nG2_HEIGHT_RECOVERY=%s\nG2_HEIGHT_RECOVERY_DELAY=%s\nG2_AUDIO_VOLUME=%s\nG2_START_DELAY=%s\n' \
        "$height" "$smoothing" "$prediction" "$angular" "$strength" "$recall" \
        "$autoexposure" "$unify_exposure" "$height_recovery" "$recovery_delay" \
        "$volume" "$start_delay" > "$tmp"
    mv -f "$tmp" "$SETTINGS_FILE"
    load_settings
    show_settings
}

show_settings() {
    printf 'Eye height: %s m\n' "$G2_EYE_HEIGHT"
    printf 'Tracking smoothing: %s\n' "$G2_SMOOTHING"
    printf 'SLAM motion prediction: %s\n' "$G2_PREDICTION_MODE"
    printf 'SteamVR angular prediction: %s at %s%% strength\n' \
        "$G2_ANGULAR_PREDICTION" "$G2_ANGULAR_PREDICTION_STRENGTH"
    printf 'Basalt landmark recall: %s\n' "$G2_FEATURE_RECALL"
    printf 'Camera auto-exposure: %s; unified across cameras: %s\n' \
        "$G2_CAMERA_AUTOEXPOSURE" "$G2_CAMERA_UNIFY_EXPOSURE"
    printf 'Upright height recovery: %s after %s s still and level\n' \
        "$G2_HEIGHT_RECOVERY" "$G2_HEIGHT_RECOVERY_DELAY"
    printf 'Headset volume at start: %s%%\n' "$G2_AUDIO_VOLUME"
    printf 'Startup positioning delay: %s s\n' "$G2_START_DELAY"
    printf 'Headset safety envelope: 5.0 x 5.0 m; floor to standing height + 0.40 m\n'
    printf 'Settings file: %s\n' "$SETTINGS_FILE"
}

show_paths() {
    local version='not detected' proton='not configured' content='not configured'
    detect_g2_audio
    if [ -r "$BEAT_SABER_DIR/BeatSaberVersion.txt" ]; then
        version="$(tr -d '\r\n' < "$BEAT_SABER_DIR/BeatSaberVersion.txt")"
    fi
    if [ -r "$BSMANAGER_CONFIG" ]; then
        proton="$(sed -n 's/^[[:space:]]*"proton-folder"[[:space:]]*:[[:space:]]*"\([^"]*\)".*/\1/p' "$BSMANAGER_CONFIG" | tail -1)"
        content="$(sed -n 's/^[[:space:]]*"installation-folder"[[:space:]]*:[[:space:]]*"\([^"]*\)".*/\1/p' "$BSMANAGER_CONFIG" | tail -1)"
    fi
    printf 'Steam root: %s\n' "${DETECTED_STEAM_ROOT:-not detected}"
    printf 'SteamVR: %s\n' "$STEAMVR"
    printf 'Beat Saber: %s\n' "${BEAT_SABER_DIR:-not detected}"
    printf 'Beat Saber version: %s\n' "$version"
    printf 'BSManager: %s\n' "$BSMANAGER"
    printf 'BSManager config: %s\n' "$BSMANAGER_CONFIG"
    printf 'BSManager content: %s\n' "${content:-not configured}"
    printf 'Proton: %s\n' "${proton:-not configured}"
    printf 'Monado: %s\n' "$MONADO"
    printf 'Basalt: %s\n' "$BASALT_LIB"
    printf 'Space Calibrator: %s\n' "$SPACECAL_DRIVER"
    printf 'G2 playback device: %s\n' "${G2_AUDIO_SINK:-not detected}"
    printf 'G2 recording device: %s\n' "${G2_AUDIO_SOURCE:-not detected}"
    printf 'OpenVR logs: %s\n' "$OPENVR_LOG_DIR"
}

load_settings

die() {
    printf '%s\n' "$*" >&2
    exit 1
}

require_file() {
    [ -e "$1" ] || die "Required file is missing: $1"
}

g2_connector() {
    local connector prefix
    local -a connectors=()
    if [ -n "${G2_DRM_CONNECTOR:-}" ]; then
        connectors+=("$G2_DRM_CONNECTOR")
    else
        connectors=(/sys/class/drm/card*-DP-*)
    fi
    for connector in "${connectors[@]}"; do
        [ -e "$connector" ] || continue
        [ "$(cat "$connector/status" 2>/dev/null)" = connected ] || continue
        prefix="$(od -An -tx1 -N12 "$connector/edid" 2>/dev/null | tr -d ' \n')"
        # EDID manufacturer 0x0e22 and product 0x36c1 (HP Reverb G2).
        if [ "$prefix" = 00ffffffffffff00220ec136 ]; then
            printf '%s\n' "$connector"
            return 0
        fi
    done
    return 1
}

watchman_radio_count() {
    local uevent node count=0
    for uevent in /sys/class/hidraw/hidraw*/device/uevent; do
        [ -r "$uevent" ] || continue
        if rg -q '^HID_ID=0003:000028DE:0000210[12]$' "$uevent"; then
            node="/dev/$(basename "$(dirname "$(dirname "$uevent")")")"
            if [ -r "$node" ] && [ -w "$node" ]; then
                count=$((count + 1))
            fi
        fi
    done
    printf '%s\n' "$count"
}

remote_play_host_enabled() {
    local config
    for config in "$STEAM_ROOT_RESOLVED/userdata"/*/config/localconfig.vdf; do
        [ -r "$config" ] || continue
        if rg -q '^\s*"EnableStreaming"\s+"1"\s*$' "$config"; then
            return 0
        fi
    done
    return 1
}

steam_client_running() {
    pgrep -f "^$STEAM_CLIENT( |$)" >/dev/null
}

have_user_systemd() {
    command -v systemctl >/dev/null 2>&1 && command -v systemd-run >/dev/null 2>&1 && \
        systemctl --user show-environment >/dev/null 2>&1
}

stop_user_unit() {
    have_user_systemd || return 0
    systemctl --user stop "$1" >/dev/null 2>&1 || true
    systemctl --user reset-failed "$1" >/dev/null 2>&1 || true
}

start_steam_client_pipewire() {
    local env_name steam_command
    local -a steam_env=()
    local -a direct_env=()
    steam_command="$(command -v steam 2>/dev/null || true)"
    [ -n "$steam_command" ] || die 'Steam command is not installed.'
    printf 'Starting Steam with PipeWire desktop capture enabled...\n'
    # Use the distribution wrapper so Steam's 32-bit runtime libraries are configured. Keep it
    # in a user service so closing the launcher terminal cannot take Steam and SteamVR with it.
    # STEAM_CLIENT remains the inner executable used to identify the live client below.
    for env_name in DISPLAY WAYLAND_DISPLAY XDG_RUNTIME_DIR DBUS_SESSION_BUS_ADDRESS XDG_SESSION_TYPE; do
        if [ -n "${!env_name:-}" ]; then
            steam_env+=(--setenv="$env_name=${!env_name}")
            direct_env+=("$env_name=${!env_name}")
        fi
    done
    stop_user_unit "$STEAM_UNIT"
    if have_user_systemd; then
        systemd-run --user --quiet --collect \
            --unit="${STEAM_UNIT%.service}" \
            --same-dir \
            --property="StandardOutput=append:$STEAM_CLIENT_LOG" \
            --property="StandardError=append:$STEAM_CLIENT_LOG" \
            "${steam_env[@]}" \
            "$steam_command" -pipewire -silent
    else
        printf 'User systemd is unavailable; supervising Steam with a detached process.\n'
        nohup env "${direct_env[@]}" "$steam_command" -pipewire -silent \
            >>"$STEAM_CLIENT_LOG" 2>&1 &
    fi
    for _i in $(seq 1 240); do
        if steam_client_running && pgrep -x steamwebhelper >/dev/null; then
            # The native client exists before its IPC/UI services are ready. Give those services
            # a short fixed settling window so vrdashboard connects on its first attempt.
            sleep 3
            return 0
        fi
        sleep 0.25
    done
    printf 'Steam did not become ready with -pipewire within 60 seconds; inspect %s\n' "$STEAM_CLIENT_LOG" >&2
    return 1
}

restart_steam_client_pipewire() {
    local still_running=0

    if steam_client_running || pgrep -x steamwebhelper >/dev/null; then
        printf 'Stopping Steam cleanly before enabling PipeWire desktop capture...\n'
        # Steam's own shutdown request lets downloads and its local databases finish cleanly.
        # Do not send a blind SIGKILL: abort VR startup if the client refuses to close.
        timeout 10s steam -shutdown >/dev/null 2>&1 || true
        for _i in $(seq 1 180); do
            if ! steam_client_running && ! pgrep -x steamwebhelper >/dev/null; then
                still_running=0
                break
            fi
            still_running=1
            sleep 0.25
        done
        if [ "$still_running" = 1 ]; then
            printf 'Steam did not close within 45 seconds; no processes were force-killed.\n' >&2
            printf 'Close Steam manually, then run the launcher again.\n' >&2
            return 1
        fi
    fi

    start_steam_client_pipewire
}

find_g2_audio_name() {
    local object_type="$1"
    command -v pactl >/dev/null 2>&1 || return 1
    pactl -f json list "$object_type" 2>/dev/null | python3 -c '
import json, sys

try:
    objects = json.load(sys.stdin)
except Exception:
    raise SystemExit(1)

for item in objects:
    name = str(item.get("name", ""))
    props = item.get("properties", {}) or {}
    vendor = str(props.get("device.vendor.id", "")).lower().removeprefix("0x").zfill(4)
    product = str(props.get("device.product.id", "")).lower().removeprefix("0x").zfill(4)
    text = " ".join((name, str(item.get("description", "")), str(props.get("device.product.name", "")))).lower()
    if (vendor, product) == ("0bda", "4c15") or "reverb g2" in text:
        if sys.argv[1] == "sources" and name.endswith(".monitor"):
            continue
        print(name)
        raise SystemExit(0)
raise SystemExit(1)
' "$object_type"
}

detect_g2_audio() {
    if [ -z "$G2_AUDIO_SINK" ]; then
        G2_AUDIO_SINK="$(find_g2_audio_name sinks 2>/dev/null || true)"
    fi
    if [ -z "$G2_AUDIO_SOURCE" ]; then
        G2_AUDIO_SOURCE="$(find_g2_audio_name sources 2>/dev/null || true)"
    fi
}

pipewire_node_id() {
    local node_name="$1"
    command -v pw-cli >/dev/null 2>&1 || return 1
    pw-cli list-objects Node 2>/dev/null | awk -v wanted="$node_name" '
        /^[[:space:]]*id [0-9]+,/ {
            id = $2
            sub(/,/, "", id)
        }
        index($0, "node.name = \"" wanted "\"") {
            print id
            exit
        }
    '
}

g2_audio_available() {
    detect_g2_audio
    [ -n "$G2_AUDIO_SINK" ] && command -v pactl >/dev/null 2>&1 && \
        pactl get-sink-volume "$G2_AUDIO_SINK" >/dev/null 2>&1
}

manage_volume() {
    local action="${1:-status}"
    g2_audio_available || die 'The G2 PipeWire sink is unavailable; wake the headset and check its USB audio endpoint.'
    case "$action" in
        status)
            pactl get-sink-volume "$G2_AUDIO_SINK"
            pactl get-sink-mute "$G2_AUDIO_SINK"
            ;;
        mute|toggle)
            pactl set-sink-mute "$G2_AUDIO_SINK" toggle
            pactl get-sink-mute "$G2_AUDIO_SINK"
            ;;
        *)
            if [[ "$action" =~ ^[+-]([0-9]+)%$ ]] && [ "${BASH_REMATCH[1]}" -le 100 ]; then
                pactl set-sink-volume "$G2_AUDIO_SINK" "$action"
                pactl get-sink-volume "$G2_AUDIO_SINK"
            elif [[ "$action" =~ ^[0-9]+$ ]] && [ "$action" -le 100 ]; then
                pactl set-sink-volume "$G2_AUDIO_SINK" "$action%"
                pactl get-sink-volume "$G2_AUDIO_SINK"
            else
                die 'Volume must be status, mute, toggle, 0..100, +N%, or -N%.'
            fi
            ;;
    esac
}

select_runtime() {
    local runtime="$1"
    require_file "$runtime"
    mkdir -p "$(dirname "$ACTIVE_RUNTIME")"
    if [ -e "$ACTIVE_RUNTIME" ] && [ ! -L "$ACTIVE_RUNTIME" ]; then
        die "$ACTIVE_RUNTIME exists and is not a symlink; refusing to overwrite it."
    fi
    ln -sfn "$runtime" "$ACTIVE_RUNTIME"
    printf 'OpenXR runtime: %s -> %s\n' "$ACTIVE_RUNTIME" "$runtime"
}

stop_vr_processes() {
    local process_name process_pid
    stop_user_unit "$MODDED_GAME_UNIT"
    stop_user_unit "$SPACECAL_UNIT"
    pkill -TERM -f '[B]eat Saber\.exe' 2>/dev/null || true
    for process_name in vrmonitor vrdashboard steamtours vrcompositor vrserver; do
        pkill -TERM -x "$process_name" 2>/dev/null || true
    done
    while read -r process_pid; do
        [ -n "$process_pid" ] && kill -TERM "$process_pid" 2>/dev/null || true
    done < <(pgrep -f "$STEAMVR/tools/steamvr_room_setup/.*/steamvr_room_setup( |$)" || true)
    while read -r process_pid; do
        [ -n "$process_pid" ] && kill -TERM "$process_pid" 2>/dev/null || true
    done < <(pgrep -f "$SPACECAL_DRIVER/bin/linux64/space-calibrator-real( |$)" || true)

    for _i in $(seq 1 30); do
        if ! pgrep -x vrserver >/dev/null && ! pgrep -x vrcompositor >/dev/null; then
            return 0
        fi
        sleep 0.1
    done
    return 0
}

stop_session() {
    stop_vr_processes
    python3 "$REPO/scripts/panel.py" off >/dev/null 2>&1 || true
    if [ -f "$MONADO_RUNTIME" ]; then
        select_runtime "$MONADO_RUNTIME"
    fi
    printf 'Mixed G2/Index session stopped.\n'
}

show_status() {
    local connector="" modes="not available" radios runtime="none"
    connector="$(g2_connector 2>/dev/null || true)"
    radios="$(watchman_radio_count)"
    [ -e "$ACTIVE_RUNTIME" ] && runtime="$(readlink -f "$ACTIVE_RUNTIME" 2>/dev/null || printf unknown)"

    if [ -n "$connector" ] && [ -r "$connector/modes" ]; then
        modes="$(paste -sd, "$connector/modes")"
    fi

    printf 'G2 connector: %s\n' "${connector:-not connected}"
    printf 'G2 DRM modes: %s\n' "$modes"
    printf 'Watchman radios: %s/2\n' "$radios"
    printf 'OpenXR runtime: %s\n' "$runtime"
    show_settings
    pgrep -a -x vrserver 2>/dev/null || printf 'vrserver: stopped\n'
    pgrep -a -x vrcompositor 2>/dev/null || printf 'vrcompositor: stopped\n'
    if [ -f "$COMPOSITOR_LOG" ] && tail -n 300 "$COMPOSITOR_LOG" | rg -q 'Direct mode: enabled'; then
        printf 'Last compositor result: direct mode enabled\n'
    fi
}

register_drivers() {
    "$VRPATHREG" adddriver "$MONADO_DRIVER" >/dev/null 2>&1 || true
    "$VRPATHREG" adddriver "$SPACECAL_DRIVER" >/dev/null 2>&1 || true
    rg -q '"activateMultipleDrivers"[[:space:]]*:[[:space:]]*true' \
        "$STEAMVR_SETTINGS" 2>/dev/null || \
        die 'SteamVR setting activateMultipleDrivers=true is missing.'
}

start_space_calibrator() {
    local env_name main_pid process_pid
    local -a spacecal_env=()
    local -a direct_env=()
    local -a spacecal_pids=()

    require_file "$SPACECAL"
    pgrep -x vrserver >/dev/null || die "SteamVR is not running. Run '$0 start' first."

    for env_name in DISPLAY WAYLAND_DISPLAY XDG_RUNTIME_DIR DBUS_SESSION_BUS_ADDRESS XDG_SESSION_TYPE; do
        if [ -n "${!env_name:-}" ]; then
            spacecal_env+=(--setenv="$env_name=${!env_name}")
            direct_env+=("$env_name=${!env_name}")
        fi
    done
    # Prefer SteamVR's registered auto-launch instance when it has already appeared. Starting a
    # second copy makes two overlays race over the driver's shared transform: a successful new
    # calibration then visibly snaps back to the stale profile held by the other process.
    for _i in $(seq 1 20); do
        mapfile -t spacecal_pids < <(
            pgrep -f "^$SPACECAL_DRIVER/bin/linux64/space-calibrator-real( |$)" || true
        )
        [ "${#spacecal_pids[@]}" -gt 0 ] && break
        sleep 0.1
    done
    if [ "${#spacecal_pids[@]}" -eq 1 ]; then
        printf 'Space Calibrator is already running as PID %s.\n' "${spacecal_pids[0]}"
        return 0
    fi

    stop_user_unit "$SPACECAL_UNIT"
    # Zero or multiple instances: restart from the saved profile and retain exactly the process
    # owned by our detached service. The overlay enables SteamVR auto-launch during startup, so a
    # second process can be spawned just after ours connects; remove that late duplicate too.
    for process_pid in "${spacecal_pids[@]}"; do
        [ -n "$process_pid" ] && kill -TERM "$process_pid" 2>/dev/null || true
    done
    for _i in $(seq 1 30); do
        if ! pgrep -f "^$SPACECAL_DRIVER/bin/linux64/space-calibrator-real( |$)" >/dev/null; then
            break
        fi
        sleep 0.1
    done
    if have_user_systemd; then
        systemd-run --user --quiet --collect \
            --unit="${SPACECAL_UNIT%.service}" \
            --same-dir \
            --property="StandardOutput=append:$SPACECAL_LOG" \
            --property="StandardError=append:$SPACECAL_LOG" \
            "${spacecal_env[@]}" \
            "$SPACECAL"
        main_pid="$(systemctl --user show "$SPACECAL_UNIT" --property=MainPID --value)"
    else
        nohup env "${direct_env[@]}" "$SPACECAL" >>"$SPACECAL_LOG" 2>&1 &
        main_pid=$!
    fi
    sleep 1
    if ! kill -0 "$main_pid" 2>/dev/null; then
        printf 'Space Calibrator did not remain open; inspect %s\n' "$SPACECAL_LOG" >&2
        return 1
    fi
    for _i in $(seq 1 20); do
        while read -r process_pid; do
            if [ -n "$process_pid" ] && [ "$process_pid" != "$main_pid" ]; then
                kill -TERM "$process_pid" 2>/dev/null || true
            fi
        done < <(pgrep -f "^$SPACECAL_DRIVER/bin/linux64/space-calibrator-real( |$)" || true)
        sleep 0.1
    done
    mapfile -t spacecal_pids < <(
        pgrep -f "^$SPACECAL_DRIVER/bin/linux64/space-calibrator-real( |$)" || true
    )
    if [ "${#spacecal_pids[@]}" -ne 1 ] || [ "${spacecal_pids[0]:-}" != "$main_pid" ]; then
        printf 'Could not establish one Space Calibrator owner; found PIDs: %s\n' \
            "${spacecal_pids[*]:-(none)}" >&2
        return 1
    fi
    if have_user_systemd; then
        printf 'Space Calibrator is running as %s.\n' "$SPACECAL_UNIT"
    else
        printf 'Space Calibrator is running as PID %s.\n' "$main_pid"
    fi
}

startup_position_countdown() {
    local remaining
    [ "$G2_START_DELAY" -gt 0 ] || return 0
    printf '\nPick up the G2 now. Stand at play-centre, upright, facing your usual forward direction.\n'
    printf 'Monado/Basalt tracking will initialize when this countdown reaches zero.\n'
    for ((remaining=G2_START_DELAY; remaining>0; remaining--)); do
        printf '\rStarting tracking in %2d second(s)...' "$remaining"
        sleep 1
    done
    printf '\rStarting tracking now.             \n'
}

confirm_position_countdown() {
    local launch_note=""
    [ "${G2_CONFIRM_START:-false}" = true ] || return 0
    if [ "${G2_AUTO_PLAY_MODDED:-false}" = true ]; then
        launch_note="\n\nThe BSManager-managed Beat Saber copy will launch automatically once SteamVR and Space Calibrator are ready."
    fi
    if command -v yad >/dev/null 2>&1; then
        yad --center --on-top --image=dialog-question \
            --title='Reverb G2 checks passed' \
            --text="Hardware, USB and native-display checks passed.\n\nStay at the computer until this dialog appears. Click Begin, then use the ${G2_START_DELAY}-second countdown to pick up or wear the headset, stand at play-centre, and face your usual forward direction.${launch_note}" \
            --button='Cancel:1' --button="Begin ${G2_START_DELAY} s countdown:0"
        return
    fi
    printf '\nAll startup checks passed. Press Enter to begin the %s-second positioning countdown, or Ctrl-C to cancel.\n' "$G2_START_DELAY"
    read -r
}

launch_steamvr_processes() {
    local smooth_position="$1" smooth_orientation="$2"
    local audio_playback_node="$3" audio_recording_node="$4"
    local position_cutoff="$5" position_beta="$6" prediction_type="$7"
    nohup env \
        VALVE_SKIP_RUNTIME_SAFETY=1 \
        XRT_LOG=info \
        WMR_LOG=debug \
        WMR_SLAM=true \
        SLAM_SUBMIT_FROM_START=true \
        WMR_AUTOEXPOSURE="$G2_CAMERA_AUTOEXPOSURE" \
        WMR_UNIFY_EXPGAIN="$G2_CAMERA_UNIFY_EXPOSURE" \
        WMR_HEAD_POSE_ANGULAR_VELOCITY="$G2_ANGULAR_PREDICTION" \
        WMR_HEAD_POSE_ANGULAR_VELOCITY_PERCENT="$G2_ANGULAR_PREDICTION_STRENGTH" \
        WMR_SLAM_SESSION_WIDTH_M=5.0 \
        WMR_SLAM_SESSION_DEPTH_M=5.0 \
        WMR_SLAM_EYE_HEIGHT_M="$G2_EYE_HEIGHT" \
        WMR_SLAM_HEADROOM_M=0.40 \
        WMR_SLAM_HEIGHT_RECOVERY="$G2_HEIGHT_RECOVERY" \
        WMR_SLAM_HEIGHT_RECOVERY_DELAY_S="$G2_HEIGHT_RECOVERY_DELAY" \
        SLAM_DIVERGENCE_ABSOLUTE_M=20.0 \
        SLAM_DIVERGENCE_RADIUS_M=4.5 \
        SLAM_DIVERGENCE_STEP_M=2.0 \
        SLAM_DIVERGENCE_VELOCITY_MPS=10.0 \
        SLAM_DIVERGENCE_RESET_FRAMES=3 \
        SLAM_PREDICTION_TYPE="$prediction_type" \
        SLAM_ONE_EURO_POSITION="$smooth_position" \
        SLAM_ONE_EURO_ORIENTATION="$smooth_orientation" \
        SLAM_ONE_EURO_POSITION_MIN_CUTOFF="$position_cutoff" \
        SLAM_ONE_EURO_POSITION_BETA="$position_beta" \
        BASALT_FEATURE_RECALL="$G2_FEATURE_RECALL" \
        STEAMVR_AUDIO_PLAYBACK_DEVICE="$G2_AUDIO_SINK" \
        STEAMVR_AUDIO_RECORDING_DEVICE="$G2_AUDIO_SOURCE" \
        STEAMVR_AUDIO_PIPEWIRE_PLAYBACK_NODE="$audio_playback_node" \
        STEAMVR_AUDIO_PIPEWIRE_RECORDING_NODE="$audio_recording_node" \
        VIT_SYSTEM_LIBRARY_PATH="$BASALT_LIB" \
        WMR_DISPLAY_INIT_SLEEP_SECONDS=2 \
        "$STEAMVR/bin/vrstartup.sh" --valve-skip-runtime-safety \
        >"$STARTUP_LOG" 2>&1 &
}

start_session() {
    local audio_playback_node="" audio_recording_node="" connector="" compositor_pid=""
    local compositor_start="" server_pid="" server_start="" success=0 radios
    local smooth_position=false smooth_orientation=false monado_failed=0 attempt
    local position_cutoff=8.0 position_beta=2.0 prediction_type=4

    require_file "$MONADO_DRIVER/bin/linux64/driver_monado.so"
    require_file "$SPACECAL_DRIVER/bin/linux64/driver_01spacecalibrator.so"
    require_file "$SPACECAL"
    require_file "$BASALT_LIB"
    require_file "$VRPATHREG"
    require_file "$STEAMVR_RUNTIME"
    require_file "$PREFLIGHT"

    if [ "${G2_AUTO_PLAY_MODDED:-false}" = true ]; then
        validate_modded_game_config
    fi

    G2_CONTROLLER_MODE=index "$PREFLIGHT" host || die 'Host preflight failed; fix the FAIL lines above before starting SteamVR.'

    radios="$(watchman_radio_count)"
    [ "$radios" -ge 2 ] || die "Only $radios/2 Watchman radios are available."

    if remote_play_host_enabled; then
        printf '\nWARNING: Steam Remote Play hosting is enabled.\n' >&2
        printf 'Steam\047s CDesktopStreamT has crashed twice here while starting desktop capture.\n' >&2
        printf 'For reliable VR, disable Settings -> Remote Play -> Enable Remote Play before launching Beat Saber.\n\n' >&2
    fi

    stop_vr_processes
    restart_steam_client_pipewire
    register_drivers

    if ! timeout 12s python3 "$REPO/scripts/panel.py" activate; then
        printf '\nThe panel control interface could not wake the headset. Current USB state:\n' >&2
        G2_CONTROLLER_MODE=index "$PREFLIGHT" usb || true
        die 'Panel activation failed. Check cable-box power/USB, then power-cycle the v1 cable box.'
    fi
    for _i in $(seq 1 60); do
        connector="$(g2_connector 2>/dev/null || true)"
        [ -n "$connector" ] && break
        sleep 0.25
    done
    if [ -z "$connector" ]; then
        G2_CONTROLLER_MODE=index "$PREFLIGHT" usb || true
        python3 "$REPO/scripts/panel.py" off >/dev/null 2>&1 || true
        die 'The G2 connector did not appear within 15 seconds; USB may be healthy but DisplayPort did not train.'
    fi

    G2_CONTROLLER_MODE=index "$PREFLIGHT" usb || {
        python3 "$REPO/scripts/panel.py" off >/dev/null 2>&1 || true
        die 'G2 USB preflight failed; SteamVR was not started. Fix the FAIL lines above.'
    }

    detect_g2_audio
    if [ -n "$G2_AUDIO_SINK" ]; then
        audio_playback_node="$(pipewire_node_id "$G2_AUDIO_SINK" 2>/dev/null || true)"
    fi
    if [ -n "$G2_AUDIO_SOURCE" ]; then
        audio_recording_node="$(pipewire_node_id "$G2_AUDIO_SOURCE" 2>/dev/null || true)"
    fi
    if [ -n "$audio_playback_node" ]; then
        printf 'G2 audio: %s (PipeWire node %s)\n' "$G2_AUDIO_SINK" "$audio_playback_node"
        pactl set-sink-volume "$G2_AUDIO_SINK" "$G2_AUDIO_VOLUME%" || true
    else
        printf 'WARNING: the G2 playback node was not found; SteamVR audio selection may be blank.\n' >&2
    fi
    case "$G2_SMOOTHING" in
        off) ;;
        position-light)
            smooth_position=true
            position_cutoff=12.0
            position_beta=3.0
            ;;
        position) smooth_position=true ;;
        full) smooth_position=true; smooth_orientation=true ;;
    esac
    case "$G2_PREDICTION_MODE" in
        none) prediction_type=0 ;;
        pose-only) prediction_type=1 ;;
        gyro) prediction_type=2 ;;
        accel-gyro) prediction_type=3 ;;
        dead-reckoning) prediction_type=4 ;;
    esac
    printf '\nActive session profile:\n'
    show_settings

    if ! rg -qx '4320x2160' "$connector/modes" 2>/dev/null; then
        printf '\nThe display driver connected the G2 but did not expose its 4320x2160 native mode.\n' >&2
        printf 'Modes currently exposed on %s: ' "$connector" >&2
        paste -sd, "$connector/modes" >&2 2>/dev/null || printf '(unreadable)\n' >&2
        printf 'SteamVR compares Monado\047s 4320x2160 window bounds with this list and will reject the DRM lease.\n' >&2
        printf 'This is a DisplayPort link/mode-validation failure, not an XWayland or login-session failure.\n' >&2
        if [ -r /proc/driver/nvidia/version ]; then
            printf 'Run this launcher with the diagnose command and inspect the NVIDIA status above.\n' >&2
        else
            printf 'Inspect the kernel DRM log for the GPU driving this connector.\n' >&2
        fi
        python3 "$REPO/scripts/panel.py" off >/dev/null 2>&1 || true
        exit 1
    fi
    printf 'G2 ready on %s with 4320x2160 exposed.\n' "$connector"
    if ! confirm_position_countdown; then
        python3 "$REPO/scripts/panel.py" off >/dev/null 2>&1 || true
        printf 'VR startup cancelled before tracking initialized; the G2 panel was turned off.\n'
        return 0
    fi
    startup_position_countdown

    for attempt in 1 2; do
        success=0
        monado_failed=0
        compositor_pid=""
        compositor_start=""
        server_pid=""
        server_start=""
        launch_steamvr_processes "$smooth_position" "$smooth_orientation" \
            "$audio_playback_node" "$audio_recording_node" \
            "$position_cutoff" "$position_beta" "$prediction_type"

        for _i in $(seq 1 120); do
            server_pid="$(pgrep -n -x vrserver 2>/dev/null || true)"
            if [ -n "$server_pid" ] && [ -f "$SERVER_LOG" ]; then
                server_start="$(
                    rg -n "vrserver .* startup with PID=${server_pid}," "$SERVER_LOG" 2>/dev/null | \
                        tail -1 | cut -d: -f1
                )"
                if [ -n "$server_start" ] && \
                   tail -n +"$server_start" "$SERVER_LOG" | \
                       rg -q 'monado: Failed to create system devices|Unable to load driver monado.*HmdNotFound'; then
                    monado_failed=1
                    break
                fi
            fi

            compositor_pid="$(pgrep -n -x vrcompositor 2>/dev/null || true)"
            if [ -n "$compositor_pid" ] && [ -f "$COMPOSITOR_LOG" ]; then
                # SteamVR truncates these logs on startup, so a line count saved
                # before launch can point beyond the new file. Anchor this run to
                # the startup header containing the live compositor PID instead.
                compositor_start="$(
                    rg -n "vrcompositor .* startup with PID=${compositor_pid}," "$COMPOSITOR_LOG" 2>/dev/null | \
                        tail -1 | cut -d: -f1
                )"
            fi
            if [ -n "$compositor_start" ] && \
               tail -n +"$compositor_start" "$COMPOSITOR_LOG" | rg -q 'Direct mode: enabled'; then
                success=1
                break
            fi
            sleep 0.25
        done

        [ "$success" = 1 ] && break
        if [ "$monado_failed" = 1 ] && [ "$attempt" = 1 ]; then
            printf '\nMonado did not create the G2 on its first attempt; releasing USB and retrying once...\n' >&2
            stop_vr_processes
            sleep 2
            continue
        fi
        break
    done
    if [ "$success" != 1 ]; then
        if [ "$monado_failed" = 1 ]; then
            printf '\nMonado loaded but could not create the G2 system after two attempts.\n' >&2
            if [ -n "$server_start" ]; then
                tail -n +"$server_start" "$SERVER_LOG" | \
                    rg 'monado:|Unable to load driver monado|HmdNotFound' | tail -12 >&2 || true
            fi
            printf 'This happened before vrcompositor requested a DRM lease. USB can enumerate correctly while the WMR device open/initialization still fails.\n' >&2
            printf 'Detailed Monado/WMR output: %s\n' "$STARTUP_LOG" >&2
        elif [ -z "$compositor_start" ]; then
            printf '\nSteamVR never started a compositor for this launch.\n' >&2
            printf 'Inspect %s and the current vrserver log; this is not yet a DRM-lease failure.\n' "$STARTUP_LOG" >&2
        else
            printf '\nSteamVR started its compositor but did not acquire the G2 DRM lease.\n' >&2
            if [ -n "$compositor_start" ]; then
                tail -n +"$compositor_start" "$COMPOSITOR_LOG"
            fi | rg 'Tried to find direct display|CannotDRMLeaseDisplay|Failed to start compositor' | \
                tail -12 >&2 || true
            printf 'The required 4320x2160 mode was present, so this is a compositor/Wayland lease failure.\n' >&2
        fi
        stop_vr_processes
        python3 "$REPO/scripts/panel.py" off >/dev/null 2>&1 || true
        exit 1
    fi

    select_runtime "$STEAMVR_RUNTIME"

    printf '\nAuto-setting the 5 x 5 m standing space from the validated startup pose...\n'
    if ! manage_origin set-now "$G2_EYE_HEIGHT" 5 5; then
        printf '\nThe startup pose did not pass the safe floor-capture checks.\n' >&2
        printf 'SteamVR is being stopped so a bad raw pose cannot be saved or used in a game.\n' >&2
        stop_vr_processes
        python3 "$REPO/scripts/panel.py" off >/dev/null 2>&1 || true
        die 'Automatic floor setup failed. Start again while upright and still at play-centre.'
    fi

    for _i in $(seq 1 80); do
        server_pid="$(pgrep -n -x vrserver 2>/dev/null || true)"
        if [ -n "$server_pid" ] && [ -f "$SERVER_LOG" ]; then
            server_start="$(
                rg -n "vrserver .* startup with PID=${server_pid}," "$SERVER_LOG" 2>/dev/null | \
                    tail -1 | cut -d: -f1
            )"
        fi
        if [ -n "$server_start" ] && \
           [ "$(tail -n +"$server_start" "$SERVER_LOG" | rg -c 'LHR-[0-9A-F]+: Connected to receiver' || true)" -ge 2 ]; then
            break
        fi
        sleep 0.25
    done

    start_space_calibrator || true

    printf '\nSteamVR direct mode is running with the G2 at 90 Hz.\n'
    printf 'Both Index controllers should appear through the lighthouse driver.\n'
    printf 'Wear the HMD at play-centre with both controllers awake, then verify the saved spaces:\n'
    printf '  %s ready %s\n' "$0" "$G2_EYE_HEIGHT"
    printf 'Calibrate in the desktop Space Calibrator window only if that check reports stale controllers.\n'
    if [ "${G2_AUTO_PLAY_MODDED:-false}" = true ]; then
        launch_modded_game
    else
        printf 'Then run:\n'
        printf '  %s play-modded\n' "$0"
    fi
}

set_floor() {
    local delay="${1:-10}" remaining
    [[ "$delay" =~ ^[0-9]+$ ]] || die 'Floor delay must be a whole number of seconds.'
    printf 'Put on the headset and stand upright at play-centre.\n'
    for ((remaining=delay; remaining>0; remaining--)); do
        printf '\rSetting floor for %.2f m eye height in %2d second(s)...' "$G2_EYE_HEIGHT" "$remaining"
        sleep 1
    done
    printf '\n'
    manage_origin set-now "$G2_EYE_HEIGHT" 5 5
}

open_mod_manager() {
    if [ ! -f "$BSMANAGER" ]; then
        die "BSManager was not found at $BSMANAGER. Install its native Linux package, then follow $REPO/docs/bsmanager.md"
    fi
    [ -x "$BSMANAGER" ] || die "BSManager is not executable: $BSMANAGER"
    mkdir -p "${XDG_CACHE_HOME:-$HOME/.cache}/reverb-g2"
    nohup "$BSMANAGER" >"${XDG_CACHE_HOME:-$HOME/.cache}/reverb-g2/bs-manager.log" 2>&1 &
    printf 'Opened BSManager. Its log is under ~/.cache/reverb-g2/bs-manager.log\n'
    printf 'Choose a separate managed Beat Saber version for which BSManager currently offers verified Core mods.\n'
}

show_diagnostics() {
    local result=0
    G2_CONTROLLER_MODE=index "$PREFLIGHT" all || result=1
    printf '\n=== live VR state ===\n'
    show_status
    if [ -f "$SERVER_LOG" ]; then
        printf '\n=== recent VR errors ===\n'
        tail -n 400 "$SERVER_LOG" | rg -i 'error|fail|disconnect|not tracking' | tail -20 || printf 'No recent matching vrserver errors.\n'
    fi
    return "$result"
}

play_game() {
    pgrep -x vrcompositor >/dev/null || die "SteamVR is not rendering. Run '$0 start' first."
    select_runtime "$STEAMVR_RUNTIME"
    printf 'Starting Beat Saber through SteamVR OpenXR.\n'
    steam -applaunch "$APP_ID"
}

bsmanager_last_version_info() {
    local config="$BSMANAGER_CONFIG"
    [ -r "$config" ] || die "BSManager setup is incomplete: $config is missing. Open native BSManager once and follow $REPO/docs/bsmanager.md"
    python3 - "$config" <<'PY'
import json
import sys

with open(sys.argv[1], encoding="utf-8") as handle:
    config = json.load(handle)

version = config.get("last-version-launched") or {}
values = (
    config.get("proton-folder"),
    config.get("installation-folder"),
    version.get("path"),
    version.get("BSVersion"),
)
if not all(isinstance(value, str) and value for value in values):
    raise SystemExit("BSManager has no complete last-version/proton configuration")
print(*values, sep="\n")
PY
}

validate_modded_game_config() {
    local -a info=()
    mapfile -t info < <(bsmanager_last_version_info)
    [ "${#info[@]}" -eq 4 ] || die 'BSManager returned incomplete managed-version information.'
    require_file "${info[0]}/proton"
    require_file "${info[2]}/Beat Saber.exe"
    require_file "${info[2]}/winhttp.dll"
    [ -d "${info[2]}/Plugins" ] || die "The BSManager instance is not modded: ${info[2]}"
    printf 'Modded auto-launch target: Beat Saber %s\n' "${info[3]}"
    printf '  instance: %s\n' "${info[2]}"
    printf '  Proton:   %s\n' "${info[0]}"
}

launch_modded_game() {
    local proton_folder installation_folder instance version exe proton compat_data
    local env_name game_pid game_launcher_pid=""
    local -a info=() game_env=()
    local -a direct_env=()

    pgrep -x vrcompositor >/dev/null || die "SteamVR is not rendering. Run '$0 start' first."
    mapfile -t info < <(bsmanager_last_version_info) || \
        die 'Could not read the last managed Beat Saber version from BSManager.'
    [ "${#info[@]}" -eq 4 ] || die 'BSManager returned incomplete managed-version information.'
    proton_folder="${info[0]}"
    installation_folder="${info[1]}"
    instance="${info[2]}"
    version="${info[3]}"
    proton="$proton_folder/proton"
    exe="$instance/Beat Saber.exe"
    compat_data="$installation_folder/BSManager/SharedContent/compatdata"

    require_file "$proton"
    require_file "$exe"
    require_file "$instance/winhttp.dll"
    [ -d "$instance/Plugins" ] || die "The BSManager instance is not modded: $instance"
    if pgrep -f '[B]eat Saber\.exe' >/dev/null; then
        die 'Beat Saber is already running.'
    fi

    mkdir -p "$compat_data"
    select_runtime "$STEAMVR_RUNTIME"
    for env_name in DISPLAY WAYLAND_DISPLAY XDG_RUNTIME_DIR DBUS_SESSION_BUS_ADDRESS XDG_SESSION_TYPE; do
        if [ -n "${!env_name:-}" ]; then
            game_env+=(--setenv="$env_name=${!env_name}")
            direct_env+=("$env_name=${!env_name}")
        fi
    done

    stop_user_unit "$MODDED_GAME_UNIT"
    printf '\nLaunching BSManager-managed Beat Saber %s in VR mode...\n' "$version"
    printf 'Instance: %s\n' "$instance"
    printf 'Proton: %s\n' "$proton_folder"
    if have_user_systemd; then
        systemd-run --user --quiet --collect \
            --unit="${MODDED_GAME_UNIT%.service}" \
            --working-directory="$instance" \
            --property="StandardOutput=append:$MODDED_GAME_LOG" \
            --property="StandardError=append:$MODDED_GAME_LOG" \
            "${game_env[@]}" \
            --setenv='WINEDLLOVERRIDES=winhttp=n,b' \
            --setenv="STEAM_COMPAT_DATA_PATH=$compat_data" \
            --setenv="STEAM_COMPAT_INSTALL_PATH=$instance" \
            --setenv="STEAM_COMPAT_CLIENT_INSTALL_PATH=$STEAM_ROOT_RESOLVED" \
            --setenv="STEAM_COMPAT_APP_ID=$APP_ID" \
            --setenv='SteamEnv=1' \
            --setenv='OXR_NO_TEXTURE_SOURCE_ALPHA=1' \
            --setenv="SteamAppId=$APP_ID" \
            --setenv="SteamOverlayGameId=$APP_ID" \
            --setenv="SteamGameId=$APP_ID" \
            "$proton" run "$exe" --no-yeet
    else
        (
            cd "$instance"
            nohup env "${direct_env[@]}" \
                'WINEDLLOVERRIDES=winhttp=n,b' \
                "STEAM_COMPAT_DATA_PATH=$compat_data" \
                "STEAM_COMPAT_INSTALL_PATH=$instance" \
                "STEAM_COMPAT_CLIENT_INSTALL_PATH=$STEAM_ROOT_RESOLVED" \
                "STEAM_COMPAT_APP_ID=$APP_ID" \
                'SteamEnv=1' 'OXR_NO_TEXTURE_SOURCE_ALPHA=1' \
                "SteamAppId=$APP_ID" "SteamOverlayGameId=$APP_ID" "SteamGameId=$APP_ID" \
                "$proton" run "$exe" --no-yeet >>"$MODDED_GAME_LOG" 2>&1 &
            printf '%s\n' "$!"
        ) >"$CACHE_DIR/modded-launcher.pid"
        game_launcher_pid="$(cat "$CACHE_DIR/modded-launcher.pid")"
    fi

    game_pid=""
    for _i in $(seq 1 120); do
        game_pid="$(pgrep -n -f '[B]eat Saber\.exe' 2>/dev/null || true)"
        [ -n "$game_pid" ] && break
        if { have_user_systemd && ! systemctl --user is-active --quiet "$MODDED_GAME_UNIT"; } || \
           { ! have_user_systemd && [ -n "$game_launcher_pid" ] && ! kill -0 "$game_launcher_pid" 2>/dev/null; }; then
            printf 'Modded Beat Saber exited during startup. Recent output:\n' >&2
            tail -n 40 "$MODDED_GAME_LOG" >&2 || true
            return 1
        fi
        sleep 0.25
    done
    [ -n "$game_pid" ] || die "Modded Beat Saber did not appear within 30 seconds; inspect $MODDED_GAME_LOG"
    printf 'Modded Beat Saber is starting as PID %s; no SteamVR desktop is required.\n' "$game_pid"
    printf 'Launch log: %s\n' "$MODDED_GAME_LOG"
}

stop_modded_game() {
    local still_running=0
    stop_user_unit "$MODDED_GAME_UNIT"
    pkill -TERM -f '[B]eat Saber\.exe' 2>/dev/null || true
    for _i in $(seq 1 80); do
        if ! pgrep -f '[B]eat Saber\.exe' >/dev/null; then
            printf 'Beat Saber is stopped; SteamVR remains running.\n'
            return 0
        fi
        still_running=1
        sleep 0.25
    done
    [ "$still_running" = 0 ] || die 'Beat Saber did not close within 20 seconds; no process was force-killed.'
}

restart_modded_game() {
    pgrep -x vrcompositor >/dev/null || die "SteamVR is not rendering. Run '$0 start' first."
    stop_modded_game
    launch_modded_game
}

show_tracking() {
    local duration="${1:-15}"
    local openvr_include="$MONADO/src/external/openvr_includes"
    local openvr_lib="$STEAMVR/bin/linux64"

    pgrep -x vrserver >/dev/null || die "SteamVR is not running. Run '$0 start' first."
    require_file "$TRACKING_SOURCE"
    require_file "$openvr_include/openvr.h"
    require_file "$openvr_lib/libopenvr_api.so"

    if [ ! -x "$TRACKING_BINARY" ] || [ "$TRACKING_SOURCE" -nt "$TRACKING_BINARY" ]; then
        mkdir -p "$(dirname "$TRACKING_BINARY")"
        printf 'Building OpenVR tracking monitor...\n'
        g++ -std=c++17 -O2 -Wall -Wextra \
            -I"$openvr_include" \
            "$TRACKING_SOURCE" \
            -L"$openvr_lib" -Wl,-rpath,"$openvr_lib" -lopenvr_api \
            -o "$TRACKING_BINARY"
    fi

    "$TRACKING_BINARY" "$duration"
}

show_timing() {
    local duration="${1:-10}"
    local openvr_include="$MONADO/src/external/openvr_includes"
    local openvr_lib="$STEAMVR/bin/linux64"

    pgrep -x vrcompositor >/dev/null || die "SteamVR is not running. Run '$0 start' first."
    require_file "$TIMING_SOURCE"
    require_file "$openvr_include/openvr.h"
    require_file "$openvr_lib/libopenvr_api.so"

    if [ ! -x "$TIMING_BINARY" ] || [ "$TIMING_SOURCE" -nt "$TIMING_BINARY" ]; then
        mkdir -p "$(dirname "$TIMING_BINARY")"
        printf 'Building OpenVR frame-timing monitor...\n'
        g++ -std=c++17 -O2 -Wall -Wextra \
            -I"$openvr_include" \
            "$TIMING_SOURCE" \
            -L"$openvr_lib" -Wl,-rpath,"$openvr_lib" -lopenvr_api \
            -o "$TIMING_BINARY"
    fi

    "$TIMING_BINARY" "$duration"
}

show_jitter() {
    local duration="${1:-10}"
    local openvr_include="$MONADO/src/external/openvr_includes"
    local openvr_lib="$STEAMVR/bin/linux64"

    pgrep -x vrserver >/dev/null || die "SteamVR is not running. Run '$0 start' first."
    require_file "$JITTER_SOURCE"
    require_file "$openvr_include/openvr.h"
    require_file "$openvr_lib/libopenvr_api.so"

    if [ ! -x "$JITTER_BINARY" ] || [ "$JITTER_SOURCE" -nt "$JITTER_BINARY" ]; then
        mkdir -p "$(dirname "$JITTER_BINARY")"
        printf 'Building OpenVR stationary-pose monitor...\n'
        g++ -std=c++17 -O2 -Wall -Wextra \
            -I"$openvr_include" \
            "$JITTER_SOURCE" \
            -L"$openvr_lib" -Wl,-rpath,"$openvr_lib" -lopenvr_api \
            -o "$JITTER_BINARY"
    fi

    "$JITTER_BINARY" "$duration"
}

manage_origin() {
    local action="${1:-status}"
    local openvr_include="$MONADO/src/external/openvr_includes"
    local openvr_lib="$STEAMVR/bin/linux64"

    pgrep -x vrserver >/dev/null || die "SteamVR is not running. Run '$0 start' first."
    require_file "$ORIGIN_SOURCE"
    require_file "$openvr_include/openvr.h"
    require_file "$openvr_lib/libopenvr_api.so"

    if [ ! -x "$ORIGIN_BINARY" ] || [ "$ORIGIN_SOURCE" -nt "$ORIGIN_BINARY" ]; then
        mkdir -p "$(dirname "$ORIGIN_BINARY")"
        printf 'Building OpenVR standing-origin tool...\n'
        g++ -std=c++17 -O2 -Wall -Wextra \
            -I"$openvr_include" \
            "$ORIGIN_SOURCE" \
            -L"$openvr_lib" -Wl,-rpath,"$openvr_lib" -lopenvr_api \
            -o "$ORIGIN_BINARY"
    fi

    shift || true
    "$ORIGIN_BINARY" "$action" "$@"
}

check_ready() {
    local expected_height="${1:-$G2_EYE_HEIGHT}"
    local -a spacecal_pids=()

    pgrep -x vrcompositor >/dev/null || die "SteamVR is not rendering. Run '$0 start' first."
    mapfile -t spacecal_pids < <(
        pgrep -f "^$SPACECAL_DRIVER/bin/linux64/space-calibrator-real( |$)" || true
    )
    if [ "${#spacecal_pids[@]}" -ne 1 ]; then
        printf 'NOT READY: expected exactly one Space Calibrator process, found %d.\n' \
            "${#spacecal_pids[@]}" >&2
        printf 'Run: %s calibrate\n' "$0" >&2
        return 1
    fi
    printf 'Space Calibrator owner: PID %s (exactly one)\n' "${spacecal_pids[0]}"
    manage_origin check "$expected_height"
}

case "${1:-start}" in
    start) start_session ;;
    start-ui) G2_CONFIRM_START=true; start_session ;;
    start-modded-ui) G2_CONFIRM_START=true G2_AUTO_PLAY_MODDED=true; start_session ;;
    steam-pipewire) restart_steam_client_pipewire ;;
    play) play_game ;;
    play-modded) launch_modded_game ;;
    stop-game) stop_modded_game ;;
    restart-modded) restart_modded_game ;;
    calibrate) start_space_calibrator ;;
    stop) stop_session ;;
    status) show_status ;;
    paths) show_paths ;;
    preflight) G2_CONTROLLER_MODE=index "$PREFLIGHT" "${2:-all}" ;;
    diagnose) show_diagnostics ;;
    nvidia)
        require_file "$NVIDIA_MANAGER"
        "$NVIDIA_MANAGER" "${2:-status}" "${3:-}"
        ;;
    tracking) show_tracking "${2:-15}" ;;
    timing) show_timing "${2:-10}" ;;
    jitter) show_jitter "${2:-10}" ;;
    ready) check_ready "${2:-$G2_EYE_HEIGHT}" ;;
    floor) set_floor "${2:-10}" ;;
    volume) manage_volume "${2:-status}" ;;
    mods) open_mod_manager ;;
    config)
        case "${2:-show}" in
            show) show_settings ;;
            set-all) save_settings "${3:-}" "${4:-}" "${5:-}" "${6:-}" "${7:-}" \
                "${8:-}" "${9:-}" "${10:-}" "${11:-}" "${12:-}" "${13:-}" "${14:-}" ;;
            *) die 'usage: config [show|set-all HEIGHT SMOOTHING ANGULAR VOLUME START-DELAY PREDICTION STRENGTH RECALL AUTOEXPOSURE UNIFY-EXPOSURE HEIGHT-RECOVERY RECOVERY-DELAY]' ;;
        esac
        ;;
    origin) shift; manage_origin "$@" ;;
    monado-runtime) select_runtime "$MONADO_RUNTIME" ;;
    steamvr-runtime) select_runtime "$STEAMVR_RUNTIME" ;;
    *)
        printf 'usage: %s [start|start-ui|start-modded-ui|steam-pipewire|calibrate|play|play-modded|restart-modded|stop-game|stop|status|paths|preflight [host|usb|all]|diagnose|nvidia [status|validate|apply|initramfs-check]|ready [eye-height]|floor [delay]|mods|config [show|set-all ...]|volume [status|mute|0..100|+N%%|-N%%]|tracking [seconds]|timing [seconds]|jitter [seconds]|origin [status|check height|identity [width depth]|set|set-now height [width depth]]|monado-runtime|steamvr-runtime]\n' "$0" >&2
        exit 2
        ;;
esac
