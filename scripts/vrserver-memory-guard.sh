#!/usr/bin/env bash
# Stop a broken SteamVR session before vrserver can exhaust system memory.

set -u

server_pid="${1:-}"
launcher="${2:-}"
requested_limit_mib="${3:-4096}"

if ! [[ "$server_pid" =~ ^[0-9]+$ ]] || [ ! -x "$launcher" ] || \
   ! [[ "$requested_limit_mib" =~ ^[0-9]+$ ]] || [ "$requested_limit_mib" -lt 1024 ]; then
    printf 'usage: %s VRSERVER_PID LAUNCHER [MAX_RSS_MIB>=1024]\n' "$0" >&2
    exit 2
fi

total_kib="$(awk '/^MemTotal:/ { print $2; exit }' /proc/meminfo 2>/dev/null)"
if ! [[ "$total_kib" =~ ^[0-9]+$ ]]; then
    total_kib=$((requested_limit_mib * 4 * 1024))
fi

# Never let one process consume more than half of physical RAM. The normal
# Monado/Basalt vrserver footprint is far below 1 GiB; 4 GiB leaves generous
# headroom while catching leaks long before the desktop starts swapping.
half_ram_mib=$((total_kib / 2048))
limit_mib="$requested_limit_mib"
if [ "$half_ram_mib" -lt "$limit_mib" ]; then
    limit_mib="$half_ram_mib"
fi
if [ "$limit_mib" -lt 1024 ]; then
    limit_mib=1024
fi
warn_mib=$((limit_mib / 2))
limit_kib=$((limit_mib * 1024))
warn_kib=$((warn_mib * 1024))
warned=0
over_limit_samples=0

printf 'Watching vrserver PID %s: warning at %s MiB, stop at %s MiB.\n' \
    "$server_pid" "$warn_mib" "$limit_mib"

while [ -r "/proc/$server_pid/status" ] && \
      [ "$(cat "/proc/$server_pid/comm" 2>/dev/null)" = vrserver ]; do
    rss_kib="$(awk '/^VmRSS:/ { print $2; exit }' "/proc/$server_pid/status" 2>/dev/null)"
    if ! [[ "$rss_kib" =~ ^[0-9]+$ ]]; then
        sleep 2
        continue
    fi

    if [ "$rss_kib" -ge "$warn_kib" ] && [ "$warned" -eq 0 ]; then
        warned=1
        printf 'WARNING: vrserver RSS reached %s MiB. It will be stopped at %s MiB.\n' \
            "$((rss_kib / 1024))" "$limit_mib"
        if command -v notify-send >/dev/null 2>&1; then
            notify-send -u critical 'Reverb G2 memory warning' \
                "vrserver is using $((rss_kib / 1024)) MiB RAM. VR will stop at ${limit_mib} MiB." \
                >/dev/null 2>&1 || true
        fi
    fi

    if [ "$rss_kib" -ge "$limit_kib" ]; then
        over_limit_samples=$((over_limit_samples + 1))
    else
        over_limit_samples=0
    fi

    # Require three samples so a short-lived allocation cannot end a session.
    if [ "$over_limit_samples" -ge 3 ]; then
        printf 'ALERT: vrserver stayed above %s MiB (now %s MiB); stopping VR to protect the host.\n' \
            "$limit_mib" "$((rss_kib / 1024))"
        if command -v notify-send >/dev/null 2>&1; then
            notify-send -u critical 'Reverb G2 stopped safely' \
                "vrserver reached $((rss_kib / 1024)) MiB RAM. Relaunch VR after it closes." \
                >/dev/null 2>&1 || true
        fi

        G2_MEMORY_GUARD_ACTIVE=true "$launcher" stop || true

        # A leaking in-process driver can make vrserver hang during shutdown.
        # Give it ten seconds to unwind, then reclaim the memory decisively.
        for _i in $(seq 1 50); do
            if [ ! -r "/proc/$server_pid/status" ] || \
               [ "$(cat "/proc/$server_pid/comm" 2>/dev/null)" != vrserver ]; then
                exit 0
            fi
            sleep 0.2
        done
        if [ "$(cat "/proc/$server_pid/comm" 2>/dev/null)" = vrserver ]; then
            printf 'ALERT: vrserver did not exit after 10 seconds; sending SIGKILL.\n'
            kill -KILL "$server_pid" 2>/dev/null || true
        fi
        exit 0
    fi

    sleep 2
done

printf 'vrserver PID %s exited; memory guard finished.\n' "$server_pid"
