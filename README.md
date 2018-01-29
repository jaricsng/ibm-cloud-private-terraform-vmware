# Terraform Template for ICP Deployment in VMware

## Before you start
Install your VMware cluster environment

## Summary
This terraform template perform the following tasks:
- Provision IBM Cloud Private VMs in VMWare Cluster
- [Call ICP Provisioning Module](https://github.com/pjgunadi/terraform-module-icp-deploy)

## Input
| Variable      | Description    | Sample Value |
| ------------- | -------------- | ------------ |
| vsphere_server| vCenter Server | 192.168.1.1  |
| vsphere_user  | vCenter User   | admin |
| vsphere_password | vCenter Password | xxxxx |
| datacenter | vSphere Datacenter Name | dc01 |
| datastore | vSphere Datastore | datastore01 |
| resource_pool | vSphere Cluster Resource Pool | cluster1/Resources |
| network | vSphere Cluster Network | VM Network |
| osfamily | Operating System | ubuntu |
| template | Image Template | ubuntu_base_image |
| ssh_user | Login user to Image Template | admin |
| ssh_password | Login password to ICP Template | xxxxx |
| vm_domain | Server Domain | domain.com |
| timezone | Timezone | Asia/Singapore |
| dns_list | DNS List | ["192.168.1.53","192.168.1.54"] |
| icp_version | ICP Version | 2.1.0.1 |
| icp_source_server | ICP Installer sFTP Server | 192.168.1.5 |
| icp_source_user | ICP Installer sFTP User | user |
| icp_source_pasword | ICP Installer sFTP Password | xxxxx |
| icp_source_path | ICP Installer Source Path | /shared/icp.tar.gz |
| icp_admin_password | ICP desired admin password | xxxxx |
| instance_prefix | VM Instance Prefix | icp |
| cluster_access_ip | ICP Cluster Access IP (Enterprise edition only) | *virtual ip or leave empty* |
| proxy_access_ip | ICP Proxy Access IP (Enterprise edition only) | *virtual ip or leave empty* |
| master | Master nodes information | *see default values in variables.tf* |
| proxy | Proxy node information | *see default values in variables.tf* |
| worker | Worker node information | *see default values in variables.tf* |
| management | Management node information | *see default values in variables.tf* |

## Deployment step from Terraform CLI
1. Clone this repository: `git clone https://github.com/pjgunadi/ibm-cloud-private-terraform-vmware.git`
2. [Download terraform](https://www.terraform.io/) if you don't have one
3. Create terraform variable file with your input value e.g. `terraform.tfvars`
4. Apply the template
```
terraform init
terraform plan
terraform apply
```

## Deployment step from IBM Cloud Automation Manager (CAM)
1. Login to CAM
2. Navigate to Library > Template, and click **Create Template**
3. Select tab **From GitHub**
4. Type the **GitHub Repository URL:** `https://github.com/pjgunadi/ibm-cloud-private-terraform-vmware`
5. Type the **GitHub Repository sub-directory:** `cam`
6. Click **Create**
7. Set **Cloud Provider** value to `IBM`
8. Save the template

## ICP Provisioning Module
This [ICP Provisioning module](https://github.com/pjgunadi/terraform-module-icp-deploy) is forked from [IBM Cloud Architecture](https://github.com/ibm-cloud-architecture/terraform-module-icp-deploy)
with few modifications:
- Added Management nodes section
- Separate Local IP and Public IP variables
- Added boot-node IP variable

