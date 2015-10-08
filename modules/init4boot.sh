#
# This handles the initramfs build by init4boot
#

CMD=$1

function initrd_install() {
    INITRD="$(ls -1 ${CROOT}/boot/initrd.img-* | sort | tail -n 1)"
    test -z "${INITRD}" && exit 1
    mkimage -A arm -O linux -T ramdisk -C gzip -a 0x00000000 -e 0x00000000 \
	    -n "RPi2 initrd" -d ${INITRD} ${CROOT_FW}/initrd7.img
    cp ${INITRD} ${CROOT_FW}/initrd7.org
}

case ${CMD} in
    package_dep)
	PACKAGES+="busybox,open-iscsi,aufs-tools,mdadm,multipath-tools,"
	PACKAGES+="kpartx,klibc-utils,"
	;;
    initrd_install)
	initrd_install
	;;
esac
