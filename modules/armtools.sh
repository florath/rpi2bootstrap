#
# Prepares the tools for arm
#
CMD=$1

function armtools_prepare_tools() {
    cd ${CONTRIB_DIR}
    if test ! -e tools;
    then
	git clone https://github.com/raspberrypi/tools tools
    fi

    export PATH=${CONTRIB_DIR}/tools/arm-bcm2708/gcc-linaro-arm-linux-gnueabihf-raspbian-x64/bin:${PATH}
}

case ${CMD} in
    prepare_tools)
	armtools_prepare_tools
	;;
esac
