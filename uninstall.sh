#!/system/bin/sh
## Kali NetHunter for KernelSU — uninstall hook
##
## KernelSU runs this AT BOOT, before system_server is up — so `pm`,
## `settings`, `setenforce` are not yet available. We can only do
## filesystem-level cleanup here. App uninstalls + setting restores are
## handled by service.sh once system_server is alive (see common/service.sh).

NHSYS=/data/local/nhsystem
PRECHROOT=$(find "$NHSYS" -maxdepth 1 -type d -name "kali-*" 2>/dev/null | head -n 1)

f_umount_fs() {
    if mountpoint -q "$PRECHROOT/$1" 2>/dev/null; then
        umount -f "$PRECHROOT/$1" 2>/dev/null \
            || umount -l "$PRECHROOT/$1" 2>/dev/null
    fi
    [ -d "$PRECHROOT/$1" ] && rm -rf "$PRECHROOT/$1"
}

do_umount() {
    for i in dev/pts dev/shm dev proc sys system; do
        f_umount_fs "$i"
    done
    if mountpoint -q "$PRECHROOT/sdcard" 2>/dev/null; then
        umount -l "$PRECHROOT/sdcard" 2>/dev/null
    fi
    rm -rf "$PRECHROOT/sdcard" 2>/dev/null
    if mountpoint -q "$PRECHROOT" 2>/dev/null; then
        umount -f "$PRECHROOT" 2>/dev/null || umount -l "$PRECHROOT" 2>/dev/null
    fi
}

# Tear down chroot mounts and remove the rootfs tree
if [ -d "$PRECHROOT" ]; then
    do_umount
fi
[ -d "$NHSYS" ] && rm -rf "$NHSYS"

# Leave a breadcrumb for service.sh — it'll uninstall the apks once Android
# framework is up, on the *next* boot (this script's own module dir is
# already being removed by KSU, so we drop the flag in /data/local).
mkdir -p /data/local/tmp
: > /data/local/tmp/.nethunter-uninstall-pending

exit 0
