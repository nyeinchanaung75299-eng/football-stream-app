# Isolated customer builds and owner project recovery

NCA production apps, endpoint configuration and signing workflow are unchanged by these opt-in tools. No demo is published to the NCA release feed. Commercial readiness remains unverified.

## Customer builds

`customer_profiles/demo-a.json` and `demo-b.json` are deliberately offline examples with different public project references, package identities, endpoints, names, colors and placeholder icons. Their `.example` hosts do not provide a working backend. Never set `test_only` to false just to bypass validation.

Prepare both application sources without changing this checkout:

```
python3 scripts/customer_profile.py --profile customer_profiles/demo-a.json --output /tmp/customer-a-source
```

One profile can build both Viewer and Admin in a separate output directory:

```
python3 scripts/customer_build.py --profile customer_profiles/demo-a.json --output /tmp/customer-a-web --target web --build-number 1
python3 scripts/customer_build.py --profile customer_profiles/demo-b.json --output /tmp/customer-b-qa --target qa-android --build-number 1
```

Install Flutter and the appropriate Android toolchain first. Export validates all owned endpoint replacements, rewrites the public Supabase key/release repository, disables NCA analytics, and omits automatic deployment workflows and secret files. A migration export is a template for a NEW, buyer-owned backend, not a command to replay migrations on NCA production.

For real customers use an ignored `customer_profiles/private/` profile with customer-owned infrastructure, a local PNG logo, and their publishable key only. Backend provisioning, routing/origin services and credential installation are separate operations; generating a profile does not create an isolated live backend.

`--target release-android` refuses demos and requires separate enrolled signing identities. Supply local protected environment variables `CUSTOMER_VIEWER_KEYSTORE`, `STORE_PASSWORD`, `KEY_ALIAS`, `KEY_PASSWORD`, `CERT_SHA256` (each prefixed `CUSTOMER_VIEWER_`; use the analogous `CUSTOMER_ADMIN_` variables). Keystores must be absolute existing paths. `apksigner` and `aapt` must be on PATH. The build checks the resulting certificate, package and version code. No release is automatically published. Keep build numbers monotonic for each package and preserve the enrolled keys. Never reuse the NCA production key for a buyer.

The preparation report explicitly leaves commercial approval false. Real backend separation, device installation/update tests, cutout/rotation/playback QA and buyer handover must pass before selling a release. Sample solid-color icons are test placeholders.

## Private Admin bot source backups

Use `/backup_source` (alias `/project_backup`) in the allowlisted private Admin bot. The command sends the latest published source ZIP only after checking fixed filename, SHA-256, size and scope. Other chats cannot retrieve a backup through this command. `/apk_admin` and `/apk_viewer` provide the signed app files separately. `/backup` remains a database-backup readiness report and does not create a database snapshot.

The source ZIP contains tracked source, migrations, build scripts, configuration examples, documentation, GitHub workflow definitions and `BACKUP-INVENTORY.json` / `RESTORE-README.txt`. It excludes secret environment files, keystores, private customer profiles, private-key material and release binaries. A detected private key blocks snapshot publication. The GitHub source/feed repository retains its existing visibility: private bot delivery does not make a public repository private.

This is NOT a full database/account recovery backup. Database rows, signing keys, service tokens, GitHub Secrets and account recovery credentials require a separate encrypted vault/database backup. Do not send them unencrypted to Telegram. Preserve migration history, account ownership and the original customer signing identity when restoring. Validate a restore in a separate backend before any production recovery.
