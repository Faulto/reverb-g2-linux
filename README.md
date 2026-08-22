# Reverb G2 Linux

A setup and session manager for running the HP Reverb G2 on Linux.

This project turns a working G2 configuration into a repeatable workflow. It builds the
required VR stack, checks the headset before every session, starts SteamVR with the right
runtime and tracking configuration, manages the NVIDIA kernel patches needed for 90 Hz,
and provides recovery tools for the failures we encountered during real play.

The current supported controller setup is:

- HP Reverb G2 for display, audio, and head tracking
- Project-VR Monado and Basalt for the headset
- native Steam and SteamVR
- two Lighthouse base stations, two Watchman receivers, and Valve Index controllers
- OpenVR Space Calibrator to align the G2 and Lighthouse tracking spaces

Native G2 motion controllers are not part of this supported build. The earlier controller
tracking experiments remain in the original
[Wintch/reverb-g2](https://github.com/Wintch/reverb-g2) research repository.

## What the tool handles

- Installs distribution dependencies on Arch, Debian/Ubuntu, and Fedora.
- Clones pinned Monado, Basalt, and Space Calibrator revisions and applies a reproducible
  patch series.
- Registers the Monado and Space Calibrator SteamVR drivers for the current user.
- Detects Steam libraries, SteamVR, Beat Saber, the G2 display connector, PipeWire audio,
  Watchman receivers, and NVIDIA source/DKMS paths without hard-coded ports or usernames.
- Checks both halves of the G2 USB cable, the tracking cameras, control interface, audio,
  udev permissions, GPU driver, and controller receivers before starting VR.
- Patches tested NVIDIA open-kernel-module releases, rebuilds DKMS, refreshes the boot
  image, and audits the result after a driver update.
- Starts and stops SteamVR, powers the panel safely, launches Space Calibrator, sets the
  floor from a validated standing pose, and restores the preferred OpenXR runtime on exit.
- Applies tracking guards for runaway SLAM poses, height drift, unsafe room-scale movement,
  and excessive smoothing or prediction.
- Launches a BSManager-managed modded Beat Saber instance without using SteamVR's desktop
  overlay.
- Exposes the common actions and tracking settings through a desktop control panel.

## Problems and mitigations

These are the failures encountered on real hardware and the protections now built into the
supported workflow.

| Problem | What happens | Mitigation in this project |
|---|---|---|
| NVIDIA 90 Hz is black or flickers | The G2 leaves EDID color depth undefined. The tested NVIDIA drivers negotiated 6 bpc and could not drive the native mode correctly. | The version-selected series from patches `0001`–`0005` fixes the VR display path, G2 link configuration, and 8-bpc range. The patch manager validates, applies, rebuilds, and audits it. |
| Patched source but an old module still boots | A driver update or stale initramfs can leave `/usr/src`, DKMS, the loaded module, and the boot image out of sync. | The manager compares running and installed versions, rebuilds DKMS even when source is already patched, refreshes the detected boot-image system, and reports pending reboots. |
| The headset appears in `lsusb` but tracking or the display fails | The cable exposes separate USB 2 and SuperSpeed branches. One half can enumerate at only 480 Mb/s while the rest looks present. | Preflight checks every required G2 function, negotiated speed, authorization, power policy, device access, and xHCI path. Startup stops before SteamVR when a required branch is missing or slow. |
| A script works only on one GPU port or Steam library | DRM card numbers, DisplayPort connectors, Steam libraries, PipeWire nodes, and hidraw numbers change across machines and reconnects. | The launcher discovers the G2 by EDID and resolves Steam, SteamVR, audio, Watchman radios, logs, and source trees dynamically. Overrides remain available for unusual layouts. |
| Tracking initializes while the headset is on the floor | The initial Basalt world and saved SteamVR origin can start tilted, upside down, or at the wrong height. | Hardware and display checks run first. A confirmation dialog and configurable countdown then give the user time to stand at play-centre before tracking initializes. |
| Head tracking jumps, flies away, changes height, or triggers a grey screen | A bad SLAM pose can contain a discontinuity, impossible speed, non-finite value, or runaway room position. | Patched Monado rejects unsafe VIT input, holds the last safe pose, resets Basalt after sustained corruption, and enforces a 5×5 m horizontal envelope from the floor to 40 cm above standing eye height. |
| The view feels delayed or stationary text jitters | Full pose smoothing reduces noise but rotational latency can cause discomfort; no smoothing leaves visible rest jitter. | Smoothing and prediction are separate settings. The tested baseline keeps smoothing off, uses dead-reckoning motion prediction, and forwards adjustable angular velocity to SteamVR. Position-only smoothing is available without filtering rotation. |
| Floor height drifts during a session | Moderate visual-tracking error can move the HMD vertically even though Lighthouse controller space remains correct. | Every startup creates a validated standing origin. Optional still-and-level recovery glides moderate height error back toward the configured eye height without rewriting Lighthouse coordinates, and the floor can be recaptured without rebuilding the stack. |
| Index controllers track but are offset from the headset | Monado and Lighthouse use different coordinate systems, or a stale/duplicate Space Calibrator process restores the wrong transform. | The launcher starts and checks one Space Calibrator instance, preserves its profile, validates controller and floor poses, and provides a ready check before games launch. |
| One Index controller floats away or disappears | Watchman radio access, USB interference, or poor dongle placement can affect one controller while its LED remains on. | Host preflight requires two accessible receiver radios and reports missing versus permission-denied devices separately. The troubleshooting guide covers receiver separation and extension-lead placement. |
| SteamVR starts but cannot acquire the G2 display | Low VRAM, a stale compositor state, or a Wayland DRM-lease failure can leave SteamVR running without direct mode. | Startup requires the native 4320×2160 mode and confirms direct mode before continuing. It distinguishes Monado device initialization from compositor/lease failure and leaves the relevant logs visible. |
| Opening SteamVR's desktop crashes Steam | Desktop capture and Remote Play hosting triggered Steam's `CDesktopStreamT` crash on the verified machine. | The launcher starts Steam with PipeWire support, warns when Remote Play hosting is enabled, and launches the BSManager-managed game directly so the VR desktop is unnecessary. |
| Beat Saber is stuck in a map or its controllers remain on the floor | The game or Proton process can fail while SteamVR, tracking, and calibration are still healthy. | `restart-modded` restarts only the managed game, retaining SteamVR, the standing origin, and Space Calibrator state. |
| SteamVR's headset volume slider does nothing | The G2 USB codec is exposed through PipeWire but is not always controlled correctly by the dashboard. | The launcher discovers the G2 sink and changes its volume directly with `pactl`; the same controls are available from the desktop panel. |

[Troubleshooting](docs/troubleshooting.md) provides the commands and recovery sequence for
each class of failure.

## Current limits

This is not yet verified on every Linux, GPU, desktop, or G2 cable revision. The complete
playable setup has been tested on Arch Linux, Plasma Wayland, an RTX 5080, NVIDIA 610 open
modules, a G2 v1 cable, and Index controllers. The display and NVIDIA work was also tested
on Debian with an RTX 3060 Ti and NVIDIA 595 open modules.

The NVIDIA patch manager accepts only the tested 595 and 610 driver families. It refuses a
new or incompatible source layout instead of guessing. AMD and Intel display paths do not
need the NVIDIA patches, but they still require fresh hardware testing before they can be
called supported.

The tool does not install or update the NVIDIA package itself. Your distribution remains
responsible for that. After a package update, this project reapplies and rebuilds the G2
patches against the new on-disk driver when that release is supported.

See [compatibility](docs/compatibility.md) for the tested matrix and known boundaries.

## Quick start

Install native Steam and SteamVR first, launch each once, then clone this repository:

```bash
git clone https://github.com/Faulto/reverb-g2-linux.git
cd reverb-g2-linux
```

Build and register the pinned VR stack:

```bash
./scripts/setup-index-controllers.sh deps
./scripts/setup-index-controllers.sh all
sudo install -m 0644 scripts/70-wmr-reverb.rules /etc/udev/rules.d/70-wmr-reverb.rules
sudo udevadm control --reload-rules
./scripts/install-control-panel.sh
```

Reconnect the headset after installing the udev rule. NVIDIA users should then audit the
driver and apply the G2 series if required:

```bash
./scripts/nvidia-g2-patch-manager.sh status
./scripts/nvidia-g2-patch-manager.sh validate
./scripts/nvidia-g2-patch-manager.sh apply
```

The apply command requests `sudo`, backs up every changed source file under
`/var/backups/reverb-g2-nvidia`, rebuilds the kernel modules and boot image, and asks you
to reboot manually. It never reboots the machine itself.

Finish the one-time SteamVR and controller setup in the
[installation guide](docs/installation.md).

## Starting VR

Open **Reverb G2 VR Control Panel** from the desktop menu and choose **Start VR**. The
control panel keeps the hardware checks visible and begins the positioning countdown only
after they pass.

The command-line equivalent is:

```bash
./scripts/g2-preflight.sh all
./scripts/beat-saber-index.sh start-ui
```

Stand at play-centre, upright and facing the usual forward direction during the countdown.
The launcher initializes tracking, confirms SteamVR direct mode at the native
4320×2160/90 Hz mode, and saves a validated 5×5 m standing space.

For a configured BSManager instance, choose **Start VR + modded Beat Saber** or run:

```bash
./scripts/beat-saber-index.sh start-modded-ui
```

Read [using the launcher](docs/using-the-launcher.md) for calibration, floor recovery,
tracking settings, Beat Saber, audio, diagnostics, and every command.

## NVIDIA driver updates

Run the patch audit after every NVIDIA package update and before starting VR:

```bash
./scripts/beat-saber-index.sh nvidia status
```

If the installed source tree is supported but unpatched, apply it and reboot:

```bash
./scripts/beat-saber-index.sh nvidia apply
```

The manager discovers the installed and running driver versions, matching `/usr/src` tree,
DKMS module, kernel, initramfs implementation, and G2 connector dynamically. It also
detects a pending reboot when the running driver and installed module differ. Details and
recovery steps are in [NVIDIA driver management](docs/nvidia-driver.md).

## Documentation

- [Install the stack](docs/installation.md)
- [Use the control panel and launcher](docs/using-the-launcher.md)
- [Manage NVIDIA patches and driver updates](docs/nvidia-driver.md)
- [Troubleshoot startup, display, USB, tracking, and games](docs/troubleshooting.md)
- [Check compatibility and tested hardware](docs/compatibility.md)

## Repository layout

```text
scripts/             setup, preflight, launcher, control panel, and diagnostics
patches/monado-wmr/  reproducible Project-VR Monado fixes and tracking mitigations
patches/basalt-wmr/  Basalt runtime control used by the launcher
patches/nvidia/      tested NVIDIA open-kernel-module patches for G2 90 Hz
docs/                user and maintainer documentation
LICENSES/            licenses for incorporated upstream patch material
```

## Safety and verification

A successful modeset or reported frame rate does not prove that both panels are lit and
stable. Verify display changes while wearing the headset. Stop immediately if a test mode
flickers badly or causes discomfort.

The NVIDIA workflow modifies kernel-module source and the boot image. Keep a fallback
kernel or another bootable entry. The patch manager validates on temporary copies and
creates backups, but it cannot make an untested driver release safe.

## Credits

The working stack builds on [Project-VR](https://github.com/AshishKumar4/Project-VR),
[Monado](https://monado.dev/), [Basalt](https://gitlab.com/VladyslavUsenko/basalt), and
[OpenVR Space Calibrator for Linux](https://github.com/xi-ve/openvr-space-calibrator-linux).
See [LICENSES/README.md](LICENSES/README.md) for the license boundaries.

Contributions should include the exact distribution, kernel, GPU and driver, desktop
session, cable revision, controller setup, and physical result. See
[CONTRIBUTING.md](CONTRIBUTING.md).
