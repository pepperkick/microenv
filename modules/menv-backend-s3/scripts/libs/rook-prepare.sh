#!/bin/bash

# ============================================================================
# Goal of this script is to create files in local disk and simulate them as block disks
# This is create only for rook
#
# Steps
# - remove reference of old disks
# - delete old disks if any
# - create new fresh files of give size
# - configure tgt to use the files as lvm disks
# - use open-iscsi to login with tgt server
# - files will be exposed to OS as block disks
#
# Requirements
# - tgt
# - open-iscsi
# OR
# - targetcli
#
# Input
# - no of disks
# - size of each disk
# ============================================================================


function prepareTargetCli() {
  for i in $(seq -f "%02g" 1 $NUMBER_OF_DISKS); do
    rm $PWD/storage/disks/disk${i}.img || true
    targetcli /backstores/fileio delete disk${i} || true
    targetcli /backstores/fileio create disk${i} $PWD/storage/disks/disk${i}.img $DISK_SIZE write_back=false
  done

  targetcli /iscsi create iqn.2023-01.com.example.server || true

  for i in $(seq -f "%02g" 1 $NUMBER_OF_DISKS); do
    targetcli /iscsi/iqn.2023-01.com.example.server/tpg1/luns create /backstores/fileio/disk${i} || true
  done

  targetcli /iscsi/iqn.2023-01.com.example.server/tpg1/acls create iqn.2023-01.com.example.client || true
  targetcli /iscsi/iqn.2023-01.com.example.server/tpg1/acls/iqn.2023-01.com.example.client set auth userid=username
  targetcli /iscsi/iqn.2023-01.com.example.server/tpg1/acls/iqn.2023-01.com.example.client set auth password=password

  echo "InitiatorName=iqn.2023-01.com.example.client" > /etc/iscsi/initiatorname.iscsi

  sed -i "s/#node.session.auth.authmethod = CHAP/node.session.auth.authmethod = CHAP/" /etc/iscsi/iscsid.conf
  sed -i "s/#node.session.auth.username = username/node.session.auth.username = username/" /etc/iscsi/iscsid.conf
  sed -i "s/#node.session.auth.password = password/node.session.auth.password = password/" /etc/iscsi/iscsid.conf

  iscsiadm -m discovery -t sendtargets -p 127.0.0.1
  iscsiadm -m node --login
}

function prepareRook() {
  if which yum; then
    yum install --nogpgcheck -y targetcli iscsi-initiator-utils
  else
    echo "No supported package manager executable found! Exiting..."
    exit 1
  fi

  mkdir -p $PWD/storage/disks || true
  iscsiadm -m node --logout || true

  if which targetcli; then
    prepareTargetCli
    return 0
  fi

  echo "" > /etc/tgt/targets.conf

  for i in $(seq -f "%02g" 1 $NUMBER_OF_DISKS); do
      rm $PWD/storage/disks/disk${i}.img || true
      dd if=/dev/zero of=$PWD/storage/disks/disk${i}.img count=0 bs=1 seek=$DISK_SIZE

      CONTENTS=$(cat /etc/tgt/targets.conf)

  cat << EOL > "/etc/tgt/targets.conf"
$CONTENTS
<target iqn.2015-12.world.srv:target${i}>
    backing-store $PWD/storage/disks/disk${i}.img
    incominguser username password
</target>
EOL
  done

  set +e
  service open-iscsi status
  OI_EXISTS=$?
  service tgt status
  TGT_EXISTS=$?
  set -e

  if [[ $OI_EXISTS == 3 ]]; then
    service open-iscsi stop
  fi
  service iscsid stop

  if [[ $TGT_EXISTS == 3 ]]; then
    service tgt stop
    service tgt start
  else
    service tgtd stop
    service tgtd start
  fi

  service iscsid start
  iscsiadm -m discovery -t sendtargets -p 127.0.0.1

  if [[ $OI_EXISTS != 3 ]]; then
    sed -i "s/#node.session.auth.authmethod = CHAP/node.session.auth.authmethod = CHAP/" /etc/iscsi/iscsid.conf
    sed -i "s/#node.session.auth.username = username/node.session.auth.username = username/" /etc/iscsi/iscsid.conf
    sed -i "s/#node.session.auth.password = password/node.session.auth.password = password/" /etc/iscsi/iscsid.conf

    iscsiadm -m discovery -t sendtargets -p 127.0.0.1
    iscsiadm -m node --login
    return 0
  fi

  for i in $(seq -f "%02g" 1 $NUMBER_OF_DISKS); do
      sed -i 's/node.session.auth.authmethod = None/node.session.auth.authmethod = CHAP/' /etc/iscsi/nodes/iqn.2015-12.world.srv\:target${i}/127.0.0.1\,3260\,1/default
      sed -i 's/node.startup = manual/node.startup = automatic/' /etc/iscsi/nodes/iqn.2015-12.world.srv\:target${i}/127.0.0.1\,3260\,1/default
      echo "node.session.auth.username = username" >> /etc/iscsi/nodes/iqn.2015-12.world.srv\:target${i}/127.0.0.1\,3260\,1/default
      echo "node.session.auth.password = password" >> /etc/iscsi/nodes/iqn.2015-12.world.srv\:target${i}/127.0.0.1\,3260\,1/default
  done
  sudo service open-iscsi start
}