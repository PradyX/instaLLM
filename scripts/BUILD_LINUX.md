# Building InstaLLM On Linux

This guide covers the Linux-specific pieces that are easy to miss:

- desktop toolchain prerequisites
- bundled `llama.cpp` runtime libraries for InstaLLM vision support

For the platform-agnostic native runtime background, also see `scripts/BUILD_LLAMA_CPP_PREBUILTS.md`.

## Prerequisites

Enable Flutter's Linux desktop target:

```bash
flutter config --enable-linux-desktop
```

Install the Linux build dependencies that Flutter, GTK, and `flutter_secure_storage` need. On Debian/Ubuntu, a typical baseline is:

```bash
sudo apt update
sudo apt install clang cmake ninja-build pkg-config libgtk-3-dev libsecret-1-dev libjsoncpp-dev patchelf
```

On Arch Linux, the equivalent build packages are typically:

```bash
sudo pacman -S --needed clang cmake ninja pkgconf gtk3 libsecret jsoncpp patchelf
```

## 1. Build The Linux Runtime Libraries

InstaLLM bundles Linux shared libraries from `linux/lib/`.
Build them from the same `llama.cpp` revision that matches the checked-in `llama_cpp_dart` package:

```bash
export LLAMA_CPP_DIR="$HOME/src/llama.cpp"
cd /path/to/InstaLLM
scripts/build_llama_native_libs.sh linux
```

Expected output files:

```text
linux/lib/libmtmd.so
linux/lib/libllama.so
linux/lib/libggml.so
linux/lib/libggml-base.so
linux/lib/libggml-cpu.so
```

`libmtmd.so` is the important one for multimodal/vision support. If it is missing, text inference may still work, but projector-based models will not.

## 2. Run The App During Development

```bash
cd /path/to/InstaLLM
flutter clean
flutter pub get
scripts/run_linux.sh
```

`scripts/run_linux.sh` creates `.env` from `.env.example` when it is missing — the
app reads that file at startup and exits without it — and reports a missing
`linux/lib` runtime with the build command from step 1, so the app never opens
with chat silently unable to load a model. Pass `--check-only` to check the
prerequisites without launching, and any other arguments through to
`flutter run`. A bare `flutter run -d linux` still works once both are in place.

## 3. Build The Release Bundle

```bash
cd /path/to/InstaLLM
flutter build linux
```

Flutter writes a relocatable Linux bundle to one of:

```text
build/linux/x64/release/bundle/
build/linux/arm64/release/bundle/
```

The executable inside the bundle is:

```text
bundle/installm
```

## 4. Create An Installable Archive

To package the Linux bundle into a release archive:

```bash
cd /path/to/InstaLLM
scripts/build_linux_archive.sh
```

That script:

- runs `flutter build linux --release`
- finds the generated Flutter bundle
- creates a compressed archive next to the release bundle

Expected output:

```text
build/linux/x64/release/installm-linux-x64.tar.gz
build/linux/arm64/release/installm-linux-arm64.tar.gz
```

## 5. Install On A Linux Machine

On the target machine, install the runtime libraries your distro needs.

On Debian/Ubuntu, a typical runtime set is:

```bash
sudo apt install libgtk-3-0 libsecret-1-0 libjsoncpp1
```

On Arch Linux, the typical runtime set is:

```bash
sudo pacman -S --needed gtk3 libsecret jsoncpp
```

Then extract the archive somewhere permanent, for example:

```bash
sudo mkdir -p /opt/installm
sudo tar -xzf installm-linux-x64.tar.gz -C /opt/installm --strip-components=1
```

Run it with:

```bash
/opt/installm/installm
```

Optional convenience symlink:

```bash
sudo ln -sf /opt/installm/installm /usr/local/bin/installm
```

That same extraction flow works on Arch:

```bash
sudo mkdir -p /opt/installm
sudo tar -xzf installm-linux-x64.tar.gz -C /opt/installm --strip-components=1
sudo ln -sf /opt/installm/installm /usr/local/bin/installm
```

## 6. Add A Desktop Launcher

InstaLLM's installed icon inside the Flutter bundle is typically:

```text
/opt/installm/data/flutter_assets/assets/icons/installm.png
```

For a per-user launcher on Ubuntu, Arch, or most other Linux desktops:

```bash
mkdir -p ~/.local/share/applications
cat > ~/.local/share/applications/installm.desktop <<'EOF'
[Desktop Entry]
Version=1.0
Type=Application
Name=InstaLLM
Comment=Privacy-first local AI assistant
Exec=/opt/installm/installm
Icon=/opt/installm/data/flutter_assets/assets/icons/installm.png
Terminal=false
Categories=Utility;Development;
StartupNotify=true
EOF

chmod +x ~/.local/share/applications/installm.desktop
```

For a system-wide launcher:

```bash
sudo tee /usr/share/applications/installm.desktop >/dev/null <<'EOF'
[Desktop Entry]
Version=1.0
Type=Application
Name=InstaLLM
Comment=Privacy-first local AI assistant
Exec=/opt/installm/installm
Icon=/opt/installm/data/flutter_assets/assets/icons/installm.png
Terminal=false
Categories=Utility;Development;
StartupNotify=true
EOF
```

On some desktops, logging out and back in or refreshing the application menu may be needed before the launcher appears.

## Notes

- Linux notifications depend on a running Freedesktop notification daemon in the desktop session.
- `flutter_secure_storage` uses the Linux keyring when available. InstaLLM falls back to app-local storage if the keyring backend is unavailable at runtime.
- If you change the bundled native libraries, run `flutter clean` before retesting so Flutter rebuilds the Linux bundle cleanly.
- `flutter test integration_test/<test>.dart -d linux` builds `build/linux/x64/debug/bundle` from the *test* entrypoint. Launching that binary straight afterwards starts the test harness rather than the app: the process runs, opens no window and prints only the engine banner. Rebuild with `flutter build linux` first, or launch through `scripts/run_linux.sh` / `flutter run -d linux`, which always build the normal entrypoint.
- The release archive is a relocatable bundle, not a `.deb`. If you want distro-native packaging later, use the generated bundle as the input to your packaging tool.
