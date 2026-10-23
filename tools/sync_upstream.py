#!/usr/bin/env python3
"""Fetch and verify the external NetHunter payloads used by this module.

The official NetHunter App Store index supplies the current APK filenames,
versions, and SHA-256 digests. The published rootfs SHA256SUMS file is the
source of truth for the Kali rootfs. The upstream installer tag is locked
separately so this script never replaces the KernelSU installer scripts; it
only updates payloads, the checksum manifest, and the source lock file.
"""

from __future__ import annotations

import argparse
import hashlib
import json
import re
import sys
import tempfile
import urllib.error
import urllib.parse
import urllib.request
from pathlib import Path


PROJECT_ID = 62423113
PROJECT_API = f"https://gitlab.com/api/v4/projects/{PROJECT_ID}"
RAW_BASE = (
    "https://gitlab.com/kalilinux/nethunter/build-scripts/"
    "kali-nethunter-installer/-/raw"
)
ROOTFS_BASE = "https://kali.download/nethunter-images/current/rootfs"
APP_INDEX_URL = "https://store.nethunter.com/repo/index-v1.json"
USER_AGENT = "Nethunter-for-KernelSU-updater/1.0"

APP_FILES = {
    "NetHunter": "data/app/NetHunter.apk",
    "NetHunterTerminal": "data/app/NetHunterTerminal.apk",
    "NetHunterKeX": "data/app/NetHunterKeX.apk",
    "NetHunterStore": "data/app/NetHunterStore.apk",
    "NetHunterStorePrivilegedExtension": "data/app/NetHunterStorePrivilegedExtension.apk",
}
APP_PACKAGES = {
    "NetHunter": "com.offsec.nethunter",
    "NetHunterTerminal": "com.offsec.nhterm",
    "NetHunterKeX": "com.offsec.nethunter.kex",
    "NetHunterStore": "com.offsec.nethunter.store",
    "NetHunterStorePrivilegedExtension": "com.offsec.nethunter.store.privileged",
}
ROOTFS_NAME = "kali-nethunter-rootfs-minimal-arm64.tar.xz"


class SyncError(RuntimeError):
    """An expected, user-actionable synchronization failure."""


def request_bytes(url: str, timeout: int = 60) -> bytes:
    request = urllib.request.Request(url, headers={"User-Agent": USER_AGENT})
    try:
        with urllib.request.urlopen(request, timeout=timeout) as response:
            return response.read()
    except (urllib.error.URLError, TimeoutError) as exc:
        raise SyncError(f"download failed: {url}: {exc}") from exc


def request_json(url: str) -> object:
    try:
        return json.loads(request_bytes(url).decode("utf-8"))
    except json.JSONDecodeError as exc:
        raise SyncError(f"invalid JSON from {url}: {exc}") from exc


def latest_release_tag() -> str:
    data = request_json(f"{PROJECT_API}/repository/tags?per_page=100")
    if not isinstance(data, list):
        raise SyncError("GitLab tags response is not a list")
    tags = []
    for item in data:
        name = item.get("name") if isinstance(item, dict) else None
        if isinstance(name, str) and re.fullmatch(r"\d{4}\.\d+", name):
            year, release = name.split(".")
            tags.append((int(year), int(release), name))
    if not tags:
        raise SyncError("no stable YYYY.N NetHunter tag was found")
    return max(tags)[2]


def tag_commit(ref: str) -> str:
    encoded = urllib.parse.quote(ref, safe="")
    data = request_json(f"{PROJECT_API}/repository/tags/{encoded}")
    if not isinstance(data, dict):
        raise SyncError(f"GitLab tag response for {ref} is not an object")
    commit = data.get("commit")
    sha = commit.get("id") if isinstance(commit, dict) else None
    if not isinstance(sha, str) or not re.fullmatch(r"[0-9a-f]{40}", sha):
        raise SyncError(f"could not resolve commit for upstream tag {ref}")
    return sha


def parse_app_sources(index_text: str) -> dict[str, dict[str, str]]:
    try:
        index = json.loads(index_text)
        packages = index["packages"]
    except (KeyError, TypeError, json.JSONDecodeError) as exc:
        raise SyncError(f"invalid NetHunter App Store index: {exc}") from exc

    result: dict[str, dict[str, str]] = {}
    for name, package_name in APP_PACKAGES.items():
        versions = packages.get(package_name)
        if not isinstance(versions, list) or not versions:
            raise SyncError(f"App Store index has no versions for {package_name}")
        candidates = [item for item in versions if isinstance(item, dict)]
        if not candidates:
            raise SyncError(f"App Store index has invalid versions for {package_name}")
        selected = max(candidates, key=lambda item: int(item.get("versionCode", 0)))
        apk_name = selected.get("apkName")
        sha256 = selected.get("hash")
        if not isinstance(apk_name, str) or not re.fullmatch(r"[A-Za-z0-9._+-]+\.apk", apk_name):
            raise SyncError(f"App Store index has an invalid APK name for {package_name}")
        if selected.get("hashType") != "sha256" or not isinstance(sha256, str) or not re.fullmatch(r"[0-9a-f]{64}", sha256):
            raise SyncError(f"App Store index has no SHA-256 for {package_name}")
        url = f"https://store.nethunter.com/repo/{apk_name}"
        result[name] = {
            "url": url,
            "sha256": sha256.lower(),
            "packageName": package_name,
            "versionName": str(selected.get("versionName", "")),
            "versionCode": str(selected.get("versionCode", "")),
        }
    missing = sorted(set(APP_FILES) - set(result))
    if missing:
        raise SyncError("official App Store index is missing app entries: " + ", ".join(missing))
    return result


def rootfs_source() -> dict[str, str]:
    sums_url = f"{ROOTFS_BASE}/SHA256SUMS"
    sums = request_bytes(sums_url).decode("utf-8", errors="replace")
    expected = None
    for line in sums.splitlines():
        fields = line.split()
        if len(fields) >= 2 and fields[1].lstrip("*") == ROOTFS_NAME:
            expected = fields[0].lower()
            break
    if not expected or not re.fullmatch(r"[0-9a-f]{64}", expected):
        raise SyncError(f"{ROOTFS_NAME} is not listed in {sums_url}")
    return {
        "url": f"{ROOTFS_BASE}/{ROOTFS_NAME}",
        "sha256": expected,
        "sums_url": sums_url,
    }


def digest_file(path: Path, algorithm: str) -> str:
    digest = hashlib.new(algorithm)
    with path.open("rb") as stream:
        for chunk in iter(lambda: stream.read(1024 * 1024), b""):
            digest.update(chunk)
    return digest.hexdigest()


def download_verified(url: str, target: Path, algorithm: str, expected: str) -> str:
    target.parent.mkdir(parents=True, exist_ok=True)
    if target.is_file() and digest_file(target, algorithm) == expected:
        return digest_file(target, "sha256")

    request = urllib.request.Request(url, headers={"User-Agent": USER_AGENT})
    digest = hashlib.new(algorithm)
    temporary = None
    try:
        with tempfile.NamedTemporaryFile(
            mode="wb", prefix=f".{target.name}.", suffix=".part", dir=target.parent, delete=False
        ) as stream:
            temporary = Path(stream.name)
            try:
                with urllib.request.urlopen(request, timeout=120) as response:
                    while True:
                        chunk = response.read(1024 * 1024)
                        if not chunk:
                            break
                        stream.write(chunk)
                        digest.update(chunk)
            except (urllib.error.URLError, TimeoutError) as exc:
                raise SyncError(f"download failed: {url}: {exc}") from exc
        actual = digest.hexdigest()
        if actual != expected:
            raise SyncError(
                f"checksum mismatch for {url}: expected {expected}, got {actual}"
            )
        temporary.replace(target)
    finally:
        if temporary is not None:
            temporary.unlink(missing_ok=True)
    return digest_file(target, "sha256")


def update_manifest(repo: Path, hashes: dict[str, str]) -> None:
    manifest = repo / "artifacts.sha256"
    existing = manifest.read_text(encoding="utf-8").splitlines()
    replaced = set()
    output = []
    for line in existing:
        fields = line.split("  ", 1)
        path = fields[1] if len(fields) == 2 else None
        if path in hashes:
            output.append(f"{hashes[path]}  {path}")
            replaced.add(path)
        else:
            output.append(line)
    for path in hashes:
        if path not in replaced:
            output.append(f"{hashes[path]}  {path}")
    manifest.write_text("\n".join(output) + "\n", encoding="utf-8")


def update_module_prop(repo: Path, ref: str) -> None:
    year, release = ref.split(".")
    version_code = f"{year}{int(release):02d}00"
    path = repo / "module.prop"
    lines = path.read_text(encoding="utf-8").splitlines()
    lines = [f"version={ref}" if line.startswith("version=") else line for line in lines]
    lines = [
        f"versionCode={version_code}" if line.startswith("versionCode=") else line
        for line in lines
    ]
    path.write_text("\n".join(lines) + "\n", encoding="utf-8")


def write_lock(repo: Path, ref: str, commit: str, apps: dict, rootfs: dict) -> None:
    lock = {
        "upstream": {
            "project": "kalilinux/nethunter/build-scripts/kali-nethunter-installer",
            "ref": ref,
            "commit": commit,
        },
        "apps": {
            name: {"path": APP_FILES[name], **apps[name]} for name in APP_FILES
        },
        "rootfs": {"path": ROOTFS_NAME, **rootfs},
    }
    (repo / "sources.lock.json").write_text(
        json.dumps(lock, indent=2, sort_keys=False) + "\n", encoding="utf-8"
    )


def read_lock(repo: Path) -> tuple[str, str, dict[str, dict[str, str]], dict[str, str]]:
    try:
        lock = json.loads((repo / "sources.lock.json").read_text(encoding="utf-8"))
        ref = lock["upstream"]["ref"]
        commit = lock["upstream"]["commit"]
        apps = lock["apps"]
        rootfs = lock["rootfs"]
    except (OSError, KeyError, TypeError, json.JSONDecodeError) as exc:
        raise SyncError(f"invalid sources.lock.json: {exc}") from exc
    if not re.fullmatch(r"\d{4}\.\d+", ref) or not re.fullmatch(r"[0-9a-f]{40}", commit):
        raise SyncError("sources.lock.json has an invalid upstream ref or commit")
    if set(apps) != set(APP_FILES):
        raise SyncError("sources.lock.json has an unexpected app set")
    for name, path in APP_FILES.items():
        source = apps[name]
        if source.get("path") != path or not re.fullmatch(r"[0-9a-f]{64}", source.get("sha256", "")):
            raise SyncError(f"invalid locked source for {name}")
    if rootfs.get("path") != ROOTFS_NAME or not re.fullmatch(r"[0-9a-f]{64}", rootfs.get("sha256", "")):
        raise SyncError("invalid locked rootfs source")
    return ref, commit, apps, rootfs


def parse_args() -> argparse.Namespace:
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("--repo", type=Path, default=Path(__file__).resolve().parents[1])
    parser.add_argument("--ref", default="latest", help="stable upstream tag (YYYY.N), or latest")
    parser.add_argument(
        "--locked",
        action="store_true",
        help="download exactly the sources.lock.json payloads",
    )
    parser.add_argument(
        "--resolve-only",
        action="store_true",
        help="write sources.lock.json without downloading payloads",
    )
    return parser.parse_args()


def main() -> int:
    args = parse_args()
    repo = args.repo.resolve()
    if args.locked:
        ref, commit, apps, rootfs = read_lock(repo)
        if tag_commit(ref) != commit:
            raise SyncError(f"locked commit for {ref} no longer matches GitLab")
    else:
        ref = latest_release_tag() if args.ref == "latest" else args.ref
        if not re.fullmatch(r"\d{4}\.\d+", ref):
            raise SyncError(f"unsupported upstream ref: {ref}")
        commit = tag_commit(ref)
        apps = parse_app_sources(request_bytes(APP_INDEX_URL).decode("utf-8", errors="replace"))
        rootfs = rootfs_source()

    if args.resolve_only and args.locked:
        raise SyncError("--resolve-only and --locked cannot be combined")
    if args.resolve_only:
        write_lock(repo, ref, commit, apps, rootfs)
        print(f"Resolved NetHunter {ref} ({commit})")
        return 0

    hashes: dict[str, str] = {}
    for name, path in APP_FILES.items():
        local = repo / path
        hashes[path] = download_verified(apps[name]["url"], local, "sha256", apps[name]["sha256"])
        apps[name]["sha256"] = hashes[path]
        print(f"Updated {path}")

    rootfs_path = repo / ROOTFS_NAME
    hashes[ROOTFS_NAME] = download_verified(
        rootfs["url"], rootfs_path, "sha256", rootfs["sha256"]
    )
    rootfs["sha256"] = hashes[ROOTFS_NAME]
    print(f"Updated {ROOTFS_NAME}")

    update_manifest(repo, hashes)
    update_module_prop(repo, ref)
    write_lock(repo, ref, commit, apps, rootfs)
    print(f"Synchronized NetHunter {ref} ({commit})")
    return 0


if __name__ == "__main__":
    try:
        raise SystemExit(main())
    except SyncError as exc:
        print(f"sync-upstream: {exc}", file=sys.stderr)
        raise SystemExit(1)
