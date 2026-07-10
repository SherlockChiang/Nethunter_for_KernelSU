# NetHunter for KernelSU

KernelSU module packaging Kali NetHunter applications, an arm64 Kali rootfs,
selected firmware, and NetHunter helper binaries. The primary test target is
Xiaomi 15. Code in this repository is adapted in part from the official Kali
NetHunter Magisk module and from
[poxiao676/Nethunter_KSU_Module](https://github.com/poxiao676/Nethunter_KSU_Module).

## Requirements

- An arm64 Android device running KernelSU.
- Installation through KernelSU Manager. Recovery flashing is not supported.
- A KernelSU mounting metamodule such as `meta-overlayfs` for the files under
  `system/` to be mounted. Without one, the APK and rootfs installation may
  work, but firmware and helper overlays will not.
- Enough free space under `/data` to stage a second rootfs during upgrades.

Xiaomi 15 is the maintained target. Other arm64 devices are experimental and
depend on their ROM, kernel configuration, KernelSU version, and mounting
metamodule.

## Build Inputs

The following files exceed GitHub's normal file limit and are downloaded
separately:

1. Put `NetHunterKeX.apk` in `data/app/`.
2. Put `kali-nethunter-rootfs-minimal-arm64.tar.xz` in the repository root.
3. Verify every input against `artifacts.sha256`:

```sh
sha256sum --check artifacts.sha256
```

The installer rejects payloads that do not match this manifest. When updating
an artifact intentionally, review its upstream source and signature, then
update the corresponding digest in the same change.

Create the module ZIP from the declared module files at the ZIP root. Do not
archive the repository directory itself or include `.git`, existing ZIPs, or
local editor state.

## Installation

1. Install and enable a KernelSU mounting metamodule if system overlays are
   required.
2. Install the module ZIP from KernelSU Manager.
3. Reboot.
4. Grant root access to the NetHunter application in KernelSU Manager.
5. Review Android runtime permissions when prompted by individual features.

The installer updates existing APKs in place and stages the new rootfs before
replacing the previous one. A failed rootfs extraction keeps the previous
chroot intact.

## Uninstallation

KernelSU invokes `uninstall.sh` before Android's package manager is available.
To remove the bundled applications as well as the module:

1. Run the module action in KernelSU Manager while Android is running.
2. Confirm that it reports `NetHunter apps removed`.
3. Remove the module in KernelSU Manager and reboot.

If the action is skipped, remove the five NetHunter packages manually from
Android settings. The filesystem uninstall hook refuses to delete the chroot
while any nested mount remains.

## Kernel Features

Bundled firmware can only support hardware for which the running kernel already
contains a compatible driver. It does not add kernel drivers, monitor mode to
the internal radio, or kernel tracepoints.

Likewise, configfs being present does not by itself guarantee HID, BadUSB,
RNDIS, or mass-storage support. Those features also depend on the device's USB
controller, kernel gadget functions, ROM behavior, and SELinux policy. A
NetHunter-patched kernel may still be required.

## Validation

Run the repository checks with:

```sh
bash tests/static.sh
```

CI also runs ShellCheck on lifecycle scripts. Physical-device validation is
still required for install, upgrade, reboot, chroot startup, module action, and
uninstall changes.
