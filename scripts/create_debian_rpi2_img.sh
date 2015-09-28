#!/bin/bash
#
# Create a Debian Jessie Rasperry Pi 2 Image
#

set -e

function usage() {
    test -n "$1" && echo "*** ERROR: $1" >&2
    cat <<EOF >&2
Usage: create_debian_rpi_img -w working_dir -d distribution -v variant -s image_size
                             -e enc_disk_id [-p pkglist] [-P proxy] [-c chroot_sh]
where
  working_dir  is the place where the image is build
               Some gigs of HD space should be available there.
  distribution one of debian or ubuntu
  variant      the version, like jessie, stretch or wily
  image_size   the initial image size, e.g. '1G'
  enc_disk_id  disk id of the USB stick where the decryption key is stored
  pkglist      [optional] comma separated list of additional packages
  proxy        [optional] when there is the need to set the http(s)_proxy
               set this to the appropriate url
  chroot_sh    [optional] Script that is executed in chroot
EOF
    exit 1
}

WORKING_DIR=""
DISTRIBUTION=""
VARIANT=""
IMAGE_SIZE=""
PROXY=""
ENC_DISK_ID=""
ADD_PACKAGES=""
USER_CHROOT_SH=""

while getopts "hw:d:v:s:P:e:p:c:" opt;
do
    case ${opt} in
	h)
	    usage ""
	    ;;
	w)
	    WORKING_DIR=${OPTARG}
	    ;;
	c)
	    USER_CHROOT_SH=${OPTARG}
	    ;;
	d)
	    DISTRIBUTION=${OPTARG}
	    ;;
	v)
	    VARIANT=${OPTARG}
	    ;;
	s)
	    IMAGE_SIZE=${OPTARG}
	    ;;
	p)
	    ADD_PACKAGES=${OPTARG}
	    ;;
	P)
	    PROXY=${OPTARG}
	    ;;
	e)
	    ENC_DISK_ID=${OPTARG}
	    ;;
	\?)
	    usage "Invalid oprtion [${opt}]"
	    ;;
	:)
	    usage "Option [${opt}] requires an argument"
	    ;;
    esac
done

test -z "${WORKING_DIR}" && usage "working dir [-w] not set"
test -z "${DISTRIBUTION}" && usage "distribution [-d] not set"
test -z "${VARIANT}" && usage "variant [-v] not set"
test -z "${IMAGE_SIZE}" && usage "image size [-v] not set"
test -z "${ENC_DISK_ID}" && usage "encrypted disk id [-e] not set"

if test -n "${PROXY}";
then
    export http_proxy=${PROXY}
    export https_proxy=${PROXY}
fi

IMAGE_PATH=${WORKING_DIR}/rpi2-${DISTRIBUTION}-${VARIANT}.img

mkdir -p ${WORKING_DIR}
# This is the place where the new image will be bootstraped.
CROOT=${WORKING_DIR}/root
mkdir -p ${CROOT}
CROOT_FW=${CROOT}/boot/firmware
CROOT_ENC=${CROOT}/enc

# If something nasty happens: cleanup
function cleanup() {
    umount ${CROOT}/proc || true
    umount ${CROOT}/sys || true
    umount ${CROOT_FW} || true
    umount ${CROOT_ENC} || true
    umount ${CROOT} || true
    lvchange -an /dev/rpi2vg/*_vol || true
    cryptsetup close /dev/mapper/crypteddisk || true
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
parted -s ${LOOPDEV} "unit s" "mkpart primary ext4 249856 2347007"
# Create /enc
parted -s ${LOOPDEV} "unit s" "mkpart primary ext4 2347008 -1"
# Make the partitions available for the system
kpartx -a ${LOOPDEV}

# Typically the kernel need some time to get the partitions up
# and running.
LOOPDEVBASE=$(echo ${LOOPDEV} | cut -d "/" -f 3)
for p in 1 2 3;
do
    while test ! -e /dev/mapper/${LOOPDEVBASE}p${p};
    do
	sleep 0.2
    done
done

# Create the key
# Create some random numbers
test ! -e ${WORKING_DIR}/rpi2-usb-random.key && \
    dd if=/dev/urandom of=${WORKING_DIR}/rpi2-usb-random.key bs=512 count=60
chmod 0400 ${WORKING_DIR}/rpi2-usb-random.key
# Extract the key
dd if=${WORKING_DIR}/rpi2-usb-random.key \
   of=${WORKING_DIR}/rpi2-enc.key bs=512 count=8

echo "*** PLEASE copy over the random keys to the USB stick, e.g.:"
echo "*** dd if=${WORKING_DIR}/rpi2-usb-random.key seek=1 of=/dev/disk/by-id/${ENC_DISK_ID}"

# Format /
LOOPDEVROOT=/dev/mapper/${LOOPDEVBASE}p2
mkfs.ext4 ${LOOPDEVROOT}
mount ${LOOPDEVROOT} ${CROOT}

# The rest goes to encrypted LVM (enc)
LOOPDEVENC=/dev/mapper/${LOOPDEVBASE}p3

cryptsetup luksFormat --batch-mode --cipher=aes-xts-plain64 --hash=sha512 \
	   --key-size=512 \
	   ${LOOPDEVENC} ${WORKING_DIR}/rpi2-enc.key

cryptsetup luksOpen \
	   --key-file ${WORKING_DIR}/rpi2-enc.key \
	   ${LOOPDEVENC} crypteddisk

ENCDISK=/dev/mapper/crypteddisk

pvcreate ${ENCDISK}
vgcreate rpi2vg ${ENCDISK}
lvcreate -l 100%FREE -n enc_vol rpi2vg
mkfs.ext4 /dev/rpi2vg/enc_vol
mkdir -p ${CROOT_ENC}
mount /dev/rpi2vg/enc_vol ${CROOT_ENC}

# Format /boot/firmware
mkfs.fat /dev/mapper/${LOOPDEVBASE}p1
mkdir -p ${WORKING_DIR}/root/boot/firmware
mkdir -p ${CROOT_FW}
mount /dev/mapper/${LOOPDEVBASE}p1 ${CROOT_FW}

# Use /enc for /home and some system things
mkdir -p ${CROOT_ENC}/home

mkdir -p ${CROOT_ENC}/system


PACKAGES="lvm2,apt-transport-https,wget,openssl,ca-certificates,"
PACKAGES+="apt-utils,net-tools,iproute2,cryptsetup-bin"

test -n "${ADD_PACKAGES}" && PACKAGES+=",${ADD_PACKAGES}"

debootstrap --arch=armhf \
	    --include=${PACKAGES} \
	    --components=main,contrib,non-free \
	    --variant=minbase --verbose --foreign \
	    ${VARIANT} \
	    ${CROOT} \
	    http://httpredir.debian.org/debian

cp /usr/bin/qemu-arm-static ${CROOT}/usr/bin

DEBIAN_FRONTEND=noninteractive DEBCONF_NONINTERACTIVE_SEEN=true \
	       LC_ALL=C LANGUAGE=C LANG=C chroot ${CROOT} \
	       /debootstrap/debootstrap --second-stage

DEBIAN_FRONTEND=noninteractive DEBCONF_NONINTERACTIVE_SEEN=true \
	       LC_ALL=C LANGUAGE=C LANG=C chroot ${CROOT} \
	       dpkg --configure -a

function cr() {
    chroot ${CROOT} /usr/bin/qemu-arm-static $@
}

echo "deb https://repositories.collabora.co.uk/debian jessie rpi2" \
     >> ${CROOT}/etc/apt/sources.list

cat <<EOF >${CROOT}/chroot_cmd.sh
#!/bin/bash

set -e
set -x

export DEBIAN_FRONTEND=noninteractive
export DEBCONF_NONINTERACTIVE_SEEN=true
export LC_ALL=C
export LANGUAGE=C
export LANG=C

function icleanup() {
    umount /proc || true
    umount /sys || true
}
trap icleanup EXIT

if test -n "${PROXY}";
then
    export http_proxy=${PROXY}
    export https_proxy=${PROXY}
fi

# mount /proc /sys /dev
mount -t proc none /proc
mount -t sysfs none /sys

echo "exit 101" >/usr/sbin/policy-rc.d
chmod a+x /usr/sbin/policy-rc.d

# 'true' needed because key not available at this point of time
apt-get --yes update || true 
apt-get --force-yes --yes install collabora-obs-archive-keyring || true
# This should do now without 'true': key is now available.
apt-get --yes update

apt-get --yes install linux-image-3.18.0-trunk-rpi2
apt-get --yes install raspberrypi-bootloader-nokernel
apt-get --yes install flash-kernel

mv /home /enc
ln -sf /enc/home /home

useradd --create-home dummy
chpasswd <<LEOF
root:qwe
dummy:qwe
LEOF

apt-get clean

EOF
chmod a+x ${CROOT}/chroot_cmd.sh

cr /bin/bash -x -e /chroot_cmd.sh

VMLINUZ="$(ls -1 ${CROOT}/boot/vmlinuz-* | sort | tail -n 1)"
test -z "${VMLINUZ}" && exit 1
cp ${VMLINUZ} ${CROOT}/boot/firmware/kernel7.img
INITRD="$(ls -1 ${CROOT}/boot/initrd.img-* | sort | tail -n 1)"
test -z "${INITRD}" && exit 1
cp ${INITRD} ${CROOT}/boot/firmware/initrd7.img

cat <<EOF >${CROOT}/etc/fstab
proc            /proc           proc    defaults          0       0
/dev/mmcblk0p2  /               ext4    defaults,noatime  0       1
/dev/mmcblk0p1  /boot/firmware  vfat    defaults          0       2
/dev/rpi2vg/enc_vol  /enc       ext4    defaults          0       2
EOF

echo debianrpi2 >${CROOT}/etc/hostname

cat <<EOF >${CROOT}/etc/hosts
127.0.0.1       localhost
::1             localhost ip6-localhost ip6-loopback
ff02::1         ip6-allnodes
ff02::2         ip6-allrouters

127.0.1.1       debianrpi2
EOF

cat <<EOF >${CROOT}/etc/network/interfaces.d/lo
# The loopback network interface
auto lo
iface lo inet loopback
EOF

cat <<EOF >${CROOT}/etc/network/interfaces.d/eth0
# The primary network interface
allow-hotplug eth0
iface eth0 inet dhcp
EOF

# Set up firmware config
cat <<EOF >${CROOT}/boot/firmware/config.txt
# For more options and information see 
# http://www.raspberrypi.org/documentation/configuration/config-txt.md
# Some settings may impact device functionality. See link above for details

EOF

echo 'dwc_otg.lpm_enable=0 console=tty1 root=/dev/mmcblk0p2 elevator=deadline rootfstype=ext4 rootwait' > ${CROOT}/boot/firmware/cmdline.txt

# XXX There are two links created - I have no idea why and whereto
# ln -sf ${CROOT}/... config
# ln -sf ${CROOT}/... cmdline

# Load sound module on boot
mkdir -p ${CROOT}/lib/modules-load.d
cat <<EOF >${CROOT}/lib/modules-load.d/rpi2.conf
snd_bcm2835
bcm2708_rng
EOF

# Blacklist platform modules not applicable to the RPi2
cat <<EOF >${CROOT}/etc/modprobe.d/rpi2.conf
blacklist snd_soc_pcm512x_i2c
blacklist snd_soc_pcm512x
blacklist snd_soc_tas5713
blacklist snd_soc_wm8804
EOF

cat <<EOF >${CROOT}/etc/crypttab
# <target name> <source device>         <key file>      <options>
lvm /dev/mmcblk0p3 /dev/disk/by-id/${ENC_DISK_ID} luks,tries=3,keyfile-size=4096,keyfile-offset=512
EOF

test -n "${USER_CHROOT_SH}" \
    && cp "${USER_CHROOT_SH}" ${CROOT}/user_chroot.sh \
    && cr /bin/bash -x -e /user_chroot.sh \
    && rm ${CROOT}/user_chroot.sh

#echo "START"
#/bin/bash
#echo "CONTINUE"
