# Shared paths and helpers for omarchy-teamviewer-launcher.
# shellcheck shell=bash
#
# The caller sets ROOT: the directory holding bin/, lib/ and share/. That is the
# git checkout, or /usr/share/omarchy-teamviewer-launcher when installed as a
# package.

TV_DESKTOP=/opt/teamviewer/tv_bin/TeamViewer_Desktop
SERVICE=com.teamviewer.TeamViewer.Desktop.service
DBUS_FILE="${XDG_DATA_HOME:-$HOME/.local/share}/dbus-1/services/$SERVICE"
STATE_FILE="${XDG_RUNTIME_DIR:-/run/user/$UID}/omarchy-teamviewer-scales.json"
DAEMON_LOG=/opt/teamviewer/logfiles/TeamViewer15_Logfile.log
HELPER_LOG="$HOME/.local/share/teamviewer15/logfiles/TeamViewer15_Logfile.log"
MENU_FILE="$HOME/.config/omarchy/extensions/omarchy-menu.jsonc"
MENU_BEGIN="// >>> omarchy-teamviewer-launcher >>>"
MENU_END="// <<< omarchy-teamviewer-launcher <<<"
PROFILE_BEGIN="# >>> omarchy-teamviewer-launcher >>>"
PROFILE_END="# <<< omarchy-teamviewer-launcher <<<"
PROFILE_D=/etc/profile.d/omarchy-teamviewer-launcher.sh

# The package starts the placeholder from /etc/profile.d and runs the scripts
# where it installed them. A checkout copies them to ~/.local/bin and adds a
# block to the login profile instead, the way the first versions did.
if [[ $ROOT == */share/omarchy-teamviewer-launcher ]]; then
  PACKAGED=true
  BIN_DIR="$ROOT/bin"
  CMD=omarchy-teamviewer-launcher
else
  PACKAGED=false
  BIN_DIR="$HOME/.local/bin"
  CMD="$ROOT/bin/omarchy-teamviewer-launcher"
fi
DESKTOP_BIN="$BIN_DIR/omarchy-teamviewer-desktop"
PLACEHOLDER_BIN="$BIN_DIR/omarchy-teamviewer-bus-placeholder"

warn() {
  echo "warning: $*" >&2
}

die() {
  echo "error: $*" >&2
  exit 1
}

# True if this user turned the launcher on: their D-Bus override is ours.
is_enabled() {
  grep -qs omarchy-teamviewer-launcher "$DBUS_FILE"
}

reload_user_bus() {
  busctl --user call org.freedesktop.DBus /org/freedesktop/DBus org.freedesktop.DBus ReloadConfig >/dev/null 2>&1
}

# The profile that SDDM's wayland-session script makes the login shell read.
profile_file() {
  local shell f
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

# Prints a file without the block between two marker lines (matched with or
# without indentation).
strip_block() {
  awk -v b="$2" -v e="$3" '
    { line = $0; sub(/^[[:space:]]+/, "", line) }
    line == b { skip = 1 }
    !skip { print }
    line == e { skip = 0 }
  ' "$1"
}

# True if the placeholder dbus-daemon runs inside this user's graphical login
# session, where TeamViewer looks for it. Prints its PID.
placeholder_in_session() {
  local session leader pid p
  session=$(loginctl show-user "$USER" -p Display --value 2>/dev/null)
  leader=$(loginctl show-session "$session" -p Leader --value 2>/dev/null)
  [[ -n $leader ]] || return 1
  for pid in $(pgrep -u "$UID" -f 'dbus-daemon .*teamviewer-placeholder-bus'); do
    p=$pid
    while [[ -n $p && $p -gt 1 ]]; do
      [[ $p == "$leader" ]] && { echo "$pid"; return 0; }
      p=$(ps -o ppid= -p "$p" 2>/dev/null | tr -d ' ')
    done
  done
  return 1
}

# True if a JSONC file parses the way the Omarchy menu reads it: full-line //
# comments and trailing commas are dropped, the rest must be a JSON object.
menu_jsonc_valid() {
  sed -E '/^[[:space:]]*\/\//d' "$1" | sed -zE 's/,([[:space:]]*[]}])/\1/g' | jq -e 'type == "object"' >/dev/null 2>&1
}
