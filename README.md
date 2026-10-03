# omarchy-teamviewer-launcher

Makes incoming TeamViewer connections work on [Omarchy](https://omarchy.org/), where Hyprland is started by uwsm from SDDM.

Without it, TeamViewer 15 on Omarchy shows the partner an endless "Connecting to partner…". Once that is fixed, it hangs after the password at "waiting for partner to confirm the request". On a scaled display it then shows no picture at all. This project fixes all three problems. You turn it on per user, from **Setup > TeamViewer** in the Omarchy menu or with the `omarchy-teamviewer-launcher` command, and it makes no changes to TeamViewer or Omarchy files.

## What it fixes

| Symptom on the connecting side | Cause on this PC | Fix |
|---|---|---|
| Endless "Connecting to partner…". The daemon log says `LaunchDesktopProcess: session bus not found` | TeamViewer finds your D-Bus session bus only through processes like `dbus-daemon` or `gnome-session` inside the login session's process tree. uwsm runs the whole desktop outside that tree. | `omarchy-teamviewer-bus-placeholder`: an idle `dbus-daemon`, started from your login profile inside that tree, that carries the real bus address |
| Password accepted, then "waiting for partner to confirm the request". The helper log says `No such interface "org.freedesktop.portal.RemoteDesktop"` | TeamViewer asks the desktop portal for RemoteDesktop unless `XDG_CURRENT_DESKTOP` contains `wlroots`. xdg-desktop-portal-hyprland doesn't implement RemoteDesktop. | `omarchy-teamviewer-desktop` adds `wlroots` to `XDG_CURRENT_DESKTOP`, so TeamViewer uses its built-in wlroots backend (screencopy plus virtual pointer and keyboard) |
| Connected, but no picture. The helper log says `Unsupported shared memory buffer (... size: 3840x2160, expected size: 3072x1728)` | The wlroots backend compares each frame's pixel size with the monitor's scaled size, so any scale other than 1 fails | While the TeamViewer helper runs, `omarchy-teamviewer-desktop` switches every scaled monitor to scale 1 at the resolution that keeps its layout (e.g. 3072×1728 instead of 3840×2160 at 1.25), and restores it afterwards |

[docs/how-it-works.md](docs/how-it-works.md) covers the full investigation and evidence. [docs/teamviewer-bug-report.md](docs/teamviewer-bug-report.md) is a ready-to-send report for TeamViewer, since all three are TeamViewer bugs.

## Requirements

- Omarchy: Hyprland started by uwsm, SDDM as the login manager. Both the Lua config (`~/.config/hypr/hyprland.lua`, current Omarchy) and the older `hyprland.conf` are supported.
- TeamViewer 15 in `/opt/teamviewer` (AUR `teamviewer`) with its daemon enabled. The package depends on it, and `enable` offers to turn on the daemon:
  ```sh
  omarchy pkg aur add teamviewer
  sudo systemctl enable --now teamviewerd
  ```
- `jq`, `hyprctl`, `busctl` and `/usr/bin/dbus-daemon` (package `dbus`). Omarchy has all of these, including on systems that use dbus-broker.
- A login shell of bash (Omarchy's default) or zsh. A checkout also works with anything that reads `~/.profile`.

## Install

### Package from the GitHub release

The AUR package isn't published yet, because new AUR account registration is paused (as of 2026-09-26). Until then, install the package attached to the [latest release](https://github.com/popovoleksandr/omarchy-teamviewer-launcher/releases/latest):

```sh
curl -LO https://github.com/popovoleksandr/omarchy-teamviewer-launcher/releases/download/v1.0.2/omarchy-teamviewer-launcher-1.0.2-1-any.pkg.tar.zst
sha256sum omarchy-teamviewer-launcher-1.0.2-1-any.pkg.tar.zst    # compare with the release notes
sudo pacman -U omarchy-teamviewer-launcher-1.0.2-1-any.pkg.tar.zst
```

Download it first: `pacman -U` with a link wants a signature file (`.sig`) next to the package, and the release has none. Or build the same package yourself; makepkg downloads the tagged release from GitHub and checks it against the PKGBUILD's checksum:

```sh
git clone https://github.com/popovoleksandr/omarchy-teamviewer-launcher.git
cd omarchy-teamviewer-launcher/packaging/aur
makepkg -si
```

Once it's on the AUR: `omarchy pkg aur add omarchy-teamviewer-launcher` (or `yay -S omarchy-teamviewer-launcher`).

Then turn incoming connections on for your user:

1. Open **Omarchy TeamViewer Launcher** from the app launcher. The first time, it adds **Setup > TeamViewer** to the Omarchy menu and opens it.
2. Pick **Incoming Connections**. A floating terminal turns it on (and offers to enable `teamviewerd` if it's off). The row then shows a ✓. From a terminal, `omarchy-teamviewer-launcher enable` does the same.
3. **Log out and back in once**, or reboot, so the placeholder starts inside your session. **Status** in the same menu checks everything.

| Setup > TeamViewer | What it does |
|---|---|
| Install TeamViewer | Installs the AUR `teamviewer` and enables its daemon. Shown only while TeamViewer is missing. |
| Incoming Connections | Turns the fix on or off for your user (`enable` / `disable`). ✓ when on. |
| Status | Checks every piece and summarises the last incoming connection |
| Restore Display | Puts monitor resolution and scale back if a session ended without doing it |

The command line has the same: `omarchy-teamviewer-launcher enable | disable | toggle | status | restore | menu | setup | unsetup`.

### From a checkout

Without the package, run it from the repository. `install.sh` runs `bin/omarchy-teamviewer-launcher enable`: it copies the scripts to `~/.local/bin`, adds the placeholder block to your login profile, installs the D-Bus override, and adds Setup > TeamViewer pointing at the checkout. It's safe to re-run after pulling changes.

```sh
git clone https://github.com/popovoleksandr/omarchy-teamviewer-launcher.git ~/Projects/omarchy-teamviewer-launcher
cd ~/Projects/omarchy-teamviewer-launcher
./install.sh
```

### What it installs

| Piece | Package | Checkout |
|---|---|---|
| Wrapper D-Bus starts instead of `TeamViewer_Desktop` | `/usr/share/omarchy-teamviewer-launcher/bin/omarchy-teamviewer-desktop` (also `/usr/bin/omarchy-teamviewer-desktop`) | `~/.local/bin/omarchy-teamviewer-desktop` |
| Placeholder `dbus-daemon` for TeamViewer's session-bus lookup | `/usr/share/omarchy-teamviewer-launcher/bin/omarchy-teamviewer-bus-placeholder` | `~/.local/bin/omarchy-teamviewer-bus-placeholder` |
| What starts the placeholder, only in SDDM's login shell | `/etc/profile.d/omarchy-teamviewer-launcher.sh`, only for users who ran `enable` | A marked block in `~/.bash_profile` (or `~/.zprofile` / `~/.profile`) |
| D-Bus override, per user (written by `enable`) | `~/.local/share/dbus-1/services/com.teamviewer.TeamViewer.Desktop.service` | same |
| Setup > TeamViewer, per user | A marked block in `~/.config/omarchy/extensions/omarchy-menu.jsonc` | same |

The D-Bus override takes priority over TeamViewer's copy in `/usr/share/dbus-1/services/` and points it at the wrapper. If the wrapper is gone, for example after removing the package without `disable`, the override runs TeamViewer's own helper instead, so TeamViewer behaves as if the launcher were never installed.

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
- Connecting to a locked screen works. If the lock has turned the display off, it comes back on for the session and shows the lock screen, and the partner unlocks it with your password. If the screen is still locked when the session ends, the display turns off again.
- If something puts your normal scale back during a session, such as a config reload (`hyprctl reload`, or saving `monitors.lua`) or the monitor reconnecting, the partner's picture freezes for up to two seconds until the wrapper switches it back.
- TeamViewer's helper sometimes keeps running after its session ends, and while it does, every new connection fails. The next connection ends it first, which adds up to three seconds to that connection.
- If a session ends abnormally and the lower resolution stays, run:
  ```sh
  omarchy-teamviewer-launcher restore   # or Setup > TeamViewer > Restore Display, or: hyprctl reload
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

Package: turn it off first, because pacman can't undo per-user changes:

```sh
omarchy-teamviewer-launcher disable     # restores scales, removes the D-Bus override, stops the placeholder
omarchy-teamviewer-launcher unsetup     # Setup > TeamViewer out of the menu
omarchy pkg drop omarchy-teamviewer-launcher     # or: sudo pacman -R omarchy-teamviewer-launcher
```

Checkout: `./uninstall.sh` does `disable` and `unsetup`, and also removes the `~/.local/bin` copies and the profile block. After either, TeamViewer falls back to its stock launcher.

## Troubleshooting

Run `omarchy-teamviewer-launcher status` (or `./status.sh` in a checkout) first. Relevant logs:

| Log | What it shows |
|---|---|
| `/opt/teamviewer/logfiles/TeamViewer15_Logfile.log` | Daemon: whether it found the session bus and how it started the helper |
| `~/.local/share/teamviewer15/logfiles/TeamViewer15_Logfile.log` | Desktop helper (`DW1` lines): backend, capture, input |
| `journalctl --user -b \| grep omarchy-teamviewer` | Wrapper: resolution/scale changes and restores |

| Log message | Meaning |
|---|---|
| `LaunchDesktopProcess: session bus not found` (daemon) | The placeholder isn't running inside the login session. Log out and back in; check `omarchy-teamviewer-launcher status`. |
| `GetOwnProcessSession: No session found!` (helper) | Same cause: without the bus, the daemon starts the helper in the wrong place |
| `StartServiceByName: Starting com.teamviewer.TeamViewer.Desktop` (daemon) | Good: the bus was found and the helper starts through D-Bus |
| `DesktopMainLin: FreedesktopPortal SPI created` (helper) | The wrapper wasn't used, so check the D-Bus override (`omarchy-teamviewer-launcher status`) |
| `DesktopMainLin: WLRoots SPI created` (helper) | Good: the wlroots backend is in use |
| `Cannot acquire lock for ".../TeamViewer_desktop_1.lock", reason: locked by other process (N)` (helper) | A helper from an earlier session is still running, so this one quits. The wrapper ends it on the next attempt and logs `ending TeamViewer helper N left from an earlier session`. |
| `Unsupported shared memory buffer (... expected size: ...)` (helper) | A monitor isn't at scale 1. A few seconds of it mid-session is the wrapper catching up after a reload or reconnect. If it doesn't stop, check the wrapper's journal lines: `still … switching again` means Hyprland isn't taking the switch; no lines at all means hyprctl or jq is missing |
| `Desktop grab succeeded` (helper) | Screen capture works |

## Files

| File | Purpose |
|---|---|
| `bin/omarchy-teamviewer-launcher` | The command: enable, disable, status, restore, menu |
| `bin/omarchy-teamviewer-desktop` | Wrapper D-Bus starts in place of `TeamViewer_Desktop`: adds `wlroots`, switches scales for the session |
| `bin/omarchy-teamviewer-bus-placeholder` | Idle `dbus-daemon` that TeamViewer's session-bus lookup finds |
| `lib/common.sh` | Paths and helpers shared by the command |
| `share/com.teamviewer.TeamViewer.Desktop.service.in` | The per-user D-Bus override, with the fallback to TeamViewer's own helper |
| `share/profile.d.sh` | Installed as `/etc/profile.d/omarchy-teamviewer-launcher.sh` by the package |
| `share/menu.jsonc` | The Setup > TeamViewer block (`@CMD@` becomes the command) |
| `share/omarchy-teamviewer-launcher.desktop`, `.svg` | App launcher entry and icon |
| `install.sh`, `status.sh`, `uninstall.sh` | Checkout wrappers around `bin/omarchy-teamviewer-launcher` |
| `Makefile` | `make DESTDIR=… PREFIX=/usr install`, used by the PKGBUILD |
| `packaging/aur/` | PKGBUILD, install messages, `.SRCINFO` and release scripts ([how to publish](packaging/aur/README.md)) |
| `docs/` | How it works, and a bug report for TeamViewer |

## Tested

Tested on 2026-09-25 and 2026-09-26: Omarchy with Hyprland 0.56.2 (Lua config), uwsm 0.26.7, SDDM 0.21.0, xdg-desktop-portal-hyprland 1.4.1, TeamViewer 15.81.5 (AUR), one 3840×2160 HDMI monitor on an NVIDIA RTX 5070 at scales 1.25, 1.6 and 2, bash login shell.

- Verified: the daemon finds the bus, the password step works, the wlroots backend is selected, screen capture works at scale 1, and remote mouse and keyboard work (a full working session was driven remotely).
- Verified on 2026-09-26: the wrapper, started through D-Bus, switched 3840×2160 at 1.25 to 2560×1440 at scale 1 (3072×1728 was refused as a custom mode), then restored 3840×2160 at 1.25 when the helper exited. The same test at scale 1.6 gave 2560×1440 at scale 1, then restored 3840×2160 at 1.6.
- Verified on 2026-09-26 with a real remote session at scale 2: on connect the display switched to 1920×1080 at scale 1, screen capture and control worked, and on disconnect 3840×2160 at scale 2 came back.
- Verified on 2026-09-27 with a real remote session to a locked screen at scale 2, with the display turned off by Omarchy's lock. The wrapper turned the display on and switched to 1920×1080 at scale 1 on the first try, capture showed the lock screen, and the partner unlocked it remotely. On disconnect 3840×2160 at scale 2 came back. Without this fix, the same case had failed with `Unsupported shared memory buffer` for the whole attempt. In a separate run with a stand-in helper, a monitor forced back to scale 2 mid-session was switched to scale 1 again within 3 seconds.
- Verified on 2026-09-26 for the package: `makepkg` builds it and `desktop-file-validate` accepts the desktop entry. From the unpacked package, `enable` wrote the override for the packaged wrapper and removed an earlier checkout install's `~/.local/bin` copies and profile block. Omarchy's own menu parser read the five Setup > TeamViewer rows. The `/etc/profile.d` script started the placeholder only under an SDDM-like parent and only for a user who had run `enable`. The override's `sh -c` fallback was checked on the session `dbus-daemon` with a stand-in service.
- Verified on 2026-10-03 with a stand-in helper and a stand-in `hyprctl`, for overlapping helpers. When a second wrapper started during a session on a locked screen, it ended the first helper. The first wrapper then left the modes and displays alone, and the second restored them and turned the displays off when it was done. A helper that ignored SIGTERM was killed after three seconds. A wrapper that started during another's restore waited for the restore to finish before it switched. With the lock file unusable, the wrapper still switched and restored.
- Not yet verified with the package: a real incoming session after installing it and logging in again.
- Not yet verified: laptop built-in screens, multiple monitors, rotated monitors, the legacy `hyprland.conf` path, zsh or other login shells.

## Why not…

- **Switch to `dbus-daemon-units`**, as TeamViewer's knowledge base suggests for dbus-broker? It isn't the cause here. The lookup fails with either bus implementation, because the problem is where uwsm runs the desktop, not which bus it uses.
- **Edit the SDDM session file?** `/usr/local/share/wayland-sessions/omarchy.desktop` belongs to the `omarchy-settings` package, so an update would silently undo the change.
- **Install the D-Bus override system-wide?** TeamViewer's package owns `/usr/share/dbus-1/services/com.teamviewer.TeamViewer.Desktop.service`, and a service directory added through `session.d` is searched after it, so its copy would still win. The per-user override is the one place that takes priority.
- **Keep the monitor at scale 1 permanently?** That works too: set it in `~/.config/hypr/monitors.lua`. At 4K that makes everything small all the time; the wrapper lowers the resolution only during a session instead.

## License

[MIT](LICENSE). This project is not affiliated with TeamViewer or Omarchy. TeamViewer is a trademark of TeamViewer Germany GmbH.
