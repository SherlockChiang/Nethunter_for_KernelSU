#!/bin/bash
SKIPMOUNT=false
PROPFILE=false
POSTFSDATA=true
LATESTARTSERVICE=false

# Define Several Variables 
[ -z $TMPDIR ] && TMPDIR=/dev/tmp;
[ ! -z $ZIP ] && { ZIPFILE="$ZIP"; unset ZIP; }
[ -z $ZIPFILE ] && ZIPFILE="$3";
DIR=$(dirname "$ZIPFILE");
TMP=$TMPDIR/$MODID;

file_getprop() { grep "^$2" "$1" | head -n1 | cut -d= -f2-; }

set_perm() {
    chown $2:$3 $1 || return 1
    chmod $4 $1 || return 1
    CON=$5
    [ -z $CON ] && CON=u:object_r:system_file:s0
    chcon $CON $1 || return 1
}

set_perm_recursive() {
    find $1 -type d 2>/dev/null | while read dir; do
        set_perm $dir $2 $3 $4 $6
    done
    find $1 -type f -o -type l 2>/dev/null | while read file; do
        set_perm $file $2 $3 $5 $6
    done
}

symlink() {
    ln -sf "$1" "$2" 2>/dev/null;
    chmod 755 $2 2>/dev/null;
}

# I dislike their wallpaper :D

f_kill_pids() {
    local lsof_full=$(lsof | awk '{print $1}' | grep -c '^lsof')
    if [ "${lsof_full}" -eq 0 ]; then
        local pids=$(lsof | grep "$PRECHROOT" | awk '{print $1}' | uniq)
    else
        local pids=$(lsof | grep "$PRECHROOT" | awk '{print $2}' | uniq)
    fi
    if [ -n "${pids}" ]; then
        kill -9 ${pids} 2> /dev/null
        return $?
    fi
    return 0
}

f_restore_setup() {
    ## set shmmax to 128mb to free memory ##
    sysctl -w kernel.shmmax=134217728 2>/dev/null

    ## remove all the remaining chroot vnc session pid and log files..##
    rm -rf $PRECHROOT/tmp/.X11* $PRECHROOT/tmp/.X*-lock $PRECHROOT/root/.vnc/*.pid $PRECHROOT/root/.vnc/*.log > /dev/null 2>&1
}

f_umount_fs() {
    isAllunmounted=0
    if mountpoint -q $PRECHROOT/$1; then
        if umount -f $PRECHROOT/$1; then
            if [ ! "$1" = "dev/pts" -a ! "$1" = "dev/shm" ]; then
                if ! rm -rf $PRECHROOT/$1; then
                    isAllunmounted=1
                fi
            fi
        else
            isAllunmounted=1
        fi
    else
        if [ -d $PRECHROOT/$1 ]; then
            if ! rm -rf $PRECHROOT/$1; then
                isAllunmounted=1
            fi
        fi
    fi
}

f_dir_umount() {
    sync
    ui_print "Killing all running pids.."
    f_kill_pids
    f_restore_setup
    ui_print "Removing all fs mounts.."
    for i in "dev/pts" "dev/shm" dev proc sys system; do
        f_umount_fs "$i"
    done
    # Don't force unmount sdcard
    # In some devices, it wipes the internal storage
    if umount -l $PRECHROOT/sdcard; then
        if ! rm -rf $PRECHROOT/sdcard; then
            isAllunmounted=1
        fi
    fi
}

f_is_mntpoint() {
    if [ -d "$PRECHROOT" ]; then
        mountpoint -q "$PRECHROOT" && return 0
        return 1
    fi
}

do_umount() {
    f_is_mntpoint
    res=$?
    case $res in
        1) f_dir_umount ;;
        *) return 0 ;;
    esac

    if [ -z "$(cat /proc/mounts | grep $PRECHROOT)" ]; then
        ui_print "All done."
        isAllunmounted=0
    else
        ui_print "there are still mounted points not unmounted yet."
        isAllunmounted=1
    fi

    return $isAllunmounted
}

verify_fs() {
    # valid architecture?
    case $FS_ARCH in
        armhf|arm64|i386|amd64) ;;
        *) return 1 ;;
    esac
    # valid build size?
    case $FS_SIZE in
        full|minimal|nano) ;;
        *) return 1 ;;
    esac
    return 0
}

do_install() {
    ui_print "Found Kali chroot to be installed: $KALIFS"
    mkdir -p "$NHSYS"

    # HACK 1/2: Rename to kali-(arm64,armhf,amd64,i386) as NetHunter App supports searching these directory after first boot
    CHROOT="$NHSYS/kali-$FS_ARCH" # Legacy rootfs directory prior to 2020.1
    ROOTFS="$NHSYS/kalifs"        # New symlink allowing to swap chroots via nethunter app on the fly
    PRECHROOT=`find /data/local/nhsystem -type d -iname kali-* | head -n 1` # previous chroot location 
       
    # Remove previous chroot
    [ -d "$PRECHROOT" ] && {
        ui_print "Previous Chroot Detected!!"
        do_umount;
        [ $? == 1 ] && { 
            ui_print "Aborting Chroot Installations.."
            ui_print "Remove the Previous Chroot and install the new chroot via NetHunter App"
            return 1
        }

        ui_print "Removing Previous chroot.."
        rm -rf "$PRECHROOT"
        rm -f "$ROOTFS"
    }

    # Extract new chroot
    ui_print "Extracting Kali rootfs, this may take up to 25 minutes..."
    unzip -p "$ZIPFILE" "$KALIFS" | tar -xJf - -C "$NHSYS" --exclude "kali-$FS_ARCH/dev"

    [ $? = 0 ] || {
        ui_print "Error: Kali $FS_ARCH $FS_SIZE chroot failed to install!"
        ui_print "Maybe you ran out of space on your data partition?"
        return 1
    }

    # HACK 2/2: create a link to be used by apps effective 2020.1
    ln -sf "$CHROOT" "$ROOTFS"
    mkdir -m 0755 "$CHROOT/dev"
    ui_print "Kali $FS_ARCH $FS_SIZE chroot installed successfully!"

    # We should remove the rootfs archive to free up device memory or storage space (if not zip install)
    [ "$1" ] || rm -f "$KALIFS"

    return 0
}

do_chroot() {
    # Chroot Common Path    
    NHSYS=/data/local/nhsystem

    # do_install [optional zip containing kalifs]
    # Check zip for kalifs-* first
    [ -e "$ZIPFILE" ] && {
        KALIFS=$(unzip -lqq "$ZIPFILE" | awk '$4 ~ /^kalifs-/ { print $4; exit }')
        # Check other locations if zip didn't contain a kalifs-*
        [ "$KALIFS" ] || {
            ui_print "No Kali rootfs found.Aborting...."
            return
        }
    
        FS_ARCH=$(echo "$KALIFS" | awk -F[-.] '{print $2}')
        FS_SIZE=$(echo "$KALIFS" | awk -F[-.] '{print $3}')
        verify_fs && do_install
    }
}

UMASK=$(umask);
umask 022;

# ensure zip installer shell is in a working scratch directory
mkdir -p $TMPDIR;
cd $TMPDIR;
# source custom installer functions and configuration
unzip -jo "$ZIPFILE" module.prop -d $TMPDIR >&2;
MODID=$(file_getprop module.prop id);

# Print Kali NetHunter Banner In Magisk Installation Terminal
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
ui_print "####  ############# NetHunter ####################"

# Extract the installer
ui_print "Unpacking the installer...";
mkdir -p $TMPDIR/$MODID;
cd $TMPDIR/$MODID;
unzip -qq "$ZIPFILE" -x "kalifs-*";
 
# Additional setup for installing apps via pm
[[ "$(getenforce)" == "Enforcing" ]] && ENFORCE=true || ENFORCE=false
${ENFORCE} && setenforce 0
VERIFY=$(settings get global verifier_verify_adb_installs)
settings put global verifier_verify_adb_installs 0
 
# Uninstall previous apps and binaries module if they are installed
ui_print "Checking for previous version of NetHunter apps and files";
rm -rf /data/local/nhsystem &> /dev/null
pm uninstall  com.offsec.nethunter &> /dev/null
pm uninstall  com.offsec.nethunter.kex &> /dev/null
pm uninstall  com.offsec.nhterm &> /dev/null
pm uninstall  com.offsec.nethunter.store &> /dev/null

# Install all NetHunter apps as user apps
# system apps might not work
ui_print "Installing apps...";

# Install the core NetHunter app
ui_print "- Installing NetHunter.apk"
pm install $TMP/data/app/NetHunter.apk &>/dev/null

# and NetHunterTerminal.apk because nethunter.apk depends on it
ui_print "- Installing NetHunterTerminal.apk"
pm install $TMP/data/app/NetHunterTerminal.apk &>/dev/null

# and NetHunterKeX.apk because nethunter.apk depends on it
ui_print "- Installing NetHunter-KeX.apk"
pm install $TMP/data/app/NetHunterKeX.apk &>/dev/null

# and NetHunterStore.apk because we need it 
ui_print "- Installing NetHunter-Store.apk"
pm install -g $TMP/data/app/NetHunterStore.apk &>/dev/null

pm install -g $TMP/data/app/NetHunterStorePrivilegedExtension.apk &> /dev/null
ui_print "- Installing privileged extension as system app"

ui_print "Done installing apps";

# Install Busybox
ui_print "Setting up busybox to automatically mount at startup"

# Install Firmware
ui_print "- Extracting firware files"
unzip -o "$ZIPFILE" 'system/*' -d $MODPATH >&2
unzip -o "$ZIPFILE" 'uninstall.sh' -d $MODPATH >&2
unzip -o "$ZIPFILE" 'module.prop' -d $MODPATH >&2

# Adding required permissions for NetHunter app
ui_print "Granting required permissions to NetHunter app"

# Granting required permissions to NetHunter app
pm grant -g com.offsec.nethunter android.permission.INTERNET
pm grant -g com.offsec.nethunter android.permission.ACCESS_WIFI_STATE
pm grant -g com.offsec.nethunter android.permission.CHANGE_WIFI_STATE
pm grant -g com.offsec.nethunter android.permission.READ_EXTERNAL_STORAGE
pm grant -g com.offsec.nethunter android.permission.WRITE_EXTERNAL_STORAGE
pm grant -g com.offsec.nethunter com.offsec.nhterm.permission.RUN_SCRIPT
pm grant -g com.offsec.nethunter com.offsec.nhterm.permission.RUN_SCRIPT_SU
pm grant -g com.offsec.nethunter com.offsec.nhterm.permission.RUN_SCRIPT_NH
pm grant -g com.offsec.nethunter com.offsec.nhterm.permission.RUN_SCRIPT_NH_LOGIN
pm grant -g com.offsec.nethunter android.permission.RECEIVE_BOOT_COMPLETED
pm grant -g com.offsec.nethunter android.permission.WAKE_LOCK
pm grant -g com.offsec.nethunter android.permission.VIBRATE
pm grant -g com.offsec.nethunter android.permission.FOREGROUND_SERVICE

# Install chroot
do_chroot;

# Random Important Magisk Stuff (Don't Remove)
cp -fp $TMP/tools/module.prop $MNT/$MODID/;
touch $MNT/$MODID/auto_mount;
[ -e /data/adb/modules ] && IMGMNT=/data/adb/modules;
mkdir -p "$IMGMNT/$MODID";
touch "$IMGMNT/$MODID/update";
cp -fp $TMP/tools/module.prop "$IMGMNT/$MODID/";

ui_print "Unmounting...";
cd /;

# Restore environmet after Installations
if [ -d /dev/block/mapper ]; then
    for block in system; do
        for slot in "" _a _b; do
            blockdev --setro /dev/block/mapper/$block$slot 2>/dev/null;
        done;
    done;
fi;
[ "$SAR" ] && mount -o ro,remount -t auto / || mount -o ro,remount -t auto /system;

# Restore also additional settings we did before
settings put global verifier_verify_adb_installs ${VERIFY}
${ENFORCE} && setenforce 1

# Handle replace folders
for TARGET in $REPLACE; do
    ui_print "- Replace target: $TARGET"
    mktouch $MODPATH$TARGET/.replace
done

# Clean up
rm -rf $TMPDIR;
umask $UMASK;

# Done
ui_print " ";
ui_print "Done!";
ui_print " ";
ui_print "************************************************";
ui_print "*       Kali NetHunter is now installed!       *";
ui_print "*==============================================*";
ui_print "*   Please update the NetHunter app via the    *";
ui_print "*   NetHunter Store to work around an Android  *";
ui_print "*   permission issue and run the NetHunter app *";
ui_print "*       to finish setting everything up!       *";
ui_print "************************************************";
ui_print " ";

set_permissions() {
set_perm_recursive  $MODPATH  0  0  0755  0644
}
