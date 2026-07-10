#!/system/bin/sh
## Kali NetHunter for KernelSU — late_start service hook
##
## Runs after system_server is up to grant supported runtime permissions if
## NetHunter.apk is installed or updated later.

MODDIR=${0%/*}
BIN="$MODDIR/system/bin"

# ---- Wait until pm is actually usable ----------------------------------
i=0
while [ $i -lt 60 ]; do
    pm path android >/dev/null 2>&1 && break
    sleep 2
    i=$((i + 1))
done

# The app creates these assets on first launch, after module installation.
SCRIPTS=/data/data/com.offsec.nethunter/assets/scripts
if [ -d "$SCRIPTS" ]; then
    mkdir -p "$BIN"
    for script in bootkali bootkali_init bootkali_login bootkali_bash killkali; do
        [ -f "$SCRIPTS/$script" ] && ln -sf "$SCRIPTS/$script" "$BIN/$script"
    done
fi

# ---- Auto-grant on subsequent boots if main app got installed later ----
if pm list packages 2>/dev/null | grep -q '^package:com.offsec.nethunter$'; then
    GRANTED_FLAG=$MODDIR/.permissions-granted
    if [ ! -f "$GRANTED_FLAG" ]; then
        grants_ok=true
        for x in ACCESS_COARSE_LOCATION \
                 ACCESS_FINE_LOCATION \
                 READ_EXTERNAL_STORAGE \
                 WRITE_EXTERNAL_STORAGE; do
            pm grant --user 0 com.offsec.nethunter "android.permission.$x" >/dev/null 2>&1 \
                || grants_ok=false
        done
        API=$(getprop ro.build.version.sdk)
        if [ "$API" -ge 29 ] 2>/dev/null; then
            pm grant --user 0 com.offsec.nethunter \
                android.permission.ACCESS_BACKGROUND_LOCATION >/dev/null 2>&1 \
                || grants_ok=false
        fi
        $grants_ok && : > "$GRANTED_FLAG"
    fi
fi
