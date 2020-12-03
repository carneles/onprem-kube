#!/bin/bash
source functions.sh

do_setup_firewall() {
    local DISTRO="$( get_linux_distro )"
    if [ "$DISTRO" == "Debian" ]; then
        apt-get install -y ufw
    fi
    if [ "$DISTRO" == "Ubuntu" ] || [ "$DISTRO" == "Debian" ]; then
        # Setup firewall
        ufw --force enable
        ufw allow 22/tcp            # ssh
        ufw allow 53/udp            # dns

        # https://kubernetes.io/docs/setup/production-environment/tools/kubeadm/install-kubeadm/#worker-node-s
        # ufw allow 6443/tcp
        ufw allow 10250/tcp         # kubelet api
        # ufw allow 10251/tcp
        # ufw allow 10255/tcp
        ufw allow 30000:32767/tcp   # node port services
        # ufw allow 2379:2380/tcp
        # kube flannel # kube flannel https://github.com/coreos/flannel/blob/master/Documentation/backends.md
        ufw allow 8285/udp
        ufw allow 8472/udp
        # calico
        # ufw allow 179/tcp

        ufw allow out on weave to 10.244.0.0/12
        ufw allow in on weave from 10.244.0.0/12

        if [ "$DISTRO" == "Debian" ]; then
            update-alternatives --set iptables /usr/sbin/iptables-legacy
            update-alternatives --set ip6tables /usr/sbin/ip6tables-legacy
        fi

        ufw reload
    fi
    if [ "$DISTRO" == "CentOS" ]; then
        # Setup firewall
        firewall-cmd --permanent --add-port=22/tcp

        firewall-cmd --permanent --add-port=53/udp
        firewall-cmd --permanent --add-port=6443/tcp
        firewall-cmd --permanent --add-port=10250/tcp
        firewall-cmd --permanent --add-port=10251/tcp
        firewall-cmd --permanent --add-port=10255/tcp
        firewall-cmd --permanent --add-port=30000-32767/tcp

        firewall-cmd --permanent --add-port=2379-2380/tcp
        # kube flannel
        firewall-cmd --permanent --add-port=8285/udp
        firewall-cmd --permanent --add-port=8472/udp
        # calico
        firewall-cmd --permanent --add-port=179/tcp

        firewall-cmd --zone=internal --add-interface=weave --permanent
        firewall-cmd --zone=internal --add-interface=docker --permanent

        #Then, add the dns service to those interfaces:

        firewall-cmd --zone=internal --add-service=dns --permanent 
        
        firewall-cmd --reload
        # Disable SELinux
        setenforce 0
        sed -i 's/SELINUX=enforcing/SELINUX=disabled/g' /etc/selinux/config
        # Kernel setting
        echo "net.bridge.bridge-nf-call-ip6tables = 1" > /etc/sysctl.d/k8s.conf
        echo "net.bridge.bridge-nf-call-iptables = 1" >> /etc/sysctl.d/k8s.conf
        sysctl -p
    fi
}

do_initialize_node() {
    echo "Please enter master node's IP Address (and port): "
    read MASTER_IP
    echo "(echo) Master IP: $MASTER_IP"
    echo "Please enter master node's token: " 
    read MASTER_TOKEN
    echo "(echo) Master Token: $MASTER_TOKEN"
    echo "Please enter master node's hashed discovery token: "
    read MASTER_DISCOVERY_TOKEN
    echo "(echo) Master Hashed Discovery Token: $MASTER_DISCOVERY_TOKEN"
    
    local DISTRO="$( get_linux_distro )"
    local HOSTNAME=""
    HOSTNAME=$(hostname)
    local USER=""
    USER=$(whoami)

    # deactivate swap
    swapoff -a
    echo "Swap disabled temporarily! Setting up /etc/fstab for permanent swapoff."
    if [ "$DISTRO" == "Ubuntu" ]; then
        sed -i.bak 's/\/swap.img/#\/swap.img/g' /etc/fstab
    fi
    if [ "$DISTRO" == "Debian" ]; then
        sed -i.bak '/swap/ s/^/#/' /etc/fstab
    fi
    if [ "$DISTRO" == "CentOS" ]; then
        sed -i.bak 's/\/dev\/mapper\/centos-swap/#\/dev\/mapper\/centos-swap/g' /etc/fstab
    fi
    
    echo "Please wait a moment..."
    sleep 10

    echo "Joining master node..."
    kubeadm join $MASTER_IP --token $MASTER_TOKEN --discovery-token-ca-cert-hash $MASTER_DISCOVERY_TOKEN
    echo "Kubernetes worker setup finished. You can now start to deploy your services."
}

echo "$( date ) Install kube worker script start"

# Step 1. Check OS type and version
echo "Checking system..."
do_check_os

# Step 2. Update the OS
echo "Updating operating system..."
do_os_update

# Step 3. Setup hostname
echo "Setup hostname..."
do_setup_hostname

# Step 4. Setup Firewall
echo "Setup Firewall..."
do_setup_firewall

# Step 5. Install Docker
echo "Installing docker..."
do_install_docker

# Step 6. Install Kubernetes
echo "Installing kubernetes..."
do_install_kubernetes

# Step 7. Initialize Master or Worker nodes
echo "Initialize node..."
do_initialize_node

echo "$( date ) Install kube worker script end"