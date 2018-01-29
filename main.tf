provider "vsphere" {
  user           = "${var.vsphere_user}"
  password       = "${var.vsphere_password}"
  vsphere_server = "${var.vsphere_server}"
  allow_unverified_ssl = true
}

data "vsphere_datacenter" "dc" {
  name = "${var.datacenter}"
}

data "vsphere_datastore" "datastore" {
  count         = "${length(var.datastore)}"
  name          = "${element(var.datastore,count.index)}"
  datacenter_id = "${data.vsphere_datacenter.dc.id}"
}

data "vsphere_resource_pool" "pool" {
  name          = "${var.resource_pool}"
  datacenter_id = "${data.vsphere_datacenter.dc.id}"
}

data "vsphere_network" "network" {
  name          = "${var.network}"
  datacenter_id = "${data.vsphere_datacenter.dc.id}"
}

data "vsphere_virtual_machine" "template" {
  name          = "${lookup(var.template,var.osfamily)}"
  datacenter_id = "${data.vsphere_datacenter.dc.id}"
}

resource "tls_private_key" "ssh" {
  algorithm = "RSA"

  provisioner "local-exec" {
    command = "cat > vmware-key <<EOL\n${tls_private_key.ssh.private_key_pem}\nEOL"
  }
}
//master
resource "vsphere_virtual_machine" "master" {
  count            = "${var.master["nodes"]}"
  name             = "${format("%s-%s-%01d", lower(var.instance_prefix), lower(var.master["name"]),count.index + 1) }"
  resource_pool_id = "${data.vsphere_resource_pool.pool.id}"
  datastore_id     = "${element(data.vsphere_datastore.datastore.*.id, (replace(element(split(":",replace(timestamp(),"Z","")),2),"0","3") + index(var.vm_types, "master") + count.index ) % length(var.datastore))}"

  num_cpus = "${var.master["cpu_cores"]}"
  memory   = "${var.master["memory"]}"
  guest_id = "${data.vsphere_virtual_machine.template.guest_id}"

  scsi_type = "${data.vsphere_virtual_machine.template.scsi_type}"

  network_interface {
    network_id   = "${data.vsphere_network.network.id}"
    adapter_type = "${data.vsphere_virtual_machine.template.network_interface_types[0]}"
  }

  disk {
    label             = "${format("%s-%s-%01d.vmdk", lower(var.instance_prefix), lower(var.master["name"]),count.index + 1) }"
    size             = "${data.vsphere_virtual_machine.template.disks.0.size}"
    eagerly_scrub    = "${data.vsphere_virtual_machine.template.disks.0.eagerly_scrub}"
    thin_provisioned = "${data.vsphere_virtual_machine.template.disks.0.thin_provisioned}"
  }

  disk {
    label             = "${format("%s-%s-%01d_1.vmdk", lower(var.instance_prefix), lower(var.master["name"]),count.index + 1) }"
    size             = "${var.master["data_disk"]}"
    unit_number      = 1
    eagerly_scrub    = false
    thin_provisioned = false
  }

  clone {
    template_uuid = "${data.vsphere_virtual_machine.template.id}"

    customize {
      linux_options {
        host_name = "${format("%s-%s-%01d", lower(var.instance_prefix), lower(var.master["name"]),count.index + 1) }"
        domain    = "${var.vm_domain}"
        time_zone = "${var.timezone}"
      }

      network_interface {
        ipv4_address = "${trimspace(element(split(",",var.master["ipaddresses"]),count.index))}"
        ipv4_netmask = "${var.master["netmask"]}"
      }

      ipv4_gateway = "${var.master["gateway"]}"
      dns_server_list = "${var.dns_list}"
    }
  }
	
connection {
    type = "ssh"
    user = "${var.ssh_user}"
    password = "${var.ssh_password}"
  }
 
  provisioner "file" {
    content = "${count.index == 0 ? tls_private_key.ssh.private_key_pem : "none"}"
    destination = "${count.index == 0 ? "~/id_rsa" : "/dev/null" }"
  }

  provisioner "file" {
    source = "scripts/createfs_master.sh"
    destination = "/tmp/createfs.sh"
  }

  provisioner "remote-exec" {
    inline = [
      "echo ${var.ssh_password} | sudo -S echo",
      "echo \"${var.ssh_user} ALL=(ALL) NOPASSWD:ALL\" | sudo tee /etc/sudoers.d/${var.ssh_user}",
      "sudo sed -i /^127.0.1.1.*$/d /etc/hosts",
      "[ ! -d $HOME/.ssh ] && mkdir $HOME/.ssh && chmod 700 $HOME/.ssh",
      "echo \"${tls_private_key.ssh.public_key_openssh}\" | tee -a $HOME/.ssh/authorized_keys && chmod 600 $HOME/.ssh/authorized_keys",
      "[ -f ~/id_rsa ] && mv ~/id_rsa $HOME/.ssh/id_rsa && chmod 600 $HOME/.ssh/id_rsa",
      "chmod +x /tmp/createfs.sh; sudo /tmp/createfs.sh"
    ]
  }
}
//proxy
resource "vsphere_virtual_machine" "proxy" {
  count            = "${var.proxy["nodes"]}"
  name             = "${format("%s-%s-%01d", lower(var.instance_prefix), lower(var.proxy["name"]),count.index + 1) }"
  resource_pool_id = "${data.vsphere_resource_pool.pool.id}"
  datastore_id     = "${element(data.vsphere_datastore.datastore.*.id, (replace(element(split(":",replace(timestamp(),"Z","")),2),"0","3") + index(var.vm_types, "proxy") + count.index ) % length(var.datastore))}"

  num_cpus = "${var.proxy["cpu_cores"]}"
  memory   = "${var.proxy["memory"]}"
  guest_id = "${data.vsphere_virtual_machine.template.guest_id}"

  scsi_type = "${data.vsphere_virtual_machine.template.scsi_type}"

  network_interface {
    network_id   = "${data.vsphere_network.network.id}"
    adapter_type = "${data.vsphere_virtual_machine.template.network_interface_types[0]}"
  }

  disk {
    label             = "${format("%s-%s-%01d.vmdk", lower(var.instance_prefix), lower(var.proxy["name"]),count.index + 1) }"
    size             = "${data.vsphere_virtual_machine.template.disks.0.size}"
    eagerly_scrub    = "${data.vsphere_virtual_machine.template.disks.0.eagerly_scrub}"
    thin_provisioned = "${data.vsphere_virtual_machine.template.disks.0.thin_provisioned}"
  }

  disk {
    label             = "${format("%s-%s-%01d_1.vmdk", lower(var.instance_prefix), lower(var.proxy["name"]),count.index + 1) }"
    size             = "${var.proxy["data_disk"]}"
    unit_number      = 1
    eagerly_scrub    = false
    thin_provisioned = false
  }

  clone {
    template_uuid = "${data.vsphere_virtual_machine.template.id}"

    customize {
      linux_options {
        host_name = "${format("%s-%s-%01d", lower(var.instance_prefix), lower(var.proxy["name"]),count.index + 1) }"
        domain    = "${var.vm_domain}"
        time_zone = "${var.timezone}"
      }

      network_interface {
        ipv4_address = "${trimspace(element(split(",",var.proxy["ipaddresses"]),count.index))}"
        ipv4_netmask = "${var.proxy["netmask"]}"
      }

      ipv4_gateway = "${var.proxy["gateway"]}"
      dns_server_list = "${var.dns_list}"
    }
  }
	
connection {
    type = "ssh"
    user = "${var.ssh_user}"
    password = "${var.ssh_password}"
  }
 
  provisioner "file" {
    source = "scripts/createfs_proxy.sh"
    destination = "/tmp/createfs.sh"
  }

  provisioner "remote-exec" {
    inline = [
      "echo ${var.ssh_password} | sudo -S echo",
      "echo \"${var.ssh_user} ALL=(ALL) NOPASSWD:ALL\" | sudo tee /etc/sudoers.d/${var.ssh_user}",
      "sudo sed -i /^127.0.1.1.*$/d /etc/hosts",
      "[ ! -d $HOME/.ssh ] && mkdir $HOME/.ssh && chmod 700 $HOME/.ssh",
      "echo \"${tls_private_key.ssh.public_key_openssh}\" | tee -a $HOME/.ssh/authorized_keys && chmod 600 $HOME/.ssh/authorized_keys",
      "[ -f ~/id_rsa ] && mv ~/id_rsa $HOME/.ssh/id_rsa && chmod 600 $HOME/.ssh/id_rsa",
      "chmod +x /tmp/createfs.sh; sudo /tmp/createfs.sh"
    ]
  }
}
//management
resource "vsphere_virtual_machine" "management" {
  count            = "${var.management["nodes"]}"
  name             = "${format("%s-%s-%01d", lower(var.instance_prefix), lower(var.management["name"]),count.index + 1) }"
  resource_pool_id = "${data.vsphere_resource_pool.pool.id}"
  datastore_id     = "${element(data.vsphere_datastore.datastore.*.id, (replace(element(split(":",replace(timestamp(),"Z","")),2),"0","3") + index(var.vm_types, "management") + count.index ) % length(var.datastore))}"

  num_cpus = "${var.management["cpu_cores"]}"
  memory   = "${var.management["memory"]}"
  guest_id = "${data.vsphere_virtual_machine.template.guest_id}"

  scsi_type = "${data.vsphere_virtual_machine.template.scsi_type}"

  network_interface {
    network_id   = "${data.vsphere_network.network.id}"
    adapter_type = "${data.vsphere_virtual_machine.template.network_interface_types[0]}"
  }

  disk {
    label             = "${format("%s-%s-%01d.vmdk", lower(var.instance_prefix), lower(var.management["name"]),count.index + 1) }"
    size             = "${data.vsphere_virtual_machine.template.disks.0.size}"
    eagerly_scrub    = "${data.vsphere_virtual_machine.template.disks.0.eagerly_scrub}"
    thin_provisioned = "${data.vsphere_virtual_machine.template.disks.0.thin_provisioned}"
  }

  disk {
    label             = "${format("%s-%s-%01d_1.vmdk", lower(var.instance_prefix), lower(var.management["name"]),count.index + 1) }"
    size             = "${var.management["data_disk"]}"
    unit_number      = 1
    eagerly_scrub    = false
    thin_provisioned = false
  }

  clone {
    template_uuid = "${data.vsphere_virtual_machine.template.id}"

    customize {
      linux_options {
        host_name = "${format("%s-%s-%01d", lower(var.instance_prefix), lower(var.management["name"]),count.index + 1) }"
        domain    = "${var.vm_domain}"
        time_zone = "${var.timezone}"
      }

      network_interface {
        ipv4_address = "${trimspace(element(split(",",var.management["ipaddresses"]),count.index))}"
        ipv4_netmask = "${var.management["netmask"]}"
      }

      ipv4_gateway = "${var.management["gateway"]}"
      dns_server_list = "${var.dns_list}"
    }
  }
	
connection {
    type = "ssh"
    user = "${var.ssh_user}"
    password = "${var.ssh_password}"
  }
 
  provisioner "file" {
    source = "scripts/createfs_management.sh"
    destination = "/tmp/createfs.sh"
  }

  provisioner "remote-exec" {
    inline = [
      "echo ${var.ssh_password} | sudo -S echo",
      "echo \"${var.ssh_user} ALL=(ALL) NOPASSWD:ALL\" | sudo tee /etc/sudoers.d/${var.ssh_user}",
      "sudo sed -i /^127.0.1.1.*$/d /etc/hosts",
      "[ ! -d $HOME/.ssh ] && mkdir $HOME/.ssh && chmod 700 $HOME/.ssh",
      "echo \"${tls_private_key.ssh.public_key_openssh}\" | tee -a $HOME/.ssh/authorized_keys && chmod 600 $HOME/.ssh/authorized_keys",
      "[ -f ~/id_rsa ] && mv ~/id_rsa $HOME/.ssh/id_rsa && chmod 600 $HOME/.ssh/id_rsa",
      "chmod +x /tmp/createfs.sh; sudo /tmp/createfs.sh"
    ]
  }
}
//worker
resource "vsphere_virtual_machine" "worker" {
  count            = "${var.worker["nodes"]}"
  name             = "${format("%s-%s-%01d", lower(var.instance_prefix), lower(var.worker["name"]),count.index + 1) }"
  resource_pool_id = "${data.vsphere_resource_pool.pool.id}"
  datastore_id     = "${element(data.vsphere_datastore.datastore.*.id, (replace(element(split(":",replace(timestamp(),"Z","")),2),"0","3") + index(var.vm_types, "worker") + count.index ) % length(var.datastore))}"

  num_cpus = "${var.worker["cpu_cores"]}"
  memory   = "${var.worker["memory"]}"
  guest_id = "${data.vsphere_virtual_machine.template.guest_id}"

  scsi_type = "${data.vsphere_virtual_machine.template.scsi_type}"

  network_interface {
    network_id   = "${data.vsphere_network.network.id}"
    adapter_type = "${data.vsphere_virtual_machine.template.network_interface_types[0]}"
  }

  disk {
    label             = "${format("%s-%s-%01d.vmdk", lower(var.instance_prefix), lower(var.worker["name"]),count.index + 1) }"
    size             = "${data.vsphere_virtual_machine.template.disks.0.size}"
    eagerly_scrub    = "${data.vsphere_virtual_machine.template.disks.0.eagerly_scrub}"
    thin_provisioned = "${data.vsphere_virtual_machine.template.disks.0.thin_provisioned}"
  }

  disk {
    label             = "${format("%s-%s-%01d_1.vmdk", lower(var.instance_prefix), lower(var.worker["name"]),count.index + 1) }"
    size             = "${var.worker["data_disk"]}"
    unit_number      = 1
    eagerly_scrub    = false
    thin_provisioned = false
  }

  clone {
    template_uuid = "${data.vsphere_virtual_machine.template.id}"

    customize {
      linux_options {
        host_name = "${format("%s-%s-%01d", lower(var.instance_prefix), lower(var.worker["name"]),count.index + 1) }"
        domain    = "${var.vm_domain}"
        time_zone = "${var.timezone}"
      }

      network_interface {
        ipv4_address = "${trimspace(element(split(",",var.worker["ipaddresses"]),count.index))}"
        ipv4_netmask = "${var.worker["netmask"]}"
      }

      ipv4_gateway = "${var.worker["gateway"]}"
      dns_server_list = "${var.dns_list}"
    }
  }
	
connection {
    type = "ssh"
    user = "${var.ssh_user}"
    password = "${var.ssh_password}"
  }
 
  provisioner "file" {
    source = "scripts/createfs_worker.sh"
    destination = "/tmp/createfs.sh"
  }

  provisioner "remote-exec" {
    inline = [
      "echo ${var.ssh_password} | sudo -S echo",
      "echo \"${var.ssh_user} ALL=(ALL) NOPASSWD:ALL\" | sudo tee /etc/sudoers.d/${var.ssh_user}",
      "sudo sed -i /^127.0.1.1.*$/d /etc/hosts",
      "[ ! -d $HOME/.ssh ] && mkdir $HOME/.ssh && chmod 700 $HOME/.ssh",
      "echo \"${tls_private_key.ssh.public_key_openssh}\" | tee -a $HOME/.ssh/authorized_keys && chmod 600 $HOME/.ssh/authorized_keys",
      "[ -f ~/id_rsa ] && mv ~/id_rsa $HOME/.ssh/id_rsa && chmod 600 $HOME/.ssh/id_rsa",
      "chmod +x /tmp/createfs.sh; sudo /tmp/createfs.sh"
    ]
  }
}
//spawn ICP Installation
module "icpprovision" {
  source = "github.com/pjgunadi/terraform-module-icp-deploy"
  //Connection IPs
  icp-ips = "${concat(vsphere_virtual_machine.master.*.default_ip_address, vsphere_virtual_machine.proxy.*.default_ip_address, vsphere_virtual_machine.management.*.default_ip_address, vsphere_virtual_machine.worker.*.default_ip_address)}"
  boot-node = "${element(vsphere_virtual_machine.master.*.default_ip_address, 0)}"

  //Configuration IPs
  icp-master = ["${vsphere_virtual_machine.master.*.default_ip_address}"] //private_ip
  icp-worker = ["${vsphere_virtual_machine.worker.*.default_ip_address}"] //private_ip
  icp-proxy = ["${vsphere_virtual_machine.proxy.*.default_ip_address}"] //private_ip
  icp-management = ["${vsphere_virtual_machine.management.*.default_ip_address}"] //private_ip

  icp-version = "${var.icp_version}"

  icp_source_server = "${var.icp_source_server}"
  icp_source_user = "${var.icp_source_user}"
  icp_source_password = "${var.icp_source_password}"
  image_file = "${var.icp_source_path}"

  /* Workaround for terraform issue #10857
  When this is fixed, we can work this out autmatically */
  cluster_size  = "${var.master["nodes"] + var.worker["nodes"] + var.proxy["nodes"] + var.management["nodes"]}"

  icp_configuration = {
    "network_cidr"              = "${var.network_cidr}"
    "service_cluster_ip_range"  = "${var.cluster_ip_range}"
    "ansible_user"              = "${var.ssh_user}"
    "ansible_become"            = "${var.ssh_user == "root" ? false : true}"
    "default_admin_password"    = "${var.icpadmin_password}"
    "calico_ipip_enabled"       = "true"
    "cluster_access_ip"         = "${var.cluster_access_ip == "" ? element(vsphere_virtual_machine.master.*.default_ip_address, 0) : var.cluster_access_ip}"
    "proxy_access_ip"           = "${var.proxy_access_ip == "" ? element(vsphere_virtual_machine.proxy.*.default_ip_address, 0) : var.proxy_access_ip}"
  }

  generate_key = true
  #icp_pub_keyfile = "${tls_private_key.ssh.public_key_openssh}"
  #icp_priv_keyfile = "${tls_private_key.ssh.private_key_pem"}"
  
  ssh_user  = "${var.ssh_user}"
  ssh_key   = "${tls_private_key.ssh.private_key_pem}"
} 
