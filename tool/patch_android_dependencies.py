#!/usr/bin/env python3
"""Force Flutter Android plugins to compile against the project's SDK level.

Some plugins resolve ``flutter.compileSdkVersion`` from the Flutter SDK rather
than from the application's Gradle file. On CI runners with an older cached
Flutter Gradle configuration this can leave a plugin at API 33 even when the app
uses API 36, causing AAR metadata validation to fail. This script patches only
the downloaded package copies referenced by this project's package_config.json.
"""

from __future__ import annotations

import argparse
import json
import re
from pathlib import Path
from urllib.parse import unquote, urlparse

ROOT = Path(__file__).resolve().parents[1]
PACKAGE_CONFIG = ROOT / ".dart_tool" / "package_config.json"
COMPILE_SDK = 36


def _package_root(root_uri: str) -> Path:
    parsed = urlparse(root_uri)
    if parsed.scheme == "file":
        return Path(unquote(parsed.path)).resolve()
    if parsed.scheme:
        raise SystemExit(f"Unsupported package root URI: {root_uri}")
    return (PACKAGE_CONFIG.parent / unquote(root_uri)).resolve()


def _patch_gradle(path: Path) -> bool:
    original = path.read_text(encoding="utf-8")
    updated = original

    replacements = (
        (
            r"compileSdk\s*=\s*flutter\.compileSdkVersion",
            f"compileSdk = {COMPILE_SDK}",
        ),
        (
            r"compileSdkVersion\s*=\s*flutter\.compileSdkVersion",
            f"compileSdkVersion = {COMPILE_SDK}",
        ),
        (
            r"compileSdkVersion\s+flutter\.compileSdkVersion",
            f"compileSdkVersion {COMPILE_SDK}",
        ),
    )
    for pattern, replacement in replacements:
        updated = re.sub(pattern, replacement, updated)

    # Also raise explicit older values. Limit the replacement to compileSdk
    # declarations; targetSdk and minSdk are intentionally untouched.
    updated = re.sub(
        r"\bcompileSdk\s*=\s*(?:[0-9]|[12][0-9]|3[0-5])\b",
        f"compileSdk = {COMPILE_SDK}",
        updated,
    )
    updated = re.sub(
        r"\bcompileSdkVersion\s*=\s*(?:[0-9]|[12][0-9]|3[0-5])\b",
        f"compileSdkVersion = {COMPILE_SDK}",
        updated,
    )
    updated = re.sub(
        r"\bcompileSdkVersion\s+(?:[0-9]|[12][0-9]|3[0-5])\b",
        f"compileSdkVersion {COMPILE_SDK}",
        updated,
    )

    if updated != original:
        path.write_text(updated, encoding="utf-8")
        return True
    return False


def _has_required_sdk(path: Path) -> bool:
    text = path.read_text(encoding="utf-8")
    patterns = (
        rf"\bcompileSdk\s*=\s*{COMPILE_SDK}\b",
        rf"\bcompileSdkVersion\s*=\s*{COMPILE_SDK}\b",
        rf"\bcompileSdkVersion\s+{COMPILE_SDK}\b",
    )
    return any(re.search(pattern, text) for pattern in patterns)


def main() -> None:
    parser = argparse.ArgumentParser()
    parser.add_argument(
        "--check",
        action="store_true",
        help="Validate plugin Gradle files without modifying them.",
    )
    args = parser.parse_args()

    if not PACKAGE_CONFIG.exists():
        raise SystemExit("Run `flutter pub get` before patching Android plugins.")

    config = json.loads(PACKAGE_CONFIG.read_text(encoding="utf-8"))
    android_gradle_files: list[tuple[str, Path]] = []

    for package in config.get("packages", []):
        name = package.get("name")
        root_uri = package.get("rootUri")
        if not isinstance(name, str) or not isinstance(root_uri, str):
            continue

        package_root = _package_root(root_uri)
        for filename in ("build.gradle.kts", "build.gradle"):
            gradle = package_root / "android" / filename
            if not gradle.exists():
                continue
            text = gradle.read_text(encoding="utf-8")
            if re.search(r"\bcompileSdk(?:Version)?\b", text):
                android_gradle_files.append((name, gradle))
            break

    if not android_gradle_files:
        raise SystemExit("No Android plugin Gradle files were found.")

    patched: list[str] = []
    invalid: list[str] = []
    for name, gradle in android_gradle_files:
        if not args.check and _patch_gradle(gradle):
            patched.append(name)
        if not _has_required_sdk(gradle):
            invalid.append(f"{name}: {gradle}")

    if invalid:
        rendered = "\n".join(f"  - {item}" for item in invalid)
        raise SystemExit(
            f"Android plugins still below compileSdk {COMPILE_SDK}:\n{rendered}"
        )

    action = "Validated" if args.check else "Configured"
    print(
        f"{action} {len(android_gradle_files)} Android plugin(s) for "
        f"compileSdk={COMPILE_SDK}. Patched: {', '.join(patched) or 'none'}."
    )


if __name__ == "__main__":
    main()
