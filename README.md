# reverb-g2

Running an [HP Reverb G2](https://www.hp.com/gb-en/tech-takes/gaming/review/hp-reverb-g2-review.html)
on Linux — patches, tools, and a procedure manual covering everything from USB topology to
the NVIDIA display driver.

The headset is discontinued and Microsoft removed Windows Mixed Reality in Windows 11 24H2,
so on Windows a G2 now needs either 23H2 or [mbucchia's Oasis
driver](https://github.com/mbucchia/Oasis-Driver-for-Windows-Mixed-Reality). Good optics
going cheap on the used market, with no vendor behind them — which is the whole reason this
repo exists.

Everything documented here was measured on a real rig. Where something does **not** work,
the manual says why and what was tried, including the conclusions that turned out to be
wrong. Several of them did.

**Scope.** The repo is named for the headset, not for an operating system, but effectively
all of the engineering here targets Linux — that is where the headset is not supported and
where the work was needed. Chapters 07, 09, 10 and 12 are Windows-side: they exist because
reading what Windows does to the panel is how several Linux questions got answered.

## The one rule that matters

**Verification is physical. Somebody has to put the headset on and look.**

The Vulkan/OpenXR layer reports a successful modeset and a happy 90.0 fps with the panel
completely dark. Every failure documented here is invisible from above the driver. Any
conclusion based on logs, `xrandr`, or a reported framerate is worthless on this hardware —
and this project produced four confidently wrong conclusions that were all reached that way.

## What works today (2026-08)

There are now two distinct stacks. Do not mix their source trees or patch
directories:

- **Supported, reproducible profile:** G2 display/head tracking through
  Project-VR Monado, native SteamVR, Lighthouse base stations, and Index
  controllers. This is the path physically verified with Beat Saber and built
  by `scripts/setup-index-controllers.sh`.
- **Research profile:** native G2-controller constellation tracking through
  Monado and xrizer. It has extensive live hardware evidence, but the exported
  `patches/monado/` directory records several divergent development lineages
  and is not one installable patch series. It is preserved for continued
  engineering, not advertised as a clean install.

| Area | State |
|---|---|
| Headset display | ✅ 60 Hz via Monado direct mode, X11 and Wayland |
| 90 Hz | ✅ clean at the G2 panel's 4320×2160 native resolution; lower modes remain diagnostic fallbacks — see below |
| Head tracking, 3DoF | ✅ solid (IMU, `WMR_SLAM=0`) |
| Head tracking, 6DoF | ✅ real Basalt SLAM, confirmed across multiple full game sessions (`docs/23`) — occasional divergence on long-uptime sessions, see `docs/06` |
| 360 / VR180 player | ✅ our own, built on `hello_xr`; 8K stereo at 60 fps |
| Headset audio | ✅ works electrically; shares a marginal USB2 contact with the panel, see `docs/22` |
| G2 controllers | 🧪 6DoF research path verified live in Aircar; current exported archive is not cleanly reproducible, and tracking quality remains below commercial-driver reliability (`docs/03`, `docs/55`) |
| Index controllers | ✅ two Watchman receivers + Lighthouse + OpenVR Space Calibrator, physically verified in Beat Saber (`docs/67`) |
| SteamVR (native) | ✅ supported profile works through Project-VR `driver_monado`; the earlier stock/lab Monado path remained lease-blocked |
| SteamVR titles (via [xrizer](https://github.com/The-personified-devil/xrizer)) | ✅ multiple titles confirmed working end to end, bypassing `vrmonitor` entirely — see `docs/23` |
| Cable/connector | ⚠️ known marginal contact (USB2 branch + panel power); reseat procedure in `docs/22`, not yet replaced |

## What came out of this: an NVIDIA driver bug

While chasing 90 Hz we root-caused a separate bug in the NVIDIA display driver, filed
upstream as
**[open-gpu-kernel-modules#1275](https://github.com/NVIDIA/open-gpu-kernel-modules/pull/1275)**
(still open and without a review as of 2026-08-22):

> `nvDpyGetOutputColorFormatInfo()` treats "the EDID did not declare a color depth" as "the
> sink wants 6 bpc" and drives the DisplayPort link at 18 bpp. The DSI branch of the same
> function already treats that input as 8 bpc. This affects **any** DisplayPort sink that
> leaves EDID Color Bit Depth undefined — on an ordinary monitor it shows up as banding,
> which is easy to misattribute to the panel.

Full write-up in [`docs/13-bug-6bpc.md`](docs/13-bug-6bpc.md), and in the
[NVIDIA forum thread](https://forums.developer.nvidia.com/t/379240).

**It was part of the fix — confirmed on NVIDIA 595 in 2026-08.** Patch 0004 stayed
unconfirmed for two extra days for a mundane reason, not a second bug: every retest after
applying it kept reusing the synthetic, injected EDID timings from the earlier
investigation instead of the panel's plain native mode.
[`docs/16-lab-vblank.md`](docs/16-lab-vblank.md) ran a careful factorial across refresh
rate, vertical blanking, and pixel clock on those injected timings and, correctly, found
none of them explained anything — the injected timings were never the actual problem. Once
the plain native EDID mode was retested with the patch applied, both native 90 Hz modes came
up clean. [`docs/13-bug-6bpc.md`](docs/13-bug-6bpc.md) separately closed the USB/HID side of
the investigation from the Windows angle: the headset's own status report is byte-identical
between Linux and Windows, including at the exact moment of a live 60↔90 Hz switch on
Windows (no special command fires). Filed as
[NVIDIA bug 5923212](docs/19-nvidia-bug-5923212-followup.md). Full three-day timeline,
including how the "still open" methodology trap was found, in
[`docs/21-project-retrospective.md`](docs/21-project-retrospective.md).

NVIDIA 610 still chose the generic 6-bpc minimum after that maximum was fixed.
Patch 0005 therefore pins both ends of the RGB range to 8 bpc only for the exact
G2 EDID. The live 610 retest then negotiated 24 bpp and held 4320×2160 at 90 Hz.
Use `scripts/nvidia-g2-patch-manager.sh`; it selects the tested 595/610 series,
validates before editing `/usr/src`, rebuilds DKMS, and refreshes the boot image.

## Getting started: supported Index-controller profile

```bash
./scripts/setup-index-controllers.sh deps
./scripts/setup-index-controllers.sh all
sudo install -m 0644 scripts/70-wmr-reverb.rules /etc/udev/rules.d/
sudo udevadm control --reload-rules
./scripts/install-control-panel.sh
```

This path requires native (non-Flatpak) Steam/SteamVR, two Lighthouse base
stations, two Watchman receiver dongles, and Index controllers. Read
[`docs/67-beat-saber-index-controllers.md`](docs/67-beat-saber-index-controllers.md)
for pairing, calibration, BSManager, recovery, and all launcher commands. Read
[`docs/00-hardware-usb.md`](docs/00-hardware-usb.md) first. If the companion device
`03f0:0580` is missing from `lsusb`, the problem is the USB port, not the software — and
you will waste days debugging Monado if you skip that chapter.

## Daily bring-up

Every session, in this order — this is the procedure, don't improvise it:

```bash
./scripts/g2-preflight.sh all
./scripts/beat-saber-index.sh start-ui
```

The launcher dynamically discovers the Steam library, SteamVR driver registry,
G2 EDID connector, PipeWire node, BSManager instance, and Watchman radios. It
validates USB negotiation and the NVIDIA patch state before turning tracking
on, then gives a positioning countdown and sets the standing origin. Nothing
above is verified until a human has the headset on and looks.

The original `preflight.sh`, `bootstrap-lab.sh`, `jack-in-wayland.sh`, and xrizer
launchers belong to the research profile. `bootstrap-lab.sh sources` is now
fail-closed because the archived Monado patches are explicitly non-linear.

## Layout

```
docs/          the manual, one chapter per procedure
patches/nvidia/            open kernel module patches, incl. the 6 bpc fix
patches/monado-wmr/        reproducible Project-VR Monado series (Index profile)
patches/basalt-wmr/        reproducible Basalt series (Index profile)
patches/monado/            non-linear research archive for native G2 controllers
patches/hello_xr-player/   the 360/VR180 viewer
scripts/       tooling: bring-up, EDID surgery, HID capture, diagnostics
experiments/   the headset's own EDID plus prepared variants for the 90 Hz work
```

## The manual

| | |
|---|---|
| [00](docs/00-hardware-usb.md) | USB topology, the SuperSpeed/USB2 split, and why it breaks |
| [01](docs/01-bringup-monado.md) | Building and running Monado + Basalt |
| [02](docs/02-player-360.md) | The 360/VR180 player: projections, pipeline, measurements |
| [03](docs/03-controllers.md) | Controller state and the 6DoF roadmap |
| [04](docs/04-lab-90hz.md) | The 90 Hz lab: separate install, patched driver, test protocol |
| [05](docs/05-resolve.md) | DaVinci Resolve (a separate goal for the same rig) |
| [06](docs/06-known-issues.md) | What does not work and why, with evidence |
| [07](docs/07-windows-hid-capture.md) | Capturing the Windows HID traffic (archived — see 09) |
| [08](docs/08-passthrough-limits.md) | Passthrough and its limits |
| [09](docs/09-oasis-driver-re.md) | Reverse-engineering the Oasis driver (what Windows sends the panel) |
| [10](docs/10-resources.md) | External resources |
| [11](docs/11-linux-hmd-landscape.md) | The state of HMDs on Linux |
| [12](docs/12-g2-protocol.md) | The G2's own protocol, from USB captures |
| [13](docs/13-bug-6bpc.md) | The 6 bpc clamp: root cause and patch |
| [14](docs/14-nvidia-report.md) | The report filed with NVIDIA |
| [15](docs/15-feedback-triage.md) | Triage of the feedback on that report |
| [16](docs/16-lab-vblank.md) | The vblank factorial: refresh rate vs. timing shape, run to completion |
| [17](docs/17-publishing.md) | Preparing this repo for publication |
| [18](docs/18-monado-upstreaming.md) | Upstreaming the Monado WMR patches |
| [19](docs/19-nvidia-bug-5923212-followup.md) | Follow-up for the NVIDIA 60Hz-only bug thread |
| [20](docs/20-desktop-plasma-crash.md) | A Plasma desktop crash hit during the lab work |
| [21](docs/21-project-retrospective.md) | Project retrospective: machines, timeline, fixes, credits |
| [22](docs/22-cable-connector-diagnosis.md) | Link anatomy + piece-by-piece diagnosis of cable/connector/power |
| [23](docs/23-game-compatibility.md) | Game-by-game compatibility results via xrizer |
| [67](docs/67-beat-saber-index-controllers.md) | Supported G2 + Lighthouse/Index + Beat Saber path |
| [68](docs/68-portability-and-public-release.md) | Support matrix, portability boundaries, and public-release audit |
| [30](docs/30-machine-handoff-protocol.md) | The two-machine topology, and the protocol for handing work off between them without it going stale |
| [34](docs/34-tracking-quaternions-slam.md) | 6DoF tracking architectures, visual-inertial SLAM, and quaternion/Lie-algebra math reference |

## Reference hardware

Debian 13 (trixie) · kernel 6.12 · RTX 3060 Ti (GA104) · HP Reverb G2 (rev B) ·
Ryzen 5 5600X · NVIDIA 595.71.05 open kernel modules

The supported Index profile was also physically verified on Arch Linux,
Plasma Wayland, RTX 5080, NVIDIA 610 open modules, a G2 v1 cable, two Lighthouse
base stations, two Watchman receivers, and Index controllers. This is a support
matrix, not a promise that every Linux/GPU/compositor combination is already
verified; see [`docs/68`](docs/68-portability-and-public-release.md).

## Contributing

See [`CONTRIBUTING.md`](CONTRIBUTING.md) before sending changes. The highest-value
work now is expanding the physical support matrix and turning the G2-controller
research history into one pinned, cleanly reproducible source branch.

What would actually move this forward now:

- **A DisplayPort AUX-channel capture** (a logic analyzer on the AUX+/AUX- pins, decoding
  DPCD read/writes during a 60→90 Hz switch) is the one layer nothing in this repo has been
  able to look at yet — mainly useful now to confirm the backlight-duty hypothesis behind
  the (also resolved) flicker, not the core bug anymore. See the open item at the end of
  [`docs/13-bug-6bpc.md`](docs/13-bug-6bpc.md).
- **Fresh AMD/Intel, X11, GNOME, Fedora, Ubuntu, and G2 rev2-cable reports** using
  the template in `docs/68`, so untested combinations can move into the verified matrix.

If you have (or can donate) an **HP Omnicept** — same headset, plus Tobii eye-tracking —
that matters too: Monado already treats it as a Reverb G2 at the USB level, so a 90 Hz
result there would show whether this is a G2 problem in general or specific to our unit.
See [`docs/10-resources.md`](docs/10-resources.md#the-omnicept-the-same-headset-inside-with-an-extra-sensor).

Everything in this repo is written in English. Measurements beat opinions: if you assert
something, say how you measured it.
