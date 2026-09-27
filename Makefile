# Installs omarchy-teamviewer-launcher as a package would. The PKGBUILD runs:
#   make DESTDIR="$pkgdir" PREFIX=/usr install
PREFIX ?= /usr
DESTDIR ?=
SHARE := $(DESTDIR)$(PREFIX)/share/omarchy-teamviewer-launcher

.PHONY: install

install:
	install -Dm755 -t $(SHARE)/bin bin/omarchy-teamviewer-launcher bin/omarchy-teamviewer-desktop bin/omarchy-teamviewer-bus-placeholder
	install -Dm644 lib/common.sh $(SHARE)/lib/common.sh
	install -Dm644 -t $(SHARE)/share share/com.teamviewer.TeamViewer.Desktop.service.in share/menu.jsonc
	install -d $(DESTDIR)$(PREFIX)/bin
	ln -sf ../share/omarchy-teamviewer-launcher/bin/omarchy-teamviewer-launcher $(DESTDIR)$(PREFIX)/bin/omarchy-teamviewer-launcher
	ln -sf ../share/omarchy-teamviewer-launcher/bin/omarchy-teamviewer-desktop $(DESTDIR)$(PREFIX)/bin/omarchy-teamviewer-desktop
	install -Dm644 share/profile.d.sh $(DESTDIR)/etc/profile.d/omarchy-teamviewer-launcher.sh
	install -Dm644 share/omarchy-teamviewer-launcher.desktop $(DESTDIR)$(PREFIX)/share/applications/omarchy-teamviewer-launcher.desktop
	install -Dm644 share/omarchy-teamviewer-launcher.svg $(DESTDIR)$(PREFIX)/share/icons/hicolor/scalable/apps/omarchy-teamviewer-launcher.svg
	install -Dm644 -t $(DESTDIR)$(PREFIX)/share/doc/omarchy-teamviewer-launcher README.md docs/how-it-works.md docs/teamviewer-bug-report.md
	install -Dm644 LICENSE $(DESTDIR)$(PREFIX)/share/licenses/omarchy-teamviewer-launcher/LICENSE
