#!/usr/bin/env python3
"""Fail closed if newly built NCA APKs cannot update the published ARM64 apps.

Run before overwriting files in the GitHub feed worktree. The old, published
APK (not merely the GitHub manifest) is the signing-certificate baseline.
No signing private keys or secrets are read or printed by this script.
"""

from __future__ import annotations

import argparse
import hashlib
import json
from pathlib import Path
import re
import subprocess
import sys

RELEASE_BASE = (
    "https://raw.githubusercontent.com/"
    "nyeinchanaung75299-eng/football-stream-app/feed/public/releases/"
)
RELEASES = {
    "Viewer": ("latest.json", "NCA-arm64-v8a-latest.apk"),
    "Admin": ("admin-latest.json", "NCA-admin-arm64-v8a-latest.apk"),
}


class IncompatibleUpdate(ValueError):
    """Release should not be published as an in-place Android update."""


def digest_file(path: Path) -> str:
    sha = hashlib.sha256()
    with path.open("rb") as source:
        for chunk in iter(lambda: source.read(1024 * 1024), b""):
            sha.update(chunk)
    return sha.hexdigest()


def published_apk(feed_dir: Path, label: str) -> Path:
    manifest_name, apk_name = RELEASES[label]
    manifest_path = feed_dir / manifest_name
    apk_path = feed_dir / apk_name
    if not manifest_path.is_file() or not apk_path.is_file():
        raise IncompatibleUpdate(f"{label}: prior published APK or manifest is missing")
    try:
        manifest = json.loads(manifest_path.read_text(encoding="utf-8"))
    except (OSError, ValueError) as error:
        raise IncompatibleUpdate(f"{label}: invalid published manifest") from error

    if (
        not isinstance(manifest, dict)
        or manifest.get("apk_url") != RELEASE_BASE + apk_name
        or manifest.get("abi") != "arm64-v8a"
        or (label == "Admin" and manifest.get("app") != "nca_admin")
        or not isinstance(manifest.get("size_bytes"), int)
        or isinstance(manifest.get("size_bytes"), bool)
        or manifest["size_bytes"] <= 0
        or not isinstance(manifest.get("sha256"), str)
        or not re.fullmatch(r"[0-9a-f]{64}", manifest["sha256"], re.I)
    ):
        raise IncompatibleUpdate(f"{label}: published release metadata is invalid")
    if apk_path.stat().st_size != manifest["size_bytes"]:
        raise IncompatibleUpdate(f"{label}: published APK size does not match manifest")
    if digest_file(apk_path) != manifest["sha256"].lower():
        raise IncompatibleUpdate(f"{label}: published APK SHA-256 does not match manifest")
    return apk_path


def signer_digest(apksigner_output: str) -> str:
    """Parse APK certificates in legacy and Build Tools 37+ output formats.

    Newer apksigner versions report "V2 Signer: certificate SHA-256 digest:"
    or "V3.0 Signer: certificate SHA-256 digest:" instead of "Signer #1".
    Several signing schemes may report the SAME certificate, but changed
    certificates, multiple signers and unknown formats must block an update.
    """
    expression = re.compile(
        r"^\s*(?:"
        r"Signer #(?P<number>\d+) certificate"
        r"|V[1-4](?:\.\d+)? Signer: certificate"
        r"|Signer \(minSdkVersion=\d+,\s*maxSdkVersion=\d+\) certificate"
        r") SHA-256 digest:\s*(?P<digest>[0-9a-fA-F:]+)\s*$",
        flags=re.IGNORECASE,
    )
    digests: set[str] = set()
    matched = 0
    for line in apksigner_output.splitlines():
        if "certificate sha-256 digest:" not in line.lower():
            continue
        # Fail closed on any unfamiliar certificate signer notation.
        match = expression.fullmatch(line)
        if match is None:
            raise IncompatibleUpdate("APK has an unrecognized certificate signer format")
        number = match.group("number")
        if number is not None and number != "1":
            raise IncompatibleUpdate("APK must have exactly one recognized signing certificate")
        digest = match.group("digest").replace(":", "").lower()
        if not re.fullmatch(r"[0-9a-f]{64}", digest):
            raise IncompatibleUpdate("APK signing certificate SHA-256 is invalid")
        matched += 1
        digests.add(digest)

    reported = re.findall(
        r"^\s*Number of signers:\s*(\d+)\s*$",
        apksigner_output, flags=re.MULTILINE | re.IGNORECASE,
    )
    if (matched == 0 or len(digests) != 1 or
            any(int(count) != 1 for count in reported)):
        raise IncompatibleUpdate("APK must have exactly one recognized signing certificate")
    return next(iter(digests))


def package_identity(aapt_output: str) -> tuple[str, int]:
    match = re.search(
        r"^package:\s+name='([^']+)'\s+versionCode='([0-9]+)'",
        aapt_output, flags=re.MULTILINE,
    )
    if not match:
        raise IncompatibleUpdate("Cannot determine APK package name/versionCode")
    return match.group(1), int(match.group(2))


def apk_identity(path: Path, *, apksigner: str, aapt: str) -> tuple[str, int, str]:
    if not path.is_file():
        raise IncompatibleUpdate(f"APK missing: {path.name}")
    try:
        signer = subprocess.run(
            [apksigner, "verify", "--print-certs", str(path)],
            check=True, capture_output=True, text=True,
        )
        badges = subprocess.run(
            [aapt, "dump", "badging", str(path)],
            check=True, capture_output=True, text=True,
        )
    except (OSError, subprocess.CalledProcessError) as error:
        # Never expose command output that might carry environmental details.
        raise IncompatibleUpdate(f"APK signing/manifest verification failed: {path.name}") from error
    package, version = package_identity(badges.stdout)
    return package, version, signer_digest(signer.stdout)


def check_update(label: str, *, feed_dir: Path, new_path: Path,
                 apksigner: str, aapt: str) -> None:
    old_path = published_apk(feed_dir, label)
    old_package, old_code, old_certificate = apk_identity(
        old_path, apksigner=apksigner, aapt=aapt,
    )
    new_package, new_code, new_certificate = apk_identity(
        new_path, apksigner=apksigner, aapt=aapt,
    )
    if old_package != new_package:
        raise IncompatibleUpdate(f"{label}: BLOCKED package name changed")
    if old_certificate != new_certificate:
        raise IncompatibleUpdate(
            f"{label}: BLOCKED signing certificate changed (would require uninstall)"
        )
    if new_code <= old_code:
        raise IncompatibleUpdate(
            f"{label}: BLOCKED versionCode not newer ({new_code} <= {old_code})"
        )
    print(f"PASS {label}: same package and signing certificate; "
          f"versionCode {old_code} -> {new_code}")


def main() -> int:
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("--feed-dir", type=Path, required=True)
    parser.add_argument("--viewer-apk", type=Path, required=True)
    parser.add_argument("--admin-apk", type=Path, required=True)
    parser.add_argument("--apksigner", required=True)
    parser.add_argument("--aapt", required=True)
    args = parser.parse_args()
    try:
        check_update("Viewer", feed_dir=args.feed_dir,
                     new_path=args.viewer_apk,
                     apksigner=args.apksigner, aapt=args.aapt)
        check_update("Admin", feed_dir=args.feed_dir,
                     new_path=args.admin_apk,
                     apksigner=args.apksigner, aapt=args.aapt)
    except IncompatibleUpdate as error:
        print("RELEASE BLOCKED: " + str(error), file=sys.stderr)
        return 1
    print("Both ARM64 APKs are compatible with the currently published versions.")
    return 0


if __name__ == "__main__":
    sys.exit(main())
