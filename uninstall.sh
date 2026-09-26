#!/usr/bin/env bash
# Removes everything install.sh added for the current user.

set -euo pipefail

BIN_DIR="$HOME/.local/bin"
DBUS_FILE="${XDG_DATA_HOME:-$HOME/.local/share}/dbus-1/services/com.teamviewer.TeamViewer.Desktop.service"
MARK_BEGIN="# >>> omarchy-teamviewer-launcher >>>"
MARK_END="# <<< omarchy-teamviewer-launcher <<<"

# Put scales back if a session is running or ended without restoring them.
if [[ -x $BIN_DIR/omarchy-teamviewer-desktop ]]; then
  "$BIN_DIR/omarchy-teamviewer-desktop" --restore || true
fi

if [[ -f $DBUS_FILE ]] && grep -q omarchy-teamviewer-launcher "$DBUS_FILE"; then
  rm -f "$DBUS_FILE"
  echo "Removed $DBUS_FILE"
  busctl --user call org.freedesktop.DBus /org/freedesktop/DBus org.freedesktop.DBus ReloadConfig >/dev/null || true
fi

for profile in "$HOME/.bash_profile" "$HOME/.bash_login" "$HOME/.profile" "${ZDOTDIR:-$HOME}/.zprofile"; do
  if [[ -f $profile ]] && grep -qxF "$MARK_BEGIN" "$profile"; then
    awk -v b="$MARK_BEGIN" -v e="$MARK_END" '$0 == b { skip = 1 } !skip { print } $0 == e { skip = 0 }' "$profile" >"$profile.tmp"
    cat "$profile.tmp" >"$profile"
    rm -f "$profile.tmp"
    echo "Removed the placeholder block from $profile"
  fi
done

if pkill -u "$UID" -f 'teamviewer-placeholder-bus'; then
  echo "Stopped the session bus placeholder"
fi

rm -f "$BIN_DIR/omarchy-teamviewer-desktop" "$BIN_DIR/omarchy-teamviewer-bus-placeholder"
echo "Removed scripts from $BIN_DIR"
echo "TeamViewer is back to its stock launcher (incoming connections will stall again on Omarchy)."
