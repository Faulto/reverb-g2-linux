# Setting up BSManager

This repo does not download or install BSManager. It also does not download Beat Saber
versions or decide which mods to install. Those choices stay in BSManager, where you can see
exactly what is being downloaded.

Once BSManager is ready, our launcher reads its config and starts the last managed version
directly through Proton. That avoids SteamVR's desktop view and keeps the VR startup routine
in one place.

## Before you start

You need to own Beat Saber on Steam and have native Steam installed. Open Steam and SteamVR
at least once before continuing.

Use a **native Linux BSManager package** with this launcher. Flatpak BSManager has a
sandboxed config location that is not supported yet. Flatpak Steam is also outside the
supported setup.

## 1. Install BSManager

Use the current package for your distribution from the official
[BSManager releases page](https://github.com/Zagrios/bs-manager/releases). The upstream
[Linux install guide](https://github.com/Zagrios/bs-manager/wiki/install-bsmanager-on-linux)
lists the maintained choices:

- **Arch:** install `bs-manager-git` from the AUR.
- **Debian or Ubuntu:** use the official guide's repository, or download its `.deb` package.
- **Fedora:** download the `.rpm` package from the release page.
- **NixOS:** install the `bs-manager` package from nixpkgs.

The executable should be available as `bs-manager` on `PATH`. A portable native copy also
works at `~/.local/opt/bs-manager/bs-manager`. For another location, start the control panel
with `BSMANAGER=/full/path/to/bs-manager`.

Open **Reverb G2 VR Control Panel → Beat Saber mods** after installation. It should open
BSManager. You can also start it normally from your desktop application menu.

## 2. Choose the content and Proton folders

BSManager asks for these on its first run:

- **Installation/content folder:** the default `~/.local/share/BSManager` worked in our
  testing and is fine with Proton. Another drive is also fine.
- **Proton folder:** choose the exact Proton version folder containing both the `proton`
  file and `files/bin/wine64`. Do not choose the parent `compatibilitytools.d` or
  `steamapps/common` folder.

Steam's Proton versions are usually under a Steam library's `steamapps/common` folder.
GE-Proton is commonly under `~/.local/share/Steam/compatibilitytools.d`. BSManager's folder
picker checks the required files, so it will reject the wrong level.

## 3. Add a Beat Saber version

In BSManager:

1. Open **Add Versions**.
2. Pick a Beat Saber version for which BSManager currently offers Core mods.
3. Choose **Steam** as the platform.
4. Sign in through BSManager or use its Steam mobile QR option.
5. Wait for the download to finish.

BSManager uses DepotDownloader for official Steam versions. It says it does not store your
Steam login details. This repo never receives or reads those credentials; it only reads the
finished instance paths from BSManager's local config.

Do not pick a version only because it is the newest. Beat Saber mods are version-specific,
and a slightly older version may have much better mod support.

## 4. Install the mods

Select the downloaded game on the left, then open its **Mods** tab. Select the mods you want
and click **Install or Update**. At minimum, let BSManager install the Core mods for that
game version.

A copy is ready for our launcher when its game folder contains:

- `Beat Saber.exe`;
- `winhttp.dll`; and
- a top-level `Plugins` folder.

Launch that managed version once from BSManager. Reach the main menu, then close the game.
This finishes the first-run mod setup and records it as BSManager's last launched version.

## 5. Check the connection to this launcher

From the Reverb G2 Linux repository, run:

```bash
./scripts/beat-saber-index.sh paths
```

Check the `BSManager`, `BSManager config`, `BSManager content`, and `Proton` lines. They
should point to the native app and the folders you just selected.

You can now use **Start VR + modded Beat Saber**. The launcher checks the config, Proton,
game executable, `winhttp.dll`, and `Plugins` folder before it starts the headset. It then
runs the game directly; BSManager does not need to stay open.

## Switching game versions

The VR button always starts the version recorded as **last launched** by BSManager. To
switch versions:

1. Open **Beat Saber mods** in the control panel.
2. Select the other managed version.
3. Update its mods if needed.
4. Launch it once from BSManager, reach the menu, and close it.

The next **Start VR + modded Beat Saber** session will use that version.

## Common setup errors

### BSManager was not found

Install a native package and make sure `bs-manager` runs from a terminal. Flatpak BSManager
is not detected by this launcher.

### BSManager config is missing

Open BSManager once and finish choosing its content and Proton folders. The native config
should appear at `~/.config/bs-manager/config.json`.

### No complete last-version or Proton configuration

Select a Proton folder, install a Beat Saber version, then launch that managed version once
from BSManager.

### The instance is not modded

Open that version's **Mods** tab and install or update the Core mods. Launch it once from
BSManager afterward.

### The wrong version starts

Open the version you want in BSManager and launch it once. Our launcher follows BSManager's
last-launched version rather than keeping a separate hard-coded game path.
