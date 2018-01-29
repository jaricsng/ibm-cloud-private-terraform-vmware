output "icp_url" {
  value = "https://${var.cluster_access_ip == "" ? element(vsphere_virtual_machine.master.*.default_ip_address, 0) : var.cluster_access_ip}:8443"
}
