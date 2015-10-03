#!/bin/bash
#
# Build a custom kernel with SELinux enabled
#

set -e
set -x

CROOT=$1
CROOT_FW=${CROOT}/boot/firmware

mkimage -A arm -O linux -T ramdisk -C gzip -a 0x00000000 -e 0x00000000 \
	-n "RPi2 initrd" -d ${CROOT}/boot/initrd.img-* ${CROOT_FW}/initrd7.img

if false;
then
WORKING_DIR=${PWD}
CROOT=${WORKING_DIR}/root
CROOT_FW=${CROOT}/boot/firmware

(cd kernel/linux
 make ARCH=arm CROSS_COMPILE=arm-linux-gnueabihf- \
      INSTALL_MOD_PATH=${CROOT} modules_install
 mv ${CROOT_FW}/kernel7.img ${CROOT_FW}/kernel7-backup.img || true
 scripts/mkknlimg arch/arm/boot/zImage ${CROOT_FW}/kernel7.img
 cp ${CROOT_FW}/kernel7.img ${CROOT}/vmlinuz-4.1.0-rpi2
 
 cp arch/arm/boot/dts/*.dtb ${CROOT_FW}
 mkdir -p ${CROOT_FW}/overlays
 cp arch/arm/boot/dts/overlays/*.dtb* ${CROOT_FW}/overlays/
 cp arch/arm/boot/dts/overlays/README ${CROOT_FW}/overlays/

 # Write u-boot config file
 cat <<EOF >${CROOT_FW}/boot.cfg
setenv fdtfile bcm2709-rpi-2-b.dtb

mmc dev 0
fatload mmc 0:1 \${kernel_addr_r} kernel7.img
fatload mmc 0:1 \${fdt_addr_r} \${fdtfile}
setenv bootargs "earlyprintk console=tty0 console=ttyAMA0 root=/dev/mmcblk0p2 rootfstype=ext4 rootwait noinitrd"
bootz \${kernel_addr_r} - \${fdt_addr_r}
EOF

 # Create scr file from config
 mkimage -A arm -O linux -T script -C none -a 0x00000000 -e 0x00000000 \
	 -n "RPi2 Boot Script" -d ${CROOT_FW}/boot.cfg ${CROOT_FW}/boot.scr
)
fi
