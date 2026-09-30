#!/usr/bin/env python3
"""Build and verify this project's universal macOS release; never push or publish."""
import argparse
import hashlib
import json
import plistlib
import re
import shutil
import subprocess
import sys
import tempfile
import zipfile
from pathlib import Path


def run(args, root, capture=False):
    print("+ " + " ".join(map(str, args)), file=sys.stderr, flush=True)
    result = subprocess.run(list(map(str, args)), cwd=root, check=True, text=True,
                            stdout=subprocess.PIPE if capture else sys.stderr)
    return result.stdout.strip() if capture else None


def verify_app(app, version, build_number, root):
    info = plistlib.loads((app / "Contents/Info.plist").read_bytes())
    if (info["CFBundleShortVersionString"], info["CFBundleVersion"]) != (version, build_number):
        raise ValueError("Packaged version/build does not match source")
    binary = app / "Contents/MacOS/mac-token-plan"
    architectures = set(run(["lipo", "-archs", binary], root, capture=True).split())
    if architectures != {"arm64", "x86_64"}:
        raise ValueError(f"Expected arm64 + x86_64, got {architectures}")
    resource_bundle = app / "Contents/Resources/mac-token-plan_mac-token-plan.bundle"
    required_resources = ["codex-mark.svg", "deepseek-mark.svg"]
    for resource in required_resources:
        if not (resource_bundle / "Contents/Resources" / resource).is_file():
            raise ValueError(f"Missing packaged Swift resource: {resource}")
    run(["codesign", "--verify", "--deep", "--strict", app], root)


def main():
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("--version", required=True, help="Release version, e.g. 1.3.1")
    args = parser.parse_args()
    if not re.fullmatch(r"(0|[1-9][0-9]*)\.(0|[1-9][0-9]*)\.(0|[1-9][0-9]*)", args.version):
        parser.error("Version must be major.minor.patch without the v prefix")
    root = Path(__file__).resolve().parents[1]
    actual_root = Path(run(["git", "rev-parse", "--show-toplevel"], root, capture=True)).resolve()
    if actual_root != root or not (root / "Package.swift").is_file():
        raise ValueError("Run this skill inside the mac-token-plan repository")
    info_path = root / "Resources/Info.plist"
    info = plistlib.loads(info_path.read_bytes())
    if info.get("CFBundleIdentifier") != "com.zgkc.mac-token-plan":
        raise ValueError("Unexpected application identity")
    if info.get("CFBundleShortVersionString") != args.version:
        raise ValueError("Update Resources/Info.plist to the requested version before building")
    build_number = info["CFBundleVersion"]
    if not str(build_number).isdigit():
        raise ValueError("CFBundleVersion must be an integer")
    if f"## [{args.version}]" not in (root / "CHANGELOG.md").read_text():
        raise ValueError("Add the target version to CHANGELOG.md before building")
    for tool in ["swift", "lipo", "codesign", "ditto"]:
        if not shutil.which(tool):
            raise ValueError(f"Required tool is unavailable: {tool}")
    run(["git", "diff", "--check"], root)
    run(["swift", "test"], root)
    binaries = []
    resource_bundles = []
    for architecture in ["arm64", "x86_64"]:
        options = ["swift", "build", "-c", "release", "--arch", architecture,
                   "--scratch-path", root / ".build/release-build" / architecture]
        run(options, root)
        binary_dir = Path(run(options + ["--show-bin-path"], root, capture=True))
        binaries.append(binary_dir / "mac-token-plan")
        resource_bundles.append(binary_dir / "mac-token-plan_mac-token-plan.bundle")

    parent = root / ".build/releases" / f"v{args.version}"
    parent.mkdir(parents=True, exist_ok=True)
    # Never overwrite old artifacts or modify the currently running local application.
    output = Path(tempfile.mkdtemp(prefix="build-", dir=parent))
    app = output / "mac-token-plan.app"
    (app / "Contents/MacOS").mkdir(parents=True)
    (app / "Contents/Resources").mkdir()
    run(["lipo", "-create", *binaries, "-output", app / "Contents/MacOS/mac-token-plan"], root)
    shutil.copy2(info_path, app / "Contents/Info.plist")
    shutil.copy2(root / "Resources/AppIcon.icns", app / "Contents/Resources/AppIcon.icns")
    for bundle in resource_bundles:
        if not bundle.is_dir():
            raise ValueError(f"Swift resource bundle not found: {bundle}")
    shutil.copytree(resource_bundles[0], app / "Contents/Resources/mac-token-plan_mac-token-plan.bundle")
    run(["codesign", "--force", "--deep", "--sign", "-", app], root)
    verify_app(app, args.version, build_number, root)

    archive = output / f"mac-token-plan-v{args.version}.zip"
    run(["ditto", "-c", "-k", "--sequesterRsrc", "--keepParent", app, archive], root)
    with zipfile.ZipFile(archive) as package:
        if package.testzip() is not None:
            raise ValueError("Archive CRC verification failed")
        for name in package.namelist():
            path = Path(name)
            if path.is_absolute() or ".." in path.parts:
                raise ValueError("Unsafe archive path")
            if path.parts[0] not in {"mac-token-plan.app", "__MACOSX"}:
                raise ValueError(f"Unexpected archive content: {name}")
            if path.name in {".env", "auth.json", "usage-history.json"}:
                raise ValueError("Private application data found in archive")
    extracted = output / "verify"
    run(["ditto", "-x", "-k", archive, extracted], root)
    verify_app(extracted / "mac-token-plan.app", args.version, build_number, root)
    checksum = hashlib.sha256(archive.read_bytes()).hexdigest()
    checksum_path = archive.with_suffix(".zip.sha256")
    checksum_path.write_text(f"{checksum}  {archive.name}\n")
    result = {"version": args.version, "buildNumber": build_number, "architectures": ["arm64", "x86_64"],
              "archive": str(archive), "checksumFile": str(checksum_path), "sha256": checksum,
              "outputDirectory": str(output)}
    (output / "release-manifest.json").write_text(json.dumps(result, indent=2) + "\n")
    print(json.dumps(result, indent=2))


if __name__ == "__main__":
    try:
        main()
    except (ValueError, OSError, subprocess.CalledProcessError) as error:
        print(f"Release build failed: {error}", file=sys.stderr)
        sys.exit(1)
