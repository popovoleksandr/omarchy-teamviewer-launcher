#!/usr/bin/env bash
# Installs teamviewer-omarchy-launcher for the current user. No sudo, safe to re-run.

set -euo pipefail

ROOT=$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)
BIN_DIR="$HOME/.local/bin"
DBUS_DIR="${XDG_DATA_HOME:-$HOME/.local/share}/dbus-1/services"
SERVICE=com.teamviewer.TeamViewer.Desktop.service
MARK_BEGIN="# >>> teamviewer-omarchy-launcher >>>"
MARK_END="# <<< teamviewer-omarchy-launcher <<<"

warn() {
  echo "warning: $*" >&2
}

die() {
  echo "error: $*" >&2
  exit 1
}

# The profile that SDDM's wayland-session script makes the login shell read.
profile_file() {
  local shell
  shell=$(getent passwd "$USER" | cut -d: -f7)

  case "${shell##*/}" in
  bash)
    # bash reads only the first of these that exists.
    for f in "$HOME/.bash_profile" "$HOME/.bash_login" "$HOME/.profile"; do
      [[ -f $f ]] && { echo "$f"; return; }
    done
    echo "$HOME/.bash_profile"
    ;;
  zsh) echo "${ZDOTDIR:-$HOME}/.zprofile" ;;
  *) echo "$HOME/.profile" ;;
  esac
}

strip_block() {
  local file=$1
  [[ -f $file ]] || return 0
  awk -v b="$MARK_BEGIN" -v e="$MARK_END" '$0 == b { skip = 1 } !skip { print } $0 == e { skip = 0 }' "$file" >"$file.tmp"
  # cat instead of mv keeps the file's permissions and any symlink in place.
  cat "$file.tmp" >"$file"
  rm -f "$file.tmp"
}

[[ -x /opt/teamviewer/tv_bin/TeamViewer_Desktop ]] ||
  die "TeamViewer is not installed in /opt/teamviewer (install the AUR package: omarchy pkg aur add teamviewer)"
[[ -x /usr/bin/dbus-daemon ]] || die "/usr/bin/dbus-daemon is missing (package: dbus)"
for cmd in hyprctl jq busctl; do
  command -v "$cmd" >/dev/null || die "$cmd is missing"
done

command -v uwsm >/dev/null || warn "uwsm not found; this is meant for Omarchy's uwsm-managed Hyprland session"
systemctl is-enabled --quiet sddm 2>/dev/null || warn "SDDM is not the display manager; the session bus placeholder only starts under SDDM"
systemctl is-enabled --quiet teamviewerd 2>/dev/null ||
  warn "teamviewerd is not enabled; run: sudo systemctl enable --now teamviewerd"

echo "Installing scripts to $BIN_DIR"
install -Dm755 "$ROOT/bin/omarchy-teamviewer-desktop" "$BIN_DIR/omarchy-teamviewer-desktop"
install -Dm755 "$ROOT/bin/omarchy-teamviewer-bus-placeholder" "$BIN_DIR/omarchy-teamviewer-bus-placeholder"

echo "Installing D-Bus override to $DBUS_DIR/$SERVICE"
mkdir -p "$DBUS_DIR"
if [[ -f $DBUS_DIR/$SERVICE ]] && ! grep -q teamviewer-omarchy-launcher "$DBUS_DIR/$SERVICE"; then
  backup="$DBUS_DIR/$SERVICE.bak.$(date +%s)"
  mv "$DBUS_DIR/$SERVICE" "$backup"
  echo "  moved the existing override to $backup"
fi
sed "s|@BIN_DIR@|$BIN_DIR|g" "$ROOT/share/$SERVICE.in" >"$DBUS_DIR/$SERVICE"
busctl --user call org.freedesktop.DBus /org/freedesktop/DBus org.freedesktop.DBus ReloadConfig >/dev/null ||
  warn "could not reload the user bus; the override takes effect after the next login"

profile=$(profile_file)
echo "Adding the session bus placeholder to $profile"
if [[ ! -e $profile && ${profile##*/} == .bash_profile ]]; then
  # A new ~/.bash_profile hides ~/.bashrc from login shells unless it sources it.
  echo '[[ -f ~/.bashrc ]] && . ~/.bashrc' >"$profile"
fi
strip_block "$profile"
if [[ -s $profile && -n $(tail -n 1 "$profile") ]]; then
  echo >>"$profile"
fi
cat >>"$profile" <<EOF
$MARK_BEGIN
# Lets TeamViewer find the session D-Bus under uwsm. Runs only in the SDDM login shell.
if [ "\$(cat /proc/\$PPID/comm 2>/dev/null)" = sddm-helper ] && [ -x "\$HOME/.local/bin/omarchy-teamviewer-bus-placeholder" ]; then
  "\$HOME/.local/bin/omarchy-teamviewer-bus-placeholder" >/dev/null 2>&1 &
fi
$MARK_END
EOF

echo
if pgrep -u "$UID" -f 'teamviewer-placeholder-bus' >/dev/null; then
  echo "Done. The session bus placeholder is already running; incoming connections should work now."
else
  echo "Done. Log out and back in (or reboot) once so the placeholder starts inside your session."
fi
echo "Check everything with: $ROOT/status.sh"
