#!/usr/bin/env bash
# Reproducibly build the G2 SteamVR/OpenXR stack from pinned upstream commits.
#
#   setup-index-controllers.sh deps       install distribution build dependencies
#   setup-index-controllers.sh sources    clone, pin, and apply the tracked patches
#   setup-index-controllers.sh build      build Basalt, Monado, and Space Calibrator
#   setup-index-controllers.sh install    register the runtimes/drivers for this user
#   setup-index-controllers.sh verify     verify sources and expected build artifacts
#   setup-index-controllers.sh all        sources + build + install + verify (default)

set -euo pipefail

REPO="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
VR_ROOT="${G2_VR_ROOT:-$HOME/vr}"
MONADO="${MONADO_DIR:-$VR_ROOT/monado-wmr}"
BASALT="${BASALT_DIR:-$VR_ROOT/basalt-wmr}"
SPACECAL_SOURCE="${SPACECAL_SOURCE_DIR:-$VR_ROOT/openvr-space-calibrator-linux}"

# These are the exact revisions used by the physically verified setup. Updating
# one is an explicit compatibility change: refresh and retest the patch series.
MONADO_URL="https://github.com/AshishKumar4/monado-wmr.git"
MONADO_COMMIT="9893ba4cb0dabe45e2383c2270fa0f3d4ed79ab2"
BASALT_URL="https://gitlab.freedesktop.org/mateosss/basalt.git"
BASALT_COMMIT="df6e970c8da7636eb401a09e3317fbeaaf829b9a"
SPACECAL_URL="https://github.com/xi-ve/openvr-space-calibrator-linux.git"
SPACECAL_COMMIT="28e3f83f7bc9808f145fac03ff8a8e455ab211fe"

ACTION="${1:-all}"

die() {
    printf 'ERROR: %s\n' "$*" >&2
    exit 1
}

need_command() {
    command -v "$1" >/dev/null 2>&1 || die "missing required command: $1"
}

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
    root="$(find_steam_root)" || return 1
    if [ -f "$root/steamapps/appmanifest_${app_id}.acf" ]; then
        printf '%s\n' "$root"
        return 0
    fi
    vdf="$root/config/libraryfolders.vdf"
    [ -r "$vdf" ] || return 1
    while IFS= read -r library; do
        library="${library//\\\\/\\}"
        if [ -f "$library/steamapps/appmanifest_${app_id}.acf" ]; then
            readlink -f "$library"
            return 0
        fi
    done < <(awk -F'"' '/^[[:space:]]*"path"/ { print $4 }' "$vdf")
    return 1
}

find_steamvr() {
    local library
    library="$(steam_library_for_app 250820)" || return 1
    printf '%s/steamapps/common/SteamVR\n' "$library"
}

install_dependencies() {
    local -a packages=()
    if command -v pacman >/dev/null 2>&1; then
        packages=(
            base-devel cmake ninja git pkgconf ripgrep usbutils yad libpulse
            eigen boost opencv tbb fmt sqlite libusb hidapi bluez-libs systemd
            vulkan-headers vulkan-icd-loader glslang libdrm
            wayland wayland-protocols libx11 libxcb libxrandr libxxf86vm
            glfw mesa libxinerama libxcursor libxi libxkbcommon libepoxy
            sdl2-compat gstreamer gst-plugins-base-libs libjpeg-turbo
        )
        printf 'Installing Arch Linux build dependencies...\n'
        sudo pacman -S --needed "${packages[@]}"
    elif command -v apt-get >/dev/null 2>&1; then
        packages=(
            build-essential cmake ninja-build git pkg-config ripgrep usbutils yad pulseaudio-utils
            libeigen3-dev libboost-all-dev libopencv-dev libtbb-dev libfmt-dev libsqlite3-dev
            libusb-1.0-0-dev libudev-dev libhidapi-dev libbluetooth-dev libuvc-dev
            libvulkan-dev glslang-tools libdrm-dev libsdl2-dev
            libgstreamer1.0-dev libgstreamer-plugins-base1.0-dev libjpeg-dev
            libepoxy-dev libxkbcommon-dev libdbus-1-dev libsystemd-dev
            libwayland-dev wayland-protocols libx11-dev libx11-xcb-dev
            libxcb-randr0-dev libxrandr-dev libxxf86vm-dev
            libglfw3-dev libgl1-mesa-dev libxinerama-dev libxcursor-dev libxi-dev
        )
        printf 'Installing Debian/Ubuntu build dependencies...\n'
        sudo apt-get update
        sudo apt-get install -y "${packages[@]}"
    elif command -v dnf >/dev/null 2>&1; then
        packages=(
            gcc gcc-c++ make cmake ninja-build git pkgconf-pkg-config ripgrep usbutils yad pulseaudio-utils
            eigen3-devel boost-devel opencv-devel tbb-devel fmt-devel sqlite-devel
            libusb1-devel hidapi-devel bluez-libs-devel libuvc-devel systemd-devel
            vulkan-headers vulkan-loader-devel glslang-devel libdrm-devel sdl2-compat-devel
            gstreamer1-devel gstreamer1-plugins-base-devel libjpeg-turbo-devel
            libepoxy-devel libxkbcommon-devel dbus-devel
            wayland-devel wayland-protocols-devel libX11-devel libX11-xcb
            libxcb-devel libXrandr-devel libXxf86vm-devel
            glfw-devel mesa-libGL-devel libXinerama-devel libXcursor-devel libXi-devel
        )
        printf 'Installing Fedora build dependencies...\n'
        sudo dnf install -y "${packages[@]}"
    else
        die 'unsupported package manager; install equivalent dependencies manually, then run the sources step (see docs/compatibility.md)'
    fi
}

ensure_checkout() {
    local name="$1" url="$2" directory="$3" commit="$4" actual remote
    if [ ! -d "$directory/.git" ]; then
        printf 'Cloning %s...\n' "$name"
        git clone "$url" "$directory"
    fi
    actual="$(git -C "$directory" rev-parse HEAD 2>/dev/null || true)"
    if [ "$actual" != "$commit" ]; then
        if [ -n "$(git -C "$directory" status --porcelain --untracked-files=no)" ]; then
            die "$name at $directory has local source changes and is on $actual, not pinned $commit; move it aside or reconcile it manually"
        fi
        remote="$(git -C "$directory" remote get-url origin 2>/dev/null || true)"
        [ -n "$remote" ] || git -C "$directory" remote add origin "$url"
        printf 'Fetching pinned %s revision %s...\n' "$name" "${commit:0:12}"
        git -C "$directory" fetch --no-tags origin "$commit"
        git -C "$directory" checkout --detach "$commit"
    fi
}

# Build the expected final source in a disposable clone. A clean source tree is
# patched in place; an existing dirty tree is accepted only when every modified
# tracked file is byte-for-byte identical to that expected final tree. This
# prevents an old hand edit from silently becoming part of a public build.
apply_verified_series() {
    local name="$1" directory="$2" patch_directory="$3"
    local work expected actual_paths expected_paths path untracked_paths
    local -a patches=()

    mapfile -d '' -t patches < <(find "$patch_directory" -maxdepth 1 -type f -name '*.patch' \
        -print0 | LC_ALL=C sort -z)
    [ "${#patches[@]}" -gt 0 ] || die "no $name patches found in: $patch_directory"

    work="$(mktemp -d -t reverb-g2-source-check.XXXXXX)"
    expected="$work/source"
    git clone --quiet --no-local "$directory" "$expected"
    for path in "${patches[@]}"; do
        git -C "$expected" apply --check "$path" || {
            rm -rf -- "$work"
            die "$(basename "$path") does not apply to the pinned $name revision"
        }
        git -C "$expected" apply "$path"
    done

    actual_paths="$(git -C "$directory" diff --name-only | LC_ALL=C sort)"
    expected_paths="$(git -C "$expected" diff --name-only | LC_ALL=C sort)"
    untracked_paths="$(git -C "$directory" status --porcelain --untracked-files=normal | \
        sed -n 's/^?? //p')"
    if [ -n "$untracked_paths" ]; then
        rm -rf -- "$work"
        printf 'Untracked files in %s source:\n%s\n' "$name" "$untracked_paths" >&2
        die "$name has untracked source files; move them aside before a reproducible build"
    fi
    if [ -z "$actual_paths" ]; then
        for path in "${patches[@]}"; do
            git -C "$directory" apply "$path"
            printf 'Applied %s patch: %s\n' "$name" "$(basename "$path")"
        done
    elif [ "$actual_paths" = "$expected_paths" ]; then
        while IFS= read -r path; do
            [ -n "$path" ] || continue
            cmp -s "$directory/$path" "$expected/$path" || {
                rm -rf -- "$work"
                die "$name has an untracked hand edit in $path; refusing a non-reproducible build"
            }
        done <<< "$expected_paths"
        printf '%s source already matches the complete tracked patch series.\n' "$name"
    else
        rm -rf -- "$work"
        printf 'Expected modified %s files:\n%s\n' "$name" "$expected_paths" >&2
        printf 'Actually modified %s files:\n%s\n' "$name" "$actual_paths" >&2
        die "$name source does not match either the clean pin or the complete patch series"
    fi
    rm -rf -- "$work"
}

update_pinned_submodules() {
    local name="$1" directory="$2" jobs
    jobs="$(nproc 2>/dev/null || printf 2)"
    if ! git -C "$directory" submodule update --init --recursive --depth 1 --jobs "$jobs"; then
        printf 'A pinned %s submodule was unavailable as a shallow fetch; retrying the full history.\n' "$name" >&2
        git -C "$directory" submodule update --init --recursive --jobs "$jobs"
    fi
}

prepare_sources() {
    need_command git
    need_command cmp
    mkdir -p "$VR_ROOT"

    ensure_checkout Monado "$MONADO_URL" "$MONADO" "$MONADO_COMMIT"
    apply_verified_series Monado "$MONADO" "$REPO/patches/monado-wmr"

    ensure_checkout Basalt "$BASALT_URL" "$BASALT" "$BASALT_COMMIT"
    update_pinned_submodules Basalt "$BASALT"
    apply_verified_series Basalt "$BASALT" "$REPO/patches/basalt-wmr"

    ensure_checkout 'OpenVR Space Calibrator' "$SPACECAL_URL" "$SPACECAL_SOURCE" "$SPACECAL_COMMIT"
    update_pinned_submodules 'OpenVR Space Calibrator' "$SPACECAL_SOURCE"
}

build_sources() {
    local steamvr
    for command_name in cmake ninja git; do
        need_command "$command_name"
    done
    [ -d "$MONADO/.git" ] || die "Monado source is missing; run '$0 sources' first"
    [ -d "$BASALT/.git" ] || die "Basalt source is missing; run '$0 sources' first"
    [ -d "$SPACECAL_SOURCE/.git" ] || die "Space Calibrator source is missing; run '$0 sources' first"
    steamvr="${STEAMVR_DIR:-$(find_steamvr 2>/dev/null || true)}"
    [ -n "$steamvr" ] && [ -f "$steamvr/bin/linux64/libopenvr_api.so" ] || \
        die 'native SteamVR was not found; install it with Steam or set STEAMVR_DIR'
    [ -f "$MONADO/src/external/openvr_includes/openvr.h" ] || \
        die 'the pinned Monado source does not contain its OpenVR headers'

    printf '=== building Basalt visual-inertial tracker ===\n'
    cmake --preset library -S "$BASALT"
    cmake --build "$BASALT/build" --parallel

    printf '=== building Project-VR Monado ===\n'
    cmake -S "$MONADO" -B "$MONADO/build" -G Ninja \
        -DCMAKE_BUILD_TYPE=RelWithDebInfo \
        -DCMAKE_INSTALL_PREFIX="$HOME/.local" \
        -DBUILD_TESTING=OFF \
        -DXRT_FEATURE_SERVICE=ON \
        -DXRT_FEATURE_SLAM=ON \
        -DXRT_FEATURE_STEAMVR_PLUGIN=ON \
        -DXRT_BUILD_DRIVER_WMR=ON \
        -DXRT_HAVE_WAYLAND=ON \
        -DXRT_HAVE_WAYLAND_DIRECT=ON
    cmake --build "$MONADO/build" --parallel --target monado-service openxr_monado driver_monado

    for cache_entry in \
        'XRT_FEATURE_SLAM:BOOL=ON' \
        'XRT_FEATURE_STEAMVR_PLUGIN:BOOL=ON' \
        'XRT_BUILD_DRIVER_WMR:BOOL=ON' \
        'XRT_HAVE_WAYLAND_DIRECT:BOOL=ON'; do
        grep -qx "$cache_entry" "$MONADO/build/CMakeCache.txt" || \
            die "Monado configured without required feature: $cache_entry"
    done

    printf '=== building OpenVR Space Calibrator ===\n'
    cmake -S "$SPACECAL_SOURCE" -B "$SPACECAL_SOURCE/build" \
        -DCMAKE_BUILD_TYPE=Release \
        -DOPENVR_INCLUDE_DIR="$MONADO/src/external/openvr_includes" \
        -DOPENVR_LIB_DIR="$steamvr/bin/linux64"
    cmake --build "$SPACECAL_SOURCE/build" --parallel
}

install_user_stack() {
    local steamvr vrpathreg active_dir active_runtime spacecal_driver spacecal_bin
    steamvr="${STEAMVR_DIR:-$(find_steamvr 2>/dev/null || true)}"
    [ -n "$steamvr" ] || die 'native SteamVR was not found; install it or set STEAMVR_DIR'
    vrpathreg="$steamvr/bin/vrpathreg.sh"
    [ -x "$vrpathreg" ] || die "SteamVR vrpathreg is missing: $vrpathreg"

    active_dir="${XDG_CONFIG_HOME:-$HOME/.config}/openxr/1"
    active_runtime="$active_dir/active_runtime.json"
    mkdir -p "$active_dir"
    if [ -e "$active_runtime" ] && [ ! -L "$active_runtime" ]; then
        die "$active_runtime exists and is not a symlink; refusing to overwrite it"
    fi
    ln -sfn "$MONADO/build/openxr_monado-dev.json" "$active_runtime"

    "$vrpathreg" adddriver "$MONADO/build/steamvr-monado" >/dev/null 2>&1 || true

    spacecal_driver="${SPACECAL_DRIVER_DIR:-${XDG_DATA_HOME:-$HOME/.local/share}/SteamVR/drivers/01spacecalibrator}"
    spacecal_bin="$spacecal_driver/bin/linux64"
    mkdir -p "$spacecal_bin"
    install -m 0755 "$SPACECAL_SOURCE/build/lib/driver_01spacecalibrator.so" \
        "$spacecal_bin/driver_01spacecalibrator.so"
    install -m 0755 "$SPACECAL_SOURCE/build/bin/space-calibrator" \
        "$spacecal_bin/space-calibrator-real"
    install -m 0644 "$SPACECAL_SOURCE/build/actions.json" "$spacecal_bin/actions.json"
    install -m 0644 "$SPACECAL_SOURCE/build/manifest.vrmanifest" "$spacecal_bin/manifest.vrmanifest"
    install -m 0644 "$SPACECAL_SOURCE/driver_01spacecalibrator/driver.vrdrivermanifest" \
        "$spacecal_driver/driver.vrdrivermanifest"
    mkdir -p "$spacecal_driver/resources"
    cp -a "$SPACECAL_SOURCE/driver_01spacecalibrator/resources/." "$spacecal_driver/resources/"

    # The overlay is intentionally wrapped rather than relying on a distribution
    # OpenVR package. SteamVR supplies the ABI-matched libopenvr_api.so.
    # shellcheck disable=SC2016 # these expressions belong to the generated wrapper
    printf '%s\n' \
        '#!/usr/bin/env bash' \
        'set -e' \
        'script_dir="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"' \
        "steamvr_lib=$(printf '%q' "$steamvr/bin/linux64")" \
        'export LD_LIBRARY_PATH="$script_dir:$steamvr_lib${LD_LIBRARY_PATH:+:$LD_LIBRARY_PATH}"' \
        'exec "$script_dir/space-calibrator-real" "$@"' \
        > "$spacecal_bin/space-calibrator"
    chmod 0755 "$spacecal_bin/space-calibrator"
    "$vrpathreg" adddriver "$spacecal_driver" >/dev/null 2>&1 || true

    printf 'User stack installed.\n'
    printf '  OpenXR: %s -> %s\n' "$active_runtime" "$MONADO/build/openxr_monado-dev.json"
    printf '  Monado SteamVR driver: %s\n' "$MONADO/build/steamvr-monado"
    printf '  Space Calibrator driver: %s\n' "$spacecal_driver"
    printf '\nInstall the G2 udev rule once, then reconnect the headset:\n'
    printf '  sudo install -m 0644 %q /etc/udev/rules.d/70-wmr-reverb.rules\n' "$REPO/scripts/70-wmr-reverb.rules"
    printf '  sudo udevadm control --reload-rules\n'
}

verify_stack() {
    local artifact steamvr
    prepare_sources
    steamvr="${STEAMVR_DIR:-$(find_steamvr 2>/dev/null || true)}"
    [ -n "$steamvr" ] || die 'native SteamVR was not found'
    for artifact in \
        "$BASALT/build/libbasalt.so" \
        "$MONADO/build/src/xrt/targets/service/monado-service" \
        "$MONADO/build/openxr_monado-dev.json" \
        "$MONADO/build/steamvr-monado/bin/linux64/driver_monado.so" \
        "$SPACECAL_SOURCE/build/lib/driver_01spacecalibrator.so" \
        "$SPACECAL_SOURCE/build/bin/space-calibrator"; do
        [ -e "$artifact" ] || die "expected build artifact is missing: $artifact"
    done
    printf 'Verified pinned sources and all required build artifacts.\n'
    printf '  Monado: %s\n' "$MONADO_COMMIT"
    printf '  Basalt: %s\n' "$BASALT_COMMIT"
    printf '  Space Calibrator: %s\n' "$SPACECAL_COMMIT"
}

case "$ACTION" in
    deps) install_dependencies ;;
    sources) prepare_sources ;;
    build) build_sources ;;
    install) install_user_stack ;;
    verify) verify_stack ;;
    all)
        prepare_sources
        build_sources
        install_user_stack
        verify_stack
        ;;
    -h|--help|help)
        sed -n '2,9p' "$0" | sed 's/^# \{0,1\}//'
        ;;
    *)
        die 'usage: setup-index-controllers.sh [deps|sources|build|install|verify|all]'
        ;;
esac
