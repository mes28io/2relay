# 2relay

2relay is a macOS voice-to-prompt relay app for coding workflows.

## Install (curl)

```bash
curl -fsSL https://raw.githubusercontent.com/mes28io/2relay/main/scripts/install.sh | bash
```

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
./scripts/build_release.sh
./scripts/make_release_zip.sh
```

Upload both files from `dist/` to the GitHub Release:

- `2relay-macos.zip`
- `2relay-macos.zip.sha256`
