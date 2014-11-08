k8s_cluster_local
=================
The goal of this repos is to create a kubernetes cluster on a local KVM hypervisor, to start the cluster and necessary services and connect to every servers using tmux.

It is made of:
- 2 shell scripts
	* `create_kubernetes_cluster.sh` to create and provision the VMs of the cluster
	* `kubernetes-localhost.sh` to start/stop the cluster and connect to VMs

Requirements
------------
- KVM
- Libvirt
- Kernel >= 3.8 (for btrf usage)

Usage
-----
To create the cluster:
`./create_kubernetes_cluster.sh`

You can pass arguments to the script to personnalize the installation - see ./create_kubernetes_cluster.sh -h`

To start the cluster:


AUTHOR:
  Francois Billant <fbillant@gmail.com>

LICENCE:
  GPL v3 - see LICENSE


# TODO:
# - Begin by a function that check if the coreos image is present in the current directory.
#   If it is not present, download it.
# - Add a function/argument to ask the path of the key to inject and modify the yaml file accordingly
# - Make the HDD_PATH more configurable through an argument
# - Make the HDD_SIZE more configurable through an argument
# - Make the RAM allocated to the VMs more configurable through an argument
#
