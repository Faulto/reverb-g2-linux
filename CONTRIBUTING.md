# Contributing

This project touches a direct-display path where a successful API return does
not prove that either G2 panel is lit. Changes are welcome, but hardware claims
must say exactly what was tested.

Before opening a pull request:

1. Run `./scripts/check-publishable.py`.
2. Run `./scripts/setup-index-controllers.sh verify` if changing the supported
   Monado/Basalt/Space Calibrator path.
3. Run `./scripts/nvidia-g2-patch-manager.sh validate` if changing the NVIDIA
   series.
4. Record the distribution, kernel, GPU and driver, desktop session, headset
   revision/cable, refresh mode, controller path, and physical panel result.
5. Do not include hardware serials, MAC addresses, account names, absolute
   home paths, raw proprietary firmware, or generated binaries.

The working source trees are intentionally not submodules. Patches must apply
in lexical order to the pinned commits documented beside each series. If a pin
changes, update CI and report a complete physical retest; a successful build is
not enough.

Historical lab scripts are retained as evidence and may be machine-specific.
New user-facing work belongs in the maintained setup, preflight, launcher, and
control-panel entry points listed in `docs/68-portability-and-public-release.md`.
