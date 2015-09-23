#!/bin/bash
#
# Create a Debian Jessie Rasperry Pi 2 Image
#

######################################################################

### Configuration

# Some GByte of HD space is needed
WORKING_DIR=/data/RP/tmp

DISTRIBUTION=debian
VARIANT=jessie

IMAGE_SIZE=1G

### End Configuration

######################################################################

set -e

IMAGE_PATH=${WORKING_DIR}/rpi2-${DISTRIBUTION}-${VARIANT}.img

mkdir -p ${WORKING_DIR}
# This is the place where the new image will be bootstraped.
CROOT=${WORKING_DIR}/root
mkdir -p ${CROOT}
CROOT_FW=${WORKING_DIR}/root/boot/firmware

# If something nasty happens: cleanup
function cleanup() {
    umount ${CROOT_FW} || true
    umount ${CROOT} || true
    lvchange -an /dev/rpi2vg/root_vol || true
    test ! -z "${LOOPDEV}" && kpartx -d "${LOOPDEV}" || true
    test ! -z "${LOOPDEV}" && losetup --detach ${LOOPDEV}
    rm -fr ${CROOT}
}

trap cleanup EXIT

# Start working on the image

cd ${WORKING_DIR}
rm -f ${IMAGE_PATH}
dd if=/dev/zero of=${IMAGE_PATH} bs=1 count=1024 seek=${IMAGE_SIZE}

LOOPDEV=$(losetup --show -f ${IMAGE_PATH})

# Need DOS label
parted -s ${LOOPDEV} "mklabel msdos"
# Create /boot/firmware
parted -s ${LOOPDEV} "unit s" "mkpart primary fat16 2048 249855"
# Create /root
parted -s ${LOOPDEV} "unit s" "mkpart primary ext4 249856 -1"
# Make the partitions available for the system
kpartx -a ${LOOPDEV}

# Typically the kernel need some time to get the partitions up
# and running.
LOOPDEVBASE=$(echo ${LOOPDEV} | cut -d "/" -f 3)
while test ! -e /dev/mapper/${LOOPDEVBASE}p1;
do
    sleep 0.2
done

# Format /boot/firmware
mkfs.fat /dev/mapper/${LOOPDEVBASE}p1
mkdir -p ${WORKING_DIR}/root/boot/firmware

# The rest goes to LVM
LOOPDEVROOT=/dev/mapper/${LOOPDEVBASE}p2
pvcreate ${LOOPDEVROOT}
vgcreate rpi2vg ${LOOPDEVROOT}

lvcreate -l 100%FREE -n root_vol rpi2vg
mkfs.ext4 /dev/rpi2vg/root_vol
mount /dev/rpi2vg/root_vol ${CROOT}
mkdir -p ${CROOT_FW}
mount /dev/mapper/${LOOPDEVBASE}p1 ${CROOT_FW}

debootstrap --arch=armhf \
	    --include=lvm2,apt-transport-https \
	    --components=main,contrib,non-free \
	    --variant=minbase --verbose --foreign \
	    ${VARIANT} \
	    ${WORKING_DIR}/root \
	    http://httpredir.debian.org/debian

cp /usr/bin/qemu-arm-static  ${WORKING_DIR}/root/usr/bin

DEBIAN_FRONTEND=noninteractive DEBCONF_NONINTERACTIVE_SEEN=true \
	       LC_ALL=C LANGUAGE=C LANG=C chroot ${WORKING_DIR}/root \
	       /debootstrap/debootstrap --second-stage

DEBIAN_FRONTEND=noninteractive DEBCONF_NONINTERACTIVE_SEEN=true \
	       LC_ALL=C LANGUAGE=C LANG=C chroot ${WORKING_DIR}/root \
	       dpkg --configure -a

function cr() {
    chroot ${WORKING_DIR}/root /usr/bin/qemu-arm-static $@
}

echo "deb https://repositories.collabora.co.uk/debian jessie rpi2" \
     >> ${WORKING_DIR}/root/etc/apt/sources.list

#cr /usr/bin/apt-get update
# Better to use /usr/bin/qemu-arm-static /bin/bash -x -e cmd.sh!?!?

echo "START"
/bin/bash
echo "CONTINUE"

# XXX Write fstab
