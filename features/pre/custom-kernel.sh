#!/bin/bash
#
# Build a custom kernel with SELinux enabled
#

set -e
set -x

CROOT=$1

WORKING_DIR=${PWD}

KERNEL_VERSION="rpi-4.1.y"

mkdir -p kernel
cd kernel

if test -e linux;
then
    (cd linux && git pull --depth=1)
else
    git clone --depth=1 https://github.com/raspberrypi/linux linux
fi
(cd linux && git checkout ${KERNEL_VERSION})

if test ! -e tools;
then
    git clone https://github.com/raspberrypi/tools tools
fi

export PATH=${PWD}/tools/arm-bcm2708/gcc-linaro-arm-linux-gnueabihf-raspbian-x64/bin:${PATH}

(cd linux
 KERNEL=kernel7

 set +e
 # Check if the .config SELinux patches are already applied
 grep "CONFIG_AUDIT=y" .config 2>/dev/null 1>&2
 GRVAL=$?
 set -e
 if test "${GRVAL}" -ne 0;
 then
     make -j6 ARCH=arm CROSS_COMPILE=arm-linux-gnueabihf- bcm2709_defconfig
     patch --reverse .config <<EOF
55c55
< CONFIG_AUDIT=y
---
> # CONFIG_AUDIT is not set
659,660c659
< # CONFIG_NETLABEL is not set
< CONFIG_NETWORK_SECMARK=y
---
> # CONFIG_NETWORK_SECMARK is not set
678d676
< # CONFIG_NF_CONNTRACK_SECMARK is not set
727d724
< # CONFIG_NETFILTER_XT_TARGET_AUDIT is not set
749d745
< # CONFIG_NETFILTER_XT_TARGET_SECMARK is not set
893d888
< # CONFIG_IP_NF_SECURITY is not set
923d917
< # CONFIG_IP6_NF_SECURITY is not set
4526d4519
< # CONFIG_FANOTIFY_ACCESS_PERMISSIONS is not set
4656d4648
< # CONFIG_NFSD_V4_SECURITY_LABEL is not set
4941c4933
< CONFIG_SECURITY=y
---
> # CONFIG_SECURITY is not set
4943,4966c4935,4936
< CONFIG_SECURITY_NETWORK=y
< # CONFIG_SECURITY_NETWORK_XFRM is not set
< # CONFIG_SECURITY_PATH is not set
< CONFIG_LSM_MMAP_MIN_ADDR=32768
< CONFIG_SECURITY_SELINUX=y
< CONFIG_SECURITY_SELINUX_BOOTPARAM=y
< CONFIG_SECURITY_SELINUX_BOOTPARAM_VALUE=1
< CONFIG_SECURITY_SELINUX_DISABLE=y
< CONFIG_SECURITY_SELINUX_DEVELOP=y
< CONFIG_SECURITY_SELINUX_AVC_STATS=y
< CONFIG_SECURITY_SELINUX_CHECKREQPROT_VALUE=1
< # CONFIG_SECURITY_SELINUX_POLICYDB_VERSION_MAX is not set
< # CONFIG_SECURITY_SMACK is not set
< # CONFIG_SECURITY_TOMOYO is not set
< # CONFIG_SECURITY_APPARMOR is not set
< # CONFIG_SECURITY_YAMA is not set
< CONFIG_INTEGRITY=y
< # CONFIG_INTEGRITY_SIGNATURE is not set
< CONFIG_INTEGRITY_AUDIT=y
< # CONFIG_IMA is not set
< # CONFIG_EVM is not set
< CONFIG_DEFAULT_SECURITY_SELINUX=y
< # CONFIG_DEFAULT_SECURITY_DAC is not set
< CONFIG_DEFAULT_SECURITY="selinux"
---
> CONFIG_DEFAULT_SECURITY_DAC=y
> CONFIG_DEFAULT_SECURITY=""
5126d5095
< CONFIG_AUDIT_GENERIC=y
EOF

 fi

 make -j6 ARCH=arm CROSS_COMPILE=arm-linux-gnueabihf- zImage modules dtbs
)

CROOT_FW=${CROOT}/boot/firmware

# Compile u-boot
if test -e u-boot;
then
    (cd u-boot && git pull)
else
    git clone git://git.denx.de/u-boot.git
fi
(cd u-boot
 make ARCH=arm CROSS_COMPILE=arm-linux-gnueabihf- rpi_2_defconfig
 make -j6 ARCH=arm CROSS_COMPILE=arm-linux-gnueabihf- all

 cp u-boot.bin ${CROOT_FW}
)

(cd linux
 make ARCH=arm CROSS_COMPILE=arm-linux-gnueabihf- \
      INSTALL_MOD_PATH=${CROOT} modules_install

 # Get the complete version number of the kernel from the
 # name of the /lib/modules directory
 KERNEL_DESC=$( (cd ${CROOT}/lib/modules && echo *) )
 
 mv ${CROOT_FW}/kernel7.img ${CROOT_FW}/kernel7-backup.img || true
 scripts/mkknlimg arch/arm/boot/zImage ${CROOT_FW}/kernel7.img
 cp ${CROOT_FW}/kernel7.img ${CROOT}/boot/vmlinuz-${KERNEL_DESC}
 cp System.map ${CROOT}/boot/System.map-${KERNEL_DESC}
 cp .config ${CROOT}/boot/config-${KERNEL_DESC}
 
 cp arch/arm/boot/dts/*.dtb ${CROOT_FW}
 mkdir -p ${CROOT_FW}/overlays
 cp arch/arm/boot/dts/overlays/*.dtb* ${CROOT_FW}/overlays/
 cp arch/arm/boot/dts/overlays/README ${CROOT_FW}/overlays/

 # Write u-boot config file
 cat <<EOF >${CROOT_FW}/boot.cfg
setenv fdtfile bcm2709-rpi-2-b.dtb

mmc dev 0
fatload mmc 0:1 \${kernel_addr_r} kernel7.img
fatload mmc 0:1 \${ramdisk_addr_r} initrd7.img
fatload mmc 0:1 \${fdt_addr_r} \${fdtfile}
setenv bootargs "ignore_loglevel loglevel=7 logo.nologo selinux=0 initrd=\${ramdisk_addr_r} rfs=exists:file=/dev/mmcblk0p2,wait=30;decrypt:dev=/dev/mmcblk0p2,name=decdisk,keyfile=/dev/disk/by-id/usb-Intenso_Rainbow_Line_77FBFA68-0:0,decmod=luks,tries=3,keyfile_size=4096,keyfile_offset=512;exists:file=/dev/mapper/decdisk,wait=15;lvm:scan;exists:file=/dev/rpi2vg/enc_vol;root:dev=/dev/rpi2vg/enc_vol bv=udev"
#setenv bootargs "debug ignore_loglevel loglevel=7 logo.nologo selinux=0 initrd=${ramdisk_addr_r} rfs=local:path=/dev/rpi2vg/enc_vol bv=lvm2,udev rootwait"
#setenv bootargs "earlyprintk console=tty0 console=ttyAMA0 root=/dev/rpi2vg/enc_vol rootfstype=ext4 rootwait initrd=\${ramdisk_addr_r}"
bootz \${kernel_addr_r} \${ramdisk_addr_r} \${fdt_addr_r}
EOF

 # Create scr file from config
 mkimage -A arm -O linux -T script -C none -a 0x00000000 -e 0x00000000 \
	 -n "RPi2 Boot Script" -d ${CROOT_FW}/boot.cfg ${CROOT_FW}/boot.scr
)

# mkimage -A arm -O linux -T ramdisk -C gzip -a 0x00000000 -e 0x00000000 -n "RPi2 initrd" -d ${CROOT}/boot/initrd.img-4.1.9-v7+ ${CROOT_FW}/initrd7.img
