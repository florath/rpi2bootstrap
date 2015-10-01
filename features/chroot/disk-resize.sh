#!/bin/bash
#
# Create a script that can be executed to resize the /enc partition
# to the maximum size.
#

set -e
set -x

CROOT=$1

apt-get --yes install parted

