#!/bin/bash
#
# Create a Debian Jessie Rasperry Pi 2 Image
#

set -e

BINDIR=$(dirname $0)
PKGDIR=$(dirname ${BINDIR})
MODULES_DIR=$(realpath ${PKGDIR}/modules)

WORKING_DIR=""
DISTRIBUTION="debian"
VARIANT="jessie"
IMAGE_SIZE="2G"
PROXY=""
ADD_PACKAGES=""
USER_MODULES_DIR=""
MODULES=""
APT_PROXY=""
APT_MIRROR="http://httpredir.debian.org/debian"

function usage() {
    test -n "$1" && echo "*** ERROR: $1" >&2
    cat <<EOF >&2
Usage: create_debian_rpi_img 
          --working-dir working_dir [--size image_size]
          --distribution distribution --variant variant 
          [--packages pkglist] [--proxy proxy] [--modules-dir mod_dir]
where
  working_dir  is the place where the image is build
               Some gigs of HD space should be available there.
  image_size   [optional] the initial image size, e.g. '2G' (default: '1G')
  distribution [optional] one of debian or ubuntu (default 'debian')
  variant      [optional] the version, like jessie, stretch or wily
               (default 'jessie')
  pkglist      [optional] comma separated list of additional packages
  proxy        [optional] when there is the need to set the http(s)_proxy
               set this to the appropriate url
  apt-mirror   [optional] use the given mirror for bootstrapping
               (default 'http://httpredir.debian.org/debian')
  apt-proxy    [optional] use the proxy for downloading packages
  modules_dir  [optional] Directory with user defined modules
  modules      [optional] Space seperated list of additional features.
               Existing modules are:
EOF
    
    # Look for buildin modules
    for module in ${MODULES_DIR}/*.sh; do
	. ${module} usage
    done

    # If the user module dir is set - have also a look there.
    if test -n "${USER_MODULES_DIR}"; then
	for module in ${USER_MODULES_DIR}/*.sh; do
	    . ${module} usage
	done
    fi
    
    exit 1
}

LONGOPTSSTR="help,working-dir:,distribution:,variant:,size:,"
LONGOPTSSTR+="packages:,proxy:,modules-dir:,apt-proxy:,apt-mirror:"

ARGS=$(getopt --options h \
	      --longoptions ${LONGOPTSSTR} \
	      -n create_debian_rpi2_img -- "$@")
test $? -ne 0 && exit 1

eval set -- "$ARGS";

while true;
do
    case "$1" in
	--distribution)
	    shift; DISTRIBUTION=$1 ;shift
	    ;;
	--proxy)
	    shift; PROXY=$1; shift
	    ;;
	--variant)
	    shift; VARIANT=$1; shift
	    ;;
	--modules-dir)
	    shift; USER_MODULES_DIR=$1; shift
	    ;;
	-h|--help)
	    usage ""
	    ;;
	--packages)
	    shift; ADD_PACKAGES=$1; shift
	    ;;
	--size)
	    shift; IMAGE_SIZE=$1; shift
	    ;;
	--working-dir)
	    shift; WORKING_DIR=$1; shift
	    ;;
	--apt-proxy)
	    shift; APT_PROXY=$1; shift
	    ;;
	--apt-mirror)
	    shift; APT_MIRROR=$1; shift
	    ;;
	--)
	    shift; break;
	    ;;
    esac
done

# The rest are the modules (with possible configuation options)
# Add the system modules: kernel and boot thingies
MODULES="armtools: init4boot: kernel: uboot: $@"

test -z "${WORKING_DIR}" && usage "working dir [-w] not set"
test -z "${DISTRIBUTION}" && usage "distribution [-d] not set"
test -z "${VARIANT}" && usage "variant [-v] not set"
test -z "${IMAGE_SIZE}" && usage "image size [-v] not set"

if test -n "${PROXY}";
then
    export http_proxy=${PROXY}
    export https_proxy=${PROXY}
fi

IMAGE_PATH=${WORKING_DIR}/rpi2-${DISTRIBUTION}-${VARIANT}.img

mkdir -p ${WORKING_DIR}
CONTRIB_DIR=${WORKING_DIR}/contrib
mkdir -p ${CONTRIB_DIR}
# This is the place where the new image will be bootstraped.
CROOT=${WORKING_DIR}/root
mkdir -p ${CROOT}
CROOT_FW=${CROOT}/boot/firmware
CROOT_ENC=${CROOT}

# If something nasty happens: cleanup
function cleanup() {
    umount ${CROOT}/proc 2>/dev/null || true
    umount ${CROOT}/sys 2>/dev/null || true
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

function execute_modules() {
    PHASE=$1

    # Do not use "" here: USER_MODULES_DIR can be empty.
    for modwparam in ${MODULES}; do
	module=$(echo ${modwparam} | cut -d ":" -f 1)
	modparams=$(echo ${modwparam} | cut -d ":" -f 2-)
	for mdir in ${MODULES_DIR} ${USER_MODULES_DIR}; do
	    if test -e ${mdir}/${module}.sh; then
		. ${mdir}/${module}.sh ${PHASE} ${modparams}
	    fi
	done
    done
}

# Start working on the image

cd ${WORKING_DIR}

execute_modules prepare_tools
execute_modules prepare_contrib

# Remove a possible old and create a new image
rm -f ${IMAGE_PATH}
dd if=/dev/zero of=${IMAGE_PATH} bs=1 count=1024 seek=${IMAGE_SIZE} 2>/dev/null

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
for p in 1 2;
do
    while test ! -e /dev/mapper/${LOOPDEVBASE}p${p};
    do
	sleep 0.2
    done
done

execute_modules prepare_disk

# Format /boot/firmware
mkfs.fat /dev/mapper/${LOOPDEVBASE}p1
mkdir -p ${CROOT_FW}
mount /dev/mapper/${LOOPDEVBASE}p1 ${CROOT_FW}

# PACKAGES needs some initializations and also a prefix
# that do not end the line with a comma
PACKAGES="apt-transport-https,openssl,ca-certificates,python-minimal,"
execute_modules package_dep
PACKAGES+="apt-utils,net-tools,iproute2,ifupdown"

test -n "${ADD_PACKAGES}" && PACKAGES+=",${ADD_PACKAGES}"

(
    if test -n "${APT_PROXY}"; then
	export http_proxy=${APT_PROXY}
	export https_proxy=${APT_PROXY}
    fi
    debootstrap --arch=armhf \
		--include=${PACKAGES} \
		--components=main,contrib,non-free \
		--variant=minbase --verbose --foreign \
		${VARIANT} \
		${CROOT} \
		${APT_MIRROR}
)

# Re-set the http(s)_proxy
if test -n "${PROXY}";
then
    export http_proxy=${PROXY}
    export https_proxy=${PROXY}
fi

cp /usr/bin/qemu-arm-static ${CROOT}/usr/bin

DEBIAN_FRONTEND=noninteractive DEBCONF_NONINTERACTIVE_SEEN=true \
	       LC_ALL=C LANGUAGE=C LANG=C chroot ${CROOT} \
	       /debootstrap/debootstrap --second-stage

DEBIAN_FRONTEND=noninteractive DEBCONF_NONINTERACTIVE_SEEN=true \
	       LC_ALL=C LANGUAGE=C LANG=C chroot ${CROOT} \
	       dpkg --configure -a

execute_modules pre_chroot

function cr() {
    chroot ${CROOT} /usr/bin/qemu-arm-static $@
}

echo "deb https://repositories.collabora.co.uk/debian jessie rpi2" \
     > ${CROOT}/etc/apt/sources.list.d/collabora.list

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

#apt-get --yes install linux-image-3.18.0-trunk-rpi2
apt-get --yes install raspberrypi-bootloader-nokernel
apt-get --yes install flash-kernel

##mv /home /enc
##ln -sf /enc/home /home

useradd --create-home --shell /bin/bash dummy
chpasswd <<LEOF
root:qwe
dummy:qwe
LEOF

#echo "deb http://httpredir.debian.org/debian jessie main contrib non-free"
#     > /etc/apt/sources.list

apt-get --yes update

apt-get clean

EOF
chmod a+x ${CROOT}/chroot_cmd.sh

cr /bin/bash -x -e /chroot_cmd.sh

# Copy the scripts to the chroot
mkdir -p ${CROOT}/chroot
for modwparam in ${MODULES}; do
    module=$(echo ${modwparam} | cut -d ":" -f 1)
    modparams=$(echo ${modwparam} | cut -d ":" -f 2-)
    for mdir in ${MODULES_DIR} ${USER_MODULES_DIR}; do
	if test -e ${mdir}/${module}.sh; then
	    cp ${mdir}/${module}.sh ${CROOT}/chroot
	    chmod a+x ${CROOT}/chroot/${module}.sh
	    echo "/chroot/${module}.sh chroot ${modparams}" \
		 >>${CROOT}/chroot_user.sh
	fi
    done
done

chmod a+x ${CROOT}/chroot_user.sh
cr /bin/bash -x -e /chroot_user.sh

cat <<EOF >${CROOT}/etc/fstab
proc            /proc           proc    defaults          0       0
/dev/rpi2vg/enc_vol  /          ext4    defaults,noatime  0       1
/dev/mmcblk0p1  /boot/firmware  vfat    defaults          0       2
EOF

echo debianrpi2 >${CROOT}/etc/hostname

cat <<EOF >${CROOT}/etc/hosts
127.0.0.1       localhost
::1             localhost ip6-localhost ip6-loopback
ff02::1         ip6-allnodes
ff02::2         ip6-allrouters

127.0.1.1       debianrpi2
EOF

mkdir -p ${CROOT}/etc/network
cat <<EOF >${CROOT}/etc/network/interfaces
source /etc/network/interfaces.d/*.cfg
EOF

mkdir -p ${CROOT}/etc/network/interfaces.d
cat <<EOF >${CROOT}/etc/network/interfaces.d/lo.cfg
# The loopback network interface
auto lo
iface lo inet loopback
EOF

cat <<EOF >${CROOT}/etc/network/interfaces.d/eth0.cfg
# The primary network interface
allow-hotplug eth0
iface eth0 inet dhcp
EOF

# Set up firmware config
cat <<EOF >${CROOT}/boot/firmware/config.txt
# For more options and information see 
# http://www.raspberrypi.org/documentation/configuration/config-txt.md
# Some settings may impact device functionality. See link above for details
kernel=u-boot.bin
EOF

# Load sound module on boot
# ToDo: Handle this also in the initramfs
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

#cat <<EOF >${CROOT}/etc/crypttab
# <target name> <source device>         <key file>      <options>
#lvm /dev/mmcblk0p2 /dev/disk/by-id/${ENC_DISK_ID} luks,tries=3,keyfile-size=4096,keyfile-offset=512
#EOF

execute_modules post_chroot

# The initrd must be build at the end:
# in between there can be packages which possible change the behaviour
#cat <<EOF >${CROOT}/chroot_cmd.sh
#!/bin/bash
#
#set -e
#set -x
#
#export KERNEL_DESC=\$( (cd /lib/modules && echo *) )
#
## Include the cryptsetup thingies in each case
## (The current check of mkinitramfs fails in this case.)
#CRYPTSETUP=yes mkinitramfs -o /boot/initrd.img-\${KERNEL_DESC} \${KERNEL_DESC}
#EOF
#chmod a+x ${CROOT}/chroot_cmd.sh
#
#cr /bin/bash -x -e /chroot_cmd.sh

execute_modules initrd_prepare

execute_modules initrd_create

execute_modules initrd_install

# Remove the policy file
rm -f ${CROOT}/usr/sbin/policy-rc.d

echo "START"
/bin/bash
echo "CONTINUE"

