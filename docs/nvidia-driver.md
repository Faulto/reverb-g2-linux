# NVIDIA driver management

The G2's EDID leaves color depth undefined. On the tested NVIDIA releases, the driver chose
a 6-bpc DisplayPort link and could not light the native 90 Hz mode correctly. The tracked
patch series fixes the G2 link configuration, color-depth range, and the supporting VR
display path.

## Supported drivers

| Driver family | Applied patches | Tested result |
|---|---|---|
| NVIDIA open 595.71.05 | `0001` through `0005` | Native 4320×2160 at 90 Hz |
| NVIDIA open 610.57.04 | `0003` through `0005` | Native 4320×2160 at 90 Hz |

The manager has series mappings only for the 595 and 610 families and validates every hunk
against the installed source before changing it. The table above lists the exact versions
that were physically tested. A later point release may already contain some fixes or may
change private NVKMS source; a successful patch application is not enough to call it
verified without a DKMS build, boot-image check, and physical headset test.

## Check the current system

```bash
./scripts/nvidia-g2-patch-manager.sh status
```

The report distinguishes the running driver from the installed on-disk module. If they
differ, a package update is waiting for a reboot. The on-disk source is audited so it can be
patched before the reboot.

The manager also reports:

- whether the open kernel module is loaded;
- the exact matching source tree under `/usr/src`;
- the state of every required patch;
- the DKMS build for the current kernel; and
- the G2 connector and exposed display modes when the headset is awake.

## Validate without changing the system

```bash
./scripts/nvidia-g2-patch-manager.sh validate
```

Validation copies only the touched source files into a temporary tree and applies the full
series there. It does not edit `/usr/src` or rebuild a module.

## Apply and rebuild

```bash
./scripts/nvidia-g2-patch-manager.sh apply
```

The script requests root access only when it is ready to modify the real source tree. It:

1. validates the complete patch series on temporary copies;
2. saves the original touched files under `/var/backups/reverb-g2-nvidia/<version>/`;
3. applies missing patches to the matching source tree;
4. rebuilds the module through DKMS for the current kernel; and
5. refreshes mkinitcpio, update-initramfs, or dracut as detected.

It rebuilds even when the source already contains the patches. This repairs the case where
the source is correct but the installed or boot-image module is stale. It never reboots
automatically.

After reboot:

```bash
./scripts/nvidia-g2-patch-manager.sh status
./scripts/nvidia-g2-patch-manager.sh initramfs-check
./scripts/g2-preflight.sh all
```

The exact embedded-module comparison currently targets dracut with systemd-boot. The apply
path still refreshes mkinitcpio and update-initramfs systems, but their check reports this
limitation rather than pretending to compare the boot image.

## After a distribution driver update

1. Do not assume the patched source or old DKMS module survived.
2. Run `status` against the newly installed version.
3. If the family is supported, run `validate` and `apply`.
4. Reboot manually.
5. Run `status`, the boot-image check where supported, and the full G2 preflight.

If the manager refuses the new family, keep the previous working driver or test a port in a
separate environment. Do not force an old patch onto changed NVKMS source.

## Recovery

Keep a fallback kernel or boot entry. If a rebuilt NVIDIA module fails, boot the fallback
entry, restore the corresponding files from `/var/backups/reverb-g2-nvidia`, and reinstall
the distribution driver package or rebuild DKMS normally.

The individual changes and their upstream origins are documented in
[`patches/nvidia/README.md`](../patches/nvidia/README.md).
