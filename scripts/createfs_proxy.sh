#!/bin/bash
#Create Physical Volumes
pvcreate /dev/sdb

#Create Volume Groups
vgcreate icp-vg /dev/sdb

#Create Logical Volumes
lvcreate -L 10G -n kubelet-lv icp-vg
lvcreate -L 40G -n docker-lv icp-vg

#Create Filesystems
mkfs.ext4 /dev/icp-vg/kubelet-lv
mkfs.ext4 /dev/icp-vg/docker-lv

#Create Directories
mkdir -p /var/lib/docker
mkdir -p /var/lib/kubelet

#Add mount in /etc/fstab
cat <<EOL | tee -a /etc/fstab
/dev/mapper/icp--vg-kubelet--lv /var/lib/kubelet ext4 defaults 0 0
/dev/mapper/icp--vg-docker--lv /var/lib/docker ext4 defaults 0 0
EOL

#Mount Filesystems
mount -a

#Disable password authentication on public network
sed -i "s/^PasswordAuthentication yes$/PasswordAuthentication no/" /etc/ssh/sshd_config
cat <<EOL | tee -a /etc/ssh/sshd_config

Match Address 10.0.0.0/8,172.16.0.0/12,192.168.0.0/16
    PasswordAuthentication yes
EOL
systemctl restart sshd