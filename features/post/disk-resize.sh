#!/bin/bash
#
# Create a script that can be executed to resize the /enc partition
# to the maximum size.
#

set -e
set -x

CROOT=$1

mkdir -p ${CROOT}/root
cat <<EOF >${CROOT}/root/resize_disk.sh
#!/bin/bash
set -e
parted /dev/mmcblk0 "resizepart 3 -1"
cryptsetup resize /dev/mapper/lvm
pvresize /dev/mapper/lvm
lvresize -l 100%FREE /dev/rpi2vg/enc_vol
resize2fs /dev/rpi2vg/enc_vol
EOF

chmod a+x ${CROOT}/root/resize_disk.sh
