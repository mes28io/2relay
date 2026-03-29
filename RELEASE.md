# 2relay Release

## One-command release

```bash
./scripts/release.sh 0.2.0
```

This single command:
1. Builds the `.app` bundle via Xcode
2. Creates the release zip (for curl installer)
3. Creates the Sparkle update zip (for in-app updates)
4. Creates the DMG installer
5. Uploads all assets to a new GitHub Release
6. Updates `appcast.xml` for Sparkle
7. Commits and pushes the updated appcast

After running, existing users will see the update via **Check for Updates** in the app.

## Requirements

- Xcode with Developer ID signing configured
- `gh` CLI authenticated (`gh auth login`)
- Sparkle private key at `~/.config/2relay/sparkle_ed25519_key`

## For unsigned local testing

```bash
ALLOW_UNSIGNED_BUILD=1 ./scripts/build_release.sh
open dist/export/2relay.app
```

## Manual steps (if needed)

```bash
# Build only
TWORELAY_MARKETING_VERSION=0.2.0 ./scripts/build_release.sh

# Package only
./scripts/make_release_zip.sh
./scripts/make_update_zip.sh dist/export/2relay.app
./scripts/make_dmg.sh

# Upload to GitHub
gh release create v0.2.0 dist/2relay-macos.zip dist/2relay-macos.zip.sha256 dist/2relay.dmg

# Update appcast
DOWNLOAD_BASE_URL="https://github.com/mes28io/2relay/releases/download/v0.2.0" \
APPCAST_BASE_URL="https://raw.githubusercontent.com/mes28io/2relay/main" \
SPARKLE_PRIVATE_KEY_PATH="$HOME/.config/2relay/sparkle_ed25519_key" \
./scripts/write_appcast.sh dist/updates/2relay-*.zip dist/export/2relay.app
```
