k8s_cluster_local
=================
The goal of this repos is to create a kubernetes cluster on a local KVM hypervisor, to start the cluster and necessary services and connect to every servers using tmux.

It is made of:
- 2 shell scripts
	* `create_kubernetes_cluster.sh` to create and provision the VMs of the cluster
	* `kubernetes-localhost.sh` to start/stop the cluster and connect to VMs
- 1 cloud-config directory
	* Contain the cloud-config yaml files for each node

Requirements
------------
- KVM
- Libvirt
- Kernel >= 3.8 (for btrf usage)
- Tmux

Usage
-----
- To create the cluster:
`./create_kubernetes_cluster.sh`

You can pass arguments to the script to personnalize the installation - see ./create_kubernetes_cluster.sh -h`

- To start the cluster:
`./kubernetes-localhost.sh start`

You can specify the ssh private key to use to connect to VMs with the -i argument. By default, if the -i argument is not provided, it uses ~/.ssh/id_rsa
`./kubernetes-localhost.sh start -i /path/to/your/private/key`

- To stop the cluster:
`./kubernetes-localhost.sh stop`

TODO: Make a script to remove everthing (https://github.com/FrancoisBillant/k8s_cluster_local/issues/1)
- To remove everthing that has been created by the cluster:
	- Stop the cluster
	- Revome all 4 VMs and their disks
	- Remove the 2 networks k8s_front and k8s_back

AUTHOR
------
  Francois Billant <fbillant@gmail.com>

LICENCE
-------
  GPL v3 - see LICENSE


TODO:
- Make the RAM allocated to the VMs more configurable through an argument

