#!/system/bin/sh

MODDIR=${0%/*}

# Choose XBIN or BIN path
SDIR=/system/xbin/
if [ ! -d $SDIR ]
then
  SDIR=/system/bin/
fi
BBDIR=$MODDIR$SDIR
mkdir -p $BBDIR
cd $BBDIR
pwd

# Check for local busybox binary
BB=busybox
BBN=busybox_nh
BBBIN=$MODDIR/$BB
if [ -f $BBBIN ]
then
  chmod 755 $BBBIN
  if [ $($BBBIN --list | wc -l) -ge 128 ] && [ ! -z "$($BBBIN | head -n 1 | grep -i $BB)" ]
  then
    chcon u:object_r:system_file:s0 $BBBIN
    Applets=$BB$'\n'$($BBBIN --list)
  else
    rm -f $BBBIN
  fi
fi

# Otherwise use KSU built-in busybox binary
if [ ! -x $BBBIN ]
then
  BBBIN=/data/adb/ksu/bin/$BB
  $BBBIN --list | wc -l
  Applets=$BB$'\n'$($BBBIN --list)
fi

# Create local symlinks for Busybox_nh
ln -s $BBBIN $SDIR$BBN

# Create local symlinks for BusyBox applets
for Applet in $Applets
do
  if [ ! -x $SDIR/$Applet ]
  then
    # Create symlink
    ln -s $BBBIN $Applet
  fi
done
chmod 755 *
chcon u:object_r:system_file:s0 *

set +x
exec 1>&3 2>&4 3>&- 4>&-
