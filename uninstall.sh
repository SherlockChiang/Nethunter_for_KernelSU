#!/system/bin/sh
## Kali NetHunter for KernelSU — uninstall hook
##
## KernelSU runs this before Android's package manager is available, so this
## hook performs filesystem cleanup only. Run the module action in KernelSU
## Manager before removal if the bundled apps should also be uninstalled.

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

# Tear down the module-owned chroot only. Keep unrelated files under
# /data/local/nhsystem if the directory is shared by another component.
if [ -d "$PRECHROOT" ]; then
    if ! do_umount; then
        echo "NetHunter uninstall: chroot mounts remain; preserving $NHSYS" >&2
        exit 1
    fi
    rm -rf -- "$PRECHROOT"
fi
case "$NHSYS" in
    /data/local/nhsystem)
        if [ -L "$NHSYS/kalifs" ]; then
            rm -f -- "$NHSYS/kalifs"
        fi
        rmdir "$NHSYS" 2>/dev/null || true
        ;;
    *) echo "NetHunter uninstall: refusing unsafe path: $NHSYS" >&2; exit 1 ;;
esac

exit 0
