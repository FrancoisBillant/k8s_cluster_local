#! /bin/bash
# REQUIREMENTS:
#   - tmux
#   - a kubernetes cluster created with the script : create_kubernetes_cluster.sh
#
# AUTHOR:
#   Francois Billant <fbillant@gmail.com>
#
# LICENCE:
#   GPL v3 - see LICENSE

USAGE="
USAGE : ./kubernetes-locahost [start|stop] -i /path/to/your/private/key
--
if -i is not provided, it default to ~/.ssh/id_rsa
"

SESSIONNAME="kubernetes-localhost"
DISCOVERY_IP=192.168.23.100
KUBE_MASTER_IP=192.168.23.111
KUBE_MINION1_IP=192.168.23.112
KUBE_MINION2_IP=192.168.23.113


function parse_args {
	while getopts "k:" OPTION
	do
	    case $OPTION in
		k) export KEY_PATH="$OPTARG" ;;
	        *) exit 1;;
	    esac
	done
}

function start_vm {
	VM_NAME=$1
	VM_EXIST=`sudo virsh list | grep $VM_NAME`
	if [ $VM_EXIST==1 ] 2> /dev/null
	then
	        sudo virsh start $VM_NAME
	else
	        echo "$VM_NAME already started"
	fi
}

function wait_for {
	VM_NAME=$1
	PORT=$2
	case $VM_NAME in
		k8s_discovery)
			IP_ADDRESS=$DISCOVERY_IP
			;;
		k8s_master)
			IP_ADDRESS=$KUBE_MASTER_IP
			;;
		k8s_minion1)
			IP_ADDRESS=$KUBE_MINION1_IP
			;;
		k8s_minion2)
			IP_ADDRESS=$KUBE_MINION2_IP
			;;
		*)
			echo "The IP address of $VM_NAME is not known - exiting..."
			exit 1
			;;
	esac

	# Waiting up until the port $PORT of the targeted ip address is open and listening
	while !  `nc -z $IP_ADDRESS $PORT`
	do
		        echo "waiting for instance $VM_NAME to open port $PORT";
		        sleep 1;
	done
}

function kubernetes_start {
	tmux has-session -t $SESSIONNAME &> /dev/null
	
	if [ $? != 0 ] 
	then
		if [[ -z $KEY_PATH ]]; then
			KEY_PATH="~/.ssh/id_rsa"
		fi
		# Start the discovery vm if it's not already running
		start_vm k8s_discovery
		wait_for k8s_discovery 22
		# Create the kubernetes session
		tmux new-session -s $SESSIONNAME -n discovery -d
		#Connect to the discovery node via ssh and launch the discovery service
		tmux send-keys -t $SESSIONNAME "ssh -i $KEY_PATH core@192.168.23.100" C-m "ps -eaf | grep etcd" C-m
	
	
		# Wait for discovery service to be up and running before the k8s cluster
		wait_for k8s_discovery 7003
		# Start the kubernetes master vm
		start_vm k8s_master
		wait_for k8s_master 22
	
		# Create the master window 
		tmux new-window -t $SESSIONNAME -n master -d
		#connect to the master vm
		tmux send-keys -t $SESSIONNAME:1 "ssh -i $KEY_PATH core@192.168.23.111" C-m
	
	
		# Start the kubernetes minion1 vm
		start_vm k8s_minion1
		wait_for k8s_minion1 22
	
		# Create the minion1 window 
		tmux new-window -t $SESSIONNAME -n minion1 -d
		#connect to the minion1 vm
		tmux send-keys -t $SESSIONNAME:2 "ssh -i $KEY_PATH core@192.168.23.112" C-m
	
	
		# Start the kubernetes minion2 vm
		start_vm k8s_minion2
		wait_for k8s_minion2 22
	
		# Create the minion2 window 
		tmux new-window -t $SESSIONNAME -n minion2 -d
		#connect to the minion2 vm
		tmux send-keys -t $SESSIONNAME:3 "ssh -i $KEY_PATH core@192.168.23.113" C-m
	
		# Activate the etcd cluster
		echo "Activating the etcd cluster..."
		tmux send-keys -t $SESSIONNAME:1 "sudo systemctl restart etcd" C-m
		sleep 5
		tmux send-keys -t $SESSIONNAME:2 "sudo systemctl restart etcd" C-m
	
		# Restart Kubernetes Services on the master
		# Master
		echo "starting kubernetes services..."
		tmux send-keys -t $SESSIONNAME:1 "sudo systemctl restart k8s_apiserver" C-m "sudo systemctl restart k8s_scheduler" C-m "sudo systemctl restart k8s_controller_manager" C-m "sudo systemctl restart k8s_kubelet" C-m "sudo systemctl restart k8s_proxy" C-m "sudo systemctl restart docker" C-m "journalctl -f -u etcd" C-m
	fi

	tmux attach -t $SESSIONNAME
}

function kubernetes_stop {
	sudo virsh shutdown k8s_minion2
	sleep 3
	sudo virsh shutdown k8s_minion1
	sleep 3
	sudo virsh shutdown k8s_master
	sleep 3
	# Wiping informations from the discovery
	tmux send-keys -t $SESSIONNAME:0 "etcdctl rm --recursive /k8s_cluster" C-m
	sleep 3
	sudo virsh shutdown k8s_discovery
	tmux kill-session -t $SESSIONNAME
}

function main {
	case $1 in
		start)
			kubernetes_start
			;;
		stop)
			kubernetes_stop
			;;
		*)
			echo $USAGE; exit;
			;;
	esac
}

main $1
