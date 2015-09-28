#!/bin/bash
#
# Create a script that can be executed to resize the /enc partition
# to the maximum size.
#

set -e
set -x

CROOT=$1

cat <<EOF ${CROOT}/resize_disk.sh
#!/bin/bash
set -e
lvresize -l 100%FREE /dev/rpi2vg/enc_vol
cryptsetup resize rpi2vg-enc_vol
resize2fs /dev/rpi2vg/enc_vol
EOF

chmod a+x ${CROOT}/resize_disk.sh
