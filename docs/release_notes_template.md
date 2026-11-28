# Release notes template

## How to use it

- Add the same change set to `CHANGELOG.md` under `## [Unreleased]`, one bullet per entry, before tagging.
- Copy this file to `build/release/RELEASE_NOTES.md` when cutting a release, then fill in the version.
- It is the exact shape fed to `gh release create --notes-file build/release/RELEASE_NOTES.md` (or `gh release edit`).
- Keep it bullets: one line per major change, at most two, no prose paragraphs and no narrative framing.
- `docs/play_store/release_notes.txt` is the same change set cut down to Play's 500-character field.

## The template

```markdown
Version <version> (versionCode <code>).

## Highlights

- <one user-visible change per line>
- <one user-visible change per line>

## Android

- `InstaLLM-<version>-android.apk` — versionCode <code>, versionName <version>, minSdk <n>, targetSdk <n>; sideload to install.

## macOS

- `InstaLLM-<version>-macos.dmg` — drag into Applications; signed with a local Apple Development identity, so right-click → Open on first launch (testing build, not notarized).
- <architecture or runtime caveat>

## Linux

- `InstaLLM-<version>-linux-x64.tar.gz` — unpack and run `installm-linux-x64/installm`; needs GTK 3 and `libsecret-1-0`.

## Checksums and build

- `SHA256SUMS.txt` covers every artifact here; the Play bundle is uploaded to Play Console and is not attached.
- Built from `<commit>`, tagged `v<version>`.
```
