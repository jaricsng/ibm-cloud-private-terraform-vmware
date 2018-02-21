#!/bin/bash

#Storage Driver options: overlay2 (ubuntu) or devicemapper (rhel)
if [ -z "$1" ]; then
  STORDRIVER="overlay2"
else
  STORDRIVER=$1
fi

#Create Physical Volumes
pvcreate /dev/sdc

#Create Volume Groups
vgcreate docker /dev/sdc

createDevMapper() {
  #Create Logical Volumes
  lvcreate --wipesignatures y -n thinpool docker -l 95%VG
  lvcreate --wipesignatures y -n thinpoolmeta docker -l 1%VG

  #Convert Docker Thinpool
  lvconvert -y --zero n -c 512K --thinpool docker/thinpool --poolmetadata docker/thinpoolmeta

  #Configure auto extension
  mkdir -p /etc/lvm/profile
  cat <<EOL | tee -a /etc/lvm/profile/docker-thinpool.profile
activation {
  thin_pool_autoextend_threshold=80
  thin_pool_autoextend_percent=20
}
EOL

  #Apply LVM Profile
  lvchange --metadataprofile docker-thinpool docker/thinpool

  #Enable LV Monitoring
  lvs -o+seg_monitor

  #Configure Docker Daemon
  mkdir -p /etc/docker
  cat <<EOL | tee -a /etc/docker/daemon.json
{
  "storage-driver": "devicemapper",
  "storage-opts": [
    "dm.thinpooldev=/dev/mapper/docker-thinpool",
    "dm.use_deferred_removal=true",
    "dm.use_deferred_deletion=true"
  ]
}
EOL
}

createOverlay() {
  lvcreate -l 100%FREE -n docker-lv docker
  mkfs.ext4 /dev/docker/docker-lv
  mkdir -p /var/lib/docker
  #Add mount in /etc/fstab
  cat <<EOL | tee -a /etc/fstab
/dev/mapper/docker-docker--lv /var/lib/docker ext4 defaults 0 0
EOL
  #Mount Filesystems
  mount -a
}

if [ "$STORDRIVER" == "devicemapper" ]; then
  createDevMapper
else
  createOverlay
fi
