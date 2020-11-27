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

do_initialize_node() {
    local DISTRO="$( get_linux_distro )"
    local HOSTNAME=""
    HOSTNAME=$(hostname)

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
    
    # initialize master node
    kubeadm init --pod-network-cidr=10.244.0.0/16
    # Configure cgroup driver used by kubelet on control-plane node
    sed -i.bak 's/KUBELET_KUBEADM_ARGS="--cgroup-driver=cgroupfs/KUBELET_KUBEADM_ARGS="--cgroup-driver=systemd/g' /var/lib/kubelet/kubeadm-flags.env
    systemctl daemon-reload
    systemctl restart kubelet

    mkdir -p /home/$SUDO_USER/.kube
    chown $SUDO_USER:$SUDO_USER /home/$SUDO_USER/.kube
    cp -i /etc/kubernetes/admin.conf /home/$SUDO_USER/.kube/config
    chown $SUDO_USER:$SUDO_USER /home/$SUDO_USER/.kube/config

    mkdir -p /root/.kube
    chown root:root /root/.kube
    cp -i /etc/kubernetes/admin.conf /root/.kube/config
    chown root:root /root/.kube/config

    echo "Please wait a moment..."
    sleep 10

    echo "Install networking pods..."
    kubectl apply -f https://raw.githubusercontent.com/coreos/flannel/master/Documentation/kube-flannel.yml
    # Deploy Pod network
    echo "Waiting master to be ready..."
    kubectl wait --for=condition=ready nodes/$HOSTNAME --timeout=60s
    echo "Kubernetes master setup finished. You can now join worker to the master."
}

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