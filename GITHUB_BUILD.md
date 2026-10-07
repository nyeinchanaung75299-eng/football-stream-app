# GitHub APK Build

This repository includes `.github/workflows/build-apks.yml`.

On a pull request to `main`, a manual run, or a push to `main` or `master`, GitHub Actions will:
1. Install Flutter.
2. Generate Android platform files.
3. Analyze and test the Admin and Viewer apps.
4. Build release APKs, compile the Web Viewer, and compile the Viewer for the iOS simulator.
5. Upload both APK files as GitHub Actions artifacts.

## Download APKs
Open the GitHub repository:
- Actions
- Open the latest `Build Android V9.8 APKs` run
- Scroll to `Artifacts`
- Download `NCA-Admin-V9.8-Release-APKs`
- Download `NCA-V9.8-Release-APKs`
- Download `NCA-Web-Review` for the compiled Web files

Pull requests and manual runs on review branches build artifacts for testing.
They use separate concurrency groups and do not publish updater files or
refresh production Pages. Stable Viewer signing and updater publication run
only on the repository's default branch when signing secrets are configured.
Fallback signing artifacts are unsuitable as an update to an existing app
signed with the production key.

`Review regression checks` also verifies player/gateway behavior, the Worker
bundle, and atomic publication against a disposable PostgreSQL database.
