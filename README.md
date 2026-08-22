# Reverb G2 Linux

Getting a Reverb G2 running on Linux normally means building several projects, patching the
display driver, checking five different USB devices, and starting everything in the right
order. This repo handles most of that for you.

Once it is set up, you can start VR from a small desktop control panel. It checks the
headset first, gives you time to stand in the right place, starts SteamVR, sets the floor,
and brings in your Index controllers.

It is not perfectly plug-and-play yet. Read the [known rough edges](#known-rough-edges)
before jumping into a long session.

## What works

The setup we use is:

- HP Reverb G2 for the display, speakers, and head tracking
- Project-VR Monado and Basalt for the headset
- native Steam and SteamVR
- two Lighthouse base stations
- two Index controllers, each with its own Watchman receiver
- OpenVR Space Calibrator to line up the G2 and Lighthouse tracking spaces

The G2 runs at its full 4320×2160 combined resolution and 90 Hz. Beat Saber is playable,
including modded versions managed by BSManager.

Native G2 motion controllers are not supported by this clean setup. That work is still in
the older [Wintch/reverb-g2](https://github.com/Wintch/reverb-g2) research repo.

## What this repo does for you

- Builds the tested Monado, Basalt, and Space Calibrator versions.
- Finds Steam, SteamVR, Beat Saber, audio devices, and the G2 display automatically.
- Checks the full G2 USB connection instead of trusting a single `lsusb` entry.
- Checks that both Index-controller receivers are present and usable.
- Patches supported NVIDIA open drivers for 90 Hz, rebuilds DKMS, and updates the boot
  image.
- Starts SteamVR only after the hardware and display checks pass.
- Sets a fresh floor and play centre each time VR starts.
- Limits bad tracking jumps and helps correct small height drift.
- Starts modded Beat Saber directly, without opening SteamVR's desktop view.
- Gives you simple buttons for settings, diagnostics, game restart, volume, and shutdown.

## Known rough edges

### Index controllers slowly move out of place

The Index controllers can pick up a small position offset after a lot of head and body
movement. We noticed it most on FitBeat maps with squats, jumps, and quick side-to-side
movement. Tracking is usually good for a song, then it may need a quick sync before the next
one.

Pause the game, open the SteamVR menu, and open the Space Calibrator overlay. Choose the same
G2 reference and Index target as before, select **Fast**, press the controller firmly against
the headset, and run calibration again. You do not need to restart SteamVR or Beat Saber.

This appears to be drift between the G2 and Lighthouse tracking spaces. We have seen the
offset follow heavy head and body movement, but have not pinned down the exact cause.

### Looking far up or down can shift your head position

Sometimes a large up/down head movement makes the view move slightly instead of only
rotating. It normally settles again quite quickly. This looks like Basalt briefly losing and
reacquiring a stable position from the room, but we have not proved the exact cause.

If your height stays wrong, stand upright, look level, and keep your head completely still.
After 8 seconds the height correction starts moving you back toward the saved 1.77 m eye
height at 5 cm per second. A larger error takes a few more seconds to finish.

If the whole play space is wrong, use **Set floor again** in the control panel instead.

### Beat Saber suddenly stutters

Check SteamVR's render resolution before changing drivers or tracking settings. SteamVR can
sometimes choose a very high per-game resolution, and **100% is not always a safe value**.
Look at the actual pixel dimensions rather than the percentage.

Each G2 panel is 2160×2160, or 4320×2160 across both eyes. Rendering at the panel resolution
can still look blurry because VR needs extra pixels for lens correction. On our test system,
a custom 4320×2160 setting gave the best balance. Treat that as a tested starting point, not
a requirement for every GPU.

After changing the resolution, fully restart Beat Saber. The game did not reliably apply
the new render size while it was still running. If it stutters, lower the custom resolution
and restart again; if it is smooth but blurry, raise it gradually.

### 90 Hz is black or flickers on NVIDIA

The G2 does not declare a colour depth in its EDID. The tested NVIDIA drivers chose a 6-bpc
DisplayPort link and failed to light the native 90 Hz mode correctly. The included patch
series fixes the G2 link and forces the tested 8-bpc path.

Run the NVIDIA patch check after every driver update. The tool catches a missing patch, an
old DKMS build, a stale boot image, and a pending reboot.

### The headset is detected, but part of it does not work

The G2 cable has separate USB 2 and USB 3 branches. One half can fail or connect at only
480 Mb/s while the headset still appears in `lsusb`.

The preflight checks every part separately. If the SuperSpeed side is slow, try another USB
3 port or a powered hub. With a v1 cable, power-cycling the cable box can also help.

### One display goes black, then the other

On our G2 with a v1 cable, high headset volume could make one panel switch off, followed by
the other. Both would return a few seconds later, sometimes with the tracking height shifted.
This appears to be another v1 cable or cable-box power problem.

Starting the G2 at 65% volume stopped the panel resets in testing, so that is now the
default. SteamVR's volume slider does not reliably control this setup; use the control panel
volume setting instead. If it still happens, power-cycle the cable box and rerun the USB
check.

### SteamVR's desktop view crashes Steam

This happened repeatedly on our test machine. The launcher starts Steam with PipeWire
support, but the reliable option is to avoid the VR desktop and launch Beat Saber directly
from this control panel. It also warns if Steam Remote Play hosting is enabled.

### A Beat Saber map is stuck

Use **Restart modded Beat Saber**. This restarts only the game and keeps SteamVR, the floor,
and Space Calibrator running.

More fixes are in the [troubleshooting guide](docs/troubleshooting.md).

## Install

You need native Steam and SteamVR. Open both once before continuing.

```bash
git clone https://github.com/Faulto/reverb-g2-linux.git
cd reverb-g2-linux
./scripts/setup-index-controllers.sh deps
./scripts/setup-index-controllers.sh all
```

Install the headset permission rule, then reconnect the G2:

```bash
sudo install -m 0644 scripts/70-wmr-reverb.rules /etc/udev/rules.d/70-wmr-reverb.rules
sudo udevadm control --reload-rules
```

Install the desktop control panel:

```bash
./scripts/install-control-panel.sh
```

NVIDIA users should check and apply the display patch before starting VR:

```bash
./scripts/nvidia-g2-patch-manager.sh status
./scripts/nvidia-g2-patch-manager.sh validate
./scripts/nvidia-g2-patch-manager.sh apply
```

The last command asks for `sudo` and tells you when to reboot. It never reboots your PC by
itself.

There are two small one-time steps left: enabling multiple SteamVR drivers and calibrating
the controllers. Follow the [full installation guide](docs/installation.md).

## Start VR

Open **Reverb G2 VR Control Panel** from your application menu and click **Start VR**.

Wait for the checks-passed message before picking up the headset. Click **Begin**, then use
the 10-second countdown to stand at play centre, upright and facing forward. Tracking starts
when the countdown reaches zero.

For modded Beat Saber, click **Start VR + modded Beat Saber** instead.

You can also use the terminal:

```bash
./scripts/g2-preflight.sh all
./scripts/beat-saber-index.sh start-ui
```

When you finish, click **Stop VR**. This closes the session, turns off the panel, and restores
Monado as your normal OpenXR runtime.

## Tested default settings

New installs now start with the profile that worked best in our Beat Saber testing:

| Setting | Default | Why |
|---|---:|---|
| Eye height | 1.77 m | Change this to your real standing eye height |
| Tracking smoothing | Off | Lowest head-motion latency |
| SLAM prediction | Dead reckoning | Best overall movement in testing |
| SteamVR angular prediction | On, 100% | Helps rotation feel immediate |
| Basalt landmark recall | Front camera | Helped the tested room without the cost of all-camera recall |
| Camera auto-exposure | On | Best general lighting behaviour |
| Unified camera exposure | Off | The safer default; unified exposure is experimental |
| Height recovery | On, after 8 seconds | Corrects small height drift while you stand still and level |
| Headset volume | 65% | Comfortable, and stopped v1-cable panel power resets in testing |
| Startup countdown | 10 seconds | Time to move from the PC to play centre |

Your saved file at `~/.config/reverb-g2/session.conf` always wins over these defaults. An
update will not replace settings you have already chosen.

Use the control panel's **Settings** button to change anything. Start with one change at a
time so it is easy to tell whether it helped.

## NVIDIA driver updates

Your Linux package manager still installs the NVIDIA driver. This repo handles the G2 patch
afterward.

After an NVIDIA update, run:

```bash
./scripts/beat-saber-index.sh nvidia status
```

If it reports missing patches on a supported version, run:

```bash
./scripts/beat-saber-index.sh nvidia apply
```

The tool backs up the files it changes, rebuilds DKMS, updates the boot image, and asks you
to reboot. It refuses unknown driver families rather than guessing.

See [NVIDIA driver updates](docs/nvidia-driver.md) for the longer explanation.

## What has been tested

The full playable setup has been tested on Arch Linux, Plasma Wayland, an RTX 5080, NVIDIA
610 open modules, a G2 v1 cable, and Index controllers. The display patches were also tested
on Debian with an RTX 3060 Ti and NVIDIA 595 open modules.

Arch, Debian/Ubuntu, and Fedora package installation is built in, but we still need more
reports from other PCs. AMD, Intel, GNOME, current Ubuntu/Fedora versions, X11, and the G2
rev2 cable should be treated as untested until someone confirms them.

Read [compatibility](docs/compatibility.md) for the exact list.

## More help

- [Install everything](docs/installation.md)
- [Use the launcher and control panel](docs/using-the-launcher.md)
- [Fix common problems](docs/troubleshooting.md)
- [Handle NVIDIA updates](docs/nvidia-driver.md)
- [Check tested hardware](docs/compatibility.md)

## Safety

A successful command or reported 90 Hz mode does not prove that both screens are actually
working. Put the headset on and check. Stop immediately if a test causes heavy flicker or
makes you feel unwell.

The NVIDIA tool changes kernel-module source and the boot image. Keep a fallback kernel or
another boot entry available.

## Credits

This work builds on [Project-VR](https://github.com/AshishKumar4/Project-VR),
[Monado](https://monado.dev/), [Basalt](https://gitlab.com/VladyslavUsenko/basalt), and
[OpenVR Space Calibrator for Linux](https://github.com/xi-ve/openvr-space-calibrator-linux).
License details are in [LICENSES/README.md](LICENSES/README.md).
