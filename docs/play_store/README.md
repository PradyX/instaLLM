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

`pubspec.yaml` holds `version: 1.7.2+6`. Play's highest version code is `5`
(`1.7.1`) and it rejects a repeated one, so every upload bumps the number
after `+`; the bundles built since then carry codes `3` (`1.6.2`), `4`
(`1.7.0`), `5` (`1.7.1`) and `6` (`1.7.2`):

```yaml
version: 1.7.2+6
```

The name before `+` is what users see; the number after `+` is `versionCode`.
Play only requires the code to increase, but a new name is how users tell one
release from the next, so bump both.

## 3. Verified in this repository

Checked on 27 November 2026 against the working tree that carries `1.7.2+6`
(and on 26 November 2026 against the tree that carried `1.7.1+5`), built with
`scripts/build_android_bundle.sh`:

- Bundles built from this repository, all signed with the same upload key:
  - `1.7.2+6` (versionCode 6), built on 27 November 2026 from `f024095`,
    142 MB on disk (148,825,843 bytes; 143 MB as Gradle reports it), SHA-256
    `4215c2ed3822ab063a3b74801e187f7008e65684a36efa13cd2a3aabfa6ed93b`,
    `scripts/build_android_bundle.sh` exited 0 and `jarsigner -verify` prints
    `jar verified.`; the sideload APK of the same build reports
    `versionCode='6' versionName='1.7.2'`, `minSdkVersion 24`,
    `targetSdkVersion 36` through `aapt2 dump badging`. This is the bundle
    attached to GitHub release `v1.7.2`, with that APK, the macOS DMG (built
    `1.7.2`/`6`) and the Linux archive. It carries the Hugging Face-style
    model catalog, the single model/thinking pill, the voice dock and the
    brain-in-chip model mark, and it fixes a tablet's filter column naming a
    Mac.
  - `1.7.1+5` (versionCode 5), built on 26 November 2026 from `e994625`,
    142 MB on disk (148.6 MB as Gradle reports it), SHA-256
    `2e17131b50a004cdc66cd76da95c8f65737375a02f5a030aa5aed08994d4fffa`,
    `scripts/build_android_bundle.sh` exited 0, `jarsigner -verify` prints
    `jar verified.`, and the manifest reports `versionCode="5"`,
    `versionName="1.7.1"`, `minSdkVersion 24`, `targetSdkVersion 36` (read back
    from the sideload APK of the same build with `aapt2 dump badging`). This is
    the bundle attached to GitHub release `v1.7.1`, along with that APK, the
    macOS DMG and the Linux archive.
  - `1.7.0+4` (versionCode 4), built on 25 November 2026 from this tree,
    148,554,338 bytes (148.6 MB as Gradle reports it), SHA-256
    `0af47d0ca30e67fac33dbe3a990472c0aeb0d00e695d5878e59e46afddeb93ed`,
    `scripts/build_android_bundle.sh` exited 0, `jarsigner -verify` prints
    `jar verified.`, and the merged release manifest reports
    `versionCode="4"`, `versionName="1.7.0"`, `minSdkVersion 24`,
    `targetSdkVersion 36`. This bundle adds the Play update prompt
    (`in_app_update` 5.0.0; `base/root/app-update.properties` is in the
    archive) on top of the `1.6.2+3` contents. Debug builds skip the prompt
    entirely (`kDebugMode`), and Google's in-app update API only answers for a
    build Play installed, so it cannot be exercised on a sideloaded APK or on
    this local `.aab` before it is uploaded.
  - `1.6.2+3` (versionCode 3), built on 23 November 2026 from `a8d69ad`,
    148.5 MB as Gradle reports it (142 MB on disk), SHA-256
    `9cbcfec5bd8f3c933d3b547baab260488597783746470a63d1a043d0f40f105e`,
    `flutter build appbundle` exited 0. This bundle carries the
    model-download repair (`2fb40dc`), the missing-file install state
    (`a7e502a`) and the chat-template fix (`ba2abd6`) that `1.6.1` predates.
  - `1.6.0+1` (versionCode 1), SHA-256
    `202f76b6944a9e34cc1d9c20149919dbb6d85dd795db250977f276539a5d8c17` —
    the build rolled out to closed testing (Alpha).
  - `1.6.1+2` (versionCode 2), built on 17 November 2026, 147.2 MB as Gradle
    reports it (140 MB on disk), SHA-256
    `08bc953132702efc97446749c6c4726265e061d6facb639d3c13618371b1afce`,
    `flutter build appbundle` exited 0. The build script deletes the previous
    file first, so only the newest bundle is on disk and the earlier two exist
    as Play uploads.
- Signature: `jarsigner -verify` prints `jar verified.`; the signer certificate
  is `CN=pocketllm, OU=pocket llm, O=pocket llm, L=LKO, ST=UP, C=IN`
  (SHA384withRSA, valid until 23 July 2053).
- Version: `versionCode 3`, `versionName 1.6.2` in the merged release
  manifest, and `versionName 1.6.2` with attribute `versionCode 3` inside the
  bundle's own `base/manifest` (read back from the `.aab` with
  `java -jar bundletool-all-1.18.1.jar dump manifest --bundle=…`, not from
  Gradle's log: `<manifest … android:versionCode="3"
  android:versionName="1.6.2" package="com.prady.installm">`);
  `minSdkVersion 24`, `targetSdkVersion 36`, `compileSdkVersion 36`. Play requires API 36 for new apps submitted from
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
  `feature_graphic_1024x500.png` is 1024x500 with no alpha channel.   Phone
  screenshots `screens/1.png` to `screens/6.png` are each 1080x2160 — 2:1, the
  widest aspect Play accepts — retaken on 27 November 2026 from `1.7.2+6` on a
  OnePlus 7T (HD1901, Android 12), from a 1080x2400 capture with the status bar
  and navigation bar cropped out (top 80 px, bottom 160 px). The phone draws a
  three-pixel capture frame at the screen edge, so the first four columns at
  each side are cloned inward before the crop. Order: 1 chat (a reply the
  installed `LFM2 · 1.2B` wrote offline), 2 drawer, 3 models, 4 settings,
  5 new chat, 6 voice mode. The theme is the phone's own: light, translucent
  surface, Blue accent.
- Framed art: `screens/framed/<device>/` holds the same captures as store
  artwork, rendered by `scripts/generate_store_art.py` at the store's exact
  sizes. Each panel carries the launcher tile and wordmark top-left, a
  two-line headline, a muted subtitle and the capture as a rounded card on an
  alternating deep-green and cream panel; the text layer renders at 2x and is
  downsampled so type and corners stay crisp, and the capture is composited at
  native scale so it is never resampled twice. The captures are cropped to app
  content, so each card reserves the platform bar's real height as empty space
  above the app: 24 dp for the phone cards, 48 px for the tablets and a
  proportional title-bar height for the desktop cards. Drawn status icons and
  traffic lights were tried and read badly at card scale, so the space is left
  empty and filled from the capture's own top edge, which keeps a drawer scrim
  or a sidebar seam running upward instead of stopping at the card edge. The
  script only needs Pillow and the fonts already on macOS.
- The 7-inch set was retaken on 27 November 2026 from `1.7.2+6` on the same
  TrebleDroid Android 13 tablet, forced to 2048x1200 at density 320: two shots,
  the catalog with its filter column reading **This device** and settings. The
  tablet has no model installed, so it still has no conversation to show. The
  capture is cut at the status bar, given a 48 px band of the app's own page
  colour and scaled to exact 16:9, because this tablet's app bar now starts
  directly under the bar and the artwork's chrome strip stretches the capture's
  first row.
- **The 10-inch and desktop sets are still the 17 November 2026 captures.** They
  were taken from a macOS window driven by hand, and this pass could not
  re-create them: the window can be sized through System Events, but the app's
  Flutter content exposes no accessibility tree, so navigation inside it would
  need synthetic clicks, which this repository's agent rules forbid. Everything
  below that describes those two sets therefore refers to the `1.7.1` UI.
- Tablet and desktop sets, captured on 17 November 2026 in light theme with the
  solid surface style: `screens/tablet_7inch/` was 2048x1152 (16:9) from the
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
   - Phone screenshots: `screens/framed/phone/1.png` to `screens/framed/phone/6.png`,
     each measured at 1080x2160, which is exactly 2:1, the widest aspect Play
     accepts (minimum 320 px, maximum 3840 px, long side at most twice the
     short side). Order: 1 chat, 2 drawer with Chats | Bots, 3 models,
     4 settings, 5 new chat, 6 voice mode.
   - 7-inch tablet screenshots: `screens/framed/tablet_7inch/1.png`,
     `2.png` (2048x1152).
   - 10-inch tablet screenshots: `screens/framed/tablet_10inch/1.png` to
     `4.png` (1920x1080).
   - Desktop screenshots: `screens/framed/desktop/1.png` to `4.png`
     (2560x1440).

   The `framed/` sets are the raw captures with a brand row, a headline and a
   subtitle on an alternating deep-green and cream panel, rendered by
   `scripts/generate_store_art.py`. That script reads the untouched captures in
   `screens/`, `screens/tablet_7inch/`, `screens/tablet_10inch/` and
   `screens/desktop/`, so the plain screens are still there for reference and
   the artwork can be regenerated after a UI change.
   - Category: Tools. Tags: local AI, offline, privacy.
4. **Release**: enable Play App Signing, upload the `.aab` to internal testing
   first and install from the Play link to confirm the bundle installs and the
   review prompt path resolves, then promote to production.
   - Release notes ("What's new in this release"): `release_notes.txt`, one
     bullet per user-visible change for 1.7.2 — a 320/500-character block with
     a 154-character variant below it, each heading carrying its own count.
5. **Promote Alpha to production** — a closed-testing release moves to
   production without rebuilding. Open **Test and release → Testing → Closed
   testing → Alpha → Releases**, open the release to publish and use **Promote
   release → Production**; creating a production release and adding the same
   bundle from the library does the same thing. Promoting keeps that release's
   version code — `2` for the 1.6.1 bundle — so only a *new* upload needs a
   higher one. Before it can be rolled out:
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

`1.6.1+2` is the build that went live first release and predates the
model-install repairs, so this tree carries `1.7.1+5`: Play rejects a repeated
version code, and `1.6.1` cannot be fixed in place because the download bug is
in the shipped Dart code. `1.7.0` is the first build that can also tell its own
users about the next one, through Play's in-app update API.

## 5. Remaining steps

Done: store graphics (`icon_512.png`, `feature_graphic_1024x500.png`), the
framed screenshot art for all four device classes
(`screens/framed/phone|tablet_7inch|tablet_10inch|desktop/`), the release
notes (`release_notes.txt`), the support email (`info@prady.website`), the
published privacy policy URL (`https://prady.website/privacy/insta-llm/`), the
1.6.0 bundle on closed testing (Alpha), the `1.6.1+2` bundle released on Play,
the `1.6.2+3` bundle built from this tree, the `1.7.0+4` bundle built from it
afterwards, the `1.7.1+5` bundle released on GitHub as `v1.7.1`, and the
`1.7.2+6` bundle released on GitHub as `v1.7.2` with refreshed phone and
7-inch screenshots.

1. Add an in-app way to report offensive AI output, or record why the
   AI-generated content policy does not apply, before the production review.
2. Upload the `1.7.2+6` bundle, then promote it to production (section 4,
   steps 4 and 5). Once that build is on a testing track, install it from the
   Play link and confirm the update prompt appears on the next launch against
   an even newer build.

The model ledger's fit column reads "Fit on this device" ("Fit" on a phone
width), so the Android and Linux screenshots no longer show macOS wording; the
7-inch tablet set left the models page out before that change was made.
