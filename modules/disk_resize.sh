#
# Creates a disk-resize script
#

CMD=$1

function disk_resize_post_chroot() {
    mkdir -p ${CROOT}/root/contrib
    cat <<EOF >${CROOT}/root/contrib/resize_disk.sh
#!/bin/bash
set -e
parted /dev/mmcblk0 "resizepart 2 -1"
cryptsetup resize /dev/mapper/decdisk
pvresize /dev/mapper/decdisk
lvresize -l 100%FREE /dev/rpi2vg/enc_vol
resize2fs /dev/rpi2vg/enc_vol
EOF

    chmod a+x ${CROOT}/root/contrib/resize_disk.sh
}

case ${CMD} in
    package_dep)
	PACKAGES+="parted,"
	;;
    post_chroot)
	disk_resize_post_chroot
	;;
esac
