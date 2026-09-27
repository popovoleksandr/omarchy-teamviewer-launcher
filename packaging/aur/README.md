# Publishing omarchy-teamviewer-launcher to the AUR

The AUR package builds from a tagged GitHub release: `PKGBUILD` downloads `v<version>.tar.gz` from GitHub and installs it with `make install`.

> **Status (2026-09-26):** not on the AUR yet. New AUR account registration is paused while the AUR deals with automated sign-ups, with no manual queue ([aur-general](https://lists.archlinux.org/mailman3/lists/aur-general.lists.archlinux.org/), [Arch news](https://archlinux.org/news/) announce when it reopens). Until then, the built package is attached to each [GitHub release](https://github.com/popovoleksandr/omarchy-teamviewer-launcher/releases). Once you have an account, finish [One-time setup](#one-time-setup) and run `packaging/aur/publish.sh`.

## One-time setup

1. Create an account at <https://aur.archlinux.org/register>.
2. Add your SSH public key to the account. Print it:
   ```sh
   cat ~/.ssh/id_ed25519.pub
   ```
   Sign in, open **My Account**, and paste the whole line (from `ssh-ed25519` to the comment at the end) into **SSH Public Key**. Then enter your current AUR password at the bottom of the form and click **Update**. The form doesn't save without the password.
3. Check it:
   ```sh
   ssh aur@aur.archlinux.org help
   ```
   It should list the AUR commands.

   The first connection asks you to confirm the AUR's host key. Answer `yes` only if the fingerprint matches one the AUR publishes at the bottom of <https://aur.archlinux.org>. As of 2026-09-26:

   | Key type | Fingerprint |
   |---|---|
   | ED25519 | `SHA256:RFzBCUItH9LZS0cKB5UE6ceAYhBD5C8GeOBip8Z11+4` |
   | ECDSA | `SHA256:uTa/0PndEgPZTf76e1DFqXKJEXKsn7m9ivhLQtzGOCI` |
   | RSA | `SHA256:5s5cIyReIfNNVGRFdDbe3hdYiI5OelHGpw2rOUud3Q8` |

SSH offers `~/.ssh/id_ed25519` by default, so no SSH config is needed. If your AUR key lives in another file, tell SSH in `~/.ssh/config`:

```
Host aur.archlinux.org
  IdentityFile ~/.ssh/<your-aur-key>
  User aur
```

## Releasing a version

1. Commit, then tag and push the release, for example `1.0.0`:
   ```sh
   git tag -a v1.0.0 -m "omarchy-teamviewer-launcher 1.0.0"
   git push origin master v1.0.0
   ```
2. Fill in the checksum and `.SRCINFO`, and test-build from the GitHub tarball:
   ```sh
   packaging/aur/update.sh 1.0.0
   ```
3. Commit the updated `PKGBUILD` and `.SRCINFO` in this repository.
4. Publish to the AUR:
   ```sh
   packaging/aur/publish.sh
   ```
   The first run clones `ssh://aur@aur.archlinux.org/omarchy-teamviewer-launcher.git` (empty for a new package) into `~/Projects/aur-omarchy-teamviewer-launcher`. Pushing to it creates the package. Later runs push updates.
5. Attach the built package to the GitHub release, for people installing without the AUR. Build it from the committed PKGBUILD in a scratch folder, so it comes from the GitHub tarball and not your working tree:
   ```sh
   dir=$(mktemp -d)
   git show HEAD:packaging/aur/PKGBUILD >"$dir/PKGBUILD"
   git show HEAD:packaging/aur/omarchy-teamviewer-launcher.install >"$dir/omarchy-teamviewer-launcher.install"
   (cd "$dir" && makepkg -f)
   gh release create v1.0.0 "$dir"/omarchy-teamviewer-launcher-1.0.0-1-any.pkg.tar.zst --verify-tag --title "omarchy-teamviewer-launcher 1.0.0" --notes "…"
   ```
   Then update the version in the download commands in the main README. Keep the release notes' install steps as download, compare the checksum, then `pacman -U` the local file: `pacman -U <link>` fails because the package isn't GPG-signed.

The package page is then <https://aur.archlinux.org/packages/omarchy-teamviewer-launcher>, and anyone can install it with `omarchy pkg aur add omarchy-teamviewer-launcher` or `yay -S omarchy-teamviewer-launcher`.

Don't move or re-create a tag after publishing it. The checksum in `PKGBUILD` belongs to the tagged commit's tarball, so a moved tag breaks every install with a checksum mismatch. Release a fix as a new version instead.

## Troubleshooting

### `Permission denied (publickey)`

```
aur@aur.archlinux.org: Permission denied (publickey).
fatal: Could not read from remote repository.
```

The AUR didn't accept the key SSH offered. Nothing was cloned or pushed, so after fixing it, just run `publish.sh` again.

1. See which key SSH offers:
   ```sh
   ssh -v aur@aur.archlinux.org help 2>&1 | grep "Offering public key"
   ```
2. Compare it with your key's fingerprint:
   ```sh
   ssh-keygen -lf ~/.ssh/id_ed25519.pub
   ```
   - The two match, but it's still refused: the key isn't on your AUR account. Paste it under **My Account → SSH Public Key**, and remember the password field (see [One-time setup](#one-time-setup)).
   - Nothing is offered, or a different key is: point SSH at the right key in `~/.ssh/config`, as above.
3. Test again with `ssh aur@aur.archlinux.org help`.

### The AUR doesn't respond

Sometimes the AUR is unreachable for a while, for example during DDoS protection: HTTPS fails with `TLS connect error` and SSH times out. `omarchy pkg aur accessible` reports whether it's back. Wait and try again.

## Changing only the packaging

For a fix to `PKGBUILD` or `omarchy-teamviewer-launcher.install` without a new release, bump `pkgrel` in `PKGBUILD`, run `makepkg --printsrcinfo > .SRCINFO` here, then `publish.sh`.

## Notes

- The AUR repository may only contain `PKGBUILD`, `.SRCINFO`, `omarchy-teamviewer-launcher.install` and similar small files. The code comes from the GitHub tarball.
- `depends` lists bash, dbus and jq from the official repositories, and `teamviewer` from the AUR (AUR packages may depend on other AUR packages; `yay` builds it first). `omarchy` and `hyprland` aren't listed: Omarchy comes from its own repository, and the wrapper leaves scales alone when `hyprctl` is missing.
- pacman can't undo changes in users' home folders, so `omarchy-teamviewer-launcher.install` tells users to run `omarchy-teamviewer-launcher disable` and `omarchy-teamviewer-launcher unsetup` before removing the package. If they don't, the D-Bus override falls back to TeamViewer's own helper, and the Setup > TeamViewer row hides itself.
