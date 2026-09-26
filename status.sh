#!/usr/bin/env bash
# Checks every piece teamviewer-omarchy-launcher relies on and summarises the
# last incoming connection from TeamViewer's logs.

DAEMON_LOG=/opt/teamviewer/logfiles/TeamViewer15_Logfile.log
HELPER_LOG="$HOME/.local/share/teamviewer15/logfiles/TeamViewer15_Logfile.log"
DBUS_FILE="${XDG_DATA_HOME:-$HOME/.local/share}/dbus-1/services/com.teamviewer.TeamViewer.Desktop.service"
STATE_FILE="${XDG_RUNTIME_DIR:-/run/user/$UID}/omarchy-teamviewer-scales.json"

ok() { printf '  \e[32mok\e[0m    %s\n' "$*"; }
bad() { printf '  \e[31mFAIL\e[0m  %s\n' "$*"; }
note() { printf '  ..    %s\n' "$*"; }

# True if $1 is $2 or one of its descendants.
descends_from() {
  local pid=$1 ancestor=$2
  while [[ -n $pid && $pid -gt 1 ]]; do
    [[ $pid == "$ancestor" ]] && return 0
    pid=$(ps -o ppid= -p "$pid" 2>/dev/null | tr -d ' ')
  done
  return 1
}

echo "TeamViewer"
if [[ -x /opt/teamviewer/tv_bin/TeamViewer_Desktop ]]; then
  ok "installed ($(pacman -Q teamviewer 2>/dev/null || echo /opt/teamviewer))"
else
  bad "not installed in /opt/teamviewer"
fi
if systemctl is-active --quiet teamviewerd; then
  ok "teamviewerd running"
else
  bad "teamviewerd not running: sudo systemctl enable --now teamviewerd"
fi

echo "Launcher"
if grep -qs omarchy-teamviewer-desktop "$DBUS_FILE"; then
  ok "D-Bus override $DBUS_FILE"
else
  bad "D-Bus override missing: run ./install.sh"
fi
if [[ -x $HOME/.local/bin/omarchy-teamviewer-desktop && -x $HOME/.local/bin/omarchy-teamviewer-bus-placeholder ]]; then
  ok "scripts in ~/.local/bin"
else
  bad "scripts missing from ~/.local/bin: run ./install.sh"
fi

echo "Session bus placeholder"
session=$(loginctl show-user "$USER" -p Display --value 2>/dev/null)
leader=$(loginctl show-session "$session" -p Leader --value 2>/dev/null)
placeholder=
for pid in $(pgrep -u "$UID" -f 'teamviewer-placeholder-bus'); do
  descends_from "$pid" "$leader" && placeholder=$pid
done
if [[ -n $placeholder ]]; then
  ok "dbus-daemon $placeholder runs inside login session $session (leader $leader)"
elif pgrep -u "$UID" -f 'teamviewer-placeholder-bus' >/dev/null; then
  bad "placeholder runs outside login session $session; TeamViewer won't see it"
else
  bad "not running; log out and back in after ./install.sh"
fi

echo "Hyprland"
if grep -qs RemoteDesktop /usr/share/xdg-desktop-portal/portals/hyprland.portal; then
  note "the Hyprland portal now offers RemoteDesktop; the wlroots workaround may no longer be needed"
else
  note "the Hyprland portal has no RemoteDesktop; TeamViewer uses its wlroots backend instead"
fi
if command -v hyprctl >/dev/null && command -v jq >/dev/null; then
  hyprctl -j monitors 2>/dev/null | jq -r '.[] | "\(.name) \(.width)x\(.height) scale \(.scale)"' |
    while read -r line; do note "$line"; done
fi
if [[ -s $STATE_FILE ]]; then
  note "scales are switched to 1 for a TeamViewer session (saved originals: $STATE_FILE)"
fi

echo "Last incoming connection"
launch=$(grep -E "LaunchDesktopProcess: session bus not found|StartServiceByName: Starting com.teamviewer.TeamViewer.Desktop" "$DAEMON_LOG" 2>/dev/null | tail -n 1)
case $launch in
"") note "none in $DAEMON_LOG" ;;
*"session bus not found"*) bad "${launch:0:23} daemon could not find the session bus" ;;
*) ok "${launch:0:23} daemon started the helper through D-Bus" ;;
esac

backend=$(grep -E "DesktopMainLin: .* SPI created" "$HELPER_LOG" 2>/dev/null | tail -n 1)
case $backend in
"") ;;
*WLRoots*) ok "${backend:0:23} helper used the wlroots backend" ;;
*) bad "${backend:0:23} helper used: ${backend##*DesktopMainLin: }" ;;
esac

capture=$(grep -E "Desktop grab (succeeded|failed)|Unsupported shared memory buffer|RemoteDesktopPortal error|no session bus connection" "$HELPER_LOG" 2>/dev/null | tail -n 1)
case $capture in
"") ;;
*"grab succeeded"*) ok "${capture:0:23} screen capture works" ;;
*) bad "${capture:0:23} ${capture##*DW1}" ;;
esac
