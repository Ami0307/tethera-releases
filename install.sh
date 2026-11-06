#!/bin/sh
# Tethera connector installer:
#   curl -fsSL https://github.com/Ami0307/tethera-releases/releases/latest/download/install.sh | sh
#
# Puts `tethera` in ~/.local/bin (no sudo), starts it at login (LaunchAgent on
# macOS, systemd --user on Linux) and shows a pairing QR code. Unsigned for
# now (no paid Apple account yet): the binary is downloaded with curl, which
# sets no quarantine flag, so Gatekeeper doesn't block it.
#
# Releases: https://github.com/Ami0307/tethera-releases (this script and the
# binaries with their .sha256 files, attached to each release).
#
# Env: TETHERA_BASE_URL (download location), TETHERA_BIN_DIR (default
# ~/.local/bin), TETHERA_NO_AGENT=1 (don't start it at login),
# TETHERA_NO_PAIR=1 (skip `tethera pair`).
set -eu

BASE_URL="${TETHERA_BASE_URL:-https://github.com/Ami0307/tethera-releases/releases/latest/download}"
BIN_DIR="${TETHERA_BIN_DIR:-$HOME/.local/bin}"

say() { printf '%s\n' "$*"; }
die() { printf 'tethera install: %s\n' "$*" >&2; exit 1; }

os=$(uname -s)
arch=$(uname -m)
case "$os" in
    Darwin) asset="tethera-macos-universal" ;;
    Linux)
        case "$arch" in
            x86_64 | amd64) asset="tethera-linux-x86_64" ;;
            aarch64 | arm64) asset="tethera-linux-aarch64" ;;
            *) die "unsupported Linux architecture: $arch" ;;
        esac
        ;;
    *) die "unsupported system: $os (macOS and Linux only)" ;;
esac

command -v curl >/dev/null 2>&1 || die "curl is needed"
mkdir -p "$BIN_DIR"
tmp=$(mktemp "${TMPDIR:-/tmp}/tethera.XXXXXX")
trap 'rm -f "$tmp" "$tmp.sha256"' EXIT INT TERM

say "Downloading ${asset}…"
curl -fsSL "$BASE_URL/$asset" -o "$tmp" || die "download failed: $BASE_URL/$asset"
# Every release has the checksum next to the binary: no checksum, no install.
curl -fsSL "$BASE_URL/$asset.sha256" -o "$tmp.sha256" || die "no checksum at $BASE_URL/$asset.sha256"
want=$(cut -d' ' -f1 < "$tmp.sha256")
if command -v shasum >/dev/null 2>&1; then got=$(shasum -a 256 "$tmp" | cut -d' ' -f1)
else got=$(sha256sum "$tmp" | cut -d' ' -f1); fi
[ -n "$want" ] && [ "$want" = "$got" ] || die "checksum mismatch for $asset"
chmod 0755 "$tmp"
mv -f "$tmp" "$BIN_DIR/tethera"
say "Installed $BIN_DIR/tethera ($("$BIN_DIR/tethera" --version))"

case ":$PATH:" in
    *":$BIN_DIR:"*) ;;
    *) say "Note: $BIN_DIR isn't on your PATH; add it to use \`tethera\` directly." ;;
esac

if [ "${TETHERA_NO_AGENT:-}" != "1" ]; then
    "$BIN_DIR/tethera" install-agent
fi

if [ "${TETHERA_NO_PAIR:-}" != "1" ]; then
    say ""
    # Piped installs have no terminal on stdin; read the y/n from the tty.
    if [ -r /dev/tty ]; then
        "$BIN_DIR/tethera" pair < /dev/tty
    else
        say "Pair your phone with: tethera pair"
    fi
fi
