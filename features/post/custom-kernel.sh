#!/bin/bash
#
# Build a custom kernel with SELinux enabled
#

set -e
set -x

CROOT=$1

WORKING_DIR=${PWD}
CROOT=${WORKING_DIR}/root
CROOT_FW=${CROOT}/boot/firmware

(cd kernel/linux
 make ARCH=arm CROSS_COMPILE=arm-linux-gnueabihf- \
      INSTALL_MOD_PATH=${CROOT} modules_install
 mv ${CROOT_FW}/kernel7.img ${CROOT_FW}/kernel7-backup.img || true
 scripts/mkknlimg arch/arm/boot/zImage ${CROOT_FW}/kernel7.img
 cp arch/arm/boot/dts/*.dtb ${CROOT_FW}
 mkdir -p ${CROOT_FW}/overlays
 cp arch/arm/boot/dts/overlays/*.dtb* ${CROOT_FW}/overlays/
 cp arch/arm/boot/dts/overlays/README ${CROOT_FW}/overlays/
)
