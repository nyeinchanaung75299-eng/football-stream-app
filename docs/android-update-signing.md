# NCA Android update signing compatibility

## One-time reinstall
An Android app installed with a different signing certificate cannot be updated
in place by the current stable APK. A user may perform a one-time uninstall and
reinstall, but first back up local-only settings and any data that might be
erased by uninstall. Then install the latest published NCA ARM64 APK from the
official in-app updater or official Telegram bots. Future releases must preserve
its signing certificate.

## Release safety gate
The existing signed Viewer/Admin APKs on the GitHub feed branch are the trusted
update reference. Before publishing replacement APKs or updater manifests,
the APK workflow performs these fail-closed checks:

1. Both Viewer and Admin require the configured stable release signing secrets.
   Missing signing configuration blocks publication of *both* updates.
2. The previous published APK and manifest must exist. The previous file size,
   SHA-256, ABI, and release URL must match its manifest before it is trusted.
3. Android apksigner verifies both old and new APKs. Their certificate SHA-256
   fingerprints must be identical for the respective app.
4. Android aapt reads package IDs and versionCodes. Viewer must retain its
   package name and Admin must retain its package name. Both newly built APK
   versionCodes must be strictly greater than their currently published ones.
5. On any failure, no replacement APK or JSON update feed is published. Debug-
   signed fallback builds are never offered as downloadable release artifacts.

Script: scripts/verify_android_update_signing.py
Test suite: python3 -m unittest discover -s scripts -p 'test_android_update_signing.py' -v
CI: .github/workflows/verify-android-update-signing.yml

Do not change Android package names or the stable keystore/key alias without an
explicit, planned signing migration. An APK SHA-256 check by itself does not
confirm its signing certificate matches an installed APK.

## Real-device validation
After a successful release CI run, verify both Viewer and Admin in-place updates
on a physical Android device running the previous stable APK, without
uninstalling. Telegram APK delivery and GitHub build success do not alone prove
the Android Package Installer will accept the upgrade. If a check fails, keep
the previous published version online.
