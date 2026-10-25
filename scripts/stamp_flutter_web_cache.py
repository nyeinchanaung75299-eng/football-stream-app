#!/usr/bin/env python3
"""Stamp Flutter web entrypoints for GitHub Pages, where cache headers are fixed.

A new query parameter on index.html is not enough: mobile Safari can reuse the
old main.dart.js even when flutter_bootstrap.js has changed.
"""
from __future__ import annotations

import re
import sys
from pathlib import Path
from urllib.parse import quote


def stamp_flutter_web(build_dir: Path, build_id: str) -> None:
    if not re.fullmatch(r"[A-Za-z0-9_-]{1,90}", build_id):
        raise ValueError("Invalid build id")

    index = build_dir / "index.html"
    bootstrap = build_dir / "flutter_bootstrap.js"
    html = index.read_text(encoding="utf-8")
    js = bootstrap.read_text(encoding="utf-8")
    version = quote(build_id, safe="-_")

    # Stamp the bootstrap and, crucially, the dart2js entrypoint itself.
    # The latter is loaded by FlutterLoader after the HTML was parsed.
    updated_html, html_count = re.subn(
        r"""(?P<q>['"])flutter_bootstrap\.js(?P=q)""",
        lambda m: f"{m.group('q')}flutter_bootstrap.js?v={version}{m.group('q')}",
        html,
    )
    # The generated HTML can contain multiple bootstrap references (for
    # example both its normal entrypoint and an error/reload fallback).
    # Version all of them so no path can load an earlier release.
    if html_count < 1:
        raise RuntimeError(
            "No flutter_bootstrap.js reference was found in index.html"
        )

    updated_js, js_count = re.subn(
        r"""(?P<q>['"])main\.dart\.js(?P=q)""",
        lambda m: f"{m.group('q')}main.dart.js?v={version}{m.group('q')}",
        js,
    )
    # Match the preload URL to FlutterLoader's versioned entrypoint. Otherwise
    # the browser would download both an old URL and the new release bundle.
    updated_html = re.sub(
        r'''(?P<q>['"])main\.dart\.js(?P=q)''',
        lambda m: f"{m.group('q')}main.dart.js?v={version}{m.group('q')}",
        updated_html,
    )
    if js_count < 1:
        raise RuntimeError(
            "Flutter bootstrap has no main.dart.js entrypoint; "
            "review the generated loader before changing the cache strategy."
        )

    bootstrap.write_text(updated_js, encoding="utf-8")
    index.write_text(updated_html, encoding="utf-8")
    # GitHub Pages uses 404.html as a fallback for nested Flutter paths.
    (build_dir / "404.html").write_text(updated_html, encoding="utf-8")
    print(
        f"Stamped {build_dir}: bootstrap script={html_count}, "
        f"compiled entrypoint refs={js_count}, build={build_id}"
    )


if __name__ == "__main__":
    if len(sys.argv) != 3:
        raise SystemExit("Usage: stamp_flutter_web_cache.py BUILD_DIR BUILD_ID")
    stamp_flutter_web(Path(sys.argv[1]), sys.argv[2])
