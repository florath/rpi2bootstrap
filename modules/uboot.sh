#
# This is the uboot booting module
#

CMD=$1

function uboot_prepare_contrib() {
    cd ${CONTRIB_DIR}
    # Compile u-boot
    if test -e u-boot;
    then
	(cd u-boot && git pull)
    else
	git clone git://git.denx.de/u-boot.git
    fi

    cd u-boot
    make ARCH=arm CROSS_COMPILE=arm-linux-gnueabihf- rpi_2_defconfig
    make -j6 ARCH=arm CROSS_COMPILE=arm-linux-gnueabihf- all
}

function uboot_post_chroot() {
    cd ${CONTRIB_DIR}/u-boot
    cp u-boot.bin ${CROOT_FW}
    # Write u-boot config file
    cat <<EOF >${CROOT_FW}/boot.cfg
setenv fdtfile bcm2709-rpi-2-b.dtb

mmc dev 0
fatload mmc 0:1 \${kernel_addr_r} kernel7.img
fatload mmc 0:1 \${ramdisk_addr_r} initrd7.img
fatload mmc 0:1 \${fdt_addr_r} \${fdtfile}
setenv bootargs "ignore_loglevel loglevel=7 initrd=\${ramdisk_addr_r} rfs=exists:file=/dev/mmcblk0p2,wait=30;decrypt:dev=/dev/mmcblk0p2,name=decdisk,keyfile=/dev/disk/by-id/usb-Intenso_Rainbow_Line_77FBFA68-0:0,decmod=luks,tries=3,keyfile_size=4096,keyfile_offset=512;exists:file=/dev/mapper/decdisk,wait=15;lvm:scan;exists:file=/dev/rpi2vg/enc_vol;root:dev=/dev/rpi2vg/enc_vol bv=udev"
bootz \${kernel_addr_r} \${ramdisk_addr_r} \${fdt_addr_r}
EOF

    # Create scr file from config
    mkimage -A arm -O linux -T script -C none -a 0x00000000 -e 0x00000000 \
	    -n "RPi2 Boot Script" -d ${CROOT_FW}/boot.cfg ${CROOT_FW}/boot.scr
}

case ${CMD} in
    prepare_contrib)
	uboot_prepare_contrib
	;;
    post_chroot)
	uboot_post_chroot
	;;
esac
