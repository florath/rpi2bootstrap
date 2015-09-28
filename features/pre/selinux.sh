#!/bin/bash

set -e
set -x

CROOT=$1

mkdir ${CROOT}/root/debs
wget -O  ${CROOT}/root/debs/selinux-policy-default_2.20140421-11_all.deb \
     http://www.coker.com.au/dists/jessie/selinux/binary-amd64/selinux-policy-default_2.20140421-11_all.deb
