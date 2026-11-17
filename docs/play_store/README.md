# Google Play release

Everything needed to build and publish InstaLLM on Google Play. The bundle is
built locally; the Play Console steps are manual.

## 1. Build the signed bundle

```bash
scripts/build_android_bundle.sh
```

Output: `build/app/outputs/bundle/release/app-release.aab`, signed with the key
`android/key.properties` points at. The script prints the bundle size, the
`pubspec.yaml` version and its SHA-256.

Both `android/key.properties` and the keystore are gitignored and live outside
the repository. A release build without them stops in Gradle with a message
naming the four missing properties, instead of producing an unsigned bundle.

**Back up the keystore and its passwords offline.** Play App Signing (enabled
when the first bundle is uploaded) keeps the app signing key, but the upload key
still signs every release, and a lost upload key needs a Play Console reset.

## 2. Version

`pubspec.yaml` holds `version: 1.6.0+1`. Play rejects a repeated version code,
so every upload bumps the number after `+`:

```yaml
version: 1.6.1+2
```

The name before `+` is what users see; the number after `+` is `versionCode`.
Play only requires the code to increase, but a new name is how users tell one
release from the next, so bump both.

## 3. Verified in this repository

Checked on 17 November 2026 against `main` at `85e063a`, rebuilt from the
working tree with `scripts/build_android_bundle.sh`:

- Bundle: `build/app/outputs/bundle/release/app-release.aab`, 147.2 MB as
  Gradle reports it (145 MB on disk), SHA-256
  `202f76b6944a9e34cc1d9c20149919dbb6d85dd795db250977f276539a5d8c17`.
- Signature: `jarsigner -verify` prints `jar verified.`; the signer certificate
  is `CN=pocketllm, OU=pocket llm, O=pocket llm, L=LKO, ST=UP, C=IN`
  (SHA384withRSA, valid until 23 July 2053).
- Version: `versionCode 1`, `versionName 1.6.0`; `minSdkVersion 24`,
  `targetSdkVersion 36`. Play requires API 36 for new apps submitted from
  31 August 2026, so this target is the current minimum.
- ABIs in the bundle: `arm64-v8a`, `armeabi-v7a`, `x86_64`. Every 64-bit
  library is 16 KB page aligned (`libapp.so` and `libflutter.so` `LOAD`
  alignment `0x10000`, the rest `0x4000`), which Play requires for apps
  targeting Android 15 and newer. The 32-bit `armeabi-v7a` llama.cpp/ggml
  libraries are aligned to `0x1000`; the requirement covers 64-bit ABIs only.
- Permissions in the merged release manifest
  (`build/app/intermediates/merged_manifest/release/processReleaseMainManifest/AndroidManifest.xml`):
  `INTERNET`, `POST_NOTIFICATIONS`, `RECORD_AUDIO`, plus `VIBRATE` and the
  signature-level `com.prady.installm.DYNAMIC_RECEIVER_NOT_EXPORTED_PERMISSION`
  that AndroidX and the Play libraries add. All are normal permissions with no
  runtime prompt and none changes the data safety answers.
- `in_app_review` is in the bundle (`base/root/review.properties` and
  `base/root/review-ktx.properties`), so the Play rating nudge resolves to the
  Play review sheet when InstaLLM was installed from Play.
- Store graphics on disk: `icon_512.png` is 512x512 with no alpha channel,
  `feature_graphic_1024x500.png` is 1024x500 with no alpha channel. Phone
  screenshots `screens/1.png` to `screens/5.png` are each 1080x2160 — 2:1, the
  widest aspect Play accepts — retaken on 17 November 2026 on a OnePlus 7T
  (HD1901, Android 12) in light theme, from a 1080x2400 capture with the status
  and navigation bars cropped out. Order: 1 chat, 2 drawer, 3 models,
  4 settings, 5 new chat.
- `flutter analyze` clean, 44/44 tests passing.

Earlier checks, 14 November 2026, before the star and Play nudges were added:

- `scripts/build_android_bundle.sh` rebuilt reproducibly: two builds (the
  second after `flutter clean` deleted `build/`) produced byte-identical
  output, SHA-256
  `18a6177ff849d9282eb89184f2fc0df8a84dadb394a84d8a67a129f99b9df519`. The
  current bundle above supersedes that artifact.
- `android.permission.INTERNET` is in the merged release manifest, not only in
  the source manifest.
- With `android/key.properties` moved aside, `flutter build appbundle --release`
  fails in 6 s with
  `Release signing is not configured: add storeFile, storePassword, keyAlias and keyPassword to android/key.properties.`
  and writes no bundle. The file was restored and is byte-identical.
- Installed on an arm64 Android 10 emulator (Pixel 4 AVD) as a signed release
  APK built from the same source and signing config: first launch, downloaded
  the ~153 MB SmolLM2-135M-Instruct catalog entry over the network, generated a
  reply at 17.3 tok/s, and kept the conversation after Home and reopen.
- `scripts/build_android_bundle.sh` deletes `app-release.aab` before running
  Gradle, so a failed build cannot leave a stale bundle behind (read from the
  script; the failing-signing run also wrote no bundle).
- `flutter analyze` clean, 44/44 tests passing.

Not verified: the `.aab` itself was never installed; the emulator run used a
separate release APK from the same source and signing config, so Play-split
APK delivery (no `bundletool` run) is untested. Nothing has been uploaded to
Play Console, and the store artwork has not been uploaded. The Play review
sheet cannot be observed until the bundle is on a Play track and installed from
Play.

## 4. Play Console checklist

0. **Developer account** — a personal account created after 13 November 2023
   must run a closed test with at least 12 testers opted in continuously for the
   preceding 14 days before Play Console enables Production; internal testing
   does not satisfy it, and production access is granted only after applying
   from the Dashboard
   ([Play Console Help](https://support.google.com/googleplay/android-developer/answer/14151465)).
   Recruit more than 12 so ordinary dropouts do not reset the streak. An
   organisation account is exempt, and so is any account created before that
   date.
1. **Create app** — name `InstaLLM`, default language English (US), app, free.
2. **App content**:
   - Privacy policy URL (host `privacy_policy.md` publicly; see section 5).
   - Ads: **No ads**.
   - Data safety: **no data collected or shared**; all processing is on-device.
     The only network traffic is a model download the user starts, which is not
     personal data. Answer microphone as "used but not collected" if the form
     asks about it.
   - Content rating: complete the questionnaire. Expected outcome: Everyone /
     PEGI 3, no user-generated content sharing, no ads, no purchases.
   - Target audience: 13+ (not designed for children).
   - News app: no. Health app: no. Financial features: no.
   - Government app: no. Data deletion: users delete chats and models inside
     the app; no account exists.
   - AI-generated content
     ([policy](https://support.google.com/googleplay/android-developer/answer/13985936)):
     the policy requires apps that generate content with AI to offer in-app
     reporting or flagging of offensive output without leaving the app. The app
     has no such affordance yet, so either add one (a Report action on an
     assistant message that opens a pre-filled `mailto:` to the support
     address) or have the reason it does not apply documented before review.
3. **Store listing**:
   - Short description, full description: `listing.md`.
   - App icon: `icon_512.png` (512x512).
   - Feature graphic: `feature_graphic_1024x500.png` (1024x500).
   - Phone screenshots: `screens/1.png` to `screens/5.png`, each measured at
     1080x2160, which is exactly 2:1, the widest aspect Play accepts (minimum
     320 px, maximum 3840 px, long side at most twice the short side). Order:
     1 chat, 2 drawer with Chats | Bots, 3 models, 4 settings, 5 Bots tab.
   - Category: Tools. Tags: local AI, offline, privacy.
4. **Release**: enable Play App Signing, upload the `.aab` to internal testing
   first and install from the Play link to confirm the bundle installs and the
   review prompt path resolves, then run the closed test from step 0 and
   promote to production from the Dashboard.

If `1.6.0+1` has already been uploaded, bump to `1.6.1+2` and rebuild before
uploading: Play rejects a repeated version code.

## 5. Remaining steps (user only)

1. Add the support email to `docs/play_store/privacy_policy.md`, line 57
   (`[SUPPORT EMAIL]`), and to `docs/play_store/listing.md`, line 53
   (`Support email: [SUPPORT EMAIL]`).
2. Host the whole of `docs/play_store/privacy_policy.md` (lines 1-57) at a
   public URL (GitHub Pages, the project site, or any static host); hosting
   changes no file in this repository.
3. Put that URL on `docs/play_store/listing.md`, line 55
   (`Privacy policy: [PRIVACY POLICY URL]`), and give it to Play Console in
   App content → Privacy policy.
4. Capture screenshots from a physical phone if the emulator frames are not
   wanted: `screens/1.png` to `screens/5.png`, any size from 320 to 3840 px
   with the long side at most twice the short side.
5. Add an in-app way to report offensive AI output, or record why the
   AI-generated content policy does not apply, before the first review.
6. Run the closed test from step 0 and apply for production access.
