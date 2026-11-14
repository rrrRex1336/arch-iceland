#!/usr/bin/env bash
# One-click dual-boot flash for the OnePlus Pad 3 Pro / Pad 4 (iceland, SM8850).
#
#   ./scripts/flash-dual.sh [boot.img] [rootfs.img]
#
# Writes:
#   boot_b  <- boot.img        (mainline kernel, Android header v2)
#   linux   <- rootfs.img      (ext4 Arch rootfs, mounted by PARTLABEL)
# and erases dtbo_b so the stock overlays cannot interfere.
#
# The "linux" partition must exist already (userdata shrunk, new GPT partition
# named "linux"). This script never repartitions and never touches userdata.
#
#   DRY_RUN=1 ./scripts/flash-dual.sh      print the plan only
#   ASSUME_YES=1 ...                       skip the confirmation
set -euo pipefail

boot_img=${1:-${BOOT_IMG:-boot.img}}
rootfs_img=${2:-${ROOTFS_IMG:-rootfs.img}}
slot=${SLOT:-b}
dry_run=${DRY_RUN:-0}
assume_yes=${ASSUME_YES:-0}

die() { echo "error: $*" >&2; exit 1; }
note() { echo "  $*"; }

command -v fastboot >/dev/null || die "fastboot not found"
[ -f "$boot_img" ] || die "boot image not found: $boot_img"
[ -f "$rootfs_img" ] || die "rootfs image not found: $rootfs_img"

# --- sanity checks on the images -------------------------------------------
[ "$(head -c 8 "$boot_img")" = "ANDROID!" ] || die "$boot_img is not an Android boot image"
[ "$(od -An -tx1 -j 1080 -N 2 "$rootfs_img" | tr -d ' \n')" = "53ef" ] ||
	die "$rootfs_img does not look like an ext4 filesystem"

rootfs_bytes=$(stat -c %s "$rootfs_img")
rootfs_gib=$(( (rootfs_bytes + 1073741823) / 1073741824 ))

# --- device checks ----------------------------------------------------------
mapfile -t devices < <(fastboot devices | awk 'NF {print $1}')
[ "${#devices[@]}" -eq 1 ] || die "expected exactly one fastboot device, found ${#devices[@]} (adb reboot bootloader first)"

var() { fastboot getvar "$1" 2>&1 | tr -d '\r' | sed -n "s/^.*$1:[[:space:]]*//p" | head -1; }

product=$(var product)
case "$product" in
	canoe|oneplus-iceland|iceland) ;;
	*) echo "warning: unexpected product '$product' (expected canoe)" >&2 ;;
esac

userspace=$(var is-userspace)
[ "$userspace" = "no" ] || die "device is in fastbootd (is-userspace=$userspace); run 'fastboot reboot bootloader' and retry"

current=$(var current-slot)
[ -n "$current" ] || die "cannot read current-slot"

size_hex=$(var partition-size:linux)
if [ -z "$size_hex" ]; then
	cat >&2 <<'EOF'
error: no "linux" partition on this device.

This script does not repartition. To get a dual-boot layout you have to
shrink userdata and add a GPT partition named "linux" first, from a recovery
or a Linux environment that can run parted/sgdisk on the UFS disk.

There is no public TWRP build for iceland (OPD2513/OPD2514) at the moment;
the SM8850 TWRP releases on GitHub target other boards (different panel and
touch controller), so do not flash those.
EOF
	exit 1
fi

part_bytes=$((size_hex))
part_gib=$(( (part_bytes + 1073741823) / 1073741824 ))
[ "$rootfs_bytes" -le "$part_bytes" ] ||
	die "rootfs.img is ${rootfs_gib}G but the linux partition is only ${part_gib}G"

# --- plan -------------------------------------------------------------------
echo
echo "device : $product (current slot: $current)"
echo "boot   : $boot_img -> boot_$slot"
echo "rootfs : $rootfs_img (${rootfs_gib}G) -> linux (${part_gib}G)"
echo "dtbo_$slot will be erased, active slot set to $slot"
echo

if [ "$dry_run" = "1" ]; then
	echo "DRY_RUN=1, nothing written"
	exit 0
fi

if [ "$assume_yes" != "1" ]; then
	read -r -p "Type YES to continue: " answer
	[ "$answer" = "YES" ] || die "aborted"
fi

# --- flash ------------------------------------------------------------------
echo "==> erasing dtbo_$slot"
fastboot erase "dtbo_$slot" || echo "warning: dtbo erase failed (continuing)"

echo "==> flashing boot_$slot"
fastboot flash "boot_$slot" "$boot_img"

echo "==> flashing linux (this can take several minutes)"
# -S keeps each USB transfer under the bootloader's max-download-size
fastboot -S 256M flash linux "$rootfs_img"

echo "==> switching active slot to $slot"
fastboot set_active "$slot" || echo "warning: set_active failed; set the slot manually if needed"

echo "==> rebooting"
fastboot reboot

cat <<EOF

Done. If the kernel does not come up:
  - the first boot can take a while, and the panel may stay dark for ~10s
  - get the log with: adb shell dmesg (if it boots) or pstore
  - the stock Android boot image is not touched; slot a still boots Android
EOF
