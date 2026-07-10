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
    path="$PRECHROOT/$1"
    mountpoint -q "$path" 2>/dev/null || return 0
    umount -f "$path" 2>/dev/null || umount -l "$path" 2>/dev/null || return 1
    mountpoint -q "$path" 2>/dev/null && return 1
    return 0
}

has_chroot_mounts() {
    awk -v root="$PRECHROOT" '$5 == root || index($5, root "/") == 1 { found=1 } END { exit !found }' \
        /proc/self/mountinfo 2>/dev/null
}

do_umount() {
    result=0
    for i in dev/pts dev/shm dev proc sys system; do
        f_umount_fs "$i" || result=1
    done
    f_umount_fs sdcard || result=1
    if mountpoint -q "$PRECHROOT" 2>/dev/null; then
        umount -f "$PRECHROOT" 2>/dev/null || umount -l "$PRECHROOT" 2>/dev/null || result=1
    fi
    has_chroot_mounts && result=1
    return "$result"
}

# Tear down chroot mounts and remove the rootfs tree
if [ -d "$PRECHROOT" ]; then
    if ! do_umount; then
        echo "NetHunter uninstall: chroot mounts remain; preserving $NHSYS" >&2
        exit 1
    fi
fi
case "$NHSYS" in
    /data/local/nhsystem) [ -d "$NHSYS" ] && rm -rf -- "$NHSYS" ;;
    *) echo "NetHunter uninstall: refusing unsafe path: $NHSYS" >&2; exit 1 ;;
esac

# Leave a breadcrumb for service.sh — it'll uninstall the apks once Android
# framework is up, on the *next* boot (this script's own module dir is
# already being removed by KSU, so we drop the flag in /data/local).
mkdir -p /data/local/tmp
: > /data/local/tmp/.nethunter-uninstall-pending

exit 0
