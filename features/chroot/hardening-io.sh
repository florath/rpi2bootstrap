#!/bin/bash
#
# Prepare the hardening scripts
#

set -e
set -x

CROOT=$1

HARDENING_DIR=/usr/local/pkg/hardening-io

apt-get --yes install puppet puppet-module-puppetlabs-stdlib puppet-module-puppetlabs-concat

echo "puppet apply --modulepath=/etc/puppet/modules:/usr/share/puppet/modules:${HARDENING_DIR} ${HARDENING_DIR}/hardening_io.pp" >/root/hardening_io.sh
chmod a+x /root/hardening_io.sh

