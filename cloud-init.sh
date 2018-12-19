#!/bin/bash
# ---------------------------------------------------------------------------
# cloud-init.sh
#
# Copyright 2018, Jean-Paul van Hamond
#
# Revision history:
# 2018-12-19 - Version 1.0 - Created
# ---------------------------------------------------------------------------
# ---- Set Cloud-Init Parameters
#
# cloud-init: User name to change ssh keys and password for
ciuser1=""
#
# cloud-init: Password to assign the user. 
cipassword1=""
#
#
#
# ---- DO NOT EDIT BELOW
# ---- 
PROGNAME="Proxmox Cloud-Init"
PROGDESC="This script prepares a Cloud-Init Template or Clone a Cloud-Init Template to a Virtual Machine "
VERSION="1.0"
# ----
clean_up() { # Perform pre-exit housekeeping
  return
}

error_exit() {
  echo -e "${PROGNAME}: ${1:-"Unknown Error"}" >&2
  clean_up
  exit 1
}

graceful_exit() {
  clean_up
  exit
}

signal_exit() { # Handle trapped signals
  case $1 in
    INT)
      error_exit "Program interrupted by user" ;;
    TERM)
      echo -e "\n$PROGNAME: Program terminated" >&2
      graceful_exit ;;
    *)
      error_exit "$PROGNAME: Terminating on unknown signal" ;;
  esac
}

help_message() {
  cat <<- _EOF_
  $PROGNAME ver. $VERSION
  $PROGDESC

  Options:
  -h, --help | Display this help message and exit.
  -p, --prepare | Preparing Cloud-Init Template in Proxmox.
  -d, --deploy | Deploying Cloud-Init Template in Proxmox to a Virtual Machine.
  -r, --remove | Remove Cloud-Init Template in Proxmox.


_EOF_
  return
}

# Preparing Cloud-Init Template
prepare() {

	date="$(date '+%d-%m-%Y')"
	
	echo -n "Enter the template ID and press [ENTER]: "
		read template_id
			
	# remove older image
	rm -rf /tmp/CentOS-7-x86_64*
	
	# download the newest image
	wget -P /tmp/ https://cloud.centos.org/centos/7/images/CentOS-7-x86_64-GenericCloud.qcow2
	
	# create a new VM
	qm create $template_id --memory 2048 --net0 virtio,bridge=vmbr0,firewall=1
	
	# import the downloaded disk to local-lvm storage
	qm importdisk $template_id /tmp/CentOS-7-x86_64-GenericCloud.qcow2 rbd_vm

	# finally attach the new disk to the VM as scsi drive
	qm set $template_id --scsihw virtio-scsi-pci --scsi0 rbd_vm:vm-$template_id-disk-0
	
	# Add Cloud-Init CDROM drive, Cloud-Init bootdrive and Serial socket
	qm set $template_id --ide2 rbd_vm:cloudinit
	qm set $template_id --boot c --bootdisk scsi0
	qm set $template_id --serial0 socket --vga serial0
	qm set $template_id --name centos7-template-$date 
	
	# Create Template from Machine
	qm template $template_id
	
	return
}

# Deploying Cloud-Init Template
deploy() {
	
	echo -n "Enter the template ID to clone vm from and press [ENTER]: "
		read clone_template_id
	
	echo -n "Enter the VM ID to use in Proxmox and press [ENTER]: "
		read clone_vm_id
		
	echo -n "Enter the domain (example.org) to use for this VM and press [ENTER]: "
		read clone_vm_domain
		
	echo -n "Enter the amount of memory (in MB's) to use for this VM and press [ENTER]: "
		read clone_vm_memory
	
	echo -n "Enter the amount of cores (1-8) to use for this VM and press [ENTER]: "
		read clone_vm_cores

	echo -n "Enter the VLAN/Bridge number to use for this VM and press [ENTER]: "
		read clone_vm_vlan
		
	echo -n "Enter the subnet (using CIDR notation 8 / 16 / 24 )to use for this VM and press [ENTER]: "
		read clone_vm_subnet	
		
	# Clone Template to VM
	qm clone $clone_template_id $clone_vm_id --name vm-$clone_vm_id.$clone_vm_domain
	
	# Set memory
	qm set $clone_vm_id --memory $clone_vm_memory
	
	# Set processors (sockets and cores)
	qm set $clone_vm_id --sockets 1 --cores $clone_vm_cores

	# Set network adress vlan/bridge number
	qm set $clone_vm_id --net0 virtio,bridge=vmbr$clone_vm_vlan
	
	# Set cloud-init username
	qm set $clone_vm_id --ciuser $ciuser1
	
	# Set cloud-init password
	qm set $clone_vm_id --cipassword $cipassword1
	
	# Set cloud-init ssh keys
	qm set $clone_vm_id --sshkey ~/.ssh/id_rsa.pub
	
	#Set cloud-init IP and Gateway
	qm set $clone_vm_id --ipconfig0 ip=10.5.$clone_vm_vlan.$clone_vm_id/$clone_vm_subnet,gw=10.5.$clone_vm_vlan.1

	# Set start on boot to enable
	qm set $clone_vm_id --onboot 1
	
	return
}


# Remove Cloud-Init Template
remove() {
	
	echo -n "Enter the template ID to remove and press [ENTER]: "
		read remove_id
	
	#Delete supplied VM id
	qm destroy $remove_id 
	
	return
}

# Trap signals
trap "signal_exit TERM" TERM HUP
trap "signal_exit INT"  INT

# Check for root UID
if [[ $(id -u) != 0 ]]; then
  error_exit "You must be the superuser to run this script."
fi

# Parse Commands
while [[ -n $1 ]]; do
  case $1 in
    -h | --help)
      help_message; graceful_exit ;;

	-p | --prepare)
	  prepare; graceful_exit ;;
	  
	-d | --deploy)
	  deploy; graceful_exit ;;
	  
	-r | --remove)
	  remove; graceful_exit ;;
  esac
  shift
done
