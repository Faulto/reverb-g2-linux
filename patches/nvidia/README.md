# NVIDIA open-gpu-kernel-modules patches (90Hz for the HP Reverb G2)

Patches 0001–0003 originate from
[AshishKumar4/Project-VR](https://github.com/AshishKumar4/Project-VR)
(`patches/consolidated/nvidia/`, branch `g2-patches-on-595.71.05`) — full credit to
Ashish Kumar Singh for root-causing and fixing NVIDIA bug 5923212. See that repo for the
long-form analysis. This copy corrects 0003's manufacturer-ID byte order and
gates it on the G2 product ID. Patches 0004 and 0005 handle the G2's undefined
EDID color depth.

What each does:

- **0001** — spec-correctness fixes: DisplayID 2.0 Type-VII descriptor stride, VESA DSC 1.1
  RC tables (the 90Hz DSC handshake), `flatnessDetThresh`, MSFT VR VSDB version gate.
  All architecture-generic (`src/common/` + both the Turing/Ampere and Ada/Blackwell
  nvkms paths — our RTX 3060 Ti uses the `nvkms-evo3.c` path, which is covered).
- **0002** — VR HMD DRM-lease enablement. The Wayland lease machinery is dead code on X11,
  **but do not skip this patch**: its `nvkms-modepool.c` hunk marks the HMD's native mode
  highest-resolution VR mode as RandR-preferred, which the X11/SteamVR path needs.
- **0003** — `forceMaxLinkConfig` for the exact raw G2 EDID ID (HPN bytes `22 0e`,
  read by DPLib as `0x0E22`; product `0x36C1`).
- **0004** — treats undefined EDID color depth as an 8-bpc maximum rather than
  incorrectly capping the sink to 6 bpc.
- **0005** — also raises the RGB minimum to 8 bpc for only that exact G2 EDID.
  On NVIDIA 610 this was required for a live 24-bpp attach and stable
  4320×2160 at 90 Hz.

Use `scripts/nvidia-g2-patch-manager.sh`: it discovers the installed open-module
source tree, selects only the physically tested series for NVIDIA 595 or 610,
validates every hunk on a temporary mini-tree, backs up touched source files,
rebuilds DKMS, and refreshes mkinitcpio, update-initramfs, or dracut. It refuses
other driver families until somebody ports and physically verifies them. Never
apply these patches to NVIDIA's proprietary kernel module.
