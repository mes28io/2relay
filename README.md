# 2relay

2relay is a macOS voice-to-prompt relay app for coding workflows.

## Install (curl)

```bash
curl -fsSL https://raw.githubusercontent.com/mes28io/2relay/main/scripts/install.sh | bash
```

This installs the latest GitHub Release, not unreleased commits on `main`.

Optional environment variables:

- `TWORELAY_VERSION=v0.1.0` to install a specific tag instead of latest release.
- `TWORELAY_INSTALL_DIR="$HOME/Applications"` to pick a custom destination.
- `TWORELAY_REPO="owner/repo"` if you fork the project.

## License

This project is open source under the MIT License. See [LICENSE](LICENSE).

## Development

```bash
swift build
swift test
```

Run app:

```bash
swift run TwoRelay
```

## Release Artifacts (for curl installer)

```bash
TWORELAY_MARKETING_VERSION=0.1.8 ./scripts/build_release.sh
./scripts/make_release_zip.sh
```

Upload both files from `dist/` to the GitHub Release:

- `2relay-macos.zip`
- `2relay-macos.zip.sha256`

## App Updates

Release builds can use Sparkle for in-app update checks. The app now reads its feed from:

- [appcast.xml](https://raw.githubusercontent.com/mes28io/2relay/main/appcast.xml)

To publish a new appcast entry for a release:

```bash
TWORELAY_MARKETING_VERSION=0.1.8 ./scripts/build_release.sh
./scripts/make_release_zip.sh
./scripts/make_update_zip.sh dist/export/2relay.app
DOWNLOAD_BASE_URL="https://github.com/mes28io/2relay/releases/download/v0.1.8" \
APPCAST_BASE_URL="https://raw.githubusercontent.com/mes28io/2relay/main" \
SPARKLE_PRIVATE_KEY_PATH="$HOME/.config/2relay/sparkle_ed25519_key" \
./scripts/write_appcast.sh dist/updates/2relay-0.1.8-$(git rev-list --count HEAD).zip dist/export/2relay.app
```
