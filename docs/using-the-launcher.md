# Using the launcher

The desktop control panel is the easiest way to run this setup. It uses the same commands
shown below and opens a terminal so you can see what passed or failed.

## Starting a normal session

1. Turn on the base stations and both Index controllers.
2. Open **Reverb G2 VR Control Panel**.
3. Click **Hardware check** if you want to test everything without starting VR.
4. Click **Start VR**, or **Start VR + modded Beat Saber**.
5. Wait for the checks-passed message. If a required check fails, the countdown will not
   start.
6. Click **Begin**, pick up the G2, and use the 10-second countdown to stand upright at play
   centre, facing your usual forward direction.
7. Run **Ready check** before playing.
8. Click **Stop VR** when you finish. This turns off the panel and restores Monado as your
   normal OpenXR runtime.

You do not have to hold the headset while the hardware checks run. The important part is
wearing it in the right place before the countdown reaches zero.

## In-headset controls

Open the SteamVR dashboard, choose **Space Calibrator**, then open **G2 Controls**. It has
two large controller-friendly buttons:

- **Start modded Beat Saber** launches BSManager's last configured modded instance without
  opening the SteamVR desktop.
- **Set floor** gives you 10 seconds to stand upright at play-centre, then runs the normal
  validated floor capture. A failed stability or pose check keeps the previous floor.

The normal calibration screen also uses taller device rows, a full-width **Start
Calibration** button, and a larger **Close** button after tracking sync completes.

## Useful commands

| Command | What it does |
|---|---|
| `./scripts/beat-saber-index.sh start-ui` | Checks the hardware, shows the confirmation, and starts VR after the countdown |
| `./scripts/beat-saber-index.sh start-modded-ui` | Starts VR and then opens the selected BSManager Beat Saber version |
| `./scripts/beat-saber-index.sh ready 1.77` | Checks the floor, HMD, controllers, and Space Calibrator |
| `./scripts/beat-saber-index.sh floor 10` | Sets the floor again after a 10-second positioning countdown |
| `./scripts/beat-saber-index.sh restart-modded` | Restarts a stuck modded game without restarting VR |
| `./scripts/beat-saber-index.sh stop-game` | Stops Beat Saber but leaves VR running |
| `./scripts/beat-saber-index.sh stop` | Stops the whole session and turns off the G2 panel |
| `./scripts/beat-saber-index.sh diagnose` | Shows paths, USB and display state, running processes, and recent errors |
| `./scripts/beat-saber-index.sh paths` | Shows where Steam, SteamVR, audio, and mod-manager files were found |
| `./scripts/beat-saber-index.sh jitter 10` | Records 10 seconds of stationary headset jitter |

Only run the jitter test with the headset resting on something solid and its cameras clear.
Holding it in your hands records normal body movement, which makes the result useless.

## Floor and height

Every full start checks your upright pose and makes a fresh 5×5 m standing area. The safe
vertical range runs from the floor to 40 cm above your saved standing eye height.

If your view ends up a little too high or low, try the automatic correction first:

1. Stand upright at play centre.
2. Look straight ahead rather than up or down.
3. Keep your head completely still for at least 8 seconds.

The correction then moves your height toward the saved 1.77 m value at 5 cm per second. A
20 cm error therefore needs roughly four more seconds after the initial wait. Change the
saved eye height in **Settings** if 1.77 m is not right for you.

This only fixes moderate vertical drift. If the floor or the whole play space is wrong,
stand at play centre and use **Set floor again**, or run:

```bash
./scripts/beat-saber-index.sh floor 10
```

To save only the standing origin with a known eye height:

```bash
./scripts/beat-saber-index.sh origin set 1.77
```

The launcher refuses to save a floor from unstable, tilted, out-of-range, or implausibly
distant tracking. A failed attempt leaves your previous origin alone.

## Quick controller resync

Very active play can leave the Index controllers with a small offset. We normally notice it
after a FitBeat song with lots of squats and side-to-side movement.

You can fix it without restarting the game:

1. Pause between songs and open the SteamVR menu.
2. Open the Space Calibrator overlay.
3. Choose the same G2 reference and Index-controller target used before.
4. Select **Fast**.
5. Press that controller firmly against the headset and run calibration.

The saved correction applies to both controllers. If one controller is floating away on
its own, check its receiver placement instead; that is a radio problem, not calibration.

## Tracking settings

The tested defaults are dead-reckoning prediction, SteamVR angular prediction at 100%, front
camera landmark recall, camera auto-exposure, no tracking smoothing, and height recovery
after 8 seconds. These are the defaults for a new install.

The control panel explains each option. Change one at a time and restart VR between tests:

- **Smoothing** can hide small stationary movement. Full smoothing also delays rotation and
  may feel uncomfortable.
- **SLAM prediction** controls how Monado estimates movement after the latest Basalt pose.
  Dead reckoning worked best on the tested G2.
- **SteamVR angular prediction** helps the compositor predict head rotation. It does not
  change Basalt itself.
- **Landmark recall** lets Basalt reuse older visual landmarks. Front-camera recall is the
  tested default. The patched cache keeps live and recent landmarks but cannot grow without
  limit. All-camera recall still costs more processing time.
- **Unified exposure** is experimental. Leave it off unless you are testing a lighting
  problem.
- **Height recovery** corrects moderate false vertical drift while you remain upright,
  level, and still. It does not change Lighthouse controller coordinates.

The patched driver also rejects impossible jumps and excessive-speed poses before they
reach SteamVR. Your choices are stored in `~/.config/reverb-g2/session.conf` and take effect
the next time VR starts.

The launcher also watches `vrserver` while VR is running. Normal use is far below the 4 GB
limit. If its real memory use stays above that limit for three checks, the launcher closes
the session and powers off the panel before the desktop is forced into heavy swapping. Run
`diagnose` to see the guard state and its latest messages.

## Beat Saber performance

If Beat Saber starts stuttering, check its SteamVR render resolution first. SteamVR can
occasionally choose a much higher per-game resolution than expected. Do not assume 100% is
correct: the pixel size behind that percentage can itself be the problem.

Open **SteamVR Settings → Video → Per-Application Video Settings → Beat Saber**, switch to a
custom value, and check the dimensions shown. The G2 has 2160×2160 pixels per eye, or
4320×2160 across both panels. A render target around the physical panel resolution is a good
performance check, but it may look blurry because the image is warped for the lenses. The
tested system used a custom 4320×2160 setting as its normal clarity/performance balance.

Restart Beat Saber every time you change this setting. In testing, the running game often
kept the old render size. Use **Restart modded Beat Saber** so SteamVR, the floor, and Space
Calibrator stay running. Lower the custom resolution if the game still stutters; raise it
gradually if performance is good but the image is too soft.

If a map freezes or the controllers load on the floor, click **Restart modded Beat Saber**:

```bash
./scripts/beat-saber-index.sh restart-modded
```

This keeps SteamVR, the floor, and Space Calibrator running. The direct launcher also avoids
SteamVR's desktop view, which repeatedly crashed Steam on the test PC. Steam is started with
`-pipewire`, but direct game launch is still the reliable route there.

## Audio

SteamVR's headset-volume slider does not control the G2 reliably in this setup. Use the
control panel or one of these commands instead:

```bash
./scripts/beat-saber-index.sh volume status
./scripts/beat-saber-index.sh volume 65
./scripts/beat-saber-index.sh volume +5%
./scripts/beat-saber-index.sh volume mute
```

The 65% default is also a display-stability workaround for the v1 cable. At higher headset
volume, the tested G2 sometimes switched off one panel and then the other before recovering.
Keeping the startup volume at 65% stopped those resets. The exact electrical cause has not
been confirmed, but the behaviour points to the v1 cable or cable-box power limit.

If a panel reset shifts your tracking height, first stand upright, look level, and remain
still for the height correction. Use **Set floor again** if the full play space has moved.
