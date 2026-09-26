# teamviewer-omarchy-launcher

Makes incoming TeamViewer connections work on [Omarchy](https://omarchy.org/), where Hyprland is started by uwsm from SDDM.

Without it, TeamViewer 15 on Omarchy shows the partner an endless "Connecting to partner…". Once that is fixed, it hangs after the password at "waiting for partner to confirm the request". On a scaled display it then shows no picture at all. This project fixes all three problems per user, with no sudo, and makes no changes to TeamViewer or Omarchy files.

## What it fixes

| Symptom on the connecting side | Cause on this PC | Fix |
|---|---|---|
| Endless "Connecting to partner…". The daemon log says `LaunchDesktopProcess: session bus not found` | TeamViewer finds your D-Bus session bus only through processes like `dbus-daemon` or `gnome-session` inside the login session's process tree. uwsm runs the whole desktop outside that tree. | `omarchy-teamviewer-bus-placeholder`: an idle `dbus-daemon`, started from your login profile inside that tree, that carries the real bus address |
| Password accepted, then "waiting for partner to confirm the request". The helper log says `No such interface "org.freedesktop.portal.RemoteDesktop"` | TeamViewer asks the desktop portal for RemoteDesktop unless `XDG_CURRENT_DESKTOP` contains `wlroots`. xdg-desktop-portal-hyprland doesn't implement RemoteDesktop. | `omarchy-teamviewer-desktop` adds `wlroots` to `XDG_CURRENT_DESKTOP`, so TeamViewer uses its built-in wlroots backend (screencopy plus virtual pointer and keyboard) |
| Connected, but no picture. The helper log says `Unsupported shared memory buffer (... size: 3840x2160, expected size: 3072x1728)` | The wlroots backend compares each frame's pixel size with the monitor's scaled size, so any scale other than 1 fails | While the TeamViewer helper runs, `omarchy-teamviewer-desktop` switches every scaled monitor to scale 1 at the resolution that keeps its layout (e.g. 3072×1728 instead of 3840×2160 at 1.25), and restores it afterwards |

[docs/how-it-works.md](docs/how-it-works.md) covers the full investigation and evidence. [docs/teamviewer-bug-report.md](docs/teamviewer-bug-report.md) is a ready-to-send report for TeamViewer, since all three are TeamViewer bugs.

## Requirements

- Omarchy: Hyprland started by uwsm, SDDM as the login manager. Both the Lua config (`~/.config/hypr/hyprland.lua`, current Omarchy) and the older `hyprland.conf` are supported.
- TeamViewer 15 in `/opt/teamviewer` (AUR `teamviewer`) with its daemon enabled:
  ```sh
  omarchy pkg aur add teamviewer
  sudo systemctl enable --now teamviewerd
  ```
- `jq`, `hyprctl`, `busctl` and `/usr/bin/dbus-daemon`. Omarchy has all of these, including on systems that use dbus-broker.
- A login shell of bash (Omarchy's default), zsh, or anything that reads `~/.profile`.

## Install

```sh
git clone <this repo> ~/Projects/teamviewer-omarchy-launcher   # or copy the folder
cd ~/Projects/teamviewer-omarchy-launcher
./install.sh
```

Then **log out and back in once**, or reboot, so the placeholder starts inside your session. Check the result:

```sh
./status.sh
```

`install.sh` is safe to re-run after pulling changes. It installs, for the current user only:

| File | Purpose |
|---|---|
| `~/.local/bin/omarchy-teamviewer-desktop` | Wrapper that D-Bus starts instead of `TeamViewer_Desktop` |
| `~/.local/bin/omarchy-teamviewer-bus-placeholder` | Placeholder `dbus-daemon` for TeamViewer's session-bus lookup |
| `~/.local/share/dbus-1/services/com.teamviewer.TeamViewer.Desktop.service` | Takes priority over TeamViewer's copy in `/usr/share/dbus-1/services/` and points it at the wrapper |
| A marked block in `~/.bash_profile` (or `~/.zprofile` / `~/.profile`) | Starts the placeholder, only when the shell is SDDM's login shell |

## Using it

- Connect from another machine as usual, with the ID and password.
- As soon as a connection arrives, each scaled monitor switches to scale 1 at a matching lower resolution, so windows and text keep roughly their usual size. It switches back when the session ends. This also happens for attempts that then fail the password.
  - The target is the monitor's scaled size: 3840×2160 at 1.25 gives 3072×1728, and at 2 gives 1920×1080.
  - If the monitor doesn't list that size, the wrapper tries it as a custom mode. If the driver or monitor refuses it, the wrapper uses the closest listed mode with the same aspect ratio. On the test PC (NVIDIA, HDMI), 3072×1728 is refused, so it uses 2560×1440, and things look slightly larger than usual.

    What the test PC gets (3840×2160 HDMI monitor that lists 2560×1440, 1920×1080 and 1280×720). 1.25, 1.6 and 2 were tested live; the other rows follow from the modes the monitor lists:

    | Your scale | Logical size | Resolution during a session |
    |---|---|---|
    | 1.25 | 3072×1728 | 2560×1440 (3072×1728 refused) |
    | 1.5 | 2560×1440 | 2560×1440 |
    | 1.6 | 2400×1350 | 2560×1440 (2400×1350 refused) |
    | 2 | 1920×1080 | 1920×1080 |
    | 3 | 1280×720 | 1280×720 |

    Any other scale works the same way; nothing is hard-coded per scale.
- There is **no local "allow" prompt**. The ID and password alone give full control, the same as TeamViewer on X11. Keep unattended passwords strong, or use only the random one-time password.
- TeamViewer can't block local input on this backend, so "Disable remote input" and "Show black screen" don't work.
- Avoid reloading the Hyprland config during a session (`hyprctl reload`, or saving `monitors.lua`). A reload puts your normal resolution and scale back and the partner's picture freezes.
- If a session ends abnormally and the lower resolution stays, run:
  ```sh
  omarchy-teamviewer-desktop --restore   # or: hyprctl reload
  ```

### Other monitors and PCs

Nothing is tied to one monitor or PC. On every connection, the wrapper reads each monitor's current resolution, scale and supported modes from Hyprland and works from those. Only the resolution a monitor gets during a session differs:

| The monitor… | Resolution during a session | How things look |
|---|---|---|
| lists the exact scaled size (e.g. 1920×1080 on a 4K monitor at scale 2) | that size | as usual |
| doesn't list it, but the GPU accepts a custom mode (may work on laptop screens with Intel or AMD graphics; untested) | that size | as usual |
| doesn't list it and refuses a custom mode (the test PC: NVIDIA over HDMI) | the closest listed mode with the same aspect ratio | slightly larger or smaller |
| lists only its full resolution | full resolution at scale 1 | everything small, but TeamViewer still works |

- The picture is never stretched. The fallback only uses modes with the monitor's own aspect ratio, and its full resolution always qualifies.
- Monitors already at scale 1 are left alone.
- With several monitors, each one is handled on its own. During a session, switched monitors are placed with position `auto`, so the arrangement can change; the exact positions come back afterwards.
- To see what each monitor got, run `journalctl --user -b | grep omarchy-teamviewer`:
  ```
  omarchy-teamviewer-desktop: HDMI-A-1: 2560x1440 at scale 1 for TeamViewer (logical size 3072x1728)
  omarchy-teamviewer-desktop: HDMI-A-1: 3840x2160@59.99700 at scale 1.25 restored
  ```

## Uninstall

```sh
./uninstall.sh
```

This restores monitor resolutions and scales if needed. It then removes the scripts, the D-Bus override and the profile block, and stops the placeholder. After that, TeamViewer falls back to its stock launcher.

## Troubleshooting

Run `./status.sh` first. Relevant logs:

| Log | What it shows |
|---|---|
| `/opt/teamviewer/logfiles/TeamViewer15_Logfile.log` | Daemon: whether it found the session bus and how it started the helper |
| `~/.local/share/teamviewer15/logfiles/TeamViewer15_Logfile.log` | Desktop helper (`DW1` lines): backend, capture, input |
| `journalctl --user -b \| grep omarchy-teamviewer` | Wrapper: resolution/scale changes and restores |

| Log message | Meaning |
|---|---|
| `LaunchDesktopProcess: session bus not found` (daemon) | The placeholder isn't running inside the login session. Log out and back in; check `./status.sh`. |
| `GetOwnProcessSession: No session found!` (helper) | Same cause: without the bus, the daemon starts the helper in the wrong place |
| `StartServiceByName: Starting com.teamviewer.TeamViewer.Desktop` (daemon) | Good: the bus was found and the helper starts through D-Bus |
| `DesktopMainLin: FreedesktopPortal SPI created` (helper) | The wrapper wasn't used, so check the D-Bus override (`./status.sh`) |
| `DesktopMainLin: WLRoots SPI created` (helper) | Good: the wlroots backend is in use |
| `Unsupported shared memory buffer (... expected size: ...)` (helper) | A monitor isn't at scale 1 (Hyprland reloaded mid-session, or hyprctl/jq failed) |
| `Desktop grab succeeded` (helper) | Screen capture works |

## Tested

Tested on 2026-09-25 and 2026-09-26: Omarchy with Hyprland 0.56.2 (Lua config), uwsm 0.26.7, SDDM 0.21.0, xdg-desktop-portal-hyprland 1.4.1, TeamViewer 15.81.5 (AUR), one 3840×2160 HDMI monitor on an NVIDIA RTX 5070 at scales 1.25, 1.6 and 2, bash login shell.

- Verified: the daemon finds the bus, the password step works, the wlroots backend is selected, screen capture works at scale 1, and remote mouse and keyboard work (a full working session was driven remotely).
- Verified on 2026-09-26: the wrapper, started through D-Bus, switched 3840×2160 at 1.25 to 2560×1440 at scale 1 (3072×1728 was refused as a custom mode), then restored 3840×2160 at 1.25 when the helper exited. The same test at scale 1.6 gave 2560×1440 at scale 1, then restored 3840×2160 at 1.6.
- Verified on 2026-09-26 with a real remote session at scale 2: on connect the display switched to 1920×1080 at scale 1, screen capture and control worked, and on disconnect 3840×2160 at scale 2 came back.
- Not yet verified: laptop built-in screens, multiple monitors, rotated monitors, the legacy `hyprland.conf` path, zsh or other login shells.

## Why not…

- **Switch to `dbus-daemon-units`**, as TeamViewer's knowledge base suggests for dbus-broker? It isn't the cause here. The lookup fails with either bus implementation, because the problem is where uwsm runs the desktop, not which bus it uses.
- **Edit the SDDM session file?** `/usr/local/share/wayland-sessions/omarchy.desktop` belongs to the `omarchy-settings` package, so an update would silently undo the change.
- **Keep the monitor at scale 1 permanently?** That works too: set it in `~/.config/hypr/monitors.lua`. At 4K that makes everything small all the time; the wrapper lowers the resolution only during a session instead.
