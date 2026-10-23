#!/usr/bin/env python3
"""Validate the checked-in upstream source lock without network access."""

import json
import re
from pathlib import Path


ROOT = Path(__file__).resolve().parents[1]
LOCK = json.loads((ROOT / "sources.lock.json").read_text(encoding="utf-8"))

assert re.fullmatch(r"\d{4}\.\d+", LOCK["upstream"]["ref"])
assert re.fullmatch(r"[0-9a-f]{40}", LOCK["upstream"]["commit"])
assert LOCK["upstream"]["project"] == (
    "kalilinux/nethunter/build-scripts/kali-nethunter-installer"
)

expected_apps = {
    "NetHunter": "data/app/NetHunter.apk",
    "NetHunterTerminal": "data/app/NetHunterTerminal.apk",
    "NetHunterKeX": "data/app/NetHunterKeX.apk",
    "NetHunterStore": "data/app/NetHunterStore.apk",
    "NetHunterStorePrivilegedExtension": "data/app/NetHunterStorePrivilegedExtension.apk",
}
assert set(LOCK["apps"]) == set(expected_apps)
for name, path in expected_apps.items():
    source = LOCK["apps"][name]
    assert source["path"] == path
    assert source["url"].startswith("https://store.nethunter.com/repo/")
    assert re.fullmatch(r"[0-9a-f]{64}", source["sha256"])
    assert source["packageName"] in {
        "com.offsec.nethunter",
        "com.offsec.nhterm",
        "com.offsec.nethunter.kex",
        "com.offsec.nethunter.store",
        "com.offsec.nethunter.store.privileged",
    }

rootfs = LOCK["rootfs"]
assert rootfs["path"] == "kali-nethunter-rootfs-minimal-arm64.tar.xz"
assert rootfs["url"].startswith("https://kali.download/")
assert rootfs["sums_url"].endswith("/SHA256SUMS")
assert re.fullmatch(r"[0-9a-f]{64}", rootfs["sha256"])

print("Upstream source lock passed")
