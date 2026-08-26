# Space Calibrator patch series

Base: `xi-ve/openvr-space-calibrator-linux` commit
`28e3f83f7bc9808f145fac03ff8a8e455ab211fe`.

| Patch | What it changes |
|---|---|
| 0001 | Adds a **G2 Controls** dashboard tab for starting the configured modded Beat Saber instance and safely resetting the floor. It also enlarges the device selectors, primary calibration button, identify button, and completed-calibration close button for easier controller use. |

The overlay can invoke only the two fixed actions exposed by
`scripts/vr-overlay-action.sh`; it does not accept arbitrary commands.

These files modify Space Calibrator source and remain subject to its upstream
MIT license. See `LICENSES/README.md` at the repository root.
