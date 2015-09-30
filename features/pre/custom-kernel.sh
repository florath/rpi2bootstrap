#!/bin/bash
#
# Build a custom kernel with SELinux enabled
#

set -e
set -x

CROOT=$1

WORKING_DIR=${PWD}

mkdir -p kernel
cd kernel

if test -e linux;
then
    (cd linux && git pull)
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

 # Check if the .config SELinux patches are already applied
 grep "CONFIG_AUDIT=y" .config 2>/dev/null 1>&2
 GRVAL=$?
 if test "${GRVAL}" -ne 0;
 then
     make -j6 ARCH=arm CROSS_COMPILE=arm-linux-gnueabihf- bcm2709_defconfig
     cat <<EOF >>.config
CONFIG_AUDIT=y
CONFIG_NETWORK_SECMARK=y
CONFIG_SECURITY=y
CONFIG_SECURITY_NETWORK=y
CONFIG_LSM_MMAP_MIN_ADDR=32768
CONFIG_SECURITY_SELINUX=y
CONFIG_SECURITY_SELINUX_BOOTPARAM=y
CONFIG_SECURITY_SELINUX_BOOTPARAM_VALUE=1
CONFIG_SECURITY_SELINUX_DISABLE=y
CONFIG_SECURITY_SELINUX_DEVELOP=y
CONFIG_SECURITY_SELINUX_AVC_STATS=y
CONFIG_SECURITY_SELINUX_CHECKREQPROT_VALUE=1
CONFIG_INTEGRITY=y
CONFIG_INTEGRITY_AUDIT=y
CONFIG_AUDIT_GENERIC=y
EOF
 fi
     
 make -j6 ARCH=arm CROSS_COMPILE=arm-linux-gnueabihf- zImage modules dtbs
)
