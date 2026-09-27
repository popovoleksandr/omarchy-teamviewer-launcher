# omarchy-teamviewer-launcher: lets TeamViewer find the session D-Bus under uwsm
# (see /usr/share/doc/omarchy-teamviewer-launcher/how-it-works.md).
#
# Starts an idle placeholder dbus-daemon inside the login session, only in the
# login shell SDDM runs for a graphical session, and only for users who turned
# the launcher on with `omarchy-teamviewer-launcher enable`.
if [ "$(cat /proc/$PPID/comm 2>/dev/null)" = sddm-helper ] &&
  grep -qs omarchy-teamviewer-launcher "${XDG_DATA_HOME:-$HOME/.local/share}/dbus-1/services/com.teamviewer.TeamViewer.Desktop.service" &&
  [ -x /usr/share/omarchy-teamviewer-launcher/bin/omarchy-teamviewer-bus-placeholder ]; then
  /usr/share/omarchy-teamviewer-launcher/bin/omarchy-teamviewer-bus-placeholder >/dev/null 2>&1 &
fi
