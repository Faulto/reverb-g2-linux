# 68 — Portability and support matrix

The goal is a reproducible setup across ordinary Linux PCs, not a claim that it
already works without issue on literally every Linux PC. Direct display,
inside-out tracking, proprietary GPU drivers, Steam packaging, and compositor
DRM leasing all have hardware-specific boundaries. The project treats an
untested combination as untested, never as implicitly supported.

## Profiles

The **supported profile** uses Project-VR Monado for the G2 display and head
tracking, native SteamVR, Lighthouse base stations, Index controllers, and
OpenVR Space Calibrator. Its three upstream repositories are pinned; both patch
series are rebuilt in CI and were reconstructed from a clean checkout locally.

The **native G2-controller profile** is currently a research archive. It has
substantial physical test evidence and several working game sessions, but
`patches/monado/` combines divergent development bases and cannot be applied in
lexical order. `bootstrap-lab.sh sources` intentionally refuses to manufacture
a tree from it. Promoting that profile requires a public pinned source branch or
bundle whose clean build and physical result can be independently reproduced.

## Maintained entry points

- `scripts/setup-index-controllers.sh` pins, patches, builds, installs, and verifies
  Monado, Basalt, and OpenVR Space Calibrator.
- `scripts/g2-preflight.sh` checks the functional USB endpoints, permissions,
  controller radios, and the applicable GPU path without assuming a DRM card or
  DisplayPort number. An NVIDIA source/patch mismatch is fatal so a package
  update cannot silently launch the known-black 90 Hz path.
- `scripts/beat-saber-index.sh` discovers Steam libraries, registered OpenVR
  drivers, logs, the G2 EDID connector, PipeWire nodes, and BSManager state.
- `scripts/g2-control-panel.sh` is the optional YAD front end.
- `scripts/nvidia-g2-patch-manager.sh` is the fail-closed NVIDIA-only patch and
  DKMS delivery path.

The older `bootstrap-lab.sh`, X11 modeset scripts, capture tools, and experiment
files document the original investigation. Some intentionally describe its
reference connectors and monitor topology; they are not the portable launcher.

## Current matrix

| Component | Status |
|---|---|
| Architecture | x86_64 required by native SteamVR/Beat Saber; other architectures unsupported |
| Arch Linux | Physically verified with Plasma Wayland, kernel 7.1, NVIDIA 610 open modules, RTX 5080 |
| Debian 13 | Earlier display/Monado lab verified with NVIDIA 595 open modules and RTX 3060 Ti; current combined installer needs a fresh community retest |
| Ubuntu | Uses the Debian dependency path; not yet physically retested |
| Fedora | Dependency names and source build path implemented; not yet physically retested |
| Other distributions | Manual dependencies are possible; package automation is not implemented |
| Native Steam | Supported and required for the maintained direct-display path |
| Flatpak Steam | Unsupported: host OpenVR driver registration and DRM leasing are not wired through this project |
| Plasma Wayland | Physically verified |
| X11 | Historical Monado/display tests worked; current mixed-driver launcher needs a fresh retest |
| Other Wayland compositors | Require DRM-lease support and a physical retest |
| NVIDIA 595.x | Patch series physically verified on Ampere |
| NVIDIA 610.x | Patch series physically verified on Blackwell, including boot-image delivery |
| Other NVIDIA families | Refused by automation until ported and physically verified |
| AMD/Intel display | Preflight and connector discovery are vendor-neutral; no physical result is recorded yet |
| Index controllers | Proven with two Watchman receivers and Lighthouse base stations |
| G2 controllers | Physically demonstrated research path; exported source lineage is not yet reproducible and tracking quality is still experimental |
| G2 v1 cable | Proven; both split hub halves are diagnosed when present |
| G2 rev2 cable | Functional endpoint checks no longer require v1 Cypress hub IDs; needs a reported physical test |

## Portability rules

The maintained scripts do not encode a username, GPU PCI address, DRM card,
DisplayPort connector, Steam library, controller serial, or PipeWire node name.
Paths can still be overridden with `G2_VR_ROOT`, `MONADO_DIR`, `BASALT_DIR`,
`STEAM_ROOT`, `STEAMVR_DIR`, `SPACECAL_DRIVER_DIR`, `BSMANAGER`, and the XDG
base-directory variables.

The setup source verifier constructs the expected final tree from each pinned
commit in a temporary clone. It accepts an existing dirty tree only when every
modified tracked file is byte-identical to the complete patch series. This is
what prevents a successful local hand edit from disappearing on a new PC.

On non-systemd desktops the launcher falls back to detached user processes for
Steam, Space Calibrator, and modded Beat Saber. That fallback is statically
checked but is not yet physically verified. The supplied device rule uses
systemd-logind's `uaccess` ACL for the active local seat; a non-systemd seat
manager needs an equivalent local device-permission policy. Reports from such
systems are especially useful.

## Public-release gates

Every public change should pass:

```bash
./scripts/check-publishable.py
shellcheck scripts/setup-index-controllers.sh scripts/beat-saber-index.sh \
  scripts/g2-preflight.sh scripts/g2-control-panel.sh \
  scripts/install-control-panel.sh scripts/nvidia-g2-patch-manager.sh \
  scripts/sync-nvidia-initramfs.sh scripts/bootstrap-lab.sh
./scripts/setup-index-controllers.sh sources
./scripts/setup-index-controllers.sh verify   # after a build
```

CI repeats the privacy/size/syntax checks, applies both supported patch series
to fresh pinned clones, and compiles the repository's maintained C/C++ tools.
The root MIT license covers original project material; upstream-derived patches
remain under their upstream licenses as mapped in `LICENSES/README.md`.

## A useful test report

Include the output of `scripts/g2-preflight.sh all`, plus:

```text
distribution and version:
kernel:
GPU and userspace/kernel driver:
desktop + X11/Wayland:
Steam packaging and SteamVR version:
G2 revision and v1/rev2 cable:
display mode and physical left/right panel result:
tracking/controller path:
```

Do not include serial numbers. If the display is black, say whether the
4320×2160 mode existed and whether SteamVR obtained a DRM lease; these identify
different failure layers.
