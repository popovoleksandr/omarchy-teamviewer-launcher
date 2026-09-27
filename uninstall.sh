#!/usr/bin/env bash
# Turns incoming connections off again and removes Setup > TeamViewer from the
# Omarchy menu.
set -euo pipefail
bin="$(dirname "${BASH_SOURCE[0]}")/bin/omarchy-teamviewer-launcher"
"$bin" disable
"$bin" unsetup
