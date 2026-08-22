# Installation

This guide installs the supported G2, SteamVR, Lighthouse, and Index-controller stack.
Envision and xrizer are not used by this profile.

## Before you begin

You need:

- an HP Reverb G2 with DisplayPort and every USB function connected;
- native Steam and SteamVR, launched at least once;
- two Lighthouse base stations;
- two Index controllers;
- two Watchman receiver radios, one per controller; and
- a well-lit play area with visible texture for the G2 tracking cameras.

The supported NVIDIA path also needs the open kernel module, its matching source under
`/usr/src`, DKMS, and a 595.x or 610.x driver. Do not apply this repository's patches to
the proprietary NVIDIA kernel module.

## 1. Build the pinned stack

```bash
./scripts/setup-index-controllers.sh deps
./scripts/setup-index-controllers.sh all
```

The first command installs build dependencies using `pacman`, `apt`, or `dnf`. The second
command clones exact Monado, Basalt, and Space Calibrator commits under `~/vr`, applies the
tracked patch series, builds them, and registers the resulting user-level drivers.

Set `G2_VR_ROOT` if you want the source and build trees elsewhere:

```bash
G2_VR_ROOT=/path/to/vr ./scripts/setup-index-controllers.sh all
```

The setup script accepts existing source trees only when they exactly match either the clean
pin or the complete patch series. It refuses unexplained edits instead of overwriting them.

## 2. Install device permissions

```bash
sudo install -m 0644 scripts/70-wmr-reverb.rules /etc/udev/rules.d/70-wmr-reverb.rules
sudo udevadm control --reload-rules
```

Reconnect the G2 afterward. The active desktop user needs a fresh `uaccess` ACL before
Monado can open the tracking-camera interface.

Your distribution's Steam/Valve udev package must also grant access to both Watchman
receivers. The preflight reports separately whether each radio is missing or merely
inaccessible.

## 3. Enable multiple SteamVR drivers

SteamVR must load the Monado HMD driver and Valve Lighthouse driver together. In SteamVR's
`steamvr.vrsettings`, set:

```json
{
  "steamvr": {
    "activateMultipleDrivers": true
  }
}
```

Merge the setting into the existing `steamvr` object; do not replace unrelated settings.
The launcher checks this value and stops with an explicit error if it is absent.

## 4. Prepare NVIDIA 90 Hz support

NVIDIA users should run:

```bash
./scripts/nvidia-g2-patch-manager.sh status
./scripts/nvidia-g2-patch-manager.sh validate
./scripts/nvidia-g2-patch-manager.sh apply
```

Reboot after `apply`, then rerun `status`. The launcher requires the native 4320×2160 mode
and audits the patch state before starting SteamVR. See
[NVIDIA driver management](nvidia-driver.md) before changing kernel-module source.

## 5. Install the control panel

```bash
./scripts/install-control-panel.sh
```

This installs a user-level launcher and desktop entry that point back to the current clone.
Rerun it if you move the repository.

## 6. Run the hardware check

```bash
./scripts/g2-preflight.sh all
```

Do not continue until required checks pass. In particular, the G2 cable's SuperSpeed half
and tracking cameras must negotiate at 5000 Mb/s. Seeing one G2 USB device is not enough;
the headset is split across multiple USB 2 and USB 3 functions.

## 7. Pair and calibrate Index controllers

Pair one Index controller to each Watchman receiver. Ordinary host Bluetooth is not used.
Place the receiver dongles away from the computer and from each other, preferably on USB
extension leads.

Start the first session:

```bash
./scripts/beat-saber-index.sh start-ui
```

In the Space Calibrator desktop window choose:

- reference space: `monado`;
- reference device: `HP Reverb Virtual Reality Headset G2`;
- target space: `lighthouse`; and
- target device: either Index controller.

Hold the selected controller firmly against the headset so their relative position cannot
change. Start regular calibration and move the headset/controller pair together through a
wide figure eight with rotation. The saved transform applies to both controllers.

Check the result while wearing the headset at play-centre:

```bash
./scripts/beat-saber-index.sh ready 1.76
```

Replace `1.76` with your standing eye height in metres. The value is also editable in the
control panel settings.

## 8. Optional modded Beat Saber setup

Install [BSManager](https://github.com/Zagrios/bs-manager), choose its content and Proton
folders, add a Beat Saber version with available core mods, and launch that managed version
once from BSManager. The launcher reads BSManager's configured folders and last-launched
version; it does not hard-code a game version or storage mount.

Put `bs-manager` on `PATH`, install it at `~/.local/opt/bs-manager/bs-manager`, or set the
`BSMANAGER` environment variable. Then use **Start VR + modded Beat Saber** in the control
panel.

For the normal Steam copy of Beat Saber, set this launch option:

```text
PRESSURE_VESSEL_IMPORT_OPENXR_1_RUNTIMES=1 %command%
```
