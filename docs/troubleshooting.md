# Troubleshooting

Start with the integrated report:

```bash
./scripts/beat-saber-index.sh diagnose
./scripts/g2-preflight.sh all
```

Do not bypass a failed required preflight. It is designed to stop before a bad USB or
display state becomes a misleading SteamVR failure.

## USB 3 reports 480 Mb/s

The G2 cable has separate USB 2 and SuperSpeed paths. The cable can enumerate while its
SuperSpeed half or tracking cameras are stuck at USB 2 speed.

The required results are:

- Cypress SuperSpeed half: at least 5000 Mb/s;
- Cypress USB 2 companion half: 480 Mb/s;
- HoloLens tracking cameras and sensors: at least 5000 Mb/s; and
- the HP control and G2 audio interfaces present.

Try a different USB 3 port or powered hub. With the v1 cable, power-cycle the cable box and
rerun the preflight. Replugging only one connector may leave the other half in the same bad
state.

## The G2 connector never appears

Confirm the HP control interface is accessible and let the launcher activate the panel.
Do not hard-code `card0-DP-1` or another connector: the tool identifies the G2 from its EDID
across every DRM card and DisplayPort connector.

If USB passes but no connector appears, check DisplayPort seating, cable-box power, kernel
messages, and whether another process still owns the headset.

## 60 Hz works but 90 Hz is black or flickers

On NVIDIA, run:

```bash
./scripts/beat-saber-index.sh nvidia status
```

Confirm the running driver is the rebuilt open module and that every patch required for its
family is applied. If the installed and running versions differ, finish the patch/rebuild
workflow and reboot. The supported target is the native 4320×2160 mode at 90 Hz; reduced
modes were useful during diagnosis but are not the intended configuration.

A reported 90 Hz modeset is not enough. Put on the headset and verify that both panels are
lit, stable, and free of severe flicker.

## SteamVR cannot acquire the display

Close GPU-heavy applications and retry. Low available VRAM has caused the SteamVR
compositor to start without acquiring the G2 lease.

On Wayland, inspect the compositor error shown by `diagnose`. An unclean SteamVR exit can
leave the desktop compositor unable to grant the HMD lease until VR is stopped cleanly or
the desktop session is restarted.

## A controller floats away or loses tracking

This is usually Lighthouse radio placement rather than G2 tracking:

- use one Watchman receiver per controller;
- move the dongles away from the computer and other high-speed USB devices;
- separate the receivers from each other with extension leads;
- confirm both base stations are visible; and
- power-cycle or re-pair only after checking placement.

The preflight reports detected and accessible radios independently.

## Both controllers track but are offset

Repeat Space Calibrator. Keep the selected controller pressed rigidly against the headset
during the full figure-eight motion. If either device shifts relative to the other, the
saved transform is wrong.

Run the ready check afterward:

```bash
./scripts/beat-saber-index.sh ready 1.76
```

## The floor or player height is wrong

Keep the headset off the floor during startup. Stand at play-centre during the positioning
countdown, then run:

```bash
./scripts/beat-saber-index.sh floor 10
```

Moderate false vertical drift should recover after the configured still-and-level delay.
A genuine tracking loss or out-of-envelope pose remains blocked. If tracking has diverged
rather than merely shifted vertically, stop the complete VR session and start again in a
well-lit, textured room.

## Beat Saber loads a frozen map or controllers are on the floor

Restart only the managed game first:

```bash
./scripts/beat-saber-index.sh restart-modded
```

This keeps SteamVR, floor calibration, and Space Calibrator alive. If the ready check also
fails, stop the full session and recalibrate instead.

## Steam crashes when opening the VR desktop

Use the launcher's direct Beat Saber action rather than SteamVR's desktop view. The control
panel starts Steam with PipeWire support, but desktop capture and Steam Remote Play hosting
still caused crashes on the verified system. The launcher warns when Remote Play hosting is
enabled but does not silently change that setting.

## Audio works but SteamVR's volume slider does not

Use the PipeWire-aware launcher control:

```bash
./scripts/beat-saber-index.sh volume 65
```

If the G2 sink is missing, rerun the USB preflight and wake the headset before changing
volume.

## Logs

The launcher stores its own logs under `~/.cache/reverb-g2` and discovers SteamVR's OpenVR
log directory through `vrpathreg.sh`. Run `diagnose` instead of assuming a Steam library or
log path.
