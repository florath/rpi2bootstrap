#
# This handles the initramfs build by init4boot
#

CMD=$1

function init4boot_prepare_contrib() {
    cd ${CONTRIB_DIR}
    if test -e init4boot; then
	(cd init4boot && git pull)
    else
	git clone https://github.com/florath/init4boot.git
    fi
}

function init4boot_initrd_create() {
    KERNEL_DESC=$( (cd ${CROOT}/lib/modules && echo *) )

    ${CONTRIB_DIR}/init4boot/i4b-mkinitramfs \
		  --output=${CROOT}/boot/initrd.img-${KERNEL_DESC} \
		  --root-dir=${CROOT} --plugins=${CONTRIB_DIR}/init4boot
}

function init4boot_initrd_install() {
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
    prepare_contrib)
	init4boot_prepare_contrib
	;;
    initrd_create)
	init4boot_initrd_create
	;;
    initrd_install)
	init4boot_initrd_install
	;;
esac
