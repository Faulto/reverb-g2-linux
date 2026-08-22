# Troubleshooting

Start with these two commands:

```bash
./scripts/beat-saber-index.sh diagnose
./scripts/g2-preflight.sh all
```

Fix any failed preflight before trying to start SteamVR again. The launcher stops early so
a bad USB or display connection does not turn into a confusing SteamVR error.

## The USB 3 connection says 480 Mb/s

The G2 cable has separate USB 2 and USB 3 branches. Half of the cable can be working while
the tracking cameras or SuperSpeed branch is stuck at USB 2 speed.

The hardware check should show:

- Cypress SuperSpeed half: at least 5000 Mb/s;
- Cypress USB 2 companion half: 480 Mb/s;
- HoloLens tracking cameras and sensors: at least 5000 Mb/s; and
- the HP control and G2 audio interfaces present.

Try another USB 3 port or a powered hub. If you have the v1 cable, unplug power from the
cable box for a few seconds and try again. Reconnecting only one plug can leave the other
half in the same bad state.

## The G2 display connector never appears

Let the launcher wake the panel. Do not hard-code a name such as `card0-DP-1`; the tool
finds the G2 by its EDID even when Linux changes the card or DisplayPort number.

If every USB check passes but the connector is still missing, check the DisplayPort plug,
cable-box power, kernel messages, and whether an old VR process still owns the headset.

## 60 Hz works but 90 Hz is black or flickers

On NVIDIA, run:

```bash
./scripts/beat-saber-index.sh nvidia status
```

The running driver must be the rebuilt NVIDIA open module, with every patch required for
its family. If the installed and running versions differ, finish the patch and rebuild,
then reboot.

This setup targets the G2's full 4320×2160 combined mode at 90 Hz. A successful modeset does
not prove the screens are healthy. Put on the headset and make sure both panels are lit and
stable. Stop immediately if they flicker badly or make you feel unwell.

## SteamVR cannot acquire the display

Close GPU-heavy programs and try again. Low free VRAM has allowed the SteamVR compositor to
start without successfully taking the G2 display.

On Wayland, `diagnose` shows the relevant compositor error. An unclean SteamVR exit can also
leave the display lease stuck. Stop VR cleanly first. If that does not help, log out and
back in or restart the desktop session.

## One controller floats away or loses tracking

This is usually a Lighthouse radio problem. Check the simple things before pairing again:

- use one Watchman receiver for each controller;
- put both receivers on extension leads;
- keep them away from the computer and other fast USB devices;
- separate them from each other; and
- make sure both base stations can see the controllers.

The hardware check reports each receiver separately. Poor dongle placement can make one
controller look fine while the other repeatedly flies away.

## Both controllers are in the wrong place

If they have been wrong since startup, repeat a normal Space Calibrator calibration. Hold
the chosen controller firmly against the headset and move them together through the full
figure-eight motion. Any movement between them gives Space Calibrator a bad transform.

Then run:

```bash
./scripts/beat-saber-index.sh ready 1.77
```

Replace `1.77` with your real standing eye height.

## The controllers become slightly offset after a song

Heavy movement can produce a small offset between the G2 headset and Index controllers. We
noticed this most after FitBeat maps with squats, jumps, and quick side-to-side movement.
It was usually good for one song, then needed a quick resync.

Pause between songs and open **Space Calibrator** from the SteamVR menu. Keep the same G2
reference and Index target, select **Fast**, press the controller firmly against the
headset, and run calibration. There is no need to restart Beat Saber or SteamVR.

This appears to be relative drift between the two tracking spaces, but the exact cause has
not been proven.

## Looking up or down shifts my position

Sometimes a large up/down head movement causes a small position change as well as rotation.
It normally settles again quickly. Basalt may be briefly losing and reacquiring its room
position, but that explanation is still a working theory.

Good lighting and visible room detail help. Avoid blank walls, mirrors, dark rooms, and
covering the G2 cameras with your hands.

If the error is mainly height and does not settle, use the stillness correction below.

## My height is too high or too low

For a moderate height error:

1. Stand upright at play centre.
2. Look straight ahead.
3. Keep your head completely still for at least 8 seconds.

Height recovery then starts moving the view toward your saved eye height at 5 cm per
second. It only runs while the headset is tracked, level, upright, inside the safe area, and
still enough. Moving your head resets the wait.

If the floor or full play space is wrong, use **Set floor again** or run:

```bash
./scripts/beat-saber-index.sh floor 10
```

Keep the headset off the floor. Wear it at play centre during the countdown. The launcher
will not save a floor from a tilted, unstable, or implausible pose.

If tracking has completely diverged, stop the whole VR session and start again in a
well-lit room with visible detail.

## Beat Saber is stuttering

Check the game's SteamVR render resolution first. SteamVR sometimes chooses a very high
per-application value, which can destroy frame rate even when the rest of VR is healthy.

Open **SteamVR Settings → Video → Per-Application Video Settings → Beat Saber**. Set it to
100% as a starting point, then lower it if the GPU still cannot hold the frame rate. Also
close programs using a lot of GPU memory.

## A map freezes or the controllers load on the floor

Restart only the managed game first:

```bash
./scripts/beat-saber-index.sh restart-modded
```

This keeps SteamVR, the saved floor, and Space Calibrator alive. If the ready check also
fails, stop the full session and recalibrate instead.

## Steam crashes when I open the VR desktop

Use **Start VR + modded Beat Saber** instead of launching the game through SteamVR's desktop
view. Desktop capture repeatedly crashed Steam on the test PC. The launcher starts Steam
with PipeWire support and warns if Remote Play hosting is enabled, but direct game launch is
still the dependable option on that machine.

This may not affect every Linux desktop, so the launcher does not silently disable Remote
Play or remove SteamVR features.

## Audio works but SteamVR's volume slider does not

Use the control panel's volume setting, or run:

```bash
./scripts/beat-saber-index.sh volume 65
```

The launcher controls the G2's PipeWire sink directly. If it cannot find the sink, rerun the
USB check and wake the headset before changing the volume.

## Finding logs

Launcher logs are under `~/.cache/reverb-g2`. SteamVR's OpenVR log folder is discovered with
`vrpathreg.sh`, so it may not be where a generic guide expects. Run `diagnose` to print the
resolved paths and recent errors.
