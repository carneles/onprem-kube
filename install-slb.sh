#!/bin/bash
source functions.sh

do_install_haproxy() {
    local DISTRO="$( get_linux_distro )"
    if [ "$DISTRO" == "Ubuntu" ] || [ "$DISTRO" == "Debian" ];  then
        add-apt-repository -y ppa:vbernat/haproxy-1.8
        apt-get update
        apt-get install -y haproxy        
    fi
    if [ "$DISTRO" == "CentOS" ]; then
        yum install -y haproxy
    fi

    echo "Please enter worker's IP Address (and port): "
    read SERVICE_IP
    echo "(echo) Service IP: $SERVICE_IP"
    echo "Please enter service's full domain (with sub domain - e.g. www.test.com): "
    read SERVICE_DOMAIN
    echo "(echo) Service domain: $SERVICE_DOMAIN"

    # Setup config
    local HOST_IP=""
    HOST_IP=$(hostname -I | cut -d \  -f1)
    echo "" >> /etc/haproxy/haproxy.cfg
    echo "frontend Local_HTTP_Server" >> /etc/haproxy/haproxy.cfg
    echo "        bind $HOST_IP:80" >> /etc/haproxy/haproxy.cfg
    echo "        mode http" >> /etc/haproxy/haproxy.cfg
    echo "        default_backend Backend_HTTP_Server" >> /etc/haproxy/haproxy.cfg
    echo "" >> /etc/haproxy/haproxy.cfg
    echo "backend Backend_HTTP_Server" >> /etc/haproxy/haproxy.cfg
    echo "        mode http" >> /etc/haproxy/haproxy.cfg
    echo "        balance roundrobin" >> /etc/haproxy/haproxy.cfg
    echo "        option forwardfor" >> /etc/haproxy/haproxy.cfg
    echo "        http-request set-header X-Forwarded-Port %[dst_port]" >> /etc/haproxy/haproxy.cfg
    echo "        http-request add-header X-Forwarded-Proto https if { ssl_fc }" >> /etc/haproxy/haproxy.cfg
    echo "        option httpchk HEAD / HTTP/1.1rnHost:localhost" >> /etc/haproxy/haproxy.cfg
    echo "        server $SERVICE_DOMAIN $SERVICE_IP" >> /etc/haproxy/haproxy.cfg
        
    if [ "$DISTRO" == "Ubuntu" ] || [ "$DISTRO" == "Debian" ];  then
        service haproxy restart
    fi

    if [ "$DISTRO" == "CentOS" ]; then
        systemctl start haproxy
        systemctl enable haproxy
    fi
}

do_setup_firewall() {
    local DISTRO="$( get_linux_distro )"
    if [ "$DISTRO" == "Debian" ]; then
        apt-get install -y ufw
    fi
    if [ "$DISTRO" == "Ubuntu" ] || [ "$DISTRO" == "Debian" ]; then
        # Setup firewall
        ufw --force enable
        ufw allow 22/tcp

        ufw allow 80/tcp
        ufw allow 443/tcp

        ufw reload
    fi
    if [ "$DISTRO" == "CentOS" ]; then
        # Setup firewall
        firewall-cmd --permanent --add-port=22/tcp
 
        firewall-cmd --permanent --add-port=80/tcp
        firewall-cmd --permanent --add-port=443/tcp
 
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

echo "$( date ) Install SLB script start"

# Step 1. Check OS type and version
echo "Checking system..."
do_check_os

# Step 2. Update the OS
echo "Updating operating system..."
do_os_update

# Step 3. Setup hostname
echo "Setup hostname..."
do_setup_hostname

# Step 4. Setup firewall
echo "Setup Firewall"
do_setup_firewall

# Step 4. Install HAProxy
echo "Install HAProxy..."
do_install_haproxy

echo "$( date ) Install SLB script end"