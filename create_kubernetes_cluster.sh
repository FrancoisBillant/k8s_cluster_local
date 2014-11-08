#! /bin/bash
# REQUIREMENTS:
#   - KVM
#   - Libvirt
#   - Kernel >= 3.8 (for btrf usage)
#
# AUTHOR:
#   Francois Billant <fbillant@gmail.com>
#
# LICENCE:
#   GPL v3 - see LICENSE


# TODO:
# - Make the RAM allocated to the VMs more configurable through an argument
#

# TODO:
#    -C CHANNEL  Release channel to use (e.g. beta) [default: ${CHANNEL_ID}]
#    -t TMPDIR   Temporary location with enough space to download images.
USAGE="Usage: sudo ./create_kubernetes_cluster.sh arg1 value1 arg2 value2...
Options:
	-p 	virual disk path	The path to the directory where VMs harddrives will be created (Default: /var/lib/libvirt/images)
	-s	virual disk size	The size in Go of the VMs harddrives that will be created (Default: 50)
	-i	image path		The path where the coreos image to install on disk is to be find (Default: pwd)
	-k	key path		The ssh ipublic key to inject into coreos instances allowing to ssh into (Default: ~/.ssh/id_rsa.pub)
    	-v 	verbose        		Super verbose, for debugging.
    	-h 	help         		This ;-)

This tool installs a Kubernetes cluster.
It creates 2 networks, 4 VMs (KVM), including a service discovery, a kubernetes master and 2 kubernetes minions and uses Coreos as base OS.
"
HDD_SIZE=""
HDD_PATH=""
IMG_PATH=""
IMG_NAME=""
KEY_PATH=""

function parse_args {
	while getopts "p:s:i:k:vh" OPTION
	do
	    case $OPTION in
		p) export HDD_PATH="$OPTARG" ;;
		s) export HDD_SIZE="$OPTARG" ;;
		i) export IMG_PATH="$OPTARG" ;;
		k) export KEY_PATH="$OPTARG" ;;
	        v) set -x ;;
	        h) echo "$USAGE"; exit;;
	        *) exit 1;;
	    esac
	done
}

function check_img_exist {
	CWD=`pwd`
	if [[ -z $IMG_PATH ]]; then
		export IMG_DIR=$CWD
		export IMG_NAME="coreos_production_image.bin.bz2"
	else
		export IMG_NAME=$(basename $IMG_PATH)
		export IMG_DIR=$(dirname $IMG_PATH)
	fi
	if [[ ! -f $IMG_DIR/$IMG_NAME ]]; then
		echo "The coreos image has not been found in $IMG_PATH. Downloading it..."
		wget http://stable.release.core-os.net/amd64-usr/current/$IMG_NAME
	else
		echo "A coreos image has been found in $IMG_PATH. Using it as OS for VMs."
	fi
	echo ""
}

function inject_key {
	if [[ -z $KEY_PATH ]]; then
		KEY_PATH="~/.ssh/id_rsa.pub"
		if [[ ! -f $KEY_PATH ]]; then
			echo "The ssh public key has not been found in $KEY_PATH. Please generate one or provide the path to an existing one by providing the "-k" argument (ie: sudo ./create_kubernetes_cluster.sh -k /home/user/.ssh/id_rsa.pub)."
			exit 1
		fi
	fi
	export KEY_PATH
	KEY=`cat $KEY_PATH`
	for i in discovery master minion1 minion2
	do
		NOT_FIRST_USE=`cat cloud-config/$i.yaml | grep your_public_key_here`
		if [[ -z $NOT_FIRST_USE ]]; then
			sed -i "s!^  - ssh-rsa.*!  - ssh-rsa your_public_key_here!" cloud-config/$i.yaml
		fi
		sed -i "s!  - ssh-rsa your_public_key_here!  - $KEY!" cloud-config/$i.yaml
	done
}

function check_net_exist {
	NET_NAME=$1
	NET_EXIST=`sudo virsh net-list | grep ${NET_NAME}`
	if [[ ! -n ${NET_EXIST} ]]; then
		create_network ${NET_NAME}
	else
		echo "${NET_NAME} network already exist... doing nothing."
	fi
	echo ""
}

function create_network {
	NET_NAME=$1
	echo "Network ${NET_NAME} doesn't exist, creating it..."

	case ${NET_NAME} in
		k8s_front)
sudo cat > /etc/libvirt/qemu/networks/k8s_front.xml << EOF
<network>
  <name>k8s_front</name>
  <uuid>43f6ac79-3e16-fc08-a472-0c3502d4ddb2</uuid>
  <forward dev='wlan0' mode='nat'>
    <interface dev='wlan0'/>
  </forward>
  <bridge name='k8s_front' stp='on' delay='0' />
  <mac address='52:54:00:88:64:79'/>
  <ip address='192.168.23.1' netmask='255.255.255.0'>
  </ip>
</network>
EOF
			;;
		k8s_back)
sudo cat > /etc/libvirt/qemu/networks/k8s_back.xml << EOF
<network>
  <name>k8s_back</name>
  <uuid>33f6ac78-3e15-fc08-a471-0c3502d4ddb1</uuid>
  <bridge name='k8s_back' stp='on' delay='0' />
  <mac address='52:54:00:87:63:78'/>
  <ip address='10.244.0.1' netmask='255.255.0.0'>
  </ip>
</network>
EOF

			;;
		*)
	 		echo "Unknown network ${NET_NAME} - Exiting..."
	 		exit 1
			;;
	esac

	sudo virsh net-define /etc/libvirt/qemu/networks/${NET_NAME}.xml
	sudo virsh net-create /etc/libvirt/qemu/networks/${NET_NAME}.xml
	if [ $? -eq 0 ]; then
 		echo "Network ${NET_NAME} has been created successfully"
 	else
		echo "An error occured during the creation of the network ${NET_NAME} - Exiting..."
		exit 1
	fi
	sudo virsh net-autostart ${NET_NAME}
}

function create_hdds {
	WORKDIR=$(mktemp --tmpdir -d k8s-install.XXXXXXXXXX)

	# If no argument "-p" is provided, HDDs will be create in libvirt default hdd folder
	if [[ -z ${HDD_PATH} ]]; then
		HDD_PATH="/var/lib/libvirt/images"
	fi
	export HDD_PATH

	# If no argument "-s" is provided, HDDs size will be 50 Go
	if [[ -z ${HDD_SIZE} ]]; then
		HDD_SIZE=50
	fi

	for i in discovery master minion1 minion2
	do
		DEVICE=`losetup -f`
		CLOUDINIT="cloud-config/$i.yaml"
	
		echo "Creating $i hdd..."
		sudo qemu-img create -f qcow2 -o preallocation=metadata ${HDD_PATH}/k8s_$i.img ${HDD_SIZE}G
	
		sudo losetup ${DEVICE} ${HDD_PATH}/k8s_$i.img
	
		echo "Copying coreos image to tmp..."
		cp ${IMG_DIR}/${IMG_NAME} ${WORKDIR}
	
		echo "Copying data to the device..."
		bunzip2 --stdout "${WORKDIR}/${IMG_NAME}" >"${DEVICE}"
	
		# inform the OS of partition table changes
		kpartx -av "$DEVICE" &> /dev/null
	
		# The ROOT partition should be #9 but make no assumptions here!
		# Also don't mount by label directly in case other devices conflict.
		ROOT_DEV=$(blkid -t "LABEL=ROOT" -o device)
		
		if [[ -z "${ROOT_DEV}" ]]; then
		    echo "Unable to find new ROOT partition on ${DEVICE}" >&2
		    exit 1
		fi
		
		echo "Installing cloud-config..."
		mkdir -p "${WORKDIR}/rootfs"
		mount -t btrfs -o subvol=root "${ROOT_DEV}" "${WORKDIR}/rootfs" > /dev/null
		
		mkdir -p "${WORKDIR}/rootfs/var/lib/coreos-install"
		cp "${CLOUDINIT}" "${WORKDIR}/rootfs/var/lib/coreos-install/user_data"
		
		umount "${WORKDIR}/rootfs" > /dev/null
		
		kpartx -d ${DEVICE} &> /dev/null
		sleep 2
	
		losetup -d ${DEVICE}
		sleep 2
		echo "=>Success"
		echo ""
	done
	
	rm -rf "${WORKDIR}"
}

function random_gen {
	echo $[ 1 + $[ RANDOM % 40 + 10 ]]
}

function create_vm {
# Create XML files to describe domains (VMs)
for i in discovery master minion1 minion2
do
	RANDOM1=$(random_gen)
	RANDOM2=$(random_gen)
	RANDOM3=$(random_gen)
	RANDOM4=$(random_gen)
	RANDOM5=$(random_gen)
	RANDOM6=$(random_gen)
cat > /etc/libvirt/qemu/k8s_$i.xml << EOF
<domain type='kvm'>
  <name>k8s_$i</name>
  <uuid>${RANDOM1}ea88ee-b93f-81aa-068a-d203172${RANDOM2}c51</uuid>
  <memory unit='KiB'>8388608</memory>
  <currentMemory unit='KiB'>8388608</currentMemory>
  <vcpu placement='static'>4</vcpu>
  <os>
    <type arch='x86_64' machine='pc-1.1'>hvm</type>
    <boot dev='hd'/>
  </os>
  <features>
    <acpi/>
    <apic/>
    <pae/>
  </features>
  <clock offset='utc'/>
  <on_poweroff>destroy</on_poweroff>
  <on_reboot>restart</on_reboot>
  <on_crash>restart</on_crash>
  <devices>
    <emulator>/usr/bin/kvm</emulator>
    <disk type='file' device='disk'>
      <driver name='qemu' type='raw'/>
      <source file='${HDD_PATH}/k8s_$i.img'/>
      <target dev='hda' bus='ide'/>
      <address type='drive' controller='0' bus='0' target='0' unit='0'/>
    </disk>
    <controller type='usb' index='0'>
      <address type='pci' domain='0x0000' bus='0x00' slot='0x01' function='0x2'/>
    </controller>
    <controller type='ide' index='0'>
      <address type='pci' domain='0x0000' bus='0x00' slot='0x01' function='0x1'/>
    </controller>
    <interface type='network'>
      <mac address='52:54:00:e9:${RANDOM3}:${RANDOM4}'/>
      <source network='k8s_front'/>
      <model type='virtio'/>
      <address type='pci' domain='0x0000' bus='0x00' slot='0x03' function='0x0'/>
    </interface>
    <interface type='network'>
      <mac address='52:54:00:bd:${RANDOM5}:${RANDOM6}'/>
      <source network='k8s_back'/>
      <model type='virtio'/>
      <address type='pci' domain='0x0000' bus='0x00' slot='0x04' function='0x0'/>
    </interface>
    <serial type='pty'>
      <target port='0'/>
    </serial>
    <console type='pty'>
      <target type='serial' port='0'/>
    </console>
    <input type='mouse' bus='ps2'/>
    <graphics type='vnc' port='-1' autoport='yes'/>
    <sound model='ich6'>
      <address type='pci' domain='0x0000' bus='0x00' slot='0x05' function='0x0'/>
    </sound>
    <video>
      <model type='cirrus' vram='9216' heads='1'/>
      <address type='pci' domain='0x0000' bus='0x00' slot='0x02' function='0x0'/>
    </video>
    <memballoon model='virtio'>
      <address type='pci' domain='0x0000' bus='0x00' slot='0x06' function='0x0'/>
    </memballoon>
  </devices>
</domain>
EOF
	sudo virsh define /etc/libvirt/qemu/k8s_$i.xml
done
}

function print_infos {
if [ $? -eq 0 ]; then
	echo "
---------------------------------------------------------------------------------------------------------------------------
Congratulation ! A kubernetes cluster has been created successfully \o/

If you ever need to reset the cluster, just rerun this script with the same arguments and you'll get a brand new cluster ;).

FYI, here is what has been created in the process:
- 2 network bridges :
	*k8s_front
	*k8s_back
- 2 virtual networks:
	*k8s_front: no dhcp, nated on wlan0
	*k8s_back: no dhcp, isolated
- 4 virtual machines:
	*k8s_discovery
		.8G Ram, 2 vcpu
		.hdd ${HDD_SIZE}Go: ${HDD_PATH}/k8s_discovery.img
		.192.168.23.100
	*k8s_master
		.8G Ram, 2 vcpu
		.hdd ${HDD_SIZE}Go: ${HDD_PATH}/k8s_master.img
		.192.168.23.111
	*k8s_minion1
		.8G Ram, 2 vcpu
		.hdd ${HDD_SIZE}Go: ${HDD_PATH}/k8s_minion1.img
		.192.168.23.112
	*k8s_minion2
		.8G Ram, 2 vcpu
		.hdd ${HDD_SIZE}Go: ${HDD_PATH}/k8s_minion2.img
		.192.168.23.113
- Auth information:
	The default user for every machine is "core".
	You can connect to every machine using the private key corresponding to the ssh public key provided: 
	${KEY_PATH}
	ie: ssh -i /home/user/.ssh/id_rsa core@ip_of_the_machine (supposing you provided the public key \"/home/user/.ssh/id_rsa.pub\".

NEXT STEP :
Now you can start and connect to you cluster using the "kubernetes-localhost.sh" script (https://github.com/FrancoisBillant/k8s_cluster_local).
To start the cluster run: ./kubernetes-localhost.sh start
"
fi
}

function main {
	parse_args $@
	check_img_exist
	inject_key
	check_net_exist k8s_front
	check_net_exist k8s_back
	create_hdds
	create_vm
	print_infos
}

main $@
