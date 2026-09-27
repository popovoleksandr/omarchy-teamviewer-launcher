#!/usr/bin/env bash
# Checks every piece omarchy-teamviewer-launcher relies on and summarises the
# last incoming connection from TeamViewer's logs.
exec "$(dirname "${BASH_SOURCE[0]}")/bin/omarchy-teamviewer-launcher" status
