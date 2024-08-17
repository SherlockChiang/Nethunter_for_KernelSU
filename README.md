# Nethunter_KSU_Module

First of all, this module is not my original, a lot of code comes from KaliNethunter official magisk module.

And as for this repo, my idea comes form [poxiao676/Nethunter_KSU_Module ](https://github.com/poxiao676/Nethunter_KSU_Module)

The difference is that I updated the install script and the dependency. I'll continually update this when official update comes out.

I have uploaded some large file via LFS, so this is why I didnt fork from poxiao. But I really appreciate his work.

## Here is how to use it:

1. Download a suitable rootfs from
https://kali.download/nethunter-images/current/rootfs/

(I use kalifs-arm64-minimal.tar.xz here, and u can simply download module from release. I think minimal rootf is enough while u can download any metapackage form Nethunter manager.)

2. Move this rootfs directly to the root directory of the module, then compress it into a zip file, and use KernelSU to flash it in.

## Improvement with my code is welcomed! Feel free to contact with me!
Known issue: 
- cant automatically uninstall apks when uninstall from kernelSU manager
- throws error such as cant find /system/bin/su
