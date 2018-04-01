provider "vsphere" {
  user                 = "${var.vsphere_user}"
  password             = "${var.vsphere_password}"
  vsphere_server       = "${var.vsphere_server}"
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
    command = "cat > ${var.vm_private_key_file} <<EOL\n${tls_private_key.ssh.private_key_pem}\nEOL"
  }

  provisioner "local-exec" {
    command = "chmod 600 ${var.vm_private_key_file}"
  }
}

//Script template
data "template_file" "createfs_master" {
  template = "${file("${path.module}/lib/templates/createfs_master.sh.tpl")}"

  vars {
    kubelet_lv    = "${var.master["kubelet_lv"]}"
    docker_lv     = "${var.master["docker_lv"]}"
    etcd_lv       = "${var.master["etcd_lv"]}"
    registry_lv   = "${var.master["registry_lv"]}"
    management_lv = "${var.master["management_lv"]}"
  }
}

data "template_file" "createfs_proxy" {
  template = "${file("${path.module}/lib/templates/createfs_proxy.sh.tpl")}"

  vars {
    kubelet_lv = "${var.proxy["kubelet_lv"]}"
    docker_lv  = "${var.proxy["docker_lv"]}"
  }
}

data "template_file" "createfs_management" {
  template = "${file("${path.module}/lib/templates/createfs_management.sh.tpl")}"

  vars {
    kubelet_lv    = "${var.management["kubelet_lv"]}"
    docker_lv     = "${var.management["docker_lv"]}"
    management_lv = "${var.management["management_lv"]}"
  }
}

data "template_file" "createfs_va" {
  template = "${file("${path.module}/lib/templates/createfs_va.sh.tpl")}"

  vars {
    kubelet_lv = "${var.va["kubelet_lv"]}"
    docker_lv  = "${var.va["docker_lv"]}"
    va_lv      = "${var.va["va_lv"]}"
  }
}

data "template_file" "createfs_worker" {
  template = "${file("${path.module}/lib/templates/createfs_worker.sh.tpl")}"

  vars {
    kubelet_lv = "${var.worker["kubelet_lv"]}"
    docker_lv  = "${var.worker["docker_lv"]}"
  }
}

//locals
locals {
  icp_boot_node_ip = "${vsphere_virtual_machine.master.0.default_ip_address}"
  heketi_ip        = "${vsphere_virtual_machine.gluster.0.default_ip_address}"
  ssh_options      = "-o UserKnownHostsFile=/dev/null -o StrictHostKeyChecking=no"
}

//master
resource "vsphere_virtual_machine" "master" {
  lifecycle {
    ignore_changes = ["disk.0", "disk.1"]
  }

  count = "${var.master["nodes"]}"

  #count            = "${length(compact(split(",",var.master["ipaddresses"])))}"
  name             = "${format("%s-%s-%01d", lower(var.instance_prefix), lower(var.master["name"]),count.index + 1) }"
  resource_pool_id = "${data.vsphere_resource_pool.pool.id}"
  datastore_id     = "${element(data.vsphere_datastore.datastore.*.id, (index(var.vm_types, "master") + count.index ) % length(var.datastore))}"
  num_cpus         = "${var.master["cpu_cores"]}"
  memory           = "${var.master["memory"]}"
  guest_id         = "${data.vsphere_virtual_machine.template.guest_id}"
  scsi_type        = "${data.vsphere_virtual_machine.template.scsi_type}"

  network_interface {
    network_id   = "${data.vsphere_network.network.id}"
    adapter_type = "${data.vsphere_virtual_machine.template.network_interface_types[0]}"
  }

  disk {
    label            = "${format("%s-%s-%01d.vmdk", lower(var.instance_prefix), lower(var.master["name"]),count.index + 1) }"
    size             = "${data.vsphere_virtual_machine.template.disks.0.size}"
    eagerly_scrub    = "${data.vsphere_virtual_machine.template.disks.0.eagerly_scrub}"
    thin_provisioned = "${data.vsphere_virtual_machine.template.disks.0.thin_provisioned}"
  }

  disk {
    label            = "${format("%s-%s-%01d_1.vmdk", lower(var.instance_prefix), lower(var.master["name"]),count.index + 1) }"
    size             = "${var.master["kubelet_lv"] + var.master["docker_lv"] + var.master["registry_lv"] + var.master["etcd_lv"] + var.master["management_lv"] + 1}"
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

      ipv4_gateway    = "${var.master["gateway"]}"
      dns_server_list = "${var.dns_list}"
    }
  }

  connection {
    type     = "ssh"
    user     = "${var.ssh_user}"
    password = "${var.ssh_password}"
  }

  provisioner "file" {
    content     = "${count.index == 0 ? tls_private_key.ssh.private_key_pem : "none"}"
    destination = "${count.index == 0 ? "~/id_rsa" : "/dev/null" }"
  }

  provisioner "file" {
    content     = "${data.template_file.createfs_master.rendered}"
    destination = "/tmp/createfs.sh"
  }

  provisioner "file" {
    source      = "${path.module}/lib/scripts/"
    destination = "/tmp/"
  }

  provisioner "remote-exec" {
    inline = [
      "echo ${var.ssh_password} | sudo -S echo",
      "echo \"${var.ssh_user} ALL=(ALL) NOPASSWD:ALL\" | sudo tee /etc/sudoers.d/${var.ssh_user}",
      "sudo sed -i /^127.0.1.1.*$/d /etc/hosts",
      "[ ! -d $HOME/.ssh ] && mkdir $HOME/.ssh && chmod 700 $HOME/.ssh",
      "echo \"${tls_private_key.ssh.public_key_openssh}\" | tee -a $HOME/.ssh/authorized_keys && chmod 600 $HOME/.ssh/authorized_keys",
      "[ -f ~/id_rsa ] && mv ~/id_rsa $HOME/.ssh/id_rsa && chmod 600 $HOME/.ssh/id_rsa",
      "chmod +x /tmp/createfs.sh; sudo /tmp/createfs.sh",
      "chmod +x /tmp/disable_ssh_password.sh; sudo /tmp/disable_ssh_password.sh",
    ]
  }
}

//proxy
resource "vsphere_virtual_machine" "proxy" {
  lifecycle {
    ignore_changes = ["disk.0", "disk.1"]
  }

  count = "${var.proxy["nodes"]}"

  #count            = "${length(compact(split(",",var.proxy["ipaddresses"])))}"
  name             = "${format("%s-%s-%01d", lower(var.instance_prefix), lower(var.proxy["name"]),count.index + 1) }"
  resource_pool_id = "${data.vsphere_resource_pool.pool.id}"
  datastore_id     = "${element(data.vsphere_datastore.datastore.*.id, (index(var.vm_types, "proxy") + count.index ) % length(var.datastore))}"
  num_cpus         = "${var.proxy["cpu_cores"]}"
  memory           = "${var.proxy["memory"]}"
  guest_id         = "${data.vsphere_virtual_machine.template.guest_id}"
  scsi_type        = "${data.vsphere_virtual_machine.template.scsi_type}"

  network_interface {
    network_id   = "${data.vsphere_network.network.id}"
    adapter_type = "${data.vsphere_virtual_machine.template.network_interface_types[0]}"
  }

  disk {
    label            = "${format("%s-%s-%01d.vmdk", lower(var.instance_prefix), lower(var.proxy["name"]),count.index + 1) }"
    size             = "${data.vsphere_virtual_machine.template.disks.0.size}"
    eagerly_scrub    = "${data.vsphere_virtual_machine.template.disks.0.eagerly_scrub}"
    thin_provisioned = "${data.vsphere_virtual_machine.template.disks.0.thin_provisioned}"
  }

  disk {
    label            = "${format("%s-%s-%01d_1.vmdk", lower(var.instance_prefix), lower(var.proxy["name"]),count.index + 1) }"
    size             = "${var.proxy["kubelet_lv"] + var.proxy["docker_lv"] + 1}"
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

      ipv4_gateway    = "${var.proxy["gateway"]}"
      dns_server_list = "${var.dns_list}"
    }
  }

  connection {
    type     = "ssh"
    user     = "${var.ssh_user}"
    password = "${var.ssh_password}"
  }

  provisioner "file" {
    content     = "${data.template_file.createfs_proxy.rendered}"
    destination = "/tmp/createfs.sh"
  }

  provisioner "file" {
    source      = "${path.module}/lib/scripts/"
    destination = "/tmp/"
  }

  provisioner "remote-exec" {
    inline = [
      "echo ${var.ssh_password} | sudo -S echo",
      "echo \"${var.ssh_user} ALL=(ALL) NOPASSWD:ALL\" | sudo tee /etc/sudoers.d/${var.ssh_user}",
      "sudo sed -i /^127.0.1.1.*$/d /etc/hosts",
      "[ ! -d $HOME/.ssh ] && mkdir $HOME/.ssh && chmod 700 $HOME/.ssh",
      "echo \"${tls_private_key.ssh.public_key_openssh}\" | tee -a $HOME/.ssh/authorized_keys && chmod 600 $HOME/.ssh/authorized_keys",
      "[ -f ~/id_rsa ] && mv ~/id_rsa $HOME/.ssh/id_rsa && chmod 600 $HOME/.ssh/id_rsa",
      "chmod +x /tmp/createfs.sh; sudo /tmp/createfs.sh",
      "chmod +x /tmp/disable_ssh_password.sh; sudo /tmp/disable_ssh_password.sh",
    ]
  }

  provisioner "local-exec" {
    when    = "destroy"
    command = "cat > ${var.vm_private_key_file} <<EOL\n${tls_private_key.ssh.private_key_pem}\nEOL"
  }

  provisioner "local-exec" {
    when    = "destroy"
    command = "chmod 600 ${var.vm_private_key_file}"
  }

  provisioner "local-exec" {
    when    = "destroy"
    command = "scp -i ${var.vm_private_key_file} ${local.ssh_options} ${path.module}/lib/destroy/delete_node.sh ${var.ssh_user}@${local.icp_boot_node_ip}:/tmp/"
  }

  provisioner "local-exec" {
    when    = "destroy"
    command = "ssh -i ${var.vm_private_key_file} ${local.ssh_options} ${var.ssh_user}@${local.icp_boot_node_ip} \"chmod +x /tmp/delete_node.sh; /tmp/delete_node.sh ${var.icp_version} ${self.default_ip_address}\"; echo done"
  }
}

//management
resource "vsphere_virtual_machine" "management" {
  lifecycle {
    ignore_changes = ["disk.0", "disk.1"]
  }

  count = "${var.management["nodes"]}"

  #count            = "${length(compact(split(",",var.management["ipaddresses"])))}"
  name             = "${format("%s-%s-%01d", lower(var.instance_prefix), lower(var.management["name"]),count.index + 1) }"
  resource_pool_id = "${data.vsphere_resource_pool.pool.id}"
  datastore_id     = "${element(data.vsphere_datastore.datastore.*.id, (index(var.vm_types, "management") + count.index ) % length(var.datastore))}"
  num_cpus         = "${var.management["cpu_cores"]}"
  memory           = "${var.management["memory"]}"
  guest_id         = "${data.vsphere_virtual_machine.template.guest_id}"
  scsi_type        = "${data.vsphere_virtual_machine.template.scsi_type}"

  network_interface {
    network_id   = "${data.vsphere_network.network.id}"
    adapter_type = "${data.vsphere_virtual_machine.template.network_interface_types[0]}"
  }

  disk {
    label            = "${format("%s-%s-%01d.vmdk", lower(var.instance_prefix), lower(var.management["name"]),count.index + 1) }"
    size             = "${data.vsphere_virtual_machine.template.disks.0.size}"
    eagerly_scrub    = "${data.vsphere_virtual_machine.template.disks.0.eagerly_scrub}"
    thin_provisioned = "${data.vsphere_virtual_machine.template.disks.0.thin_provisioned}"
  }

  disk {
    label            = "${format("%s-%s-%01d_1.vmdk", lower(var.instance_prefix), lower(var.management["name"]),count.index + 1) }"
    size             = "${var.management["kubelet_lv"] + var.management["docker_lv"] + var.management["management_lv"] + 1}"
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

      ipv4_gateway    = "${var.management["gateway"]}"
      dns_server_list = "${var.dns_list}"
    }
  }

  connection {
    type     = "ssh"
    user     = "${var.ssh_user}"
    password = "${var.ssh_password}"
  }

  provisioner "file" {
    content     = "${data.template_file.createfs_management.rendered}"
    destination = "/tmp/createfs.sh"
  }

  provisioner "file" {
    source      = "${path.module}/lib/scripts/"
    destination = "/tmp/"
  }

  provisioner "remote-exec" {
    inline = [
      "echo ${var.ssh_password} | sudo -S echo",
      "echo \"${var.ssh_user} ALL=(ALL) NOPASSWD:ALL\" | sudo tee /etc/sudoers.d/${var.ssh_user}",
      "sudo sed -i /^127.0.1.1.*$/d /etc/hosts",
      "[ ! -d $HOME/.ssh ] && mkdir $HOME/.ssh && chmod 700 $HOME/.ssh",
      "echo \"${tls_private_key.ssh.public_key_openssh}\" | tee -a $HOME/.ssh/authorized_keys && chmod 600 $HOME/.ssh/authorized_keys",
      "[ -f ~/id_rsa ] && mv ~/id_rsa $HOME/.ssh/id_rsa && chmod 600 $HOME/.ssh/id_rsa",
      "chmod +x /tmp/createfs.sh; sudo /tmp/createfs.sh",
      "chmod +x /tmp/disable_ssh_password.sh; sudo /tmp/disable_ssh_password.sh",
    ]
  }

  provisioner "local-exec" {
    when    = "destroy"
    command = "cat > ${var.vm_private_key_file} <<EOL\n${tls_private_key.ssh.private_key_pem}\nEOL"
  }

  provisioner "local-exec" {
    when    = "destroy"
    command = "chmod 600 ${var.vm_private_key_file}"
  }

  provisioner "local-exec" {
    when    = "destroy"
    command = "scp -i ${var.vm_private_key_file} ${local.ssh_options} ${path.module}/lib/destroy/delete_node.sh ${var.ssh_user}@${local.icp_boot_node_ip}:/tmp/"
  }

  provisioner "local-exec" {
    when    = "destroy"
    command = "ssh -i ${var.vm_private_key_file} ${local.ssh_options} ${var.ssh_user}@${local.icp_boot_node_ip} \"chmod +x /tmp/delete_node.sh; /tmp/delete_node.sh ${var.icp_version} ${self.default_ip_address}\"; echo done"
  }
}

//va
resource "vsphere_virtual_machine" "va" {
  lifecycle {
    ignore_changes = ["disk.0", "disk.1"]
  }

  count = "${var.va["nodes"]}"

  #count            = "${length(compact(split(",",var.va["ipaddresses"])))}"
  name             = "${format("%s-%s-%01d", lower(var.instance_prefix), lower(var.va["name"]),count.index + 1) }"
  resource_pool_id = "${data.vsphere_resource_pool.pool.id}"
  datastore_id     = "${element(data.vsphere_datastore.datastore.*.id, (index(var.vm_types, "va") + count.index ) % length(var.datastore))}"
  num_cpus         = "${var.va["cpu_cores"]}"
  memory           = "${var.va["memory"]}"
  guest_id         = "${data.vsphere_virtual_machine.template.guest_id}"
  scsi_type        = "${data.vsphere_virtual_machine.template.scsi_type}"

  network_interface {
    network_id   = "${data.vsphere_network.network.id}"
    adapter_type = "${data.vsphere_virtual_machine.template.network_interface_types[0]}"
  }

  disk {
    label            = "${format("%s-%s-%01d.vmdk", lower(var.instance_prefix), lower(var.va["name"]),count.index + 1) }"
    size             = "${data.vsphere_virtual_machine.template.disks.0.size}"
    eagerly_scrub    = "${data.vsphere_virtual_machine.template.disks.0.eagerly_scrub}"
    thin_provisioned = "${data.vsphere_virtual_machine.template.disks.0.thin_provisioned}"
  }

  disk {
    label            = "${format("%s-%s-%01d_1.vmdk", lower(var.instance_prefix), lower(var.va["name"]),count.index + 1) }"
    size             = "${var.va["kubelet_lv"] + var.va["docker_lv"] + var.va["va_lv"] + 1}"
    unit_number      = 1
    eagerly_scrub    = false
    thin_provisioned = false
  }

  clone {
    template_uuid = "${data.vsphere_virtual_machine.template.id}"

    customize {
      linux_options {
        host_name = "${format("%s-%s-%01d", lower(var.instance_prefix), lower(var.va["name"]),count.index + 1) }"
        domain    = "${var.vm_domain}"
        time_zone = "${var.timezone}"
      }

      network_interface {
        ipv4_address = "${trimspace(element(split(",",var.va["ipaddresses"]),count.index))}"
        ipv4_netmask = "${var.va["netmask"]}"
      }

      ipv4_gateway    = "${var.va["gateway"]}"
      dns_server_list = "${var.dns_list}"
    }
  }

  connection {
    type     = "ssh"
    user     = "${var.ssh_user}"
    password = "${var.ssh_password}"
  }

  provisioner "file" {
    content     = "${data.template_file.createfs_va.rendered}"
    destination = "/tmp/createfs.sh"
  }

  provisioner "file" {
    source      = "${path.module}/lib/scripts/"
    destination = "/tmp/"
  }

  provisioner "remote-exec" {
    inline = [
      "echo ${var.ssh_password} | sudo -S echo",
      "echo \"${var.ssh_user} ALL=(ALL) NOPASSWD:ALL\" | sudo tee /etc/sudoers.d/${var.ssh_user}",
      "sudo sed -i /^127.0.1.1.*$/d /etc/hosts",
      "[ ! -d $HOME/.ssh ] && mkdir $HOME/.ssh && chmod 700 $HOME/.ssh",
      "echo \"${tls_private_key.ssh.public_key_openssh}\" | tee -a $HOME/.ssh/authorized_keys && chmod 600 $HOME/.ssh/authorized_keys",
      "[ -f ~/id_rsa ] && mv ~/id_rsa $HOME/.ssh/id_rsa && chmod 600 $HOME/.ssh/id_rsa",
      "chmod +x /tmp/createfs.sh; sudo /tmp/createfs.sh",
      "chmod +x /tmp/disable_ssh_password.sh; sudo /tmp/disable_ssh_password.sh",
    ]
  }
}

//worker
resource "vsphere_virtual_machine" "worker" {
  lifecycle {
    ignore_changes = ["disk.0", "disk.1"]
  }

  count = "${var.worker["nodes"]}"

  #count            = "${length(compact(split(",",var.worker["ipaddresses"])))}"
  name             = "${format("%s-%s-%01d", lower(var.instance_prefix), lower(var.worker["name"]),count.index + 1) }"
  resource_pool_id = "${data.vsphere_resource_pool.pool.id}"
  datastore_id     = "${element(data.vsphere_datastore.datastore.*.id, (index(var.vm_types, "worker") + count.index ) % length(var.datastore))}"
  num_cpus         = "${var.worker["cpu_cores"]}"
  memory           = "${var.worker["memory"]}"
  guest_id         = "${data.vsphere_virtual_machine.template.guest_id}"
  scsi_type        = "${data.vsphere_virtual_machine.template.scsi_type}"

  network_interface {
    network_id   = "${data.vsphere_network.network.id}"
    adapter_type = "${data.vsphere_virtual_machine.template.network_interface_types[0]}"
  }

  disk {
    label            = "${format("%s-%s-%01d.vmdk", lower(var.instance_prefix), lower(var.worker["name"]),count.index + 1) }"
    size             = "${data.vsphere_virtual_machine.template.disks.0.size}"
    eagerly_scrub    = "${data.vsphere_virtual_machine.template.disks.0.eagerly_scrub}"
    thin_provisioned = "${data.vsphere_virtual_machine.template.disks.0.thin_provisioned}"
  }

  disk {
    label            = "${format("%s-%s-%01d_1.vmdk", lower(var.instance_prefix), lower(var.worker["name"]),count.index + 1) }"
    size             = "${var.worker["kubelet_lv"] + var.worker["docker_lv"] + 1}"
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

      ipv4_gateway    = "${var.worker["gateway"]}"
      dns_server_list = "${var.dns_list}"
    }
  }

  connection {
    type     = "ssh"
    user     = "${var.ssh_user}"
    password = "${var.ssh_password}"
  }

  provisioner "file" {
    content     = "${data.template_file.createfs_worker.rendered}"
    destination = "/tmp/createfs.sh"
  }

  provisioner "file" {
    source      = "${path.module}/lib/scripts/"
    destination = "/tmp/"
  }

  provisioner "remote-exec" {
    inline = [
      "echo ${var.ssh_password} | sudo -S echo",
      "echo \"${var.ssh_user} ALL=(ALL) NOPASSWD:ALL\" | sudo tee /etc/sudoers.d/${var.ssh_user}",
      "sudo sed -i /^127.0.1.1.*$/d /etc/hosts",
      "[ ! -d $HOME/.ssh ] && mkdir $HOME/.ssh && chmod 700 $HOME/.ssh",
      "echo \"${tls_private_key.ssh.public_key_openssh}\" | tee -a $HOME/.ssh/authorized_keys && chmod 600 $HOME/.ssh/authorized_keys",
      "[ -f ~/id_rsa ] && mv ~/id_rsa $HOME/.ssh/id_rsa && chmod 600 $HOME/.ssh/id_rsa",
      "chmod +x /tmp/createfs.sh; sudo /tmp/createfs.sh",
      "chmod +x /tmp/disable_ssh_password.sh; sudo /tmp/disable_ssh_password.sh",
    ]
  }

  provisioner "local-exec" {
    when    = "destroy"
    command = "cat > ${var.vm_private_key_file} <<EOL\n${tls_private_key.ssh.private_key_pem}\nEOL"
  }

  provisioner "local-exec" {
    when    = "destroy"
    command = "chmod 600 ${var.vm_private_key_file}"
  }

  provisioner "local-exec" {
    when    = "destroy"
    command = "scp -i ${var.vm_private_key_file} ${local.ssh_options} ${path.module}/lib/destroy/delete_node.sh ${var.ssh_user}@${local.icp_boot_node_ip}:/tmp/"
  }

  provisioner "local-exec" {
    when    = "destroy"
    command = "ssh -i ${var.vm_private_key_file} ${local.ssh_options} ${var.ssh_user}@${local.icp_boot_node_ip} \"chmod +x /tmp/delete_node.sh; /tmp/delete_node.sh ${var.icp_version} ${self.default_ip_address}\"; echo done"
  }
}

//gluster
resource "vsphere_virtual_machine" "gluster" {
  lifecycle {
    ignore_changes = ["disk.0", "disk.1"]
  }

  count = "${var.gluster["nodes"]}"

  #count            = "${length(compact(split(",",var.gluster["ipaddresses"])))}"
  name             = "${format("%s-%s-%01d", lower(var.instance_prefix), lower(var.gluster["name"]),count.index + 1) }"
  resource_pool_id = "${data.vsphere_resource_pool.pool.id}"
  datastore_id     = "${element(data.vsphere_datastore.datastore.*.id, (index(var.vm_types, "gluster") + count.index ) % length(var.datastore))}"
  num_cpus         = "${var.gluster["cpu_cores"]}"
  memory           = "${var.gluster["memory"]}"
  guest_id         = "${data.vsphere_virtual_machine.template.guest_id}"
  scsi_type        = "${data.vsphere_virtual_machine.template.scsi_type}"

  network_interface {
    network_id   = "${data.vsphere_network.network.id}"
    adapter_type = "${data.vsphere_virtual_machine.template.network_interface_types[0]}"
  }

  disk {
    label            = "${format("%s-%s-%01d.vmdk", lower(var.instance_prefix), lower(var.gluster["name"]),count.index + 1) }"
    size             = "${data.vsphere_virtual_machine.template.disks.0.size}"
    eagerly_scrub    = "${data.vsphere_virtual_machine.template.disks.0.eagerly_scrub}"
    thin_provisioned = "${data.vsphere_virtual_machine.template.disks.0.thin_provisioned}"
  }

  disk {
    label            = "${format("%s-%s-%01d_1.vmdk", lower(var.instance_prefix), lower(var.gluster["name"]),count.index + 1) }"
    size             = "${var.gluster["data_disk"]}"
    unit_number      = 1
    eagerly_scrub    = false
    thin_provisioned = false
  }

  clone {
    template_uuid = "${data.vsphere_virtual_machine.template.id}"

    customize {
      linux_options {
        host_name = "${format("%s-%s-%01d", lower(var.instance_prefix), lower(var.gluster["name"]),count.index + 1) }"
        domain    = "${var.vm_domain}"
        time_zone = "${var.timezone}"
      }

      network_interface {
        ipv4_address = "${trimspace(element(split(",",var.gluster["ipaddresses"]),count.index))}"
        ipv4_netmask = "${var.gluster["netmask"]}"
      }

      ipv4_gateway    = "${var.gluster["gateway"]}"
      dns_server_list = "${var.dns_list}"
    }
  }

  connection {
    type     = "ssh"
    user     = "${var.ssh_user}"
    password = "${var.ssh_password}"
  }

  provisioner "remote-exec" {
    inline = [
      "echo ${var.ssh_password} | sudo -S echo",
      "echo \"${var.ssh_user} ALL=(ALL) NOPASSWD:ALL\" | sudo tee /etc/sudoers.d/${var.ssh_user}",
      "sudo sed -i /^127.0.1.1.*$/d /etc/hosts",
      "[ ! -d $HOME/.ssh ] && mkdir $HOME/.ssh && chmod 700 $HOME/.ssh",
      "echo \"${tls_private_key.ssh.public_key_openssh}\" | tee -a $HOME/.ssh/authorized_keys && chmod 600 $HOME/.ssh/authorized_keys",
      "sudo mkdir /root/.ssh && sudo chmod 700 /root/.ssh",
      "echo \"${tls_private_key.ssh.public_key_openssh}\" | sudo tee -a /root/.ssh/authorized_keys && sudo chmod 600 /root/.ssh/authorized_keys",
    ]
  }

  provisioner "local-exec" {
    when    = "destroy"
    command = "cat > ${var.vm_private_key_file} <<EOL\n${tls_private_key.ssh.private_key_pem}\nEOL"
  }

  provisioner "local-exec" {
    when    = "destroy"
    command = "chmod 600 ${var.vm_private_key_file}"
  }

  provisioner "local-exec" {
    when    = "destroy"
    command = "scp -i ${var.vm_private_key_file} ${local.ssh_options} ${path.module}/lib/destroy/delete_gluster.sh ${var.ssh_user}@${local.heketi_ip}:/tmp/"
  }

  provisioner "local-exec" {
    when    = "destroy"
    command = "ssh -i ${var.vm_private_key_file} ${local.ssh_options} ${var.ssh_user}@${local.heketi_ip} \"chmod +x /tmp/delete_gluster.sh; /tmp/delete_gluster.sh ${self.default_ip_address}\"; echo done"
  }
}

# Copy Delete scripts
resource "null_resource" "copy_delete_node" {
  connection {
    host        = "${local.icp_boot_node_ip}"
    user        = "${var.ssh_user}"
    private_key = "${tls_private_key.ssh.private_key_pem}"
  }

  provisioner "file" {
    source      = "${path.module}/lib/destroy/delete_node.sh"
    destination = "/tmp/delete_node.sh"
  }
}

resource "null_resource" "copy_delete_gluster" {
  connection {
    host        = "${local.heketi_ip}"
    user        = "${var.ssh_user}"
    private_key = "${tls_private_key.ssh.private_key_pem}"
  }

  provisioner "file" {
    source      = "${path.module}/lib/destroy/delete_gluster.sh"
    destination = "/tmp/delete_gluster.sh"
  }
}

//spawn ICP Installation
module "icpprovision" {
  #source = "github.com/pjgunadi/terraform-module-icp-deploy"
  source = "github.com/pjgunadi/terraform-module-icp-deploy?ref=2.1.0.2"

  //Connection IPs
  #icp-ips   = "${concat(vsphere_virtual_machine.master.*.default_ip_address, vsphere_virtual_machine.proxy.*.default_ip_address, vsphere_virtual_machine.management.*.default_ip_address, vsphere_virtual_machine.va.*.default_ip_address, vsphere_virtual_machine.worker.*.default_ip_address)}"
  icp-ips = "${concat(vsphere_virtual_machine.master.*.default_ip_address)}"

  boot-node = "${element(vsphere_virtual_machine.master.*.default_ip_address, 0)}"

  //Configuration IPs
  icp-master     = ["${vsphere_virtual_machine.master.*.default_ip_address}"]
  icp-worker     = ["${vsphere_virtual_machine.worker.*.default_ip_address}"]
  icp-proxy      = ["${split(",",var.proxy["nodes"] == 0 ? join(",",vsphere_virtual_machine.master.*.default_ip_address) : join(",",vsphere_virtual_machine.proxy.*.default_ip_address))}"]
  icp-management = ["${split(",",var.management["nodes"] == 0 ? "" : join(",",vsphere_virtual_machine.management.*.default_ip_address))}"]
  icp-va         = ["${split(",",var.va["nodes"] == 0 ? "" : join(",",vsphere_virtual_machine.va.*.default_ip_address))}"]

  # Workaround for terraform issue #10857
  cluster_size    = "${var.master["nodes"]}"
  worker_size     = "${var.worker["nodes"]}"
  proxy_size      = "${var.proxy["nodes"]}"
  management_size = "${var.management["nodes"]}"
  va_size         = "${var.va["nodes"]}"

  icp_source_server   = "${var.icp_source_server}"
  icp_source_user     = "${var.icp_source_user}"
  icp_source_password = "${var.icp_source_password}"
  image_file          = "${var.icp_source_path}"

  icp-version = "${var.icp_version}"

  icp_configuration = {
    "cluster_name"                 = "${var.cluster_name}"
    "network_cidr"                 = "${var.network_cidr}"
    "service_cluster_ip_range"     = "${var.cluster_ip_range}"
    "ansible_user"                 = "${var.ssh_user}"
    "ansible_become"               = "${var.ssh_user == "root" ? false : true}"
    "default_admin_password"       = "${var.icpadmin_password}"
    "calico_ipip_enabled"          = "true"
    "docker_log_max_size"          = "10m"
    "docker_log_max_file"          = "10"
    "disabled_management_services" = ["${split(",",var.va["nodes"] != 0 ? "" : join(",",var.disable_management))}"]
    "cluster_vip"                  = "${var.cluster_vip == "" ? element(vsphere_virtual_machine.master.*.default_ip_address, 0) : var.cluster_vip}"
    "vip_iface"                    = "${var.cluster_vip_iface == "" ? "eth0" : var.cluster_vip_iface}"
    "proxy_vip"                    = "${var.proxy_vip == "" ? element(split(",",var.proxy["nodes"] == 0 ? join(",",vsphere_virtual_machine.master.*.default_ip_address) : join(",",vsphere_virtual_machine.proxy.*.default_ip_address)), 0) : var.proxy_vip}"
    "proxy_vip_iface"              = "${var.proxy_vip_iface == "" ? "eth0" : var.proxy_vip_iface}"

    #"cluster_access_ip"         = "${vsphere_virtual_machine.master.0.default_ip_address}"
    #"proxy_access_ip"           = "${vsphere_virtual_machine.proxy.0.default_ip_address}"
  }

  #Gluster
  #Gluster and Heketi nodes are set to worker nodes for demo. Use separate nodes for production
  install_gluster = "${var.install_gluster}"

  gluster_size        = "${var.gluster["nodes"]}"
  gluster_ips         = ["${vsphere_virtual_machine.gluster.*.default_ip_address}"] #Connecting IP
  gluster_svc_ips     = ["${vsphere_virtual_machine.gluster.*.default_ip_address}"] #Service IP
  device_name         = "/dev/sdb"                                                  #update according to the device name provided by cloud provider
  heketi_ip           = "${vsphere_virtual_machine.gluster.0.default_ip_address}"   #Connectiong IP
  heketi_svc_ip       = "${vsphere_virtual_machine.gluster.0.default_ip_address}"   #Service IP
  cluster_name        = "${var.cluster_name}.icp"
  gluster_volume_type = "${var.gluster_volume_type}"
  heketi_admin_pwd    = "${var.heketi_admin_pwd}"
  generate_key        = true

  #icp_pub_keyfile = "${tls_private_key.ssh.public_key_openssh}"
  #icp_priv_keyfile = "${tls_private_key.ssh.private_key_pem"}"

  ssh_user = "${var.ssh_user}"
  ssh_key  = "${tls_private_key.ssh.private_key_pem}"
}
