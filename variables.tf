variable vsphere_user {
  description = "vCenter user"
}

variable vsphere_password {
  description = "vCenter password"
}

variable vsphere_server {
  description = "vCenter server"
}

variable datacenter {
  description = "vCenter Datacenter"
}

variable datastore {
  description = "vCenter Datastore"
  type        = "list"
  default     = ["v3700_vol3_datastore", "v3700_vol4_datastore", "v3700_vol5_datastore"]
}

variable resource_pool {
  description = "vCenter Cluster/Resource pool"
}

variable network {
  description = "vCenter Network"
  default     = "VM Network"
}

variable osfamily {
  description = "Operating System"
  default     = "ubuntu"
}

variable template {
  description = "VM Template"
  type        = "map"

  default = {
    "redhat" = "rhel74_base"
    "ubuntu" = "ubuntu1604_base"
  }
}

variable storage_driver {
  description = "Docker Storage Driver"
  type        = "map"

  default = {
    "redhat" = "devicemapper"
    "ubuntu" = "overlay2"
  }
}

variable ssh_user {
  description = "VM Username"
}

variable ssh_password {
  description = "VM Password"
}

variable vm_domain {
  description = "VM Domain"
}

variable timezone {
  description = "Time Zone"
  default     = "Asia/Singapore"
}

variable dns_list {
  description = "DNS List"
  type        = "list"
}

variable vm_types {
  description = "VM Type List"
  type        = "list"
  default     = ["master", "proxy", "management", "worker", "va", "gluster"]
}

variable vm_private_key_file {
  default = "vmware-key"
}

##### ICP Instance details ######
variable "icp_version" {
  description = "ICP Version"
  default     = "2.1.0.1"
}

variable icp_source_server {
  default = ""
}

variable icp_source_user {
  default = ""
}

variable icp_source_password {
  default = ""
}

variable icp_source_path {
  default = ""
}

variable "icpadmin_password" {
  description = "ICP admin password"
  default     = "admin"
}

variable "network_cidr" {
  default = "172.16.0.0/16"
}

variable "cluster_ip_range" {
  default = "192.168.0.1/24"
}

variable "cluster_vip" {
  default = ""
}

variable "cluster_vip_iface" {
  default = "ens160"
}

variable "proxy_vip" {
  default = ""
}

variable "proxy_vip_iface" {
  default = "ens160"
}

variable "instance_prefix" {
  default = "icp"
}

variable install_gluster {
  default = false
}

variable "cluster_name" {
  default = "mycluster"
}

variable "disable_management" {
  default = ["va"]
}

variable "gluster_volume_type" {
  default = "none"
}

variable "heketi_admin_pwd" {
  default = "none"
}

variable "master" {
  type = "map"

  default = {
    nodes         = "1"
    name          = "master"
    cpu_cores     = "8"
    kubelet_lv    = "10"
    docker_lv     = "50"
    etcd_lv       = "4"
    registry_lv   = "20"
    management_lv = "20"
    memory        = "8192"
    ipaddresses   = "192.168.1.81"
    netmask       = "24"
    gateway       = "192.168.1.1"
  }
}

variable "proxy" {
  type = "map"

  default = {
    nodes       = "1"
    name        = "proxy"
    cpu_cores   = "4"
    kubelet_lv  = "10"
    docker_lv   = "40"
    memory      = "4096"
    ipaddresses = "192.168.1.84"
    netmask     = "24"
    gateway     = "192.168.1.1"
  }
}

variable "management" {
  type = "map"

  default = {
    nodes         = "1"
    name          = "mgmt"
    cpu_cores     = "8"
    kubelet_lv    = "10"
    docker_lv     = "40"
    management_lv = "50"
    memory        = "8192"
    ipaddresses   = "192.168.1.87"
    netmask       = "24"
    gateway       = "192.168.1.1"
  }
}

variable "va" {
  type = "map"

  default = {
    nodes         = "1"
    name          = "va"
    cpu_cores     = "8"
    kubelet_lv    = "10"
    docker_lv     = "40"
    management_lv = "50"
    memory        = "8192"
    ipaddresses   = "192.168.1.88"
    netmask       = "24"
    gateway       = "192.168.1.1"
  }
}

variable "worker" {
  type = "map"

  default = {
    nodes       = "3"
    name        = "worker"
    cpu_cores   = "8"
    kubelet_lv  = "10"
    docker_lv   = "70"
    memory      = "8192"
    ipaddresses = "192.168.1.90,192.168.1.91,192.168.1.92"
    netmask     = "24"
    gateway     = "192.168.1.1"
  }
}

variable "gluster" {
  type = "map"

  default = {
    nodes       = "0"
    name        = "gluster"
    cpu_cores   = "2"
    data_disk   = "100"                                    // GB
    memory      = "2048"
    ipaddresses = "192.168.1.95,192.168.1.96,192.168.1.97"
    netmask     = "24"
    gateway     = "192.168.1.1"
  }
}
