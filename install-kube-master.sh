#!/bin/bash
source misc.sh

do_setup_firewall() {
    local DISTRO="$( get_linux_distro )"
    if [ "$DISTRO" == "Debian" ]; then
        apt-get install -y ufw
    fi
    if [ "$DISTRO" == "Ubuntu" ] || [ "$DISTRO" == "Debian" ]; then
        # Setup firewall
        ufw --force enable

        ufw allow 22/tcp            # ssh
        ufw allow 53/udp            
        ufw allow 443/tcp           # https
        ufw allow 6443/tcp
        ufw allow 2379:2380/tcp
        ufw allow 10250/tcp
        ufw allow 10251/tcp
        ufw allow 10252/tcp
        ufw allow 10255/tcp
        # kube flannel
        ufw allow 8285/udp
        ufw allow 8472/udp

        ufw allow out on weave to 10.244.0.0/12
        ufw allow in on weave from 10.244.0.0/12

        if [ "$1" == "Debian" ]; then
            update-alternatives --set iptables /usr/sbin/iptables-legacy
            update-alternatives --set ip6tables /usr/sbin/ip6tables-legacy
        fi
        ufw reload
    fi
    if [ "$1" == "CentOS" ]; then
        # Setup firewall
        firewall-cmd --permanent --add-port=22/tcp
        firewall-cmd --permanent --add-port=53/udp
        firewall-cmd --permanent --add-port=443/tcp

        firewall-cmd --permanent --add-port=6443/tcp
        firewall-cmd --permanent --add-port=2379-2380/tcp
        firewall-cmd --permanent --add-port=10250/tcp
        firewall-cmd --permanent --add-port=10251/tcp
        firewall-cmd --permanent --add-port=10252/tcp
        firewall-cmd --permanent --add-port=10255/tcp

        # kube flannel
        firewall-cmd --permanent --add-port=8285/udp
        firewall-cmd --permanent --add-port=8472/udp

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

# Step 1. Check OS type and version
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
do_install_docker "$DISTRO"

    ## Step 4. Install Kubernetes
    echo "Installing kubernetes..."
    do_install_kubernetes "$DISTRO"

    ## Step 5. Initialize Master or Worker nodes
    echo "Initialize node..."
    do_initialize_node "$DISTRO" "$1"