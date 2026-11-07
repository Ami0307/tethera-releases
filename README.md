# Tethera connector

The computer side of [Tethera](https://herdr.dev), the iPhone client for Herdr: it lets your phone reach the coding agents (Claude Code, Codex) that Herdr runs on this computer.

This repository only hosts the installer and the release binaries.

## Install (macOS and Linux)

```sh
curl -fsSL https://github.com/Ami0307/tethera-releases/releases/latest/download/install.sh | sh
```

The installer puts `tethera` in `~/.local/bin` (no sudo), checks the download against its `.sha256`, starts the connector at login (a LaunchAgent on macOS, a `systemd --user` service on Linux) and shows a one-time QR code. Scan it in the Tethera app and confirm that the 6 digits match on both sides.

Builds: macOS universal (Apple silicon and Intel), Linux x86_64 and aarch64 (static, any distribution). If the login service can't be set up (Linux without `systemd --user`, such as some containers or WSL; a Mac reached over SSH with nobody logged in to the desktop), the installer says why and how to start the connector yourself with `tethera serve`, and still finishes. `TETHERA_NO_AGENT=1` skips the login service entirely:

```sh
curl -fsSL https://github.com/Ami0307/tethera-releases/releases/latest/download/install.sh | TETHERA_NO_AGENT=1 sh
```

## Use

| Command | What it does |
|---|---|
| `tethera pair` | Pair another phone (one-time QR code, valid 5 minutes) |
| `tethera devices` | List paired phones |
| `tethera revoke <name>` | Remove a phone; its connections end at once |
| `tethera status` | Is it running, relay, direct addresses, phones |
| `tethera config set relay n0\|off\|URL` | Choose the relay (default: n0 public relays) |
| `tethera config set port N` | UDP port for direct connections (default 47011) |
| `tethera uninstall` | Remove the agent, the binary and all connector state |

## Security

- Only paired phones get in; the connector only forwards to this computer's `hc connect` and opens no listening port to the internet.
- Traffic is end-to-end encrypted (QUIC over iroh); a relay only sees ciphertext.
- Each phone has its own key and can be removed on its own, here or from the app.

The macOS binary is not signed or notarized yet. A file downloaded with `curl` has no quarantine flag, so macOS runs it without the Gatekeeper prompt.

## iPhone app: SideStore source

The Tethera iPhone app can be installed and updated from SideStore (or AltStore). Add this source once:

```
https://raw.githubusercontent.com/Ami0307/tethera-releases/main/sidestore/source.json
```

New versions then show up in SideStore and update in place. The IPAs are attached to the `app-v*` releases here (the newest 5 are kept); `sidestore/` only holds `source.json` and the app icon.
