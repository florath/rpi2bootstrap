#
# Handles SELinux
#
CMD=$1

#
# There is currently a problem with Debian Jessie default policy
# Therefore a special handling is needed
#

function selinux_pre_chroot() {
    mkdir -p ${CROOT}/etc/ssh/auth_keys
    
    mkdir -p ${CROOT}/root/contrib/debs
    wget -O  ${CROOT}/root/contrib/debs/selinux-policy-default_2.20140421-11_all.deb \
     http://www.coker.com.au/dists/jessie/selinux/binary-amd64/selinux-policy-default_2.20140421-11_all.deb
}

function selinux_chroot() {
    dpkg -i /root/contrib/debs/selinux-policy-default_2.20140421-11_all.deb
    apt-get --yes install selinux-basics auditd
    ## XXX if everything is tested:
    # selinux-activate

}

function selinux_chroot() {
    mkdir -p ${CROOT}/root/contrib/
    cat <<EOF >${CROOT}/root/contrib/selinux.sh
#!/bin/bash
selinux-activate
semanage fcontext -a -t ssh_home_t "/etc/ssh/auth_keys/.*"
restorecon -v -R /etc/ssh/auth_keys
EOF
    chmod a+x ${CROOT}/root/contrib/selinux.sh
}

case ${CMD} in
    package_dep)
	PACKAGES+="policycoreutils,python,selinux-utils,"
	PACKAGES+="puppet-module-puppetlabs-concat,"
	;;
    pre_chroot)
	selinux_pre_chroot
	;;
    post_chroot)
	selinux_post_chroot
	;;
    chroot)
	selinux_chroot
	;;
esac
