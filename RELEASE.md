# 2relay Release Checklist (GitHub ZIP + curl installer)

Project and target:
- Project: `/Users/mdapro/Desktop/2relay/mac-app/2relay.xcodeproj`
- Scheme: `2relay`
- Bundle id (placeholder): `dev.tworelay.app`
- Primary distribution: GitHub Release zip + `scripts/install.sh`

## 1) One-time setup

1. Generate/refresh the wrapper project:
```bash
cd /Users/mdapro/Desktop/2relay/mac-app
xcodegen generate
```
2. In Xcode, open target `2relay` and confirm:
- Signing (Release): `Developer ID Application`
- Hardened Runtime: enabled
- Skip Install: `NO`
- Shared scheme: `2relay`

## 2) Build release app

```bash
cd /Users/mdapro/Desktop/2relay
./scripts/build_release.sh
```

Expected output:
- `dist/export/2relay.app`

## 3) Build GitHub release artifacts for curl installer

```bash
./scripts/make_release_zip.sh
```

Expected outputs:
- `dist/2relay-macos.zip`
- `dist/2relay-macos.zip.sha256`

## 4) Publish GitHub release

Create a GitHub Release (for example tag `v0.1.0`) and upload:
- `dist/2relay-macos.zip`
- `dist/2relay-macos.zip.sha256`

Installer command users run:

```bash
curl -fsSL https://raw.githubusercontent.com/mes28io/2relay/main/scripts/install.sh | bash
```

Install a specific tag:

```bash
curl -fsSL https://raw.githubusercontent.com/mes28io/2relay/main/scripts/install.sh | TWORELAY_VERSION=v0.1.0 bash
```

## 5) Verification commands

```bash
codesign --verify --deep --strict --verbose=2 dist/export/2relay.app
spctl --assess --type execute -vv dist/export/2relay.app
shasum -a 256 dist/2relay-macos.zip
cat dist/2relay-macos.zip.sha256
```

## Optional: DMG flow (legacy)

If you still need DMG distribution:

```bash
./scripts/make_dmg.sh
./scripts/notarize_dmg.sh dist/2relay.dmg
```

## Common pitfalls

1. Archive fails with “requires a development team”:
- Set `TEAM_ID` in shell or set Team in Xcode target Signing settings.
2. `dist/export/2relay.app` is missing:
- Confirm archive succeeded and contains `Products/Applications/2relay.app`.
3. `curl` installer fails with 404:
- Ensure the release includes both `2relay-macos.zip` and `2relay-macos.zip.sha256`.
- Ensure `scripts/install.sh` default repo matches your GitHub repo.
4. `spctl` says app is rejected:
- App is signed but not notarized/stapled; notarize the app artifact before release if you want best Gatekeeper UX.
5. You only want to test archive/export paths locally:
- Run `ALLOW_UNSIGNED_BUILD=1 ./scripts/build_release.sh` (local verification only, not shippable).
