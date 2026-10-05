# Release APK build

The GitHub Actions workflow now builds release APKs with:

flutter build apk --release --split-per-abi

This creates separate APKs for Android CPU architectures, usually:
- arm64-v8a — most modern Android phones
- armeabi-v7a — older 32-bit Android phones
- x86_64 — mainly emulators / some devices

For most current physical Android phones, install the `arm64-v8a` APK.

This setup is intended for testing / direct installation. For Play Store publication,
configure your own production signing keystore first.
