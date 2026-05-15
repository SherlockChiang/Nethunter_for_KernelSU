# Nethunter_KSU_Module

First of all, this module is not my original, a lot of code comes from KaliNethunter official magisk module.

And as for this repo, my idea comes form [poxiao676/Nethunter_KSU_Module ](https://github.com/poxiao676/Nethunter_KSU_Module)

The difference is that I updated the install script and the dependency. I'll continually update this when official update comes out.

I have uploaded some large file via LFS, so this is why I didnt fork from poxiao. But I really appreciate his work.

## How to use it
Get latest release from https://github.com/SherlockChiang/Nethunter_for_KernelSU/releases and flash via KernelSU Manager.

## Target devices

Primary target is **Xiaomi 15** (Snapdragon 8 Elite). Should work on any arm64 Android device with KernelSU rooted, since the module only overlays files onto `/system` (firmware blobs + apps + chroot) and does **not** patch the kernel.

## Why USB Wi-Fi / HID / BadUSB works on stock kernels

The module ships kernel-side firmware blobs in `system/etc/firmware/` (rtlwifi, brcm, ath9k_htc, mt7601u, …). KernelSU mounts this overlay over `/system/etc/firmware/` at boot, so when you plug in an external USB Wi-Fi adapter the stock Xiaomi kernel can finally find the firmware it asks for and bring the device up. Likewise, USB-gadget tricks (HID/BadUSB, mass storage, RNDIS) work because the stock kernel already exposes `/sys/kernel/config/usb_gadget/` (`CONFIG_USB_CONFIGFS=y`, used for ADB/MTP) — NetHunter just re-configures it from userspace.

What it does **not** do: load extra Wi-Fi drivers, enable monitor mode on the internal radio, or patch any kernel tracepoints. Those need a NetHunter-patched kernel flashed separately.
