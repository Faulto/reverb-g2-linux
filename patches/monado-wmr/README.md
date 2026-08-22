# Project-VR Monado patch series

Base: `AshishKumar4/monado-wmr` commit
`9893ba4cb0dabe45e2383c2270fa0f3d4ed79ab2` from the
`g2-linux-integration` branch.

The files are applied in lexical order with `git apply` by
`scripts/setup-index-controllers.sh`. Together they reproduce the source used by
the physically verified G2 + SteamVR session:

| Patch | Purpose |
|---|---|
| 0001–0003 | OpenCV 5 and GCC 16 build compatibility |
| 0004 | Treat a failed WMR tracking-camera open as a device failure instead of crashing |
| 0005 | Expose PipeWire playback/recording node names to SteamVR |
| 0006 | Separate position and orientation One Euro filter controls |
| 0007 | Reject non-finite, discontinuous, over-speed, and runaway SLAM poses; reset after sustained corruption |
| 0008 | Forward optional head angular velocity so SteamVR can predict rotation to photon time |
| 0009 | Bound the session tracking volume, hold the last safe pose, and recover moderate upright height drift without moving controllers independently |
| 0010 | Keep IMU/camera tracking alive when the v1 cable’s separate companion-control interface drops; use non-blocking retry backoff adapted from Wintch/reverb-g2’s measured fix |

The setup script first constructs the expected final tree in a disposable
clone. An existing source tree is accepted only if its tracked modifications
are byte-for-byte identical to this entire series, preventing hand-edited
build drift from being mistaken for a reproducible fix.

These patches modify Monado source and remain subject to Monado's upstream
Boost Software License; see `LICENSES/README.md` at the repository root.
