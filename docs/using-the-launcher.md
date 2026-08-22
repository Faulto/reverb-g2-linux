# Using the launcher

The desktop control panel is the recommended interface. It runs the same commands shown
below and leaves failures visible in a terminal.

## Normal session

1. Put the headset at play-centre with its cameras facing a lit, textured room.
2. Turn on both base stations and Index controllers.
3. Choose **Hardware check**.
4. Choose **Start VR**.
5. When the success dialog appears, pick up the headset and stand upright at play-centre
   during the countdown.
6. Run **Ready check** before launching a game.
7. Choose **Stop VR** when finished so the panel is powered down and Monado is restored as
   the active OpenXR runtime.

If any required hardware check fails, the success dialog never appears and tracking does
not initialize.

## Main commands

| Command | Purpose |
|---|---|
| `./scripts/beat-saber-index.sh start-ui` | Checked SteamVR startup with confirmation and positioning countdown |
| `./scripts/beat-saber-index.sh start-modded-ui` | Start VR, then launch the configured modded Beat Saber instance |
| `./scripts/beat-saber-index.sh ready 1.76` | Check floor, Space Calibrator, HMD, and controller poses |
| `./scripts/beat-saber-index.sh floor 10` | Recreate the standing origin after a ten-second positioning delay |
| `./scripts/beat-saber-index.sh restart-modded` | Restart a stuck modded game without restarting SteamVR |
| `./scripts/beat-saber-index.sh stop-game` | Stop Beat Saber but leave VR running |
| `./scripts/beat-saber-index.sh stop` | Stop the complete session and power off the panel |
| `./scripts/beat-saber-index.sh diagnose` | Show resolved paths, USB/display state, processes, and recent errors |
| `./scripts/beat-saber-index.sh paths` | Show dynamically discovered Steam, VR, audio, and mod-manager paths |
| `./scripts/beat-saber-index.sh jitter 10` | Record a ten-second stationary pose-jitter sample |

Run the jitter test only with the headset resting rigidly and the cameras unobstructed. A
hand-held sample contains real body motion and is not a useful smoothing measurement.

## Floor and height

Every successful full startup validates the upright pose and creates a fresh 5×5 m standing
space. This avoids carrying a stale Basalt origin across a reboot.

If the floor becomes wrong without a complete tracking failure, stand at play-centre and
run:

```bash
./scripts/beat-saber-index.sh floor 10
```

To set only the standing origin with a known eye height:

```bash
./scripts/beat-saber-index.sh origin set 1.76
```

Floor capture refuses unstable, tilted, out-of-range, or implausibly distant tracking. A
failed capture does not overwrite the saved origin.

## Tracking mitigations

The patched Monado driver includes two layers of protection:

- invalid, discontinuous, excessive-speed, and runaway SLAM poses are rejected before they
  reach SteamVR; and
- the session is limited to a 5×5 m horizontal area and from the floor to 40 cm above the
  configured standing eye height.

The default tracking profile uses dead-reckoning prediction, SteamVR angular prediction at
100%, camera auto-exposure, tracking smoothing off, feature recall off, and upright height
recovery after eight seconds of still, level tracking.

Change one tracking option at a time:

- **Smoothing** reduces stationary translation jitter. Full smoothing also filters rotation
  and can add uncomfortable head-motion latency.
- **SLAM prediction** controls how Monado advances the latest Basalt pose. Dead reckoning is
  the tested baseline.
- **SteamVR angular prediction** scales the angular velocity exported for final compositor
  prediction. It does not change Basalt internally.
- **Feature recall** reuses old image landmarks. It is experimental and increases CPU and
  memory use, especially in all-camera mode.
- **Unified exposure** is an experimental lighting test. Leave it disabled unless comparing
  a specific camera-exposure problem.
- **Height recovery** slowly returns moderate false vertical drift toward the startup height
  while the headset remains still and level. It does not rewrite Lighthouse coordinates.

Settings are saved in `~/.config/reverb-g2/session.conf` and take effect at the next VR
start.

## Audio

The launcher discovers the G2 PipeWire sink rather than relying on SteamVR's volume slider:

```bash
./scripts/beat-saber-index.sh volume status
./scripts/beat-saber-index.sh volume 65
./scripts/beat-saber-index.sh volume +5%
./scripts/beat-saber-index.sh volume mute
```

## Beat Saber

The modded launcher starts BSManager's last managed version directly through its selected
Proton build. This avoids walking back to the desktop after tracking calibration and avoids
using SteamVR's desktop overlay.

If a map is frozen or the controllers remain on the floor, use **Restart modded Beat Saber**
before restarting the complete VR session:

```bash
./scripts/beat-saber-index.sh restart-modded
```

The normal SteamVR desktop view has crashed Steam on the verified machine. The launcher
starts Steam with `-pipewire`, but direct game launch remains the reliable path. It also
warns when Steam Remote Play hosting is enabled because desktop capture caused the same
failure during testing.
