#!/bin/bash

# Define Several Variables 
[ -z $TMPDIR ] && TMPDIR=/dev/tmp;
NHSYS=/data/local/nhsystem
ROOTFS="$NHSYS/kalifs"
PRECHROOT=`find /data/local/nhsystem -type d -iname kali-* | head -n 1`

# Function to unmount file systems
f_umount_fs() {
    if mountpoint -q $PRECHROOT/$1; then
        umount -f $PRECHROOT/$1
    fi
    [ -d $PRECHROOT/$1 ] && rm -rf $PRECHROOT/$1
}

# Function to clean up directories and unmount file systems
do_umount() {
    for i in "dev/pts" "dev/shm" dev proc sys system; do
        f_umount_fs "$i"
    done

    umount -l $PRECHROOT/sdcard
    rm -rf $PRECHROOT/sdcard

    # Final unmount and clean up
    if [ -d "$PRECHROOT" ]; then
        umount -f $PRECHROOT
        rm -rf $PRECHROOT
    fi
}

# Function to remove installed apps
pm uninstall com.offsec.nethunter &>/dev/null
pm uninstall com.offsec.nethunter.kex &>/dev/null
pm uninstall com.offsec.nhterm &>/dev/null
pm uninstall com.offsec.nethunter.store &>/dev/null

# Function to restore permissions and SELinux enforcing state
restore_settings() {
    [[ "$(getenforce)" == "Enforcing" ]] && ENFORCE=true || ENFORCE=false
    settings put global verifier_verify_adb_installs 1

    ${ENFORCE} && setenforce 1
}

# Unmount and clean up the chroot environment
if [ -d "$PRECHROOT" ]; then
    do_umount
fi

# Remove NetHunter system and app files
rm -rf $NHSYS
remove_apps

# Restore system settings
restore_settings

# Remove module files
rm -rf "$MODPATH"
