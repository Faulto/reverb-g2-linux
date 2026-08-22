# Installation

This is the full setup for a Reverb G2 headset with Index controllers. You only need to do
most of it once.

This setup uses Monado and Basalt for the G2, then adds Valve's Lighthouse driver for the
Index controllers. It does not use Envision or xrizer.

## What you need

- an HP Reverb G2 with DisplayPort and USB connected;
- native Steam and SteamVR, opened at least once;
- two Lighthouse base stations;
- two Index controllers;
- two Watchman receiver dongles, one for each controller; and
- a well-lit play area with visible detail on the walls and furniture.

If you have an NVIDIA GPU, you also need the open kernel module and its matching source in
`/usr/src`. The included display patches support the 595 and 610 driver families. They do
not work with NVIDIA's proprietary kernel module.

## 1. Build the VR software

From the repository folder, run:

```bash
./scripts/setup-index-controllers.sh deps
./scripts/setup-index-controllers.sh all
```

The first command installs the build packages through `pacman`, `apt`, or `dnf`. The second
downloads the tested Monado, Basalt, and Space Calibrator versions, patches them, builds
them, and registers the SteamVR drivers.

They are stored under `~/vr` by default. To put them elsewhere:

```bash
G2_VR_ROOT=/path/to/vr ./scripts/setup-index-controllers.sh all
```

The script will not overwrite a source tree with unknown edits. It accepts either the clean
tested version or this repo's complete patch set.

## 2. Give your user access to the G2

```bash
sudo install -m 0644 scripts/70-wmr-reverb.rules /etc/udev/rules.d/70-wmr-reverb.rules
sudo udevadm control --reload-rules
```

Unplug and reconnect the G2 after this. Reconnecting gives your desktop session permission
to open the tracking cameras.

Your distribution's Steam or Valve udev package must also allow access to both Watchman
receivers. The hardware check tells you whether a receiver is missing or merely blocked by
permissions.

## 3. Let SteamVR load both drivers

SteamVR needs the Monado headset driver and Valve Lighthouse driver at the same time. Find
SteamVR's `steamvr.vrsettings` file and add this inside its existing `steamvr` section:

```json
{
  "steamvr": {
    "activateMultipleDrivers": true
  }
}
```

Keep any settings already in that section. Do not replace the whole file with this small
example. The launcher checks the value and gives you a clear error if it is missing.

## 4. Fix 90 Hz on NVIDIA

Skip this step on AMD or Intel. NVIDIA users should run:

```bash
./scripts/nvidia-g2-patch-manager.sh status
./scripts/nvidia-g2-patch-manager.sh validate
./scripts/nvidia-g2-patch-manager.sh apply
```

`apply` asks for `sudo`, rebuilds the driver, and tells you when a reboot is needed. It does
not reboot the PC for you. After rebooting, run `status` again.

Read the [NVIDIA guide](nvidia-driver.md) before applying the patch if you use a different
driver family or are unsure whether the open module is installed.

## 5. Install the control panel

```bash
./scripts/install-control-panel.sh
```

You will now have **Reverb G2 VR Control Panel** in your application menu. The entry points
back to this clone, so rerun the installer if you move the repository.

## 6. Check the headset

```bash
./scripts/g2-preflight.sh all
```

Fix any reported failure before starting VR. The important USB results are 5000 Mb/s for
the G2 cable's SuperSpeed half and 5000 Mb/s for the HoloLens tracking cameras. A G2 can
still appear in `lsusb` when only half of its USB connection is working.

## 7. Pair and calibrate the Index controllers

Pair one controller to each Watchman receiver. The controllers do not use ordinary PC
Bluetooth. Put the receiver dongles on USB extension leads, away from the computer and away
from each other. This makes a surprisingly large difference to tracking.

Start VR:

```bash
./scripts/beat-saber-index.sh start-ui
```

In the desktop Space Calibrator window, choose:

- reference space: `monado`;
- reference device: `HP Reverb Virtual Reality Headset G2`;
- target space: `lighthouse`; and
- target device: either Index controller.

For the first calibration, hold the selected controller firmly against the headset. Run a
normal calibration while moving the headset and controller together in a wide figure eight
with some rotation. The result is used for both controllers.

Put on the headset at play centre and check the saved spaces:

```bash
./scripts/beat-saber-index.sh ready 1.77
```

Replace `1.77` with your real standing eye height in metres. You can also change it with
the control panel's **Settings** button.

## 8. Optional: modded Beat Saber

This repo does not install BSManager, download a Beat Saber version, or choose mods. It reads
an existing native BSManager setup and launches its last-used modded copy directly.

Follow [Setting up BSManager](bsmanager.md) for the Linux install choices, Proton folder,
content folder, game download, Core mods, first launch, and the check that connects it to
this control panel.

For an ordinary Steam copy of Beat Saber, add this Steam launch option:

```text
PRESSURE_VESSEL_IMPORT_OPENXR_1_RUNTIMES=1 %command%
```

Installation is now finished. See [Using the launcher](using-the-launcher.md) for the normal
start-up routine and the quick controller resync used between active songs.
