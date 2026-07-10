#!/usr/bin/env bash
set -euo pipefail

repo=$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)
cd "$repo"

scripts=(
    action.sh
    customize.sh
    uninstall.sh
    common/post-fs-data.sh
    common/service.sh
    META-INF/com/google/android/update-binary
)

for script in "${scripts[@]}"; do
    bash -n "$script"
done

grep -qx 'SKIPUNZIP=1' customize.sh
grep -q '\[ "$KSU" = true \]' customize.sh

for member in customize.sh action.sh artifacts.sha256 module.prop uninstall.sh; do
    grep -q "'$member'" build.ps1
done
if grep -qE "^[[:space:]]*'install\.sh',[[:space:]]*$" build.ps1; then
    echo "Build manifest contains obsolete install.sh" >&2
    exit 1
fi

if grep -n -E 'magisk/util_functions|pm grant -g|setenforce 0|verifier_verify_adb_installs' \
    customize.sh uninstall.sh common/post-fs-data.sh common/service.sh \
    META-INF/com/google/android/update-binary; then
    echo "Unsafe legacy installer pattern found" >&2
    exit 1
fi

if grep -q -E -- '--list|ln -sf busybox_nh' common/post-fs-data.sh; then
    echo "BusyBox applet overlay regression found" >&2
    exit 1
fi

sha256sum --check --ignore-missing artifacts.sha256

echo "Static checks passed"
