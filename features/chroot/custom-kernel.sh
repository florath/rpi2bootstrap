#!/bin/bash
#
# Build a custom kernel with SELinux enabled
#

set -e
set -x

export KERNEL_DESC=$( (cd /lib/modules && echo *) )
mkinitramfs -o /boot/initrd.img-${KERNEL_DESC} ${KERNEL_DESC}
