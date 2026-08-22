# Compatibility

The scripts are written to discover system paths and hardware dynamically, but portable
detection is not the same as verified hardware support.

## Physically tested

| Component | Verified configuration |
|---|---|
| Headset | HP Reverb G2, including a v1 cable |
| Display | Native 4320×2160 at 90 Hz |
| Linux | Arch Linux with Plasma Wayland; Debian 13 used during display-driver testing |
| GPU | NVIDIA RTX 5080 and RTX 3060 Ti |
| NVIDIA driver | Open kernel modules, 610.57.04 and 595.71.05 |
| Head tracking | Project-VR Monado with Basalt visual-inertial tracking |
| Controllers | Valve Index controllers through two Watchman receivers |
| Positional alignment | OpenVR Space Calibrator for Linux |
| Game | Native SteamVR with Beat Saber, including a BSManager-managed modded instance |

## Implemented but needing more machines

The dependency installer has package lists for Arch, Debian/Ubuntu, and Fedora. The launcher
supports native Steam libraries outside the default path, XDG path overrides, different DRM
card and DisplayPort numbers, user-selected source roots, PipeWire audio node changes, and
BSManager content on another filesystem.

Fresh reports are still needed for:

- current Ubuntu and Fedora releases;
- GNOME Wayland and additional X11 desktops;
- AMD and Intel GPUs;
- the G2 rev2 cable; and
- NVIDIA releases newer than the tested 595/610 families.

## Not currently supported

- Native Reverb G2 motion-controller tracking. The previous experiments did not form one
  clean, reproducible source series with reliable enough tracking for this tool.
- Flatpak Steam. The supported profile uses native Steam/SteamVR paths, runtime files, and
  driver registration.
- NVIDIA's proprietary kernel module. The included patches target the published open-module
  source tree.
- Automatic patching of an unknown NVIDIA release.
- Continuous Lighthouse/G2 calibration without a tracker physically attached to the HMD.

## Useful overrides

Most systems should not need overrides. Unusual layouts can set:

| Variable | Purpose |
|---|---|
| `G2_VR_ROOT` | Parent directory for Monado, Basalt, and Space Calibrator source trees |
| `STEAM_ROOT` | Native Steam root |
| `STEAMVR_DIR` | SteamVR installation directory |
| `BEAT_SABER_DIR` | Normal Steam Beat Saber directory |
| `MONADO_DIR` | Project-VR Monado source/build directory |
| `BASALT_DIR` | Basalt source/build directory |
| `SPACECAL_DRIVER_DIR` | Installed Space Calibrator SteamVR driver |
| `G2_DRM_CONNECTOR` | Explicit G2 DRM connector for diagnosis only |
| `BSMANAGER` | BSManager executable |
| `NVIDIA_SOURCE_DIR` | Exact NVIDIA open-module source tree |

Run `./scripts/beat-saber-index.sh paths` to see what the launcher discovered before adding
an override.

## Reporting a new configuration

Include the distribution and release, kernel, desktop and X11/Wayland session, GPU, driver
and open/proprietary module type, headset and cable revision, USB controller/topology,
controller hardware, exposed display mode, and the physical result seen in both panels.
Build success or a reported frame rate alone is not a display verification.
