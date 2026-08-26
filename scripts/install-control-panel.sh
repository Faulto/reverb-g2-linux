#!/bin/bash
# Install portable user-level launchers for the checkout containing this file.

set -euo pipefail

REPO="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
BIN_DIR="${XDG_BIN_HOME:-$HOME/.local/bin}"
APP_DIR="${XDG_DATA_HOME:-$HOME/.local/share}/applications"

mkdir -p "$BIN_DIR" "$APP_DIR"
ln -sfn "$REPO/scripts/g2-control-panel.sh" "$BIN_DIR/reverb-g2-control-panel"
ln -sfn "$REPO/scripts/vr-overlay-action.sh" "$BIN_DIR/reverb-g2-vr-action"
desktop_tmp="$(mktemp "$APP_DIR/reverb-g2-control-panel.desktop.XXXXXX")"
awk -v executable="$BIN_DIR/reverb-g2-control-panel" \
    '{ gsub(/@CONTROL_PANEL@/, executable); print }' \
    "$REPO/reverb-g2-control-panel.desktop" > "$desktop_tmp"
chmod 0644 "$desktop_tmp"
mv -f "$desktop_tmp" "$APP_DIR/reverb-g2-control-panel.desktop"

if command -v update-desktop-database >/dev/null 2>&1; then
    update-desktop-database "$APP_DIR" >/dev/null 2>&1 || true
fi
if command -v kbuildsycoca6 >/dev/null 2>&1; then
    kbuildsycoca6 --noincremental >/dev/null 2>&1 || true
fi

printf 'Installed: %s\n' "$BIN_DIR/reverb-g2-control-panel"
printf 'VR overlay helper: %s\n' "$BIN_DIR/reverb-g2-vr-action"
printf 'Desktop entry: %s\n' "$APP_DIR/reverb-g2-control-panel.desktop"
printf 'Resolved checkout: %s\n' "$REPO"
