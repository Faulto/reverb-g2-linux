# Licensing map

Original scripts, documentation, and configuration in this repository are
licensed under the root MIT license.

Patch files contain small portions of the upstream projects they modify and
remain subject to the corresponding upstream license:

| Path | Upstream project | License copy |
|---|---|---|
| `patches/monado/`, `patches/monado-wmr/` | Monado / Project-VR Monado | `Boost-1.0.txt` |
| `patches/basalt/`, `patches/basalt-wmr/` | Basalt | `BSD-3-Clause-Basalt.txt` |
| `patches/nvidia/` | NVIDIA open-gpu-kernel-modules | `NVIDIA-open-kernel-modules-COPYING.txt` |
| `patches/hello_xr-player/` | Khronos OpenXR SDK Source | `Apache-2.0.txt`; the vendored `stb_image.h` patch hunk carries Sean Barrett's dual MIT/public-domain terms inline |

Source trees and binaries are not vendored. The setup scripts download them
from their respective upstream projects, whose licenses continue to apply.
