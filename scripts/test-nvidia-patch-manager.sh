#!/usr/bin/env bash
# Exercise DKMS rebuild ordering without touching system drivers or needing root.
set -euo pipefail

script_dir="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
# shellcheck source=scripts/nvidia-g2-patch-manager.sh
source "$script_dir/nvidia-g2-patch-manager.sh"
KERNEL_VERSION=test-kernel
calls=()
build_result=0
install_result=0

dkms() {
    calls+=("$*")
    case "$1" in
        build) return "$build_result" ;;
        install) return "$install_result" ;;
        *) return 99 ;;
    esac
}

rebuild_dkms_module nvidia/test-version
[[ "${calls[*]}" = 'build --force nvidia/test-version -k test-kernel install --force nvidia/test-version -k test-kernel' ]]
printf 'PASS: force compilation before installation, including an existing cached build\n'

calls=()
build_result=1
if rebuild_dkms_module nvidia/test-version; then
    printf 'FAIL: a failed build was accepted\n' >&2
    exit 1
fi
[[ "${calls[*]}" = 'build --force nvidia/test-version -k test-kernel' ]]
printf 'PASS: a failed build never installs a stale cached binary\n'

calls=()
build_result=0
install_result=1
if rebuild_dkms_module nvidia/test-version; then
    printf 'FAIL: a failed installation was accepted\n' >&2
    exit 1
fi
[[ "${#calls[@]}" = 2 ]]
printf 'PASS: installation errors propagate to the caller\n'
