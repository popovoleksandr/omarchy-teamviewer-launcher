#!/usr/bin/env bash
# Turns incoming TeamViewer connections on straight from this checkout, without
# the package: copies the scripts to ~/.local/bin, adds the placeholder block to
# your login profile, installs the D-Bus override, and adds Setup > TeamViewer
# to the Omarchy menu. No sudo (except to enable teamviewerd if it's off). Safe
# to re-run.
exec "$(dirname "${BASH_SOURCE[0]}")/bin/omarchy-teamviewer-launcher" enable
