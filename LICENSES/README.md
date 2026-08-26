# Licensing map

Original scripts, documentation, and configuration in this repository are
licensed under the root MIT license.

Patch files contain small portions of the upstream projects they modify and
remain subject to the corresponding upstream license:

| Path | Upstream project | License copy |
|---|---|---|
| `patches/monado-wmr/` | Monado / Project-VR Monado | `Boost-1.0.txt` |
| `patches/basalt-wmr/` | Basalt | `BSD-3-Clause-Basalt.txt` |
| `patches/space-calibrator/` | OpenVR Space Calibrator for Linux | `MIT-Space-Calibrator.txt` |
| `patches/nvidia/` | NVIDIA open-gpu-kernel-modules | `NVIDIA-open-kernel-modules-COPYING.txt` |

Source trees and binaries are not vendored. The setup scripts download them
from their respective upstream projects, whose licenses continue to apply.
