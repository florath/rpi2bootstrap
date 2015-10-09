#
# Prepares the hardening io
#
CMD=$1

function hardening_io_pre_chroot() {
    HARDENING_DIR=/usr/local/pkg/hardening-io
    CR_HARDENING_DIR=${CROOT}/${HARDENING_DIR}
    mkdir -p ${CR_HARDENING_DIR}
    (cd ${CR_HARDENING_DIR}

     git clone https://github.com/saz/puppet-ssh.git ssh
     (cd ssh && git checkout -b stable v2.8.1)
 
     git clone https://github.com/hardening-io/puppet-os-hardening.git \
	 os_hardening
     (cd os_hardening && git checkout -b stable 1.1.2)

     git clone https://github.com/hardening-io/puppet-ssh-hardening.git \
	 ssh_hardening
     (cd ssh_hardening && git checkout -b stable 1.0.5)

     git clone https://github.com/thias/puppet-sysctl.git sysctl
     (cd sysctl && git checkout -b stable 1.0.2)
    )

    cat <<EOF >${CR_HARDENING_DIR}/hardening_io.pp
class { hardening_io:
}
EOF

    mkdir -p ${CR_HARDENING_DIR}/hardening_io/manifests
    cat <<EOF >${CR_HARDENING_DIR}/hardening_io/manifests/init.pp
class hardening_io {
  # OS Hardening
  class {'os_hardening':
    enable_ipv6 => "false"
  }

  # SSH Hardening
  class { 'ssh_hardening':
    server_options => {
      'AuthorizedKeysFile' => '/etc/ssh/auth_keys/%u'
    }
  }
}
EOF

    mkdir -p ${CROOT}/etc/ssh/auth_keys

    echo "ssh-rsa AAAAB3NzaC1yc2EAAAADAQABAAAEAQCrOZsP0GJL3PFxZvgeORqjMApDA5PR3+c/YAXi+9u5gnc/ucTZGH67vPcl8fjHdKNS/WZu+I/MiFofYl1sAx2i5BEucPjth17Xm52ZiFE4IaHTCVCONlnWSrzL83VxzkqQePytggM59Vy9fzRymvvhIW6nWRCbUQj3DWsg+puHfEv2kKQAOHKzRqIYcU0gooc/Q8xPaAZ/+Hf3KO3J38vuSQGQr69K+44OW8rWb4/OZHOyqyEMt1lfXU4pWixEA4HwU7Qlup8dSEGxxn1fDSckyTG1QfI8tl2+z1MFWGyk+ba7lS4KAD2jW6d4gvCDMkIL9R4Cjl/8ZtiCcwXN9O0oxBj/bDsFQVC1prTIcHkZZXfkapd+tLUpjB3IPw44bR8LuDCM/rnh9QJIN/PtkpQebtf5G1bqTtHTlIvpqaaCEwQmizMrtsIyn8cSZ4Jv+HDK3azkiLSf8v3wZG3ZtXsunOBSffidFLm2GBFgUg1lq+1eG0doiYOLBpYjAfhwQF0Up7y1oXom6C1SmEdCC91iI6zqprkr0njFh04xpbTRa2tSGuCce7Fuxojq6Xzwd+ZaCuBxSpBFk2X+pVA3M8T8qp7FSi0cOQa/XtlIa2jvUS80ZLuG4xidNgt9rjpM1vPYxuds3AeqpOqnae3CXtftjfnikk3a4QTFpS4RRgxLMSI6GRbLwfjLoc88Qcxk0m37y6A0a9meesdN9X1zxo7QmnQuh7Ji6iBkC7nG21NNcgxX+ATfzikn0N82PbOQG+G84AJ6lZhlJwHe0hdOS4y0MloS4Zvtk2F/0BoazDoqsjRWDvKv1HbnVUlC/2As1oDXomjsEbOX3GgwXvV6iJhNyrr4dXxYkJTodSsoaB+Op2HuMu7QM3SbIGaf/+IwnipyEkTBbHvEmyaQRWjKhXhdSXsxI7KYTY5yKszUvzeH3ATHrQpSKutxomiaTCd17qwzMST68krVc8U5P6Qa2W/2/YnmCvw/sEfIlUYlAuuuJ8xQLO4/3IZjgJQQd4d2bgS1+OR8YHjxoaEwgpcrRJ83kkCNghvvPrZHxJ8RpPnGWClBaJrfe3ywid3VDC46+3tjx+fm8AqRMIY4TToAnMzRGCRdJRyxhqpcWfdNvaYbeSCvsQ5fCVyexSglPxXraBK/YdA7A3XpikvBoT6uNekcM2MgaexSDQrUWtjhjlo8XInFV9HanV9ga9HF4TBpNz1onUpodkBSUU+utRLtQuMKsDafz0PjXQCuk76iNWAb4x7QqVhPlpm2T5NL4Sr06y2D3/1VdWL58rQrxLbp+NmYe1+XHbRSWRuYOcXefTAaJG6d1sqEXSyMOH0SueZTNs42UbZ8i7bEqZqQh040pKgx dummy@nowhere" >${CROOT}/etc/ssh/auth_keys/dummy

    chmod 444 ${CROOT}/etc/ssh/auth_keys/dummy

    mkdir -p  ${CROOT}/root/contrib
    echo "puppet apply --modulepath=/etc/puppet/modules:/usr/share/puppet/modules:${HARDENING_DIR} ${HARDENING_DIR}/hardening_io.pp" >${CROOT}/root/contrib/hardening_io.sh
    chmod a+x ${CROOT}/root/contrib/hardening_io.sh
}

case ${CMD} in
    package_dep)
	PACKAGES+="puppet-module-puppetlabs-stdlib,puppet,"
	PACKAGES+="puppet-module-puppetlabs-concat,"
	;;
    pre_chroot)
	hardening_io_pre_chroot
	;;
esac
