#!/system/bin/sh
## Kali NetHunter for KernelSU - native installer
##
## Sourced by KernelSU's built-in module installer.
## Adapted from the official Kali NetHunter 2026.1 generic-arm64-full installer
## (META-INF/com/google/android/update-magisk + tools/install-chroot.sh).
##
## Differences vs. the Magisk-targeted upstream:
##   * Uses KernelSU's native customize.sh contract and installer helpers.
##   * No on-the-fly kernel flash (boot-patcher / magic-flash.sh): a KSU module
##     cannot patch boot.img — users wanting kernel-side NetHunter features must
##     flash a NetHunter-patched kernel separately.
##   * Firmware blobs ship inside the module's system/etc/firmware/ tree so that
##     KernelSU's overlay layers them onto /system/etc/firmware/ at boot — this
##     is what makes external USB Wi-Fi adapters & HID gadgets work on stock
##     Xiaomi 15 kernels (see README).

SKIPUNZIP=1

[ "$KSU" = true ] || abort "! Install this module with KernelSU Manager"
[ "$ARCH" = arm64 ] || abort "! This package supports arm64 devices only"

#-----------------------------------------------------------------------------
# Variables supplied by KernelSU, plus installer-local paths.
#-----------------------------------------------------------------------------
TMP="$TMPDIR/nethunter"

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
make_symlink() {
    ln -sf "$1" "$2" 2>/dev/null
    chmod 755 "$2" 2>/dev/null
}

#-----------------------------------------------------------------------------
# Chroot installation and safe replacement.
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
    path="$PRECHROOT/$1"
    mountpoint -q "$path" 2>/dev/null || return 0
    umount -f "$path" 2>/dev/null || umount -l "$path" 2>/dev/null || return 1
    mountpoint -q "$path" 2>/dev/null && return 1
    return 0
}

f_dir_umount() {
    sync
    ui_print "  - Killing chroot pids"
    f_kill_pids
    f_restore_setup
    ui_print "  - Removing fs mounts"
    result=0
    for i in dev/pts dev/shm dev proc sys system sdcard; do
        f_umount_fs "$i" || result=1
    done
    return "$result"
}

do_umount() {
    f_dir_umount || return 1
    if mountpoint -q "$PRECHROOT" 2>/dev/null; then
        umount -f "$PRECHROOT" 2>/dev/null || umount -l "$PRECHROOT" 2>/dev/null || return 1
    fi
    ! awk -v root="$PRECHROOT" '$5 == root || index($5, root "/") == 1 { found=1 } END { exit !found }' \
        /proc/self/mountinfo 2>/dev/null
}

verify_fs() {
    [ "$FS_ARCH" = arm64 ] || return 1
    case "$FS_SIZE" in full|minimal|nano) ;; *) return 1 ;; esac
    return 0
}

validate_rootfs_archive() {
    list="$TMP/rootfs.list"
    tar -tJf "$1" > "$list" 2>/dev/null || return 1
    awk '
        /^\// { bad=1 }
        {
            count=split($0, part, "/")
            if (part[1] == "") bad=1
            for (i=1; i<=count; i++) if (part[i] == "..") bad=1
            if (top == "") top=part[1]
            else if (part[1] != top) bad=1
        }
        END {
            if (bad || top !~ /^kali-[A-Za-z0-9._-]+$/) exit 1
            print top
        }
    ' "$list"
}

do_install() {
    ui_print "  - Found Kali chroot to be installed: $KALIFS"
    mkdir -p "$NHSYS" || return 1

    CHROOT="$NHSYS/kali-$FS_ARCH"
    ROOTFS="$NHSYS/kalifs"
    STAGE="$NHSYS/.staging-$$"
    BACKUP="$NHSYS/.backup-$$"
    ARCHIVE="$TMP/rootfs.tar.xz"
    rm -rf "$STAGE" "$BACKUP"
    mkdir -p "$STAGE" || return 1

    unzip -p "$ZIPFILE" "$KALIFS" > "$ARCHIVE" || {
        rm -rf "$STAGE" "$ARCHIVE"
        return 1
    }
    TOPDIR=$(validate_rootfs_archive "$ARCHIVE") || {
        ui_print "  ! Rootfs archive contains an unsafe or unexpected layout"
        rm -rf "$STAGE" "$ARCHIVE"
        return 1
    }

    ui_print "  - Extracting Kali rootfs (this may take 10-25 minutes)"
    tar -xJf "$ARCHIVE" -C "$STAGE" --exclude "$TOPDIR/dev" || {
        ui_print "  ! Kali $FS_ARCH $FS_SIZE chroot failed to extract"
        ui_print "  - Check free space on /data"
        rm -rf "$STAGE" "$ARCHIVE"
        return 1
    }
    rm -f "$ARCHIVE"

    EXTRACTED="$STAGE/$TOPDIR"
    [ -f "$EXTRACTED/bin/sh" ] || {
        ui_print "  ! Extracted rootfs is missing /bin/sh"
        rm -rf "$STAGE"
        return 1
    }

    PRECHROOT=$(find "$NHSYS" -mindepth 1 -maxdepth 1 -type d -name "kali-*" | head -n 1)
    if [ -n "$PRECHROOT" ]; then
        ui_print "  - Previous chroot detected, preparing replacement"
        do_umount || {
            ui_print "  ! Could not unmount previous chroot"
            rm -rf "$STAGE"
            return 1
        }
        mv "$PRECHROOT" "$BACKUP" || {
            rm -rf "$STAGE"
            return 1
        }
    fi

    rm -f "$ROOTFS"
    if ! mv "$EXTRACTED" "$CHROOT"; then
        [ ! -d "$BACKUP" ] || mv "$BACKUP" "$PRECHROOT"
        rm -rf "$STAGE"
        return 1
    fi
    if ! mkdir -p -m 0755 "$CHROOT/dev" || ! ln -s "$CHROOT" "$ROOTFS"; then
        rm -rf "$CHROOT" "$ROOTFS"
        [ ! -d "$BACKUP" ] || mv "$BACKUP" "$PRECHROOT"
        rm -rf "$STAGE"
        return 1
    fi
    rm -rf "$STAGE" "$BACKUP"
    ui_print "  - Kali $FS_ARCH $FS_SIZE chroot installed"
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
            verify_fs && do_install && return
        fi
    fi

    ui_print "  ! No valid arm64 Kali rootfs found in the module zip"
    return 1
}

#-----------------------------------------------------------------------------
# Installer entry point
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

install_nethunter() {
    UMASK=$(umask)
    umask 022

    # Stage the payload without retaining the large rootfs in the module.
    rm -rf "$TMP"
    mkdir -p "$TMP"
    cd "$TMP" || abort "! Cannot cd to $TMP"
    ui_print "- Unpacking installer payload"
    unzip -qq "$ZIPFILE" -x "kalifs-*" "kali-nethunter-rootfs-*" >&2 \
        || abort "! Failed to extract installer payload"

    # Stage system overlay (firmware, xbin/hid-keyboard, etc.) into $MODPATH
    ui_print "- Copying system overlay into module"
    mkdir -p "$TARGET" || abort "! Cannot create module system directory"
    [ -d "$TMP/system" ] || abort "! System overlay is missing"
    cp -a "$TMP/system"/. "$TARGET/" || abort "! Failed to copy system overlay"
    [ -f "$TMP/uninstall.sh" ] || abort "! Uninstall hook is missing"
    [ -f "$TMP/common/post-fs-data.sh" ] || abort "! post-fs-data hook is missing"
    [ -f "$TMP/common/service.sh" ] || abort "! Service hook is missing"
    cp -a "$TMP/uninstall.sh" "$MODPATH/uninstall.sh" || abort "! Failed to install uninstall hook"
    cp -a "$TMP/common/post-fs-data.sh" "$MODPATH/post-fs-data.sh" || abort "! Failed to install post-fs-data hook"
    cp -a "$TMP/common/service.sh" "$MODPATH/service.sh" || abort "! Failed to install service hook"

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
            make_symlink "/data/data/com.offsec.nethunter/assets/scripts/$s" "$BIN/$s"
        done
    fi

    #-------------------------------------------------------------------------
    # Install the chroot/rootfs
    #-------------------------------------------------------------------------
    ui_print "- Installing Kali chroot"
    do_chroot || abort "! Kali chroot installation failed"

    #-------------------------------------------------------------------------
    # Permissions on everything we dropped into the module
    #-------------------------------------------------------------------------
    ui_print "- Fixing permissions"
    set_perm_recursive "$TARGET" 0 0 0755 0644 || abort "! Failed to set overlay permissions"
    [ ! -d "$BIN" ]  || set_perm_recursive "$BIN"  0 0 0755 0755 || abort "! Failed to set bin permissions"
    [ ! -d "$XBIN" ] || set_perm_recursive "$XBIN" 0 0 0755 0755 || abort "! Failed to set xbin permissions"

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

print_modname
install_nethunter
