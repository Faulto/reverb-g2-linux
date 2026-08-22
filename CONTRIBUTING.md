# Contributing

Changes are welcome, especially reports from hardware and distributions not yet listed in
[the compatibility matrix](docs/compatibility.md).

Before opening a pull request:

1. Run `./scripts/check-publishable.py`.
2. Run `./scripts/setup-index-controllers.sh verify` after changing the Monado, Basalt, or
   Space Calibrator setup.
3. Run `./scripts/nvidia-g2-patch-manager.sh validate` after changing the NVIDIA series.
4. Run ShellCheck on the maintained shell entry points listed in `.github/workflows/ci.yml`.
5. State the distribution, kernel, GPU and driver, X11 or Wayland desktop, G2 cable revision,
   controller path, display mode, and physical result.

A successful API call, reported refresh rate, or passing build does not prove the G2 panels
are lit and stable. Mark hardware results as physically verified only when someone wore the
headset and checked both panels.

Do not commit account names, hardware serials, MAC addresses, absolute personal paths, raw
firmware, host diagnostic archives, screenshots, or generated binaries.

The source trees built under `G2_VR_ROOT` are not submodules. Patch files must apply in
lexical order to the pinned commits documented beside each series. Changing a pin requires
a complete build and physical retest.
