#!/bin/bash
## Kali NetHunter for KernelSU — installer
##
## Sourced by META-INF/com/google/android/update-binary (KernelSU module flow).
## Adapted from the official Kali NetHunter 2026.1 generic-arm64-full installer
## (META-INF/com/google/android/update-magisk + tools/install-chroot.sh).
##
## Differences vs. the Magisk-targeted upstream:
##   * No magisk util_functions.sh dependency at the chroot stage — KernelSU
##     already exports MODPATH/MNT/NVBASE/MODID via update-binary, and busybox
##     is provided by /data/adb/ksu/bin/busybox (handled by post-fs-data.sh).
##   * No on-the-fly kernel flash (boot-patcher / magic-flash.sh): a KSU module
##     cannot patch boot.img — users wanting kernel-side NetHunter features must
##     flash a NetHunter-patched kernel separately.
##   * Firmware blobs ship inside the module's system/etc/firmware/ tree so that
##     KernelSU's overlay layers them onto /system/etc/firmware/ at boot — this
##     is what makes external USB Wi-Fi adapters & HID gadgets work on stock
##     Xiaomi 15 kernels (see README).

SKIPMOUNT=false
PROPFILE=false
POSTFSDATA=true
LATESTARTSERVICE=true

#-----------------------------------------------------------------------------
# Variables — most are exported by update-binary; we just fall back safely.
#-----------------------------------------------------------------------------
[ -z "$TMPDIR" ] && TMPDIR=/dev/tmp
[ -n "$ZIP" ] && { ZIPFILE="$ZIP"; unset ZIP; }
[ -z "$ZIPFILE" ] && ZIPFILE="$3"
DIR=$(dirname "$ZIPFILE")

# update-binary already set MODID before sourcing us. Keep a local fallback.
file_getprop() { grep "^$2" "$1" | head -n1 | cut -d= -f2-; }
[ -z "$MODID" ] && MODID=$(file_getprop "$TMPDIR/module.prop" id)
TMP="$TMPDIR/$MODID"

# Modules root paths (KernelSU uses the same /data/adb layout as Magisk).
[ -z "$NVBASE" ] && NVBASE=/data/adb
[ -z "$MODPATH" ] && MODPATH="$NVBASE/modules_update/$MODID"
MNT="$NVBASE/modules_update"

# Targets inside the module — overlayed onto /system at boot by KernelSU.
TARGET="$MODPATH/system"
ETC="$TARGET/etc"
BIN="$TARGET/bin"
if [ -d /system/xbin ]; then
    XBIN="$TARGET/xbin"
else
    XBIN="$TARGET/bin"
fi
if [ -d /system/media ]; then
    MEDIA="$TARGET/media"
elif [ -d /system/product/media ]; then
    MEDIA="$TARGET/product/media"
fi

#-----------------------------------------------------------------------------
# Helpers
#-----------------------------------------------------------------------------
set_perm() {
    chown "$2:$3" "$1" || return 1
    chmod "$4" "$1" || return 1
    CON=$5
    [ -z "$CON" ] && CON=u:object_r:system_file:s0
    chcon "$CON" "$1" || return 1
}

set_perm_recursive() {
    find "$1" -type d 2>/dev/null | while read -r dir; do
        set_perm "$dir" "$2" "$3" "$4" "$6"
    done
    find "$1" -type f -o -type l 2>/dev/null | while read -r file; do
        set_perm "$file" "$2" "$3" "$5" "$6"
    done
}

symlink() {
    ln -sf "$1" "$2" 2>/dev/null
    chmod 755 "$2" 2>/dev/null
}

#-----------------------------------------------------------------------------
# Chroot install (verbatim port of upstream tools/install-chroot.sh, minus the
# Magisk-only do_umount path — on a booted KSU system we always have shell, so
# we use the same unmount logic but without the BB-via-Magisk indirection).
#-----------------------------------------------------------------------------
f_kill_pids() {
    local lsof_full=$(lsof | awk '{print $1}' | grep -c '^lsof')
    if [ "$lsof_full" -eq 0 ]; then
        local pids=$(lsof | grep "$PRECHROOT" | awk '{print $1}' | uniq)
    else
        local pids=$(lsof | grep "$PRECHROOT" | awk '{print $2}' | uniq)
    fi
    if [ -n "$pids" ]; then
        kill -9 $pids 2>/dev/null
    fi
    return 0
}

f_restore_setup() {
    sysctl -w kernel.shmmax=134217728 2>/dev/null
    rm -rf "$PRECHROOT"/tmp/.X11* "$PRECHROOT"/tmp/.X*-lock \
           "$PRECHROOT"/root/.vnc/*.pid "$PRECHROOT"/root/.vnc/*.log >/dev/null 2>&1
}

f_umount_fs() {
    isAllunmounted=0
    if mountpoint -q "$PRECHROOT/$1"; then
        if umount -f "$PRECHROOT/$1"; then
            if [ ! "$1" = "dev/pts" ] && [ ! "$1" = "dev/shm" ]; then
                rm -rf "$PRECHROOT/$1" || isAllunmounted=1
            fi
        else
            isAllunmounted=1
        fi
    elif [ -d "$PRECHROOT/$1" ]; then
        rm -rf "$PRECHROOT/$1" || isAllunmounted=1
    fi
}

f_dir_umount() {
    sync
    ui_print "  - Killing chroot pids"
    f_kill_pids
    f_restore_setup
    ui_print "  - Removing fs mounts"
    for i in "dev/pts" "dev/shm" dev proc sys system; do
        f_umount_fs "$i"
    done
    if mount | grep -q "$PRECHROOT/sdcard"; then
        umount -l "$PRECHROOT/sdcard" 2>/dev/null
        rm -rf "$PRECHROOT/sdcard" 2>/dev/null
    fi
}

f_is_mntpoint() {
    [ -d "$PRECHROOT" ] && mountpoint -q "$PRECHROOT" && return 0
    return 1
}

do_umount() {
    f_is_mntpoint && f_dir_umount
    if [ -z "$(grep "$PRECHROOT" /proc/mounts)" ]; then
        return 0
    fi
    return 1
}

verify_fs() {
    case "$FS_ARCH" in armhf|arm64|i386|amd64) ;; *) return 1 ;; esac
    case "$FS_SIZE" in full|minimal|nano) ;; *) return 1 ;; esac
    return 0
}

# do_install [optional zip containing kalifs-*]
do_install() {
    ui_print "  - Found Kali chroot to be installed: $KALIFS"
    mkdir -p "$NHSYS"

    CHROOT="$NHSYS/kali-$FS_ARCH"            # legacy name expected by NetHunter app
    ROOTFS="$NHSYS/kalifs"                   # symlink for hot-swap
    PRECHROOT=$(find /data/local/nhsystem -type d -name "kali-*" | head -n 1)

    [ -d "$PRECHROOT" ] && {
        ui_print "  - Previous chroot detected, removing"
        do_umount || {
            ui_print "  ! Could not unmount previous chroot — aborting"
            ui_print "  - Remove the old chroot manually via the NetHunter app"
            return 1
        }
        rm -rf "$PRECHROOT"
        rm -f "$ROOTFS"
    }

    ui_print "  - Extracting Kali rootfs (this may take 10-25 minutes)"
    if [ -n "$1" ]; then
        unzip -p "$1" "$KALIFS" | tar -xJf - -C "$NHSYS" --exclude "kali-$FS_ARCH/dev"
    else
        tar -xJf "$KALIFS" -C "$NHSYS" --exclude "kali-$FS_ARCH/dev"
    fi
    [ $? -eq 0 ] || {
        ui_print "  ! Kali $FS_ARCH $FS_SIZE chroot failed to extract"
        ui_print "  - Check free space on /data"
        return 1
    }

    # Some 2026.x rootfs tarballs unpack into a slightly different top-level dir;
    # rename it to the canonical kali-$FS_ARCH so the NetHunter app finds it.
    if [ ! -d "$NHSYS/kali-$FS_ARCH" ]; then
        EXTRACTED=$(find "$NHSYS" -mindepth 1 -maxdepth 1 -type d -name "kali-*" | head -n 1)
        [ -n "$EXTRACTED" ] && [ "$EXTRACTED" != "$CHROOT" ] && mv "$EXTRACTED" "$CHROOT"
    fi

    ln -sf "$CHROOT" "$ROOTFS"
    mkdir -p -m 0755 "$CHROOT/dev"
    ui_print "  - Kali $FS_ARCH $FS_SIZE chroot installed"

    # Drop the archive only if it was outside the zip (matches upstream)
    [ -z "$1" ] && rm -f "$KALIFS"
    return 0
}

do_chroot() {
    NHSYS=/data/local/nhsystem

    # 1) Inside the flashed zip
    if [ -e "$ZIPFILE" ]; then
        # Match both 2026.1 ("kalifs-full-arm64.tar.xz") and kali.download
        # ("kali-nethunter-rootfs-minimal-arm64.tar.xz") naming.
        KALIFS=$(unzip -lqq "$ZIPFILE" \
            | awk '$4 ~ /^(kalifs-|kali-nethunter-rootfs-).*\.tar\.xz$/ { print $4; exit }')
        if [ -n "$KALIFS" ]; then
            BASE=$(basename "$KALIFS" .tar.xz)
            case "$BASE" in
                kalifs-*)
                    # kalifs-<size>-<arch>
                    FS_SIZE=$(echo "$BASE" | awk -F- '{print $2}')
                    FS_ARCH=$(echo "$BASE" | awk -F- '{print $3}')
                    ;;
                kali-nethunter-rootfs-*)
                    # kali-nethunter-rootfs-<size>-<arch>
                    FS_SIZE=$(echo "$BASE" | awk -F- '{print $4}')
                    FS_ARCH=$(echo "$BASE" | awk -F- '{print $5}')
                    ;;
            esac
            verify_fs && do_install "$ZIPFILE" && return
        fi
    fi

    # 2) Fallback locations
    for fsdir in "$TMP" "/data/local" "/sdcard" "/external_sd"; do
        for KALIFS in "$fsdir"/kalifs-*-*.tar.xz "$fsdir"/kali-nethunter-rootfs-*-*.tar.xz; do
            [ -s "$KALIFS" ] || continue
            BASE=$(basename "$KALIFS" .tar.xz)
            case "$BASE" in
                kalifs-*)
                    FS_SIZE=$(echo "$BASE" | awk -F- '{print $2}')
                    FS_ARCH=$(echo "$BASE" | awk -F- '{print $3}')
                    ;;
                kali-nethunter-rootfs-*)
                    FS_SIZE=$(echo "$BASE" | awk -F- '{print $4}')
                    FS_ARCH=$(echo "$BASE" | awk -F- '{print $5}')
                    ;;
            esac
            verify_fs && do_install && return
        done
    done

    ui_print "  ! No Kali rootfs archive found — skipping chroot install"
}

#-----------------------------------------------------------------------------
# print_modname / on_install — called back from update-binary
#-----------------------------------------------------------------------------
print_modname() {
    ui_print "##################################################"
    ui_print "##                                              ##"
    ui_print "##  88      a8P         db        88        88  ##"
    ui_print "##  88    .88'         d88b       88        88  ##"
    ui_print "##  88   88'          d8''8b      88        88  ##"
    ui_print "##  88 d88           d8'  '8b     88        88  ##"
    ui_print "##  8888'88.        d8YaaaaY8b    88        88  ##"
    ui_print "##  88P   Y8b      d8''''''''8b   88        88  ##"
    ui_print "##  88     '88.   d8'        '8b  88        88  ##"
    ui_print "##  88       Y8b d8'          '8b 888888888 88  ##"
    ui_print "##                                              ##"
    ui_print "####  ######### NetHunter (KSU) #################"
    ui_print "##  Kali NetHunter for KernelSU — 2026.1 base   ##"
    ui_print "##################################################"
}

on_install() {
    UMASK=$(umask)
    umask 022

    # Stage the full zip contents (everything except the heavy rootfs) into $TMP
    rm -rf "$TMP"
    mkdir -p "$TMP"
    cd "$TMP" || abort "! Cannot cd to $TMP"
    ui_print "- Unpacking installer payload"
    unzip -qq "$ZIPFILE" -x "kalifs-*" "kali-nethunter-rootfs-*" >&2 \
        || ui_print "  ! Some files failed to extract"

    # Stage system overlay (firmware, xbin/hid-keyboard, etc.) into $MODPATH
    ui_print "- Copying system overlay into module"
    [ -d "$TMP/system" ]      && cp -a "$TMP/system"/. "$TARGET/"
    [ -d "$TMP/data" ]        && mkdir -p "$MODPATH/data" && cp -a "$TMP/data"/. "$MODPATH/data/"

    #-------------------------------------------------------------------------
    # SELinux + ADB install verifier — temporarily relax so `pm install` works
    #-------------------------------------------------------------------------
    if [ "$(getenforce 2>/dev/null)" = "Enforcing" ]; then
        ENFORCE=true
        setenforce 0
    else
        ENFORCE=false
    fi
    VERIFY=$(settings get global verifier_verify_adb_installs 2>/dev/null)
    settings put global verifier_verify_adb_installs 0 2>/dev/null

    #-------------------------------------------------------------------------
    # Remove legacy installs (apps + previous nhsystem)
    #-------------------------------------------------------------------------
    ui_print "- Removing previous NetHunter installation"
    pm uninstall com.offsec.nethunter        &>/dev/null
    pm uninstall com.offsec.nethunter.kex    &>/dev/null
    pm uninstall com.offsec.nhterm           &>/dev/null
    pm uninstall com.offsec.nethunter.store  &>/dev/null
    pm uninstall com.offsec.nethunter.store.privileged &>/dev/null

    #-------------------------------------------------------------------------
    # Install NetHunter apps
    #-------------------------------------------------------------------------
    ui_print "- Installing NetHunter apps"
    APKDIR="$TMP/data/app"
    for apk in NetHunter.apk NetHunterTerminal.apk NetHunterKeX.apk; do
        if [ -f "$APKDIR/$apk" ]; then
            ui_print "  - $apk"
            pm install "$APKDIR/$apk" &>/dev/null || ui_print "    ! $apk failed"
        fi
    done
    for apk in NetHunterStore.apk NetHunterStorePrivilegedExtension.apk; do
        if [ -f "$APKDIR/$apk" ]; then
            ui_print "  - $apk (granted)"
            pm install -g "$APKDIR/$apk" &>/dev/null || ui_print "    ! $apk failed"
        fi
    done

    #-------------------------------------------------------------------------
    # Grant runtime permissions to NetHunter — only if it's actually installed.
    # The 2026.1 generic-arm64-full package doesn't ship NetHunter.apk itself
    # (it expects users to grab it from NetHunter Store after first launch),
    # so this block is normally skipped on a clean install and re-runs after
    # the user updates from the Store.
    #-------------------------------------------------------------------------
    if pm list packages 2>/dev/null | grep -q '^package:com.offsec.nethunter$'; then
        ui_print "- Granting runtime permissions"
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
            pm grant -g com.offsec.nethunter "android.permission.$x" &>/dev/null
        done
        for x in RUN_SCRIPT RUN_SCRIPT_SU RUN_SCRIPT_NH RUN_SCRIPT_NH_LOGIN; do
            pm grant -g com.offsec.nethunter "com.offsec.nhterm.permission.$x" &>/dev/null
        done
    else
        ui_print "- NetHunter.apk not installed yet (expected on a clean install)"
        ui_print "  Open NetHunter Store, install/update NetHunter, then reboot."
    fi

    #-------------------------------------------------------------------------
    # bootkali symlinks (only available after first launch of NetHunter.apk)
    #-------------------------------------------------------------------------
    if [ -e /data/data/com.offsec.nethunter/assets/scripts/ ]; then
        ui_print "- Symlinking bootkali scripts"
        mkdir -p "$BIN"
        for s in bootkali bootkali_init bootkali_login bootkali_bash killkali; do
            symlink "/data/data/com.offsec.nethunter/assets/scripts/$s" "$BIN/$s"
        done
    fi

    #-------------------------------------------------------------------------
    # Install the chroot/rootfs
    #-------------------------------------------------------------------------
    ui_print "- Installing Kali chroot"
    do_chroot

    #-------------------------------------------------------------------------
    # Permissions on everything we dropped into the module
    #-------------------------------------------------------------------------
    ui_print "- Fixing permissions"
    set_perm_recursive "$TARGET" 0 0 0755 0644
    [ -d "$BIN" ]  && set_perm_recursive "$BIN"  0 0 0755 0755
    [ -d "$XBIN" ] && set_perm_recursive "$XBIN" 0 0 0755 0755

    #-------------------------------------------------------------------------
    # Restore SELinux + verifier
    #-------------------------------------------------------------------------
    [ -n "$VERIFY" ] && settings put global verifier_verify_adb_installs "$VERIFY" 2>/dev/null
    $ENFORCE && setenforce 1

    umask "$UMASK"

    ui_print " "
    ui_print "************************************************"
    ui_print "*       Kali NetHunter is now installed!       *"
    ui_print "*==============================================*"
    ui_print "*  REBOOT now, then in KernelSU Manager grant  *"
    ui_print "*  root access to the NetHunter app before     *"
    ui_print "*  launching it. All apps are pre-bundled and  *"
    ui_print "*  permissions are already granted.            *"
    ui_print "************************************************"
    ui_print " "
}
