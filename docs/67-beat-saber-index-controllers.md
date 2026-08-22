# 67 — Beat Saber with Lighthouse and Index controllers

The display milestone is now proven physically: the G2 shows a stable
4320x2160 image at 90 Hz.  Rendering and controller tracking are separate
problems, so bring them up in this order.

This chapter covers the supported, reproducible profile: Project-VR Monado for
the G2 display and head tracking, native SteamVR, Lighthouse base stations,
Index controllers, and OpenVR Space Calibrator. The separate native
G2-controller/xrizer stack remains a research profile because its exported
Monado patches do not yet form one clean source lineage; see `docs/68`.

## 1. Build and install the pinned stack

Install the distribution dependencies, then reproduce the pinned, verified
source stack:

```bash
cd /path/to/reverb-g2
./scripts/setup-index-controllers.sh deps
./scripts/setup-index-controllers.sh all
```

The dependency installer supports Arch, Debian/Ubuntu, and Fedora package
names. The source step pins Monado, Basalt, and OpenVR Space Calibrator to the
exact revisions used for the physical test, applies every tracked patch, and
rejects unexplained source edits. Arch's OpenCV 5 compatibility changes are
part of that series; `survive` and a system OpenVR development package are not
required.

Install the G2 device-access rule once. This uses systemd `uaccess` rather than
the nonexistent Arch `plugdev` group and is required for libusb to claim the
tracking-camera interface:

```bash
sudo install -m 0644 scripts/70-wmr-reverb.rules /etc/udev/rules.d/70-wmr-reverb.rules
sudo udevadm control --reload-rules
```

Reconnect the G2 after installing the rule so the active desktop session gets
fresh device ACLs.

In Steam, set Beat Saber **Properties -> Launch Options** to:

```text
PRESSURE_VESSEL_IMPORT_OPENXR_1_RUNTIMES=1 %command%
```

The source verifier creates a clean expected tree from every pin and accepts an
existing modified tree only when it is byte-identical to the complete tracked
series. Envision is not used by this profile. Xrizer is also unnecessary because
native SteamVR loads Project-VR's `driver_monado.so` directly.

## 2. Align Index controllers with the G2

This is now the proven control path:

```text
SteamVR compositor
  + Project-VR driver_monado.so (G2 HMD)
  + Valve lighthouse driver    (Index controllers)
  + OpenVR Space Calibrator    (align the two tracking spaces)
```

The verified system uses two Watchman endpoints, one for each paired Index
controller. The launcher counts the receiver radios dynamically and never
depends on their serial numbers. Ordinary host Bluetooth is not part of this
path.

By default, the Linux port of Space Calibrator is built at
`~/vr/openvr-space-calibrator-linux` and installed as the external SteamVR
driver `~/.local/share/SteamVR/drivers/01spacecalibrator`. A G2 controller is
not required: for a headset with no same-system controller, select the G2 HMD
itself as the reference device in the desktop calibration window.

Start the mixed session with:

```bash
./scripts/beat-saber-index.sh start
```

In Space Calibrator select:

- Reference space: `monado`
- Reference device: `HP Reverb Virtual Reality Headset G2` (HMD)
- Target space: `lighthouse`
- Target device: either Index controller

Press the selected Index controller firmly against the headset so they cannot
shift relative to one another. Start regular calibration from the desktop
window, then sweep and rotate the headset/controller pair together through a
wide figure eight. The resulting transform is applied to both Index
controllers. Continuous calibration needs a dedicated tracker fixed to the
headset; an ordinary one-time calibration is sufficient for a fixed Beat Saber
play area and can be repeated if the spaces drift.

After calibration, launch the game with:

```bash
./scripts/beat-saber-index.sh ready 1.76
./scripts/beat-saber-index.sh play
```

Run `ready` while wearing the HMD, standing upright at play-centre, with both
controllers awake. It samples the live standing pose for two seconds and
refuses a stale floor transform, an implausible Space Calibrator transform, a
lost controller, or multiple racing Space Calibrator processes. Every successful
`start` already validates the upright startup pose and automatically saves a
fresh 5 x 5 m floor/centre before controllers or Beat Saber are started. If only
the height is wrong during an already-running session, recalibrate it with:

```bash
./scripts/beat-saber-index.sh origin set 1.76
```

The SteamVR chaperone transform and Space Calibrator profile are saved on disk,
so restarting Beat Saber within the same SteamVR session retains both. Basalt's
raw SLAM world can be initialized differently after a complete SteamVR restart
or reboot, which is why the launcher replaces the floor transform on every
successful start. Before `start`, put the HMD at play-centre facing the usual
forward direction with its cameras seeing a well-lit, textured room; after
startup, use `ready` for an additional live check.

The Monado SteamVR driver also enforces a session-local headset envelope. The
first valid upright pose is the anchor: horizontal movement is limited to 5 x 5
m, and vertical movement is limited from the configured floor through 0.40 m
above the configured standing eye height. An out-of-envelope SLAM pose is
reported out-of-range while translation is held at the last safe pose. The VIT
input guard separately rejects non-finite, excessive-step, excessive-speed, and
runaway-room poses and resets Basalt after three consecutive rejected poses.

For a numerical stationary-jitter capture, put the HMD on a rigid surface with
the cameras unobstructed and run:

```bash
./scripts/beat-saber-index.sh jitter 10
```

Do not tune pose smoothing from a hand-held capture: it includes real head and
body motion and cannot distinguish that motion from tracker noise.

Steam Remote Play hosting should be disabled for this setup. One successful
Beat Saber session ended because Steam's 32-bit `CDesktopStreamT` thread
segfaulted exactly when it attempted to switch from game capture to desktop
capture; there was no NVIDIA Xid, GPU reset, OOM kill, or Beat Saber crash. The
launcher warns when `EnableStreaming` is still enabled but does not silently
change the user's Steam/Shield/Deck configuration.

The same Remote Play failure had already killed Steam once before the final
session. Starting SteamVR while Steam was absent created a reduced/fallback VR
dashboard; starting Beat Saber later relaunched Steam and changed the dashboard
in place. This was not a SteamVR beta-branch switch. The launcher now starts
and settles the Steam client before `vrstartup`, so the dashboard and external
Space Calibrator overlay register against one stable client session.

The G2 USB codec appears in PipeWire as
`alsa_output.usb-Generic_USB_Audio-00.analog-stereo`. The launcher supplies its
live PipeWire node ID to the Monado SteamVR driver and offers a direct fallback
that does not depend on the dashboard's volume control:

```bash
./scripts/beat-saber-index.sh volume status
./scripts/beat-saber-index.sh volume 70
./scripts/beat-saber-index.sh volume +5%
./scripts/beat-saber-index.sh volume mute
```

This command selects SteamVR's OpenXR runtime so Beat Saber sees the Index
controllers. Stop afterward (and restore native Monado as the active OpenXR
runtime) with:

```bash
./scripts/beat-saber-index.sh stop
```

SteamVR owns the DRM lease and display presentation in this path; Monado is
loaded only as the G2 device/tracking driver. On Plasma Wayland, an uncleanly
terminated SteamVR compositor can leave KWin's HMD lease unavailable until the
desktop session is restarted. The launcher detects that failure instead of
opening Beat Saber without a display.

## Control panel and saved session settings

`Reverb G2 VR Control Panel` is installed in the Plasma application menu. It
runs `scripts/g2-control-panel.sh` and exposes the proven workflow without
requiring command-line arguments:

1. Hardware check
2. Start VR
3. Start VR + modded Beat Saber
4. Ready check
5. Set floor again (only when the automatically set height is wrong)
6. Open BSManager to manage versions/mods
7. Stop VR

Settings are stored in `~/.config/reverb-g2/session.conf`. The defaults are a
1.76 m standing eye height, 100% G2 volume, dead-reckoning SLAM prediction,
100% SteamVR angular prediction, Basalt feature recall off, camera auto-exposure
on, tracking smoothing off, upright height recovery after 8 seconds, and a
10-second positioning countdown. The countdown
runs after the panel/display/USB checks but immediately before SteamVR loads
Monado and Basalt. Use it to pick up the HMD and stand at play-centre, upright
and facing the usual forward direction, so tracking does not initialize from a
headset lying on the floor. Once direct mode and tracking are ready, the launcher
samples that pose for about two seconds and automatically sets the 5 x 5 m floor;
if the sample is unstable, tilted, implausibly far away, or outside the driver
envelope, startup stops instead of saving it. Set the countdown to zero in
**Settings** to disable only the positioning delay.

When **Start VR** is launched from the control panel, Steam is first restarted
with `-pipewire`. Steam's desktop overlay still crashes this Steam build while
starting `CDesktopStreamT`, so the desktop overlay must not be used even with
that flag. The checks then run in a held terminal. A separate **Reverb G2
checks passed** dialog appears only after
all required checks succeed. Click **Begin** there, then move into position
during the countdown. If a check fails, that success dialog never appears and
the held terminal retains the exact failure. Cancelling the success dialog
turns the panel back off without starting Monado.

**Start VR + modded Beat Saber** performs that same checked startup and then
launches BSManager's `last-version-launched` directly through the Proton version
selected in BSManager. It recreates BSManager's launch environment, including
its shared compatibility prefix and `winhttp` mod-loader override, but omits
the `fpfc` desktop-mode argument. This avoids SteamVR's crashing desktop-capture
overlay and does not require walking back to the computer after tracking starts.

The **Settings** page describes every tracking control in-place. They are all
reversible and take effect on the next SteamVR start:

- **Smoothing**: `off` is sharpest; `position-light` and `position` progressively
  reduce translational rest jitter without delaying rotation; `full` also filters
  orientation and is experimental because rotational lag can cause discomfort.
- **SLAM prediction**: selects how Monado advances Basalt's most recent pose.
  `dead-reckoning` is the current recommendation: `gyro` did not improve perceived
  movement and allowed more centre drift in the G2 test. `accel-gyro`, `pose-only`,
  and `none` remain diagnostic choices.
- **SteamVR angular prediction**: forwards head angular velocity for SteamVR's
  final photon-time extrapolation. The strength control scales only that exported
  velocity from 0% to 150%; it does not alter Basalt's internal prediction.
- **Basalt landmark recall**: `front` and `all` enable experimental reuse of old
  image landmarks to help relocalisation. Start with `off`; `all` has the largest
  CPU and memory cost, and recalled patches remain for the current tracker session.
- **Camera exposure**: auto-exposure should normally stay on. Unified exposure
  makes all four cameras share an exposure/gain decision and is an experimental
  lighting test, not a general-purpose improvement.
- **Upright height recovery**: after the HMD is continuously level, tracked and
  nearly motionless for the selected delay (8 seconds by default), a false vertical
  offset glides toward the startup standing height at 5 cm/s. Moderate vertical-only
  excursions are held without reporting `Running_OutOfRange`, avoiding SteamVR's
  grey screen; genuinely lost, horizontally runaway, or extreme poses still invoke
  the strict guard. Index/Lighthouse coordinates and the Space Calibrator transform
  are not rewritten. If height recovery occurs while calibrating controllers, let it
  finish and then run controller calibration again from the corrected pose.

Change one tracking control at a time so an improvement or regression has a
clear cause. The current useful baseline is `dead-reckoning`, smoothing off,
angular prediction at 100%, landmark recall off, and the exposure defaults.

Settings take effect on the next SteamVR start. The equivalent commands are:

```bash
./scripts/beat-saber-index.sh config show
./scripts/beat-saber-index.sh config set-all 1.76 off true 100 10
./scripts/beat-saber-index.sh floor 10
```

The five-value `set-all` form remains compatible and preserves the newer
tracking fields. The control panel is the recommended way to edit all fields.

## Strict startup/preflight checks

`start` now has two preflight phases. Before waking the headset it checks the
loaded NVIDIA open module, `nvidia_modeset`, Steam/PipeWire tools, the udev
rule, and both Watchman receivers. After the panel is activated it checks the
G2's physically separate USB functions and their negotiated speeds:

- Cypress cable SuperSpeed half `04b4:6504`: at least 5000 Mb/s
- Cypress cable USB 2 companion half `04b4:6506`: at least 480 Mb/s
- HoloLens tracking sensors `045e:0659`: at least 5000 Mb/s
- HP control interface `03f0:0580`
- Realtek G2 audio `0bda:4c15` (audio-only warning if absent)

It also reports USB authorization, user access, runtime power control, the
xHCI PCI path, and recent kernel USB resets/errors. A failed USB 3 negotiation
stops before SteamVR and specifically suggests power-cycling the v1 cable box
or using the powered hub. The later DRM check still requires the native
`4320x2160` mode, so a missing NVIDIA display patch is also caught.

If SteamVR loads the Monado driver but WMR device creation transiently returns
`HmdNotFound`, the launcher releases the devices and retries once while the user
remains in position. A repeated Monado initialization failure is reported as
such; it is no longer mislabeled as a DRM-lease failure when `vrcompositor`
never started. Genuine compositor/Wayland lease failures retain their separate
diagnosis.

Run either phase independently with:

```bash
./scripts/beat-saber-index.sh preflight host
./scripts/beat-saber-index.sh preflight usb
./scripts/beat-saber-index.sh diagnose
```

## Beat Saber modding

Install [BSManager](https://github.com/Zagrios/bs-manager) and complete its
first-run setup. Its content folder may be on any writable filesystem; Proton
compatibility is not affected by keeping managed game instances outside the
Steam library. Put the executable on `PATH`, install it at
`~/.local/opt/bs-manager/bs-manager`, or set `BSMANAGER` explicitly.

Keep the normal Steam copy unchanged. In BSManager use **Add a version** to
download a separate version for which the Mods tab currently offers verified
Core/Essential mods. The launcher reads BSManager's `installation-folder`,
`proton-folder`, and `last-version-launched` fields dynamically; no game
version, storage mount, or Proton build is hardcoded. Launch that managed
version once in BSManager so those fields are complete, install its core mods,
then use **Start VR + modded Beat Saber** in this project's control panel.

Open it with:

```bash
./scripts/beat-saber-index.sh mods
```

## Portability and NVIDIA updates

The playable launcher and control panel do not assume a DRM card or DisplayPort
number. They wake the headset and identify it from the G2's exact EDID
manufacturer/product bytes, so `card0-DP-1`, `card1-DP-3`, or a different port all
work without editing a script. They also discover:

- Steam and every Steam library from `libraryfolders.vdf` plus the app manifests
  for SteamVR (`250820`) and Beat Saber (`620980`)
- registered Monado and Space Calibrator drivers, and the OpenVR log directory,
  from SteamVR's `vrpathreg.sh`
- the installed and running NVIDIA versions, the exact matching `/usr/src` tree,
  and the current kernel/DKMS build

Review the resolved values at any time with:

```bash
./scripts/beat-saber-index.sh paths
./scripts/beat-saber-index.sh nvidia status
```

Environment overrides such as `G2_VR_ROOT`, `STEAM_ROOT`, `STEAMVR_DIR`,
`BEAT_SABER_DIR`, `MONADO_DIR`, `BASALT_DIR`, `SPACECAL_DRIVER_DIR`,
`VIT_SYSTEM_LIBRARY_PATH`, and `G2_DRM_CONNECTOR` remain available for unusual
layouts. They are overrides, not requirements for this machine.

After an NVIDIA package update, open the control panel and run **NVIDIA patch
status** before rebooting. If the new source is unpatched, choose **Patch NVIDIA
driver**. The patch manager validates the full selected series on temporary
copies, refuses an unknown/incompatible source layout, saves recovery copies
under `/var/backups/reverb-g2-nvidia`, rebuilds DKMS for the running kernel, and
refreshes the detected initramfs implementation. It performs the DKMS and boot
image rebuild even when the source is already patched, which also repairs the
"patched source, stale boot module" failure. It never reboots automatically.
After reboot, run **Boot-image check** and **Hardware check**.

There is deliberately no silent package-manager hook. A future NVIDIA release
can change the private NVKMS source enough to require a patch rebase; failing
visibly before the reboot is safer than automatically installing a driver that
was only partly patched.

Install or refresh the menu entry for the current checkout with:

```bash
./scripts/install-control-panel.sh
```

Some older X11/lab reproduction scripts and historical chapters remain pinned to
the connector and NVIDIA version used for those experiments. They preserve old
measurements and are not called by the portable Beat Saber launcher or control
panel.
