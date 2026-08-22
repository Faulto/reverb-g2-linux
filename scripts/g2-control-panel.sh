#!/bin/bash
# Small YAD front-end for the reproducible G2 + Index controller launcher.

set -uo pipefail

SCRIPT_PATH="$(readlink -f "${BASH_SOURCE[0]}")"
REPO="$(cd "$(dirname "$SCRIPT_PATH")/.." && pwd)"
LAUNCHER="$REPO/scripts/beat-saber-index.sh"
SETTINGS_FILE="${XDG_CONFIG_HOME:-$HOME/.config}/reverb-g2/session.conf"

command -v yad >/dev/null 2>&1 || {
    printf 'This control panel needs yad (installed package: yad).\n' >&2
    exit 1
}

setting() {
    local wanted="$1" fallback="$2" key value
    if [ -r "$SETTINGS_FILE" ]; then
        while IFS='=' read -r key value; do
            [ "$key" = "$wanted" ] && { printf '%s\n' "$value"; return; }
        done < "$SETTINGS_FILE"
    fi
    printf '%s\n' "$fallback"
}

terminal_run() {
    local quoted
    if command -v konsole >/dev/null 2>&1; then
        nohup konsole --hold -e "$LAUNCHER" "$@" >/dev/null 2>&1 &
    elif command -v gnome-terminal >/dev/null 2>&1; then
        printf -v quoted '%q ' "$LAUNCHER" "$@"
        nohup gnome-terminal -- bash -lc \
            "${quoted}; result=\$?; printf '\\nExit status: %s. Press Enter to close.\\n' \"\$result\"; read -r; exit \"\$result\"" \
            >/dev/null 2>&1 &
    elif command -v kitty >/dev/null 2>&1; then
        nohup kitty --hold "$LAUNCHER" "$@" >/dev/null 2>&1 &
    elif command -v foot >/dev/null 2>&1; then
        nohup foot --hold "$LAUNCHER" "$@" >/dev/null 2>&1 &
    elif command -v xterm >/dev/null 2>&1; then
        nohup xterm -hold -e "$LAUNCHER" "$@" >/dev/null 2>&1 &
    else
        "$LAUNCHER" "$@"
    fi
}

edit_settings() {
    local height smoothing prediction angular strength recall autoexposure unify_exposure
    local height_recovery recovery_delay volume start_delay
    local smoothing_label prediction_label recall_label result output
    height="$(setting G2_EYE_HEIGHT 1.77)"
    smoothing="$(setting G2_SMOOTHING off)"
    prediction="$(setting G2_PREDICTION_MODE dead-reckoning)"
    angular="$(setting G2_ANGULAR_PREDICTION true)"
    strength="$(setting G2_ANGULAR_PREDICTION_STRENGTH 100)"
    recall="$(setting G2_FEATURE_RECALL front)"
    autoexposure="$(setting G2_CAMERA_AUTOEXPOSURE true)"
    unify_exposure="$(setting G2_CAMERA_UNIFY_EXPOSURE false)"
    height_recovery="$(setting G2_HEIGHT_RECOVERY true)"
    recovery_delay="$(setting G2_HEIGHT_RECOVERY_DELAY 8)"
    volume="$(setting G2_AUDIO_VOLUME 65)"
    start_delay="$(setting G2_START_DELAY 10)"
    case "$smoothing" in
        position-light) smoothing_label='Light position — less jitter, very little lag' ;;
        position) smoothing_label='Standard position — smoother translation' ;;
        full) smoothing_label='Full experimental — also filters rotation' ;;
        *) smoothing_label='Off — sharpest and lowest latency' ;;
    esac
    case "$prediction" in
        none) prediction_label='None — diagnostic, highest latency' ;;
        pose-only) prediction_label='Pose only — uses recent visual poses' ;;
        gyro) prediction_label='Gyro only — less translation prediction; drifted in G2 test' ;;
        accel-gyro) prediction_label='Accel + gyro — intermediate IMU prediction' ;;
        *) prediction_label='Dead reckoning — recommended G2 setting' ;;
    esac
    case "$recall" in
        front) recall_label='Front camera — tested default, moderate cost' ;;
        all) recall_label='All cameras — experimental, high CPU/memory' ;;
        *) recall_label='Off — lower resource use' ;;
    esac

    result="$(yad --title='Reverb G2 tracking and session settings' --width=840 --height=790 --form \
        --text='All tracking changes take effect on the next SteamVR start and are reversible here.\n\nChange one control at a time. Dead reckoning and front-camera landmark recall are the tested defaults. Full smoothing and all-camera recall are experimental.' \
        --field='Standing eye height in metres:NUM' "$height!1.00..2.50!0.01!2" \
        --field='Smoothing — position presets do not delay rotation:CB' "$smoothing_label!Off — sharpest and lowest latency!Light position — less jitter, very little lag!Standard position — smoother translation!Full experimental — also filters rotation" \
        --field='SLAM prediction — how Monado advances the last Basalt pose:CB' "$prediction_label!Dead reckoning — recommended G2 setting!Gyro only — less translation prediction; drifted in G2 test!Accel + gyro — intermediate IMU prediction!Pose only — uses recent visual poses!None — diagnostic, highest latency" \
        --field='Let SteamVR predict rotation to photon time:CHK' "$angular" \
        --field='SteamVR angular prediction strength (100 = current):NUM' "$strength!0..150!5!0" \
        --field='Basalt landmark recall — may reduce drift/relocalisation:CB' "$recall_label!Front camera — tested default, moderate cost!Off — lower resource use!All cameras — experimental, high CPU/memory" \
        --field='Camera auto-exposure — keep on unless testing lighting:CHK' "$autoexposure" \
        --field='Use one exposure for all four cameras — experimental:CHK' "$unify_exposure" \
        --field='Recover false height drift while upright — avoids mild-drift grey screens:CHK' "$height_recovery" \
        --field='Seconds continuously still and level before height recovery:NUM' "$recovery_delay!3..30!1!0" \
        --field='Headset volume at start:NUM' "$volume!0..100!1!0" \
        --field='Positioning countdown before tracking:NUM' "$start_delay!0..60!1!0" \
        --button='Cancel:1' --button='Save:0')" || return 0
    IFS='|' read -r height smoothing_label prediction_label angular strength recall_label \
        autoexposure unify_exposure height_recovery recovery_delay volume start_delay _rest <<< "$result"
    case "$smoothing_label" in
        'Light position'* ) smoothing=position-light ;;
        'Standard position'* ) smoothing=position ;;
        'Full experimental'* ) smoothing=full ;;
        *) smoothing=off ;;
    esac
    case "$prediction_label" in
        'None'* ) prediction=none ;;
        'Pose only'* ) prediction=pose-only ;;
        'Gyro only'* ) prediction=gyro ;;
        'Accel + gyro'* ) prediction=accel-gyro ;;
        *) prediction=dead-reckoning ;;
    esac
    case "$recall_label" in
        'Front camera'* ) recall=front ;;
        'All cameras'* ) recall=all ;;
        *) recall=off ;;
    esac
    angular="${angular,,}"
    autoexposure="${autoexposure,,}"
    unify_exposure="${unify_exposure,,}"
    height_recovery="${height_recovery,,}"
    height="${height/,/.}"
    strength="${strength%%.*}"
    recovery_delay="${recovery_delay%%.*}"
    volume="${volume%%.*}"
    start_delay="${start_delay%%.*}"
    if output="$($LAUNCHER config set-all "$height" "$smoothing" "$angular" "$volume" \
        "$start_delay" "$prediction" "$strength" "$recall" "$autoexposure" "$unify_exposure" \
        "$height_recovery" "$recovery_delay" 2>&1)"; then
        yad --info --title='Settings saved' --text="$output" --button='OK:0'
    else
        yad --error --title='Invalid settings' --text="$output" --button='OK:0'
    fi
}

while true; do
    choice="$(yad --title='Reverb G2 + Index Control Panel' --width=760 --height=520 \
        --list --no-headers --column='Action' --column='Purpose' --print-column=1 \
        'Hardware check' 'Explain USB negotiation, NVIDIA, permissions, and Watchman failures' \
        'Start VR' 'Check the G2, start SteamVR, validate/set the floor, then start Space Calibrator' \
        'Start VR + modded Beat Saber' "Run checked startup with automatic floor setup, then launch BSManager's last managed version" \
        'Restart modded Beat Saber' 'Recover from a stuck map without recalibrating or restarting SteamVR' \
        'Stop Beat Saber only' 'Close the game while leaving the headset, tracking and SteamVR active' \
        'Ready check' 'Verify one calibrator and sensible floor/controller poses' \
        'Set floor again (10 s)' 'Redo the automatic floor if needed; stand at play-centre during the countdown' \
        'Beat Saber mods' 'Open BSManager for version-matched mods, maps, and game versions' \
        'NVIDIA patch status' 'Match the loaded driver to its source tree and audit every required G2 patch' \
        'Patch NVIDIA driver' 'Validate, patch and rebuild the matching open driver (sudo and reboot required)' \
        'Boot-image check' 'Compare the on-disk and embedded nvidia-modeset modules where supported' \
        'Tracking jitter test' 'Measure the stationary headset pose for 10 seconds' \
        'Headset volume' 'Open the normal KDE audio controls' \
        'Settings' 'Tune prediction, smoothing, feature recall, exposure, automatic height recovery and session options' \
        'Diagnostics' 'Show full hardware state and recent VR errors' \
        'Stop VR' 'Stop SteamVR/calibrator, power off the panel, restore Monado OpenXR' \
        --button='Close:1' --button='Run:0')" || exit 0
    choice="${choice%%|*}"
    case "$choice" in
        'Hardware check') terminal_run preflight all ;;
        'Start VR') terminal_run start-ui ;;
        'Start VR + modded Beat Saber') terminal_run start-modded-ui ;;
        'Restart modded Beat Saber') terminal_run restart-modded ;;
        'Stop Beat Saber only') terminal_run stop-game ;;
        'Ready check') terminal_run ready ;;
        'Set floor again (10 s)') terminal_run floor 10 ;;
        'Beat Saber mods')
            if output="$($LAUNCHER mods 2>&1)"; then
                path_info="$($LAUNCHER paths 2>&1)"
                yad --info --title='BSManager first-run paths' \
                    --text="$path_info\n\nUse a Beat Saber version for which BSManager offers verified Core mods. Keep a separate managed copy so Steam updates cannot overwrite it. Once it is selected as BSManager’s last-launched version, use Start VR + modded Beat Saber in this panel." \
                    --button='OK:0'
            else
                yad --error --title='BSManager could not start' --text="$output" --button='OK:0'
            fi
            ;;
        'NVIDIA patch status') terminal_run nvidia status ;;
        'Patch NVIDIA driver')
            if yad --image=dialog-question --title='Patch NVIDIA open driver?' \
                --text='This will resolve the source tree matching the installed/on-disk NVIDIA version (or the loaded version when they match), validate the full G2 patch series on temporary copies, modify /usr/src only if every patch is compatible, rebuild DKMS and refresh the initramfs. It will ask for sudo and will not reboot automatically. Continue?' \
                --button='Cancel:1' --button='Continue:0'; then
                terminal_run nvidia apply
            fi
            ;;
        'Boot-image check') terminal_run nvidia initramfs-check ;;
        'Tracking jitter test') terminal_run jitter 10 ;;
        'Headset volume')
            if command -v plasmawindowed >/dev/null 2>&1; then
                nohup plasmawindowed org.kde.plasma.volume >/dev/null 2>&1 &
            else
                terminal_run volume status
            fi
            ;;
        'Settings') edit_settings ;;
        'Diagnostics') terminal_run diagnose ;;
        'Stop VR') terminal_run stop ;;
    esac
done
