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
- Signing material is local only. `pocketllm.jks` at the repository root and
  `android/key.properties` are ignored by `.gitignore`, and a scan of every
  commit, branch and tag on 17 November 2026 found neither file (nor any
  `*.keystore`, `*.p12` or PEM key) in the history, so there is nothing to
  purge. `android/app/build.gradle.kts` only *reads* `key.properties`.
- `in_app_review` is in the bundle (`base/root/review.properties` and
  `base/root/review-ktx.properties`), so the Play rating nudge resolves to the
  Play review sheet when InstaLLM was installed from Play.
- Store graphics on disk: `icon_512.png` is 512x512 RGBA and transparent
  outside the launcher tile, with an 18 px clear margin; keeping the alpha is
  what stops the tile's antialiased edge from turning into a black band and
  green specks, which an RGB flatten produced, and
  `feature_graphic_1024x500.png` is 1024x500 with no alpha channel. Phone
  screenshots `screens/1.png` to `screens/6.png` are each 1080x2160 — 2:1, the
  widest aspect Play accepts — retaken on 17 November 2026 on a OnePlus 7T
  (HD1901, Android 12) in light theme, from a 1080x2400 capture with the status
  and navigation bars cropped out. Order: 1 chat, 2 drawer, 3 models,
  4 settings, 5 new chat, 6 voice mode.
- Tablet and desktop sets, captured on 17 November 2026 in light theme with the
  solid surface style: `screens/tablet_7inch/` is 2048x1152 (16:9) from the
  TrebleDroid Android 13 tablet at 2048x1200, cropped by 48 px of status bar and
  64 px of gesture bar and scaled to exact 16:9 — two shots, home then settings,
  because that tablet has no model installed and cannot show a conversation;
  `screens/tablet_10inch/` is 1920x1080 and `screens/desktop/` is 2560x1440,
  both from the macOS app window resized to 960x540 pt and 1280x720 pt, with the
  title bar and the window's rounded corners cropped off. Order for both
  macOS sets: 1 chat, 2 home, 3 models, 4 settings.
- `description.txt` holds the short (66/80) and full (1540/4000) listing copy
  as plain blocks, and names the banner and logo files at the top.
- Store artwork replaced on 17 November 2026: the feature graphic is the
  deep-green banner (cream wordmark, launcher tile, the app's orb rings) and the
  icon is the launcher tile full bleed, so the listing matches what installed
  users see.
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
APK delivery (no `bundletool` run) is untested. The bundle was uploaded and
rolled out to a closed testing track (Alpha) on 17 November 2026; nothing has
been promoted to production and the store artwork has not been uploaded. The
Play review sheet cannot be observed until an install comes from Play.

## 4. Play Console checklist

0. **Developer account** — this release goes through an organisation account,
   which is exempt from the 12-testers-for-14-days closed-test rule that applies
   to personal accounts created after 13 November 2023
   ([Play Console Help](https://support.google.com/googleplay/android-developer/answer/14151465)).
   Production is available immediately; the internal and closed tracks are still
   the cheapest way to test a Play-signed install first.
1. **Create app** — name `InstaLLM`, default language English (US), app, free.
2. **App content**:
   - Privacy policy URL: `https://prady.website/privacy/insta-llm/` (already
     published; `privacy_policy.md` is the repository copy).
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
   - Short description, full description: `description.txt` (plain blocks with
     character counts, ready to paste; `listing.md` is the same copy with the
     contact block alongside).
   - App icon: `icon_512.png` (512x512).
   - Feature graphic: `feature_graphic_1024x500.png` (1024x500).
   - Phone screenshots: `screens/1.png` to `screens/6.png`, each measured at
     1080x2160, which is exactly 2:1, the widest aspect Play accepts (minimum
     320 px, maximum 3840 px, long side at most twice the short side). Order:
     1 chat, 2 drawer with Chats | Bots, 3 models, 4 settings, 5 new chat,
     6 voice mode.
   - 7-inch tablet screenshots: `screens/tablet_7inch/1.png`,
     `2.png` (2048x1152).
   - 10-inch tablet screenshots: `screens/tablet_10inch/1.png` to `4.png`
     (1920x1080).
   - Desktop screenshots: `screens/desktop/1.png` to `4.png` (2560x1440).
   - Category: Tools. Tags: local AI, offline, privacy.
4. **Release**: enable Play App Signing, upload the `.aab` to internal testing
   first and install from the Play link to confirm the bundle installs and the
   review prompt path resolves, then promote to production.
   - Release notes ("What's new in this release"): `release_notes.txt`, a
     479/500-character block for 1.6.0 (first release) with a 179-character
     variant below it.
5. **Promote Alpha to production** — a closed-testing release moves to
   production without rebuilding. Open **Test and release → Testing → Closed
   testing → Alpha → Releases**, open the 1.6.0 release and use **Promote
   release → Production**; creating a production release and adding the same
   bundle from the library does the same thing. The version code stays `1` —
   only a *new* upload needs a higher one. Before it can be rolled out:
   - **App content** complete and accepted (section 4, step 2), including the
     AI-generated content answer below,
   - **Store listing** complete (section 4, step 3),
   - **Countries/regions** chosen on the production track,
   - no other release left at a partial staged rollout, and no unpublished
     change held on the Publishing overview page.

   A first production release has no staged-rollout percentage: it goes to
   100% of the chosen countries at once, and it is reviewed again after the
   closed-test review (Google quotes a few days, longer for a first app). The
   12-testers-for-14-days rule does not block promotion here: it covers
   personal accounts created after 13 November 2023, and this developer account
   is an organisation account. Organisation accounts need website verification
   instead of the personal accounts' Android device verification.

If `1.6.0+1` has already been uploaded, bump to `1.6.1+2` and rebuild before
uploading: Play rejects a repeated version code.

## 5. Remaining steps

Done: store graphics (`icon_512.png`, `feature_graphic_1024x500.png`), the six
1080x2160 phone screenshots, the 7-inch, 10-inch and desktop sets, the release
notes (`release_notes.txt`), the support email (`info@prady.website`), the
published privacy policy URL (`https://prady.website/privacy/insta-llm/`) and
the 1.6.0 bundle on closed testing (Alpha).

1. Add an in-app way to report offensive AI output, or record why the
   AI-generated content policy does not apply, before the production review.
2. Promote the 1.6.0 release from Alpha to production (section 4, step 5).

Known copy issue: `lib/features/model_selection/presentation/model_selection_page.dart:1280`
hardcodes the column heading "Fit on this Mac", so Android and Linux users see
the same wording. The 7-inch tablet set leaves the models page out for that
reason; the macOS desktop and 10-inch sets show it correctly.
