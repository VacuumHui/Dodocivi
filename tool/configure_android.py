#!/usr/bin/env python3
"""Apply deterministic Android settings after `flutter create`."""

from __future__ import annotations

import re
from pathlib import Path

ROOT = Path(__file__).resolve().parents[1]
ANDROID = ROOT / "android"
COMPILE_SDK = 36
TARGET_SDK = 35
MIN_SDK = 24
ANDROID_GRADLE_PLUGIN = "8.12.1"
KOTLIN_PLUGIN = "2.2.0"
GRADLE_VERSION = "8.13"
APP_LABEL = "SDXL Collector"


def _first_existing(*paths: Path) -> Path:
    path = next((candidate for candidate in paths if candidate.exists()), None)
    if path is None:
        rendered = ", ".join(str(candidate.relative_to(ROOT)) for candidate in paths)
        raise SystemExit(f"Expected generated file was not found: {rendered}")
    return path


def patch_app_gradle() -> None:
    gradle = _first_existing(
        ANDROID / "app" / "build.gradle.kts",
        ANDROID / "app" / "build.gradle",
    )
    text = gradle.read_text(encoding="utf-8")
    replacements = (
        (r"compileSdk\s*=\s*flutter\.compileSdkVersion", f"compileSdk = {COMPILE_SDK}"),
        (r"compileSdkVersion\s+flutter\.compileSdkVersion", f"compileSdkVersion {COMPILE_SDK}"),
        (r"compileSdkVersion\s*=\s*flutter\.compileSdkVersion", f"compileSdkVersion = {COMPILE_SDK}"),
        (r"targetSdk\s*=\s*flutter\.targetSdkVersion", f"targetSdk = {TARGET_SDK}"),
        (r"targetSdkVersion\s+flutter\.targetSdkVersion", f"targetSdkVersion {TARGET_SDK}"),
        (r"targetSdkVersion\s*=\s*flutter\.targetSdkVersion", f"targetSdkVersion = {TARGET_SDK}"),
        (r"minSdk\s*=\s*flutter\.minSdkVersion", f"minSdk = {MIN_SDK}"),
        (r"minSdkVersion\s+flutter\.minSdkVersion", f"minSdkVersion {MIN_SDK}"),
        (r"minSdkVersion\s*=\s*flutter\.minSdkVersion", f"minSdkVersion = {MIN_SDK}"),
    )

    updated = text
    for pattern, replacement in replacements:
        updated = re.sub(pattern, replacement, updated)

    declarations = (
        (
            rf"compileSdk(?:Version)?\s*(?:=\s*)?{COMPILE_SDK}\b",
            "android {",
            f"compileSdk = {COMPILE_SDK}"
            if gradle.suffix == ".kts"
            else f"compileSdkVersion {COMPILE_SDK}",
        ),
        (
            rf"targetSdk(?:Version)?\s*(?:=\s*)?{TARGET_SDK}\b",
            "defaultConfig {",
            f"targetSdk = {TARGET_SDK}"
            if gradle.suffix == ".kts"
            else f"targetSdkVersion {TARGET_SDK}",
        ),
        (
            rf"minSdk(?:Version)?\s*(?:=\s*)?{MIN_SDK}\b",
            "defaultConfig {",
            f"minSdk = {MIN_SDK}"
            if gradle.suffix == ".kts"
            else f"minSdkVersion {MIN_SDK}",
        ),
    )

    for validation_pattern, marker, syntax in declarations:
        if re.search(validation_pattern, updated):
            continue
        if marker not in updated:
            raise SystemExit(f"Unable to locate {marker} in Android Gradle file.")
        updated = updated.replace(marker, f"{marker}\n        {syntax}", 1)

    gradle.write_text(updated, encoding="utf-8")


def patch_plugin_versions() -> None:
    settings = _first_existing(
        ANDROID / "settings.gradle.kts",
        ANDROID / "settings.gradle",
    )
    text = settings.read_text(encoding="utf-8")

    substitutions = (
        (
            r'(id\(["\']com\.android\.application["\']\)\s+version\s+)["\'][^"\']+["\']',
            rf'\g<1>"{ANDROID_GRADLE_PLUGIN}"',
        ),
        (
            r'(id\s+["\']com\.android\.application["\']\s+version\s+)["\'][^"\']+["\']',
            rf'\g<1>"{ANDROID_GRADLE_PLUGIN}"',
        ),
        (
            r'(id\(["\']org\.jetbrains\.kotlin\.android["\']\)\s+version\s+)["\'][^"\']+["\']',
            rf'\g<1>"{KOTLIN_PLUGIN}"',
        ),
        (
            r'(id\s+["\']org\.jetbrains\.kotlin\.android["\']\s+version\s+)["\'][^"\']+["\']',
            rf'\g<1>"{KOTLIN_PLUGIN}"',
        ),
    )

    updated = text
    for pattern, replacement in substitutions:
        updated = re.sub(pattern, replacement, updated)

    agp_found = re.search(
        rf'com\.android\.application["\']?\)?\s+version\s+["\']{re.escape(ANDROID_GRADLE_PLUGIN)}["\']',
        updated,
    )
    kotlin_found = re.search(
        rf'org\.jetbrains\.kotlin\.android["\']?\)?\s+version\s+["\']{re.escape(KOTLIN_PLUGIN)}["\']',
        updated,
    )
    if agp_found is None or kotlin_found is None:
        raise SystemExit(
            "Unable to pin Android/Kotlin plugin versions in generated settings file."
        )

    settings.write_text(updated, encoding="utf-8")


def patch_gradle_wrapper() -> None:
    wrapper = _first_existing(
        ANDROID / "gradle" / "wrapper" / "gradle-wrapper.properties"
    )
    text = wrapper.read_text(encoding="utf-8")
    updated, count = re.subn(
        r"gradle-[0-9][0-9.]*-(?:all|bin)\.zip",
        f"gradle-{GRADLE_VERSION}-all.zip",
        text,
        count=1,
    )
    if count != 1:
        raise SystemExit("Unable to pin Gradle wrapper version.")
    wrapper.write_text(updated, encoding="utf-8")


def patch_manifest() -> None:
    manifest = _first_existing(
        ANDROID / "app" / "src" / "main" / "AndroidManifest.xml"
    )
    text = manifest.read_text(encoding="utf-8")
    permission = '<uses-permission android:name="android.permission.INTERNET" />'
    if permission not in text:
        match = re.search(r"<manifest\b[^>]*>", text)
        if match is None:
            raise SystemExit("Unable to locate <manifest> element.")
        close = match.end()
        text = text[:close] + f"\n    {permission}" + text[close:]

    text, count = re.subn(
        r'android:label="[^"]*"',
        f'android:label="{APP_LABEL}"',
        text,
        count=1,
    )
    if count != 1:
        raise SystemExit("Unable to set Android application label.")
    manifest.write_text(text, encoding="utf-8")


def main() -> None:
    if not ANDROID.exists():
        raise SystemExit("Run `flutter create --platforms=android .` first.")

    patch_app_gradle()
    patch_plugin_versions()
    patch_gradle_wrapper()
    patch_manifest()
    print(
        "Android configured: "
        f"compileSdk={COMPILE_SDK}, targetSdk={TARGET_SDK}, minSdk={MIN_SDK}, "
        f"AGP={ANDROID_GRADLE_PLUGIN}, "
        f"Kotlin={KOTLIN_PLUGIN}, Gradle={GRADLE_VERSION}."
    )


if __name__ == "__main__":
    main()
