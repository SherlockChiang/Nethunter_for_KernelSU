#!/system/bin/sh

# Run from KernelSU Manager before removing the module to clean up its apps.
if ! pm path android >/dev/null 2>&1; then
    echo "Android package manager is not ready" >&2
    exit 1
fi

result=0
for app in com.offsec.nethunter \
           com.offsec.nethunter.kex \
           com.offsec.nhterm \
           com.offsec.nethunter.store \
           com.offsec.nethunter.store.privileged; do
    if pm path "$app" >/dev/null 2>&1; then
        echo "Uninstalling $app"
        pm uninstall --user 0 "$app" >/dev/null 2>&1 || result=1
    fi
done

if [ "$result" -ne 0 ]; then
    echo "One or more NetHunter apps could not be removed" >&2
    exit 1
fi

echo "NetHunter apps removed"
