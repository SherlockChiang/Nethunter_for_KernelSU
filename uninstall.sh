#!/bin/bash

# Define Several Variables 
[ -z $TMPDIR ] && TMPDIR=/dev/tmp;
NHSYS=/data/local/nhsystem
ROOTFS="$NHSYS/kalifs"
PRECHROOT=`find /data/local/nhsystem -type d -iname kali-* | head -n 1`

# Function to unmount file systems safely
f_umount_fs() {
    if mountpoint -q $PRECHROOT/$1; then
        umount -f $PRECHROOT/$1
    fi
    if [ -d $PRECHROOT/$1 ]; then
        echo "Removing directory: $PRECHROOT/$1"
        rm -rf $PRECHROOT/$1
    else
        echo "Directory not found: $PRECHROOT/$1"
    fi
}

# Function to clean up directories and unmount file systems
do_umount() {
    for i in "dev/pts" "dev/shm" dev proc sys system; do
        f_umount_fs "$i"
    done

    if mountpoint -q $PRECHROOT/sdcard; then
        umount -l $PRECHROOT/sdcard
        echo "Unmounted sdcard"
    else
        echo "sdcard not mounted"
    fi
    rm -rf $PRECHROOT/sdcard

    # Final unmount and clean up
    if [ -d "$PRECHROOT" ]; then
        echo "Unmounting and removing $PRECHROOT"
        umount -f $PRECHROOT
        rm -rf $PRECHROOT
    else
        echo "Directory $PRECHROOT does not exist"
    fi
}

# Function to remove installed apps safely
remove_apps() {
    APPS=("com.offsec.nethunter" "com.offsec.nethunter.kex" "com.offsec.nhterm" "com.offsec.nethunter.store")
    for APP in "${APPS[@]}"; do
        if pm list packages | grep -q $APP; then
            pm uninstall $APP &>/dev/null
            echo "Uninstalled $APP"
        else
            echo "$APP not installed"
        fi
    done
}

# Function to restore permissions and SELinux enforcing state
restore_settings() {
    [[ "$(getenforce)" == "Enforcing" ]] && ENFORCE=true || ENFORCE=false
    settings put global verifier_verify_adb_installs 1
    echo "Restored ADB install verification setting"

    ${ENFORCE} && setenforce 1
    echo "SELinux enforcing state restored"
}

# Unmount and clean up the chroot environment safely
if [ -d "$PRECHROOT" ]; then
    do_umount
else
    echo "No chroot environment found at $PRECHROOT"
fi

# Remove NetHunter system and app files safely
if [ -d "$NHSYS" ]; then
    rm -rf $NHSYS
    echo "Removed NetHunter system files at $NHSYS"
else
    echo "$NHSYS directory does not exist"
fi

remove_apps

# Restore system settings
restore_settings
