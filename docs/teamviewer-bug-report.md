# Bug report draft for TeamViewer

Send to TeamViewer support (ticket) or post in the Linux section of the TeamViewer Community forum. Attach both log files mentioned below.

---

**Subject:** Linux/Wayland: incoming connections fail on Hyprland (uwsm): session bus lookup, missing wlroots fallback, and wrong buffer size check with fractional scaling

**Environment**

- TeamViewer 15.81.5 (DEB build, via the Arch AUR package)
- Arch Linux / Omarchy. Hyprland 0.56.2 started by uwsm 0.26.7 from SDDM 0.21.0
- xdg-desktop-portal 1.22.1, xdg-desktop-portal-hyprland 1.4.1 (provides Screenshot, ScreenCast, GlobalShortcuts, InputCapture; no RemoteDesktop)
- One 3840×2160 monitor at scale 1.25

Incoming connections to this machine fail in three consecutive ways. Each needs a local workaround before the next one appears. With all three worked around, remote access works, which shows the machine is otherwise capable.

### 1. The session D-Bus lookup relies on process names in the login session's process tree

Daemon log:

```
LaunchDesktopProcess: session bus not found, Errorcode=11
CreateProcess '/opt/teamviewer/tv_bin/TeamViewer_Desktop' as user … marked with 'TV_SPAWNED'
```

The spawned helper then fails with `SysSessionInfoManager::GetOwnProcessSession: No session found!` and the partner sees "Connecting to partner…" forever.

teamviewerd and TeamViewer_Desktop look for the session bus by walking the logind session leader's descendants, reading `/proc/*/stat`, and checking for known names (`gnome-session`, `plasmashell`, `dbus-daemon`, `labwc`, `wayfire`, `sway`, …). With uwsm, which the Hyprland wiki recommends and Omarchy uses by default, the compositor and the session bus run as systemd user units under `user@<uid>.service`. The session scope contains only the display manager's launcher processes (`sddm-helper`, `sh`, `systemctl`), so the lookup always fails. Replacing dbus-broker with dbus-daemon, as your knowledge base suggests, doesn't help.

**Expected:** use the systemd user bus at `$XDG_RUNTIME_DIR/bus` (`/run/user/<uid>/bus`), or read `DBUS_SESSION_BUS_ADDRESS` from the user manager's environment. teamviewerd already queries that environment for `WAYLAND_DISPLAY`/`XDG_RUNTIME_DIR` (`SystemdSessionReadiness`).

**Workaround:** keep an idle process named `dbus-daemon`, with the right `DBUS_SESSION_BUS_ADDRESS`, as a child of the login shell inside the session.

### 2. No fallback to the wlroots backend when the RemoteDesktop portal is missing

Helper log after a successful password check:

```
DesktopMainLin: FreedesktopPortal SPI created
RemoteDesktopPortal error: calling method CreateSession on interface org.freedesktop.portal.RemoteDesktop failed:
  DBus: 'org.freedesktop.DBus.Error.UnknownMethod' (No such interface "org.freedesktop.portal.RemoteDesktop" …)
FreedesktopPortalScreenPlatformInterface: invalid state (2)
```

The partner then waits at "waiting for partner to confirm the request" indefinitely. TeamViewer_Desktop contains a working wlroots backend (`WLRootsSPI`: wlr-screencopy plus virtual pointer and keyboard), but chooses it only when `XDG_CURRENT_DESKTOP` contains `wlroots`, which no compositor sets by default. The binary already recognises `Hyprland` as a desktop environment.

**Expected:** if `org.freedesktop.portal.RemoteDesktop` isn't available but the compositor advertises `zwlr_screencopy_manager_v1`, use the wlroots backend. At minimum, treat Hyprland, sway, river, niri and similar as wlroots-protocol compositors.

**Workaround:** start TeamViewer_Desktop with `XDG_CURRENT_DESKTOP=Hyprland:wlroots`, using a user D-Bus service override.

### 3. The wlroots backend rejects screencopy buffers on scaled outputs

```
WLRScreenCopyFrame: Unsupported shared memory buffer (format: 0, size: 3840x2160, expected size: 3072x1728), grabbing failed
ScreenGrabMethodWLRoots: grab failed for output with monitor id 0, Errorcode=11
Desktop grab failed.
```

The screencopy buffer is sized in the output's physical pixels (3840×2160), as the wlr-screencopy protocol specifies. TeamViewer compares it with the logical, scaled size (3840/1.25 = 3072, 2160/1.25 = 1728) and rejects every frame. At scale 1 capture works immediately (`Desktop grab succeeded.`). This affects every wlroots compositor with output scaling, sway included.

**Expected:** accept the buffer size announced by `zwlr_screencopy_frame_v1.buffer` and map input coordinates using the output scale.

**Workaround:** switch outputs to scale 1 for the duration of the session.

**Attached:** `/opt/teamviewer/logfiles/TeamViewer15_Logfile.log` (daemon) and `~/.local/share/teamviewer15/logfiles/TeamViewer15_Logfile.log` (desktop helper).
