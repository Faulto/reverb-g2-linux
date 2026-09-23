# NVIDIA driver updates

The Reverb G2 does not specify its colour depth in the EDID. On the NVIDIA releases we
tested, the driver chose a 6-bpc DisplayPort link and could not light the full 90 Hz mode
correctly. This repo carries the small driver patch series used to get a stable 8-bpc link.

Your normal package manager still installs and updates NVIDIA. This tool patches the
matching open-module source afterward, rebuilds DKMS, and updates the boot image.

## Supported drivers

| Driver | Patches used | Result tested in the headset |
|---|---|---|
| NVIDIA open 595.71.05 | `0001` to `0005` | 4320×2160 combined at 90 Hz |
| NVIDIA open 610.57.04 | `0003` to `0005` | 4320×2160 combined at 90 Hz |
| NVIDIA open 615.71.09 | `0003` and `0006` | Source and DKMS verified; headset retest required after reboot |

The manager knows the 595, 610 and 615 driver families. The 595 and 610 versions above have
been physically tested in a headset. NVIDIA 615 changed the relevant NVKMS function, so it
uses a separate exact-context port rather than applying the 610 patches with offsets and
fuzz. A clean build still needs a real 90 Hz headset test after reboot.

The script checks every patch hunk before editing anything. Even so, a clean patch and DKMS
build do not prove that a new driver works. The final test is both G2 screens running
without flicker at 90 Hz.

The patches require NVIDIA's **open kernel module**. Do not apply them to the proprietary
kernel module.

## Check the installed driver

```bash
./scripts/nvidia-g2-patch-manager.sh status
```

This reports:

- the driver currently loaded in memory;
- the driver installed on disk;
- whether the open module is in use;
- the matching source folder under `/usr/src`;
- each required patch;
- the DKMS build for the current kernel; and
- the G2 connector and modes, when the headset is awake.

If the running and installed versions differ, the package update is waiting for a reboot.
The tool audits the new source on disk so you can patch it before rebooting.

## Test the patch without changing anything

```bash
./scripts/nvidia-g2-patch-manager.sh validate
```

This copies only the files touched by the patch into a temporary folder and tests the full
series there. It does not edit `/usr/src` or rebuild the driver.

## Apply the patch

```bash
./scripts/nvidia-g2-patch-manager.sh apply
```

The script waits until it is ready to change the real source before asking for `sudo`. It
then:

1. tests the complete patch on temporary copies;
2. backs up the original files to `/var/backups/reverb-g2-nvidia/<version>/`;
3. applies any missing patches;
4. rebuilds NVIDIA through DKMS for the current kernel; and
5. refreshes the boot image with mkinitcpio, update-initramfs, or dracut.

It rebuilds DKMS even if the source already contains every patch. This fixes the common
case where `/usr/src` is correct but the installed module or boot image is stale.

The tool never reboots automatically. When it tells you to reboot, do that yourself and
then run:

```bash
./scripts/nvidia-g2-patch-manager.sh status
./scripts/nvidia-g2-patch-manager.sh initramfs-check
./scripts/g2-preflight.sh all
```

The exact embedded-module comparison currently works with dracut and systemd-boot. On
mkinitcpio and update-initramfs systems, `apply` still refreshes the boot image, but the
follow-up check explains that it cannot make the same exact comparison.

## After a normal NVIDIA update

1. Let your package manager finish installing NVIDIA.
2. Run `./scripts/beat-saber-index.sh nvidia status`.
3. For a supported family, run `validate` and then `apply` if patches are missing.
4. Reboot when asked.
5. Run `status`, the boot-image check where supported, and the full G2 preflight.

Do not assume an old DKMS build survived the update. If the manager refuses a new driver
family, do not force an older patch onto it. Keep the previous working driver or test a
proper patch port separately.

## If the rebuilt driver does not load

Keep a fallback kernel or boot entry before patching. Boot that entry, restore the matching
files from `/var/backups/reverb-g2-nvidia`, and reinstall your distribution's NVIDIA package
or rebuild DKMS normally.

The individual changes and their upstream sources are listed in
[`patches/nvidia/README.md`](../patches/nvidia/README.md).
