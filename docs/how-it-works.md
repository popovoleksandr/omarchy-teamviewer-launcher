# How it works

These are notes from diagnosing incoming TeamViewer connections on Omarchy on 2026-09-23 and 2026-09-25. Paths and versions are from that machine; see the Tested section of the README.

## How TeamViewer starts a remote session on Linux

1. `teamviewerd` is a root system service. It gets the incoming connection from TeamViewer's router.
2. It needs a per-user **desktop helper**, `/opt/teamviewer/tv_bin/TeamViewer_Desktop`, running inside the user's graphical session to capture the screen and inject input.
3. To start the helper, the daemon looks for the user's **session D-Bus**. If it finds the bus, it calls `StartServiceByName("com.teamviewer.TeamViewer.Desktop")` on it. D-Bus then starts the helper with the session's activation environment (`WAYLAND_DISPLAY`, `XDG_CURRENT_DESKTOP`, `HYPRLAND_INSTANCE_SIGNATURE`, …).
4. The helper chooses a screen backend, connects back to the daemon on `127.0.0.1:5939`, runs the password check, and streams the screen.

Each of the three problems below breaks one of these steps.

## Problem 1: "session bus not found"

Daemon log:

```
LaunchDesktopProcess: session bus not found, Errorcode=11
CreateProcess '/opt/teamviewer/tv_bin/TeamViewer_Desktop' as user … marked with 'TV_SPAWNED'
```

When the bus isn't found, the daemon starts the helper itself, inside its own system-service cgroup. The helper can't match itself to a login session and quits (`GetOwnProcessSession: No session found!`). The client waits at "Connecting to partner…" forever.

**How TeamViewer finds the bus.** A gdb syscall trace of `TeamViewer_Desktop` showed the lookup. The daemon uses the same code, and its binary contains the same name list.

1. Get the logind session leader, here `sddm-helper` (`loginctl show-session <id> -p Leader`).
2. Read `/proc/*/stat` for every process to build the parent/child tree.
3. Among the leader's descendants, look for a process whose name is on a built-in list: `plasmashell`, `plasma-desktop`, `kwin_x11`, `kwin_wayland`, `startplasma-wayland`, `openbox`, `gdm-wayland-session`, `gnome-session`, `gnome-session-binary`, `cinnamon`, `cinnamon-session`, `xfce4-session`, `lxsession`, `dbus-daemon`, `wayfire`, `labwc`, `sway`, …
4. Read `DBUS_SESSION_BUS_ADDRESS` from that process's `/proc/<pid>/environ`.

**Why Omarchy fails.** uwsm starts Hyprland as a systemd **user** unit (`wayland-wm@hyprland.desktop.service` under `user@1000.service`). The login session's scope ends up holding only the launcher chain:

```
session-1.scope
├─ sddm-helper … --start "uwsm start -g -1 -e -D Hyprland hyprland.desktop"
├─ sh /usr/lib/uwsm/signal-handler.sh wayland-session-envelope@hyprland.desktop.target
└─ systemctl --user start --wait wayland-session-envelope@hyprland.desktop.target
```

None of those names is on the list. Hyprland, the real session `dbus-daemon`, and every app live under `user@1000.service`. `Hyprland` isn't on the list either.

Things tested that did **not** help:

- Replacing dbus-broker with `dbus-daemon-units`, as TeamViewer's knowledge base suggests. The real bus daemon is then called `dbus-daemon`, but it still sits outside the tree.
- A `dbus-daemon` started with `systemd-run --user` that had `XDG_SESSION_ID=1` and `DBUS_SESSION_BUS_ADDRESS` in its environment. Environment variables don't count; only ancestry does.

**Fix.** SDDM runs every Wayland session through `/usr/share/sddm/scripts/wayland-session`. That script re-executes itself as a *login shell* of the user's shell (`bash --login`), so `~/.bash_profile` runs **inside** the session tree, as a child of `sddm-helper`. At that point the environment from PAM already holds `DBUS_SESSION_BUS_ADDRESS=unix:path=/run/user/<uid>/bus`.

The profile block starts `omarchy-teamviewer-bus-placeholder` in the background. The package does the same from `/etc/profile.d/omarchy-teamviewer-launcher.sh` instead: a login shell reads `/etc/profile`, which sources `/etc/profile.d/*.sh`, before `~/.bash_profile` (on Arch, zsh reads `/etc/profile` through `/etc/zsh/zprofile`). That script starts the placeholder only for users whose D-Bus override (below) is in place, so installing the package changes nothing for anyone who hasn’t run `omarchy-teamviewer-launcher enable`. That script `exec`s a real `/usr/bin/dbus-daemon` that listens on its own unused socket, so its process name is `dbus-daemon` and its parent is the login shell. TeamViewer finds it, reads the real bus address from its environment, and from then on talks to the real bus.

Details:

- The block checks that its parent process is `sddm-helper`, so it does nothing in terminals, SSH or TTY logins.
- `setsid` must not be used: it would move the process out of the tree.
- uwsm's `signal-handler.sh` waits only for its own `systemctl` child, so the extra child doesn't hold up logout. When the session ends, logind stops the scope and the placeholder with it.

## Problem 2: RemoteDesktop portal

Once the bus is found, the helper starts through D-Bus and the password check succeeds. Then the helper log shows:

```
DesktopMainLin: FreedesktopPortal SPI created
RemoteDesktopPortal error: calling method CreateSession on interface org.freedesktop.portal.RemoteDesktop failed:
  DBus: 'org.freedesktop.DBus.Error.UnknownMethod' (No such interface "org.freedesktop.portal.RemoteDesktop" …)
FreedesktopPortalScreenPlatformInterface: invalid state (2)
tvpipewirespi::ScreenGrabMethodPipeWire::…: Could not start streaming because no stream buffers are available.
```

TeamViewer's portal backend requires the **RemoteDesktop** portal, which combines screen sharing and input. `xdg-desktop-portal-hyprland` 1.4.1 implements only `Screenshot`, `ScreenCast`, `GlobalShortcuts` and `InputCapture` (see `/usr/share/xdg-desktop-portal/portals/hyprland.portal`). The session never starts, and the partner waits for a local confirmation that is never shown.

`TeamViewer_Desktop` also contains a **wlroots backend** (`tvwlrootsspi`). It uses `zwlr_screencopy_manager_v1` for capture and `zwlr_virtual_pointer_manager_v1` and `zwp_virtual_keyboard_manager_v1` for input, and Hyprland supports all of them. In the binary, the strings `XDG_CURRENT_DESKTOP`, `XDG_SESSION_DESKTOP` and `wlroots` sit next to each other, which suggests the backend is chosen from those variables. Setting `XDG_CURRENT_DESKTOP=Hyprland:wlroots` for the helper alone was tested and switches it over:

```
DesktopMainLin: WLRoots SPI created
```

**Fix.** A per-user D-Bus service file, `~/.local/share/dbus-1/services/com.teamviewer.TeamViewer.Desktop.service`, takes priority over TeamViewer's copy in `/usr/share/dbus-1/services/`. Its `Exec=` points at `omarchy-teamviewer-desktop`, which appends `wlroots` to `XDG_CURRENT_DESKTOP` and then runs the real helper. No other app sees the changed variable. The `Exec=` line runs the wrapper through `/bin/sh -c` and falls back to `/opt/teamviewer/tv_bin/TeamViewer_Desktop` when the wrapper is missing, so removing the package without running `disable` leaves TeamViewer as it was, not broken.

## Problem 3: fractional scaling

With the wlroots backend the session starts, but every frame is rejected:

```
WLRScreenCopyFrame: Unsupported shared memory buffer (format: 0, size: 3840x2160, expected size: 3072x1728), grabbing failed
ScreenGrabMethodWLRoots: grab failed for output with monitor id 0
Desktop grab failed.
```

The screencopy buffer is in physical pixels, 3840×2160. TeamViewer expects the monitor's logical size, 3840/1.25 × 2160/1.25 = 3072×1728, and throws away anything else. Setting the monitor to scale 1 during a live session fixed it immediately:

```
Desktop: Grabbed screen is ok.
Desktop grab succeeded.
```

**Fix.** Before starting the helper, `omarchy-teamviewer-desktop` saves every monitor whose scale isn't 1 to `$XDG_RUNTIME_DIR/omarchy-teamviewer-scales.json`, then switches it to scale 1 at the resolution that keeps its logical layout: the monitor's size divided by its scale, so 3072×1728 for 3840×2160 at 1.25 and 1920×1080 at 2. The mode is chosen in this order:

1. A listed mode (`availableModes`) of exactly that size.
2. Otherwise, that size as a custom mode. Hyprland tries it with an atomic test commit. On the test PC (NVIDIA RTX 5070, 4K HDMI monitor), the commit fails with `Invalid argument` for 3072×1728, most likely because the driver or the monitor accepts only the modes the monitor lists.
3. If that's refused, the closest listed mode with the same aspect ratio (2560×1440 on the test PC). Hyprland falls back on its own when a custom mode is refused, and on the test PC it picked the same mode, so the wrapper only sets it when Hyprland chose something else.

At scale 1 the screencopy buffer and the logical size are the same whatever the resolution, so TeamViewer accepts the frames. The wrapper changes the monitor the same way Omarchy's own `omarchy-hyprland-monitor-scaling` does: `hyprctl eval 'hl.monitor({…})'`, or `hyprctl keyword monitor` on a `hyprland.conf` setup. When the helper exits, the saved values are restored. `--restore` does the same by hand.

**Locked screen.** Omarchy's lock turns the displays off (DPMS) a few seconds after locking. Hyprland answers `ok` to a mode change for a display that is off but applies it only when the display comes back on. Until then TeamViewer rejects every frame, and the partner can't see the lock screen to type the password. So if a monitor that needs switching is off, the wrapper turns the displays on first. When the session ends and the screen is still locked (`omarchy-hyprland-session-locked`), it turns them off again, because the lock would otherwise wait for a key press.

**Mid-session changes.** Anything that sets a monitor up again puts its configured scale back: a config reload, the monitor dropping off HDMI and reconnecting, or a switch that didn't take. TeamViewer then rejects frames until the monitor is at scale 1 again, and it picks up again once the monitor is back at scale 1. The wrapper checks every two seconds while the helper runs and switches any scaled monitor back, adding monitors it hasn't seen yet to the saved state. It logs only changes. When the helper exits, it waits for that check to stop before restoring, so nothing is switched again after the restore.

The helper is also started as soon as a connection arrives, before the password check, so the resolution changes for failed attempts too.

**Overlapping helpers.** teamviewerd starts a new helper once it has given up on the previous one, and retries about every 12 seconds while starts fail. The previous helper can still be running then. On 2026-10-03 one never exited. A retry failed because the helper before it was still shutting down. Its wrapper then restored scale 2 and turned the displays off (the screen was locked), just as the next helper started capturing. Hyprland held the mode change back while the displays were off, so the new wrapper still saw scale 1 and didn't step in, and the capture got no frames. When the partner disconnected 17 minutes later, that helper ignored the daemon's request to stop. It kept TeamViewer's lock, `$XDG_RUNTIME_DIR/TeamViewer_desktop_1.lock`, so for five hours every new helper logged `Cannot acquire lock … locked by other process` and quit after a few seconds. Each of those retries switched the display back and forth. Two changes in the wrapper prevent this:

- Every wrapper holds `$XDG_RUNTIME_DIR/omarchy-teamviewer-desktop.lock` shared while its helper runs, and restores only if it can take the lock exclusively. Only the last wrapper to exit restores the modes or turns the displays off, and a new wrapper waits for a restore in progress before it switches.
- Before starting its helper, the wrapper ends any older `TeamViewer_Desktop` of the same user: SIGTERM, then SIGKILL after three seconds, because a stuck helper ignores SIGTERM. teamviewerd has already given up on it, so no session depends on it.

## Why the helper starts where it does

For reference, when the daemon starts the helper through D-Bus:

- `dbus-daemon`, with `/usr/bin/dbus-daemon` running the user bus, starts the command from the service file as its own child, under `user@<uid>.service`.
- The helper finds its login session because the activation environment carries `XDG_SESSION_ID`. It finds the bus again through the same process-tree lookup, so the placeholder is needed for the helper as well as the daemon.
- `HYPRLAND_INSTANCE_SIGNATURE` is in the activation environment (uwsm exports it), which is what lets the wrapper call `hyprctl`.
