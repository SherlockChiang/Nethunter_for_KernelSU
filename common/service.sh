#!/system/bin/sh
## Kali NetHunter for KernelSU — late_start service hook
##
## Runs after system_server is up (so `pm` / `settings` work). Used to:
##   1. Honour an uninstall left pending by uninstall.sh — uninstall.sh runs
##      pre-Android-framework so it cannot call `pm`, it just leaves a flag
##      at /data/local/tmp/.nethunter-uninstall-pending and we finish the job
##      here on the next boot.
##   2. (Optionally) auto-grant runtime permissions if NetHunter.apk has
##      since been installed via NetHunter Store.

MODDIR=${0%/*}

PENDING=/data/local/tmp/.nethunter-uninstall-pending

# ---- Wait until pm is actually usable ----------------------------------
i=0
while [ $i -lt 60 ]; do
    pm path android >/dev/null 2>&1 && break
    sleep 2
    i=$((i + 1))
done

# ---- Pending uninstall: drop all NetHunter packages --------------------
if [ -f "$PENDING" ]; then
    for app in com.offsec.nethunter \
               com.offsec.nethunter.kex \
               com.offsec.nhterm \
               com.offsec.nethunter.store \
               com.offsec.nethunter.store.privileged; do
        pm uninstall "$app" >/dev/null 2>&1
    done
    settings put global verifier_verify_adb_installs 1 2>/dev/null
    rm -f "$PENDING"
    exit 0
fi

# ---- Auto-grant on subsequent boots if main app got installed later ----
if pm list packages 2>/dev/null | grep -q '^package:com.offsec.nethunter$'; then
    GRANTED_FLAG=$MODDIR/.permissions-granted
    if [ ! -f "$GRANTED_FLAG" ]; then
        for x in ACCESS_BACKGROUND_LOCATION \
                 ACCESS_COARSE_LOCATION \
                 ACCESS_FINE_LOCATION \
                 READ_EXTERNAL_STORAGE \
                 WRITE_EXTERNAL_STORAGE \
                 WRITE_SECURE_SETTINGS \
                 RECEIVE_BOOT_COMPLETED \
                 WAKE_LOCK \
                 VIBRATE \
                 FOREGROUND_SERVICE; do
            pm grant -g com.offsec.nethunter "android.permission.$x" >/dev/null 2>&1
        done
        for x in RUN_SCRIPT RUN_SCRIPT_SU RUN_SCRIPT_NH RUN_SCRIPT_NH_LOGIN; do
            pm grant -g com.offsec.nethunter "com.offsec.nhterm.permission.$x" >/dev/null 2>&1
        done
        : > "$GRANTED_FLAG"
    fi
fi
