#!/system/bin/sh

MODDIR=${0%/*}

# 使用 KernelSU 的 busybox 二进制文件
BB=/data/adb/ksu/bin/busybox
SDIR=/system/xbin/
if [ ! -d $SDIR ]; then
  SDIR=/system/bin/
fi
BBDIR=$MODDIR$SDIR
mkdir -p $BBDIR
cd $BBDIR

# 检查 BusyBox 是否有效
if [ -x $BB ] && [ $($BB --list | wc -l) -ge 128 ]; then
  Applets=$BB$'\n'$($BB --list)
else
  echo "KernelSU BusyBox 未找到或无效"
  exit 1
fi

# 为 BusyBox applets 创建本地符号链接
for Applet in $Applets; do
  if [ ! -x $SDIR/$Applet ]; then
    ln -s $BB $SDIR/$Applet
  fi
done

chmod 755 *
chcon u:object_r:system_file:s0 *
