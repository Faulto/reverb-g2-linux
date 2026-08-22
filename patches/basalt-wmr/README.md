# Basalt patch series

Base: `mateosss/basalt` commit
`df6e970c8da7636eb401a09e3317fbeaaf829b9a`.

Patches 0001–0012 are imported unchanged from
[`Wintch/reverb-g2`](https://github.com/Wintch/reverb-g2), audited at commit
`0bb5bbb21627158d154fbaacafa4f622046786f1`. Their commit metadata and
co-authorship are kept in each patch.

The useful behavior changes are:

| Patches | What they change |
|---|---|
| 0001–0002 | Bound the tracker output and camera-input queues. The upstream G2 tests measured frame-to-pose age falling from 819 ms to 109 ms and resting position residual falling from 9.8 mm to 0.57 mm. |
| 0003–0006 | Add opt-in `VIT_COLLAPSE_LOG` instrumentation. These are inactive unless that environment variable is set. |
| 0007–0008 | Stop an empty IMU queue from blocking visual tracking until it collapses to roughly 1.5 Hz. The non-blocking recovery is on by default and can be disabled with `BASALT_IMU_NONBLOCK_CATCHUP=0`. |
| 0009–0010 | Shorten the optical-flow-to-VIO queue without enabling the measured-bad drop-oldest behavior. `BASALT_VISION_NONBLOCK=0` restores the stock queue; `BASALT_VISION_DROP_OLDEST=1` exists only for diagnosis. |
| 0011 | Bound statistics storage that otherwise grew by about 72 MB per hour in the upstream nine-hour test. |
| 0012 | Give Basalt worker threads recognizable names for performance diagnosis. |
| 0013 | Expose this launcher’s `BASALT_FEATURE_RECALL=off|front|all` setting. |

The `legacy/` directory contains the previous recall-only series. It is not
applied to a fresh build; the setup script uses it only to recognize and safely
migrate installations made by an older release.

These files modify Basalt source and remain subject to Basalt’s BSD-3-Clause
license. See `LICENSES/README.md` at the repository root.
