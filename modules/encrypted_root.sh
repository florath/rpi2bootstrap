#
# This handles the encrypted root directory
#
# Please note that currently the key will be stored on a USB stick
#

CMD=$1
CLP=$2

for param in $(echo ${CLP} | tr "," " "); do
    case ${param} in
	dev=*)
	    KEYDEVICE=${param#dev=}
	    ;;
	*)
	    echo "*** Invalid parameter for 'dev' [${param}]"
	    exit 1
	    ;;
    esac
done

function prepare_disk() {
    # Create the key
    # Create some random numbers
    test ! -e ${WORKING_DIR}/rpi2-usb-random.key && \
	dd if=/dev/urandom of=${WORKING_DIR}/rpi2-usb-random.key bs=512 count=60
    chmod 0400 ${WORKING_DIR}/rpi2-usb-random.key
    # Extract the key
    dd if=${WORKING_DIR}/rpi2-usb-random.key \
       of=${WORKING_DIR}/rpi2-enc.key bs=512 count=8

    echo "*** PLEASE copy over the random keys to the USB stick, e.g.:"
    echo "*** dd if=${WORKING_DIR}/rpi2-usb-random.key seek=1 of=${KEYDEVICE}"

    LOOPDEVENC=/dev/mapper/${LOOPDEVBASE}p2

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
    mount /dev/rpi2vg/enc_vol ${CROOT_ENC}
}

case ${CMD} in
    usage)
	echo "    encrypted_root the root partition will be encrypted"
	;;
    package_dep)
	PACKAGES+="lvm2,cryptsetup-bin,cryptsetup,"
	;;
    prepare_disk)
	prepare_disk
	;;
esac
