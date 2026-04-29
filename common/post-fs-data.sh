#!/system/bin/sh
## Kali NetHunter for KernelSU — post-fs-data hook
##
## Two jobs:
##   1. Make sure busybox_nh is available under /system/xbin (or /system/bin
##      on devices without xbin) — NetHunter scripts hard-call this name.
##      The actual binary ships in this module's system/xbin/busybox_nh-<ver>;
##      we just create the unversioned symlink + applet symlinks here so the
##      overlay stays self-contained.
##   2. Fall back to KernelSU's own busybox if the bundled one is missing
##      (older releases of this module didn't ship it).

MODDIR=${0%/*}

# Pick xbin or bin depending on what /system has
if [ -d /system/xbin ]; then
    SDIR=/system/xbin
else
    SDIR=/system/bin
fi
TARGET="$MODDIR$SDIR"
mkdir -p "$TARGET"
cd "$TARGET" || exit 1

# 1) Find the NetHunter busybox shipped with the module
BB=""
for f in busybox_nh-*; do
    [ -f "$f" ] && BB="$TARGET/$f" # take the highest-versioned one (last in glob order)
done

# 2) Fallback: KernelSU's busybox
if [ -z "$BB" ] || [ ! -x "$BB" ]; then
    if [ -x /data/adb/ksu/bin/busybox ]; then
        cp -f /data/adb/ksu/bin/busybox "$TARGET/busybox_nh-ksu"
        BB="$TARGET/busybox_nh-ksu"
    else
        echo "post-fs-data: no busybox available (neither bundled nor KSU)" >&2
        exit 1
    fi
fi

chmod 0755 "$BB"

# 3) Canonical busybox_nh symlink that NetHunter scripts call
ln -sf "$BB" "$TARGET/busybox_nh"
[ -e "$TARGET/busybox" ] || ln -sf "$BB" "$TARGET/busybox"

# 4) Applet symlinks. On /system/bin we only override applets that already
#    exist there (so we don't shadow Android utilities); on /system/xbin we
#    create them all.
SYSBIN=$(ls /system/bin 2>/dev/null)
for applet in $("$BB" --list); do
    case "$TARGET" in
        */bin)
            if echo "$SYSBIN" | "$BB" grep -q "^$applet$"; then
                "$BB" ln -sf busybox_nh "$applet"
            fi
            ;;
        *)
            "$BB" ln -sf busybox_nh "$applet"
            ;;
    esac
done

# 5) Permissions / SELinux context for everything we just dropped
chmod 0755 ./*
chcon u:object_r:system_file:s0 ./*
