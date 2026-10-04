# GitHub APK Build

This repository includes `.github/workflows/build-apks.yml`.

When files are pushed to `main` or `master`, GitHub Actions will:
1. Install Flutter.
2. Generate Android platform files.
3. Build the Admin app.
4. Build the User app.
5. Upload both APK files as GitHub Actions artifacts.

## Download APKs
Open the GitHub repository:
- Actions
- Open the latest `Build Android APKs` run
- Scroll to `Artifacts`
- Download `Football-Admin-APK`
- Download `Football-User-APK`

These are debug APKs intended for testing. Release/store publishing needs a signing key and release configuration.
