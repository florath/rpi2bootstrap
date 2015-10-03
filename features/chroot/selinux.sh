#!/bin/bash

set -e
set -x

# This is the workaround - as long as the package is not in jessie
apt-get --yes install policycoreutils python selinux-utils
dpkg -i /root/debs/selinux-policy-default_2.20140421-11_all.deb
apt-get --yes install selinux-basics auditd 

# When everything is fixed:
# apt-get --yes install selinux-basics auditd selinux-policy-default
## XXX Problem!!! selinux-activate
