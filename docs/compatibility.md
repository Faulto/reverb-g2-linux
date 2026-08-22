# Compatibility

The launcher finds most paths, USB devices, displays, and audio nodes automatically. That
helps it work on different PCs, but it does not mean every combination has been tested yet.

## Fully tested setup

| Part | What was tested |
|---|---|
| Headset | HP Reverb G2, including a v1 cable |
| Display | Full 4320×2160 combined mode at 90 Hz |
| Linux | Arch Linux with Plasma Wayland; Debian 13 for NVIDIA display-driver testing |
| GPU | NVIDIA RTX 5080 and RTX 3060 Ti |
| NVIDIA driver | Open kernel modules 610.57.04 and 595.71.05 |
| Head tracking | Project-VR Monado with Basalt visual-inertial tracking |
| Controllers | Index controllers with two Watchman receivers |
| Space alignment | OpenVR Space Calibrator for Linux |
| Game | Native SteamVR and Beat Saber, including a modded BSManager instance |

## Built in, but still needs more testers

The dependency installer supports Arch, Debian/Ubuntu, and Fedora package managers. The
launcher also handles:

- native Steam libraries outside the usual folder;
- XDG path overrides;
- changing DRM card and DisplayPort numbers;
- source trees outside `~/vr`;
- changing PipeWire audio node numbers; and
- BSManager content stored on another filesystem.

We still need fresh, physical tests on:

- current Ubuntu and Fedora releases;
- GNOME Wayland and more X11 desktops;
- AMD and Intel GPUs;
- the G2 rev2 cable; and
- NVIDIA drivers newer than the tested 595 and 610 families.

If you try one of these, a successful build is useful but not enough. Please confirm that
both G2 panels light properly, run at 90 Hz, and remain stable during real head movement.

## Not supported right now

- **Native G2 motion controllers.** The earlier experiments did not produce one clean,
  repeatable patch series with tracking reliable enough for this launcher.
- **Flatpak Steam.** This setup expects native Steam and SteamVR paths, runtime files, and
  driver registration.
- **Flatpak BSManager integration.** BSManager itself offers a Flatpak, but this launcher
  currently reads the native app's config and executable. Use a native BSManager package.
- **NVIDIA's proprietary kernel module.** The display patches target NVIDIA's published
  open-module source.
- **Automatic patching of an unknown NVIDIA family.** The tool refuses to guess.
- **Permanent G2/Lighthouse alignment without recalibration.** Without a Lighthouse tracker
  fixed to the HMD, very active play can still need a Fast Space Calibrator resync.

## Overrides for unusual installs

Most people should not need these. Run `./scripts/beat-saber-index.sh paths` first to see
what the launcher found on its own.

| Variable | Use it to change |
|---|---|
| `G2_VR_ROOT` | Parent folder for Monado, Basalt, and Space Calibrator source |
| `STEAM_ROOT` | Native Steam root |
| `STEAMVR_DIR` | SteamVR installation folder |
| `BEAT_SABER_DIR` | Normal Steam Beat Saber folder |
| `MONADO_DIR` | Project-VR Monado source and build folder |
| `BASALT_DIR` | Basalt source and build folder |
| `SPACECAL_DRIVER_DIR` | Installed Space Calibrator SteamVR driver |
| `G2_DRM_CONNECTOR` | Exact G2 DRM connector, for diagnosis only |
| `BSMANAGER` | Native BSManager executable |
| `BSMANAGER_CONFIG` | Native BSManager `config.json` file |
| `NVIDIA_SOURCE_DIR` | Exact NVIDIA open-module source folder |

## Sending a compatibility report

Please include:

- distribution and release;
- kernel version;
- desktop and whether it uses X11 or Wayland;
- GPU and driver version;
- NVIDIA open or proprietary module type, when relevant;
- G2 cable revision;
- USB controller and topology;
- controller hardware;
- the display mode reported by Linux; and
- what you actually saw in both panels.

Frame rate, build success, or a reported 90 Hz mode alone does not confirm that the display
works correctly.
