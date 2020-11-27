#!/bin/bash
source helper.sh

do_check_os() {
    local OS_TYPE="$( get_os )"
    if [ "$OS_TYPE" == "linux" ]; then
        local DISTRO="$( get_linux_distro )"
        if [ "$DISTRO" == "Ubuntu" ] || [ "$DISTRO" == "CentOS" ] || [ "$DISTRO" == "Debian" ]; then
            local DISTRO_VERSION="$( get_linux_distro_version $DISTRO )"
            if ([ "$DISTRO" == "Ubuntu" ] && [ "$DISTRO_VERSION" == "18.04" ]) || ([ "$DISTRO" == "CentOS" ] && [ "$DISTRO_VERSION" == "7" ]) || ([ "$DISTRO" == "Debian" ] && [ "$DISTRO_VERSION" == "10" ]); then
                echo "Will install on ${DISTRO} ${DISTRO_VERSION}."
            else
                echo "Invalid Linux distro version. Only accept Ubuntu 18.04, Debian 10 or CentOS 7."
                exit 1
            fi
        else
            echo "Invalid Linux distro. Only accept Ubuntu, Debian or CentOS."
            exit 1
        fi
    else
        echo "Invalid operating system. Only accept Linux Ubuntu, Debian or CentOS."
        exit 1
    fi 
}

do_os_update () {
    local DISTRO="$( get_linux_distro )"
    if [ "$DISTRO" == "Ubuntu" ] || [ "$DISTRO" == "Debian" ]; then
        apt-get update
        apt-get install -y apt-transport-https ca-certificates curl gnupg-agent software-properties-common
    fi
    if [ "$DISTRO" == "CentOS" ]; then
        yum update -y
    fi
}

do_setup_hostname () {
    local DISTRO="$( get_linux_distro )"
    local HOSTNAME=""
    HOSTNAME=$(hostname)
    local HOST_IP=""
    HOST_IP=$(hostname -I | cut -d \  -f1)
    if [ "$DISTRO" == "Ubuntu" ] || [ "$DISTRO" == "Debian" ]; then
        sed -i.bak 's/127.0.1.1/#127.0.1.1/g' /etc/hosts
    fi
    echo "$HOST_IP $HOSTNAME" >> /etc/hosts

    # For ubuntu, change /etc/resolv.conf
    if [ "$DISTRO" == "Ubuntu" ]; then
        mv /etc/resolv.conf /etc/resolv.conf.bak
        sudo ln -sf /run/systemd/resolve/resolv.conf /etc/resolv.conf
    fi
}

do_install_docker() {
    local DISTRO="$( get_linux_distro )"
    if [ "$DISTRO" == "Ubuntu" ]; then
        curl -fsSL https://download.docker.com/linux/ubuntu/gpg | apt-key add -
        add-apt-repository "deb [arch=amd64] https://download.docker.com/linux/ubuntu $(lsb_release -cs) stable"
        apt-get update && apt-get install -y containerd.io=1.2.10-3 docker-ce=5:19.03.4~3-0~ubuntu-$(lsb_release -cs) docker-ce-cli=5:19.03.4~3-0~ubuntu-$(lsb_release -cs)
        echo "{" > /etc/docker/daemon.json 
        echo "\"exec-opts\": [\"native.cgroupdriver=systemd\"]," >> /etc/docker/daemon.json 
        echo "\"log-driver\": \"json-file\"," >> /etc/docker/daemon.json 
        echo "\"log-opts\": {" >> /etc/docker/daemon.json 
        echo "\"max-size\": \"100m\"" >> /etc/docker/daemon.json 
        echo "}," >> /etc/docker/daemon.json 
        echo "\"storage-driver\": \"overlay2\"" >> /etc/docker/daemon.json 
        echo "}" >> /etc/docker/daemon.json 
        mkdir -p /etc/systemd/system/docker.service.d
        systemctl daemon-reload
        systemctl restart docker
    fi
    if [ "$DISTRO" == "Debian" ]; then
        curl -fsSL https://download.docker.com/linux/debian/gpg | apt-key add -
        add-apt-repository "deb [arch=amd64] https://download.docker.com/linux/debian $(lsb_release -cs) stable"
        apt-get update && apt-get install -y containerd.io=1.2.10-3 docker-ce=5:19.03.4~3-0~debian-$(lsb_release -cs) docker-ce-cli=5:19.03.4~3-0~debian-$(lsb_release -cs)
        echo "{" > /etc/docker/daemon.json 
        echo "\"exec-opts\": [\"native.cgroupdriver=systemd\"]," >> /etc/docker/daemon.json 
        echo "\"log-driver\": \"json-file\"," >> /etc/docker/daemon.json 
        echo "\"log-opts\": {" >> /etc/docker/daemon.json 
        echo "\"max-size\": \"100m\"" >> /etc/docker/daemon.json 
        echo "}," >> /etc/docker/daemon.json 
        echo "\"storage-driver\": \"overlay2\"" >> /etc/docker/daemon.json 
        echo "}" >> /etc/docker/daemon.json 
        mkdir -p /etc/systemd/system/docker.service.d
        systemctl daemon-reload
        systemctl restart docker
    fi
    if [ "$DISTRO" == "CentOS" ]; then
        yum install -y yum-utils device-mapper-persistent-data lvm2
        yum-config-manager --add-repo https://download.docker.com/linux/centos/docker-ce.repo
        yum update
        yum install -y containerd.io-1.2.10 docker-ce-19.03.4 docker-ce-cli-19.03.4
        mkdir /etc/docker
        echo "{" > /etc/docker/daemon.json 
        echo "\"exec-opts\": [\"native.cgroupdriver=systemd\"]," >> /etc/docker/daemon.json 
        echo "\"log-driver\": \"json-file\"," >> /etc/docker/daemon.json 
        echo "\"log-opts\": {" >> /etc/docker/daemon.json 
        echo "\"max-size\": \"100m\"" >> /etc/docker/daemon.json 
        echo "}," >> /etc/docker/daemon.json 
        echo "\"storage-driver\": \"overlay2\"," >> /etc/docker/daemon.json 
        echo "\"storage-opts\": [" >> /etc/docker/daemon.json 
        echo "\"overlay2.override_kernel_check=true\"" >> /etc/docker/daemon.json 
        echo "]" >> /etc/docker/daemon.json 
        echo "}" >> /etc/docker/daemon.json 
        mkdir -p /etc/systemd/system/docker.service.d
        systemctl daemon-reload
        systemctl restart docker
        systemctl enable docker
    fi
}

do_install_kubernetes() {
    local DISTRO="$( get_linux_distro )"
    if [ "$DISTRO" == "Ubuntu" ] || [ "$DISTRO" == "Debian" ]; then
        # Ensure IP tables tooling does not use nftables backend
        update-alternatives --set iptables /usr/sbin/iptables-legacy
        update-alternatives --set ip6tables /usr/sbin/ip6tables-legacy
        update-alternatives --set arptables /usr/sbin/arptables-legacy
        update-alternatives --set ebtables /usr/sbin/ebtables-legacy
        # Configure kubernetes repository
        curl -s https://packages.cloud.google.com/apt/doc/apt-key.gpg | apt-key add -
        apt-add-repository "deb http://apt.kubernetes.io/ kubernetes-xenial main"
        apt-get update
        apt-get install -y kubelet kubeadm kubectl
    fi
    if [ "$DISTRO" == "CentOS" ]; then
        # Ensure IP tables tooling does not use nftables backend
        update-alternatives --set iptables /usr/sbin/iptables-legacy
        # Configure kubernetes repository
        echo "[kubernetes]" > /etc/yum.repos.d/kubernetes.repo
        echo "name=Kubernetes" >> /etc/yum.repos.d/kubernetes.repo
        echo "baseurl=https://packages.cloud.google.com/yum/repos/kubernetes-el7-x86_64" >> /etc/yum.repos.d/kubernetes.repo
        echo "enabled=1" >> /etc/yum.repos.d/kubernetes.repo
        echo "gpgcheck=1" >> /etc/yum.repos.d/kubernetes.repo
        echo "repo_gpgcheck=1" >> /etc/yum.repos.d/kubernetes.repo
        echo "gpgkey=https://packages.cloud.google.com/yum/doc/yum-key.gpg https://packages.cloud.google.com/yum/doc/rpm-package-key.gpg" >> /etc/yum.repos.d/kubernetes.repo
        echo "exclude=kube*" >> /etc/yum.repos.d/kubernetes.repo
        # Install kubeadm, kubelet and kubectl 
        yum install -y kubelet kubeadm kubectl --disableexcludes=kubernetes
        systemctl enable kubelet 
        systemctl start kubelet
    fi
}




get_current_user_home_dir() {
    local USER=""
    USER=$(whoami)
    local USER_DIR=""
    USER_DIR=$(getent passwd $USER | cut -d: -f6)

    echo "$USER_DIR"
}









do_setup_firewall() {
    if [ "$1" == "Debian" ]; then
        apt-get install -y ufw
    fi
    if [ "$1" == "Ubuntu" ] || [ "$1" == "Debian" ]; then
        # Setup firewall
        ufw --force enable
        ufw allow 22/tcp
        if [ "$2" == "master" ]; then
            ufw allow 53/udp
            ufw allow 443/tcp
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
        fi
        if [ "$2" == "worker" ]; then 
            ufw allow 53/udp
            ufw allow 6443/tcp
            ufw allow 10250/tcp
            ufw allow 10251/tcp
            ufw allow 10255/tcp
            ufw allow 30000:32767/tcp
            ufw allow 2379:2380/tcp
            # kube flannel
            ufw allow 8285/udp
            ufw allow 8472/udp
            # calico
            ufw allow 179/tcp

            ufw allow out on weave to 10.244.0.0/12
            ufw allow in on weave from 10.244.0.0/12

            if [ "$1" == "Debian" ]; then
                update-alternatives --set iptables /usr/sbin/iptables-legacy
                update-alternatives --set ip6tables /usr/sbin/ip6tables-legacy
            fi
        fi
        if [ "$2" == "database" ]; then 
            ufw allow 5432/tcp
        fi
        if [ "$2" == "slb" ]; then 
            ufw allow 80/tcp
            ufw allow 443/tcp
        fi
        if [ "$2" == "dns" ]; then 
            ufw allow Bind9
            ufw allow 53/tcp
        fi
        if [ "$2" == "nfs" ]; then
            ufw allow from $WORKER_SUBNET_IP to any port nfs
        fi
        if [ "$2" == "minio" ]; then
            ufw allow 2379:2380/tcp
            ufw allow 9000:9010/tcp
            ufw allow 9443/tcp
        fi
        ufw reload
    fi
    if [ "$1" == "CentOS" ]; then
        # Setup firewall
        firewall-cmd --permanent --add-port=22/tcp
        if [ "$2" == "master" ]; then
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
        fi
        if [ "$2" == "worker" ]; then 
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
        fi
        if [ "$2" == "database" ]; then 
            firewall-cmd --permanent --add-port=5432/tcp
        fi
        if [ "$2" == "slb" ]; then 
            firewall-cmd --permanent --add-port=80/tcp
            firewall-cmd --permanent --add-port=443/tcp
        fi
        if [ "$2" == "dns" ]; then
            firewall-cmd --permanent --add-service=dns
            firewall-cmd --permanent --add-port=53/tcp
        fi
        if [ "$2" == "nfs" ]; then
            firewall-cmd --permanent --zone=public --add-source=$WORKER_SUBNET_IP --add-service=nfs
        fi
        if [ "$2" == "minio" ]; then
            firewall-cmd --get-active-zones
            firewall-cmd --zone=public --add-port=2379-2380/tcp --permanent
            firewall-cmd --zone=public --add-port=9000-9010/tcp --permanent
            firewall-cmd --zone=public --add-port=9443/tcp --permanent
        fi
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
    local HOSTNAME=""
    HOSTNAME=$(hostname)
    local USER=""
    USER=$(whoami)

    # deactivate swap
    swapoff -a
    echo "Swap disabled temporarily! Setting up /etc/fstab for permanent swapoff."
    if [ "$1" == "Ubuntu" ]; then
        sed -i.bak 's/\/swap.img/#\/swap.img/g' /etc/fstab
    fi
    if [ "$1" == "Debian" ]; then
        sed -i.bak '/swap/ s/^/#/' /etc/fstab
    fi
    if [ "$1" == "CentOS" ]; then
        sed -i.bak 's/\/dev\/mapper\/centos-swap/#\/dev\/mapper\/centos-swap/g' /etc/fstab
    fi
    
    if [ "$2" == "master" ]; then
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
    fi
    if [ "$2" == "worker" ]; then
        echo "Please wait a moment..."
        sleep 10

        echo "Joining master node..."
        kubeadm join $MASTER_IP --token $MASTER_TOKEN --discovery-token-ca-cert-hash $MASTER_DISCOVERY_TOKEN
        echo "Kubernetes worker setup finished. You can now start to deploy your services."
    fi
}

do_install_haproxy() {
    if [ "$1" == "Ubuntu" ] || [ "$1" == "Debian" ];  then
        add-apt-repository -y ppa:vbernat/haproxy-1.8
        apt-get update
        apt-get install -y haproxy        
    fi
    if [ "$1" == "CentOS" ]; then
        yum install -y haproxy
    fi

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
        
    if [ "$1" == "Ubuntu" ] || [ "$1" == "Debian" ];  then
        service haproxy restart
    fi

    if [ "$1" == "CentOS" ]; then
        systemctl start haproxy
        systemctl enable haproxy
    fi
}

do_install_database() {
    local DB_PASSWORD=$(cat /dev/urandom | tr -dc 'a-zA-Z0-9' | fold -w 10 | head -n 1)
    if [ "$1" == "Ubuntu" ] || [ "$1" == "Debian" ]; then
        apt install -y curl ca-certificates gnupg
        curl https://www.postgresql.org/media/keys/ACCC4CF8.asc | sudo apt-key add -
        RELEASE=$(lsb_release -cs)
        echo "deb http://apt.postgresql.org/pub/repos/apt/ ${RELEASE}"-pgdg main | sudo tee  /etc/apt/sources.list.d/pgdg.list
        apt update
        apt -y install postgresql-10
        su -c "psql -U postgres -c \"CREATE USER $DB_USERNAME WITH SUPERUSER CREATEDB REPLICATION PASSWORD '$DB_PASSWORD';\"" postgres
        sed -i.bak "s/#listen_addresses\ =\ 'localhost'/listen_addresses\ =\ '*'/g" /etc/postgresql/10/main/postgresql.conf 
        sed -i.bak 's/\(host  *all  *all  *127.0.0.1\/32  *\)ident/\1md5/' /etc/postgresql/10/main/pg_hba.conf
        sed -i.bak 's/\(host  *all  *all  *::1\/128  *\)ident/\1md5/' /etc/postgresql/10/main/pg_hba.conf
        echo "host    all             all             0.0.0.0/0               md5" >> /etc/postgresql/10/main/pg_hba.conf
        systemctl restart postgresql
    fi
    if [ "$1" == "CentOS" ]; then
        sed -i.bak '/-\ Base/ i exclude=postgresql*' /etc/yum.repos.d/CentOS-Base.repo
        sed -i.bak '/-\ Updates/ i exclude=postgresql*' /etc/yum.repos.d/CentOS-Base.repo
        yum install -y https://download.postgresql.org/pub/repos/yum/reporpms/EL-7-x86_64/pgdg-redhat-repo-latest.noarch.rpm
        yum install -y postgresql10-server
        /usr/pgsql-10/bin/postgresql-10-setup initdb
        systemctl start postgresql-10
        su -c "psql -U postgres -c \"CREATE USER $DB_USERNAME WITH SUPERUSER CREATEDB REPLICATION PASSWORD '$DB_PASSWORD';\"" postgres
        sed -i.bak "s/#listen_addresses\ =\ 'localhost'/listen_addresses\ =\ '*'/g" /var/lib/pgsql/10/data/postgresql.conf
        sed -i.bak 's/\(host  *all  *all  *127.0.0.1\/32  *\)ident/\1md5/' /var/lib/pgsql/10/data/pg_hba.conf
        sed -i.bak 's/\(host  *all  *all  *::1\/128  *\)ident/\1md5/' /var/lib/pgsql/10/data/pg_hba.conf
        echo "host    all             all             0.0.0.0/0               md5" >> /var/lib/pgsql/10/data/pg_hba.conf
        systemctl restart postgresql-10
        systemctl enable postgresql-10
    fi
    echo "Your Database password is: $DB_PASSWORD"
}

do_install_bind9() {
    local HOST_IP=""
    HOST_IP=$(hostname -I | cut -d \  -f1)

    if [ "$1" == "Ubuntu" ] || [ "$1" == "Debian" ]; then
        if [ "$1" == "Ubuntu" ]; then
            apt-get install -y bind9 bind9utils bind9-doc
        fi
        if [ "$1" == "Debian" ]; then
            apt update
            apt install -y bind9 bind9utils bind9-doc
        fi
        
        sed -i.bak 's/OPTIONS=\"-u bind\"/OPTIONS=\"-u bind -4\"/g' /etc/default/bind9

        systemctl restart bind9

        # named.conf.options
        mv /etc/bind/named.conf.options /etc/bind/named.conf.options.bak
        echo "acl \"trusted\" {" > /etc/bind/named.conf.options
        echo "        $HOST_IP;             # ns1 - can be set to localhost" >> /etc/bind/named.conf.options
        echo "        $FRONTEND_SLB_IP;     # frontend SLB IP" >> /etc/bind/named.conf.options
        echo "        $BACKEND_SLB_IP;      # backend SLB IP" >> /etc/bind/named.conf.options
        echo "};" >> /etc/bind/named.conf.options
        echo "" >> /etc/bind/named.conf.options
        echo "options {" >> /etc/bind/named.conf.options
        echo "        directory \"/var/cache/bind\";" >> /etc/bind/named.conf.options
        echo "        recursion yes;                 # enables resursive queries" >> /etc/bind/named.conf.options
        echo "        allow-recursion { trusted; };  # allows recursive queries from \"trusted\" clients" >> /etc/bind/named.conf.options
        echo "        listen-on { $HOST_IP; };   # ns1 private IP address - listen on private network only" >> /etc/bind/named.conf.options
        echo "        allow-transfer { none; };      # disable zone transfers by default" >> /etc/bind/named.conf.options
        echo "" >> /etc/bind/named.conf.options
        echo "        forwarders {" >> /etc/bind/named.conf.options
        echo "                8.8.8.8;" >> /etc/bind/named.conf.options
        echo "                8.8.4.4;" >> /etc/bind/named.conf.options
        echo "        };" >> /etc/bind/named.conf.options
        echo "" >> /etc/bind/named.conf.options
        echo "        dnssec-validation auto;" >> /etc/bind/named.conf.options
        if [ "$1" == "Ubuntu" ]; then
            echo "        auth-nxdomain no;    # conform to RFC1035" >> /etc/bind/named.conf.options
        fi
        echo "        listen-on-v6 { any; };" >> /etc/bind/named.conf.options
        echo "};" >> /etc/bind/named.conf.options

        local IP=(${FRONTEND_SLB_IP//./ });
        # named.conf.local
        mv /etc/bind/named.conf.local /etc/bind/named.conf.local.bak
        echo "zone \"$SERVICE_DOMAIN\" {" > /etc/bind/named.conf.local
        echo "    type master;" >> /etc/bind/named.conf.local
        echo "    file \"/etc/bind/zones/db.$SERVICE_DOMAIN\"; # zone file path" >> /etc/bind/named.conf.local
        echo "};" >> /etc/bind/named.conf.local
        echo "" >> /etc/bind/named.conf.local
        echo "zone \"${IP[1]}.${IP[0]}.in-addr.arpa\" {" >> /etc/bind/named.conf.local
        echo "    type master;" >> /etc/bind/named.conf.local
        echo "    file \"/etc/bind/zones/db.${IP[0]}.${IP[1]}\";  # x.y.0.0/16 subnet" >> /etc/bind/named.conf.local
        echo "};" >> /etc/bind/named.conf.local

        mkdir /etc/bind/zones
        echo "\$TTL    604800" > /etc/bind/zones/db.$SERVICE_DOMAIN
        echo "@       IN      SOA     ns1.$SERVICE_DOMAIN. admin.$SERVICE_DOMAIN. (" >> /etc/bind/zones/db.$SERVICE_DOMAIN
        echo "                  3     ; Serial" >> /etc/bind/zones/db.$SERVICE_DOMAIN
        echo "             604800     ; Refresh" >> /etc/bind/zones/db.$SERVICE_DOMAIN
        echo "              86400     ; Retry" >> /etc/bind/zones/db.$SERVICE_DOMAIN
        echo "            2419200     ; Expire" >> /etc/bind/zones/db.$SERVICE_DOMAIN
        echo "             604800 )   ; Negative Cache TTL" >> /etc/bind/zones/db.$SERVICE_DOMAIN
        echo ";" >> /etc/bind/zones/db.$SERVICE_DOMAIN
        echo "; name servers - NS records" >> /etc/bind/zones/db.$SERVICE_DOMAIN
        echo "     IN      NS      ns1.$SERVICE_DOMAIN." >> /etc/bind/zones/db.$SERVICE_DOMAIN
        echo "" >> /etc/bind/zones/db.$SERVICE_DOMAIN
        echo "; name servers - A records" >> /etc/bind/zones/db.$SERVICE_DOMAIN
        echo "ns1.$SERVICE_DOMAIN.          IN      A       $HOST_IP" >> /etc/bind/zones/db.$SERVICE_DOMAIN
        echo "" >> /etc/bind/zones/db.$SERVICE_DOMAIN
        echo "; ${IP[0]}.${IP[1]}.0.0/16 - A records" >> /etc/bind/zones/db.$SERVICE_DOMAIN
        echo "$FRONTEND_SUB_DOMAIN.$SERVICE_DOMAIN.        IN      A      $FRONTEND_SLB_IP" >> /etc/bind/zones/db.$SERVICE_DOMAIN
        echo "$BACKEND_SUB_DOMAIN.$SERVICE_DOMAIN.        IN      A      $BACKEND_SLB_IP" >> /etc/bind/zones/db.$SERVICE_DOMAIN

        local IP_FRONTEND=(${FRONTEND_SLB_IP//./ });
        local IP_BACKEND=(${BACKEND_SLB_IP//./ });
        local IP_HOST=(${HOST_IP//./ });

        echo "\$TTL    604800" > /etc/bind/zones/db.${IP[0]}.${IP[1]}
        echo "@       IN      SOA     $SERVICE_DOMAIN. admin.$SERVICE_DOMAIN. (" >> /etc/bind/zones/db.${IP[0]}.${IP[1]}
        echo "                  2     ; Serial" >> /etc/bind/zones/db.${IP[0]}.${IP[1]}
        echo "             604800     ; Refresh" >> /etc/bind/zones/db.${IP[0]}.${IP[1]}
        echo "              86400     ; Retry" >> /etc/bind/zones/db.${IP[0]}.${IP[1]}
        echo "            2419200     ; Expire" >> /etc/bind/zones/db.${IP[0]}.${IP[1]}
        echo "             604800 )   ; Negative Cache TTL" >> /etc/bind/zones/db.${IP[0]}.${IP[1]}
        #echo ";" >> /etc/bind/zones/db.${IP[0]}.${IP[1]}
        echo "; name servers" >> /etc/bind/zones/db.${IP[0]}.${IP[1]}
        echo "     IN      NS      ns1.$SERVICE_DOMAIN." >> /etc/bind/zones/db.${IP[0]}.${IP[1]}
        echo "" >> /etc/bind/zones/db.${IP[0]}.${IP[1]}
        echo "; PTR Records" >> /etc/bind/zones/db.${IP[0]}.${IP[1]}
        echo "${IP_HOST[3]}.${IP_HOST[2]}   IN      PTR     ns1.$SERVICE_DOMAIN.    ; $HOST_IP" >> /etc/bind/zones/db.${IP[0]}.${IP[1]}
        echo "" >> /etc/bind/zones/db.${IP[0]}.${IP[1]}
        echo "${IP_FRONTEND[3]}.${IP_FRONTEND[2]} IN      PTR     $FRONTEND_SUB_DOMAIN.$SERVICE_DOMAIN.  ; $FRONTEND_SLB_IP" >> /etc/bind/zones/db.${IP[0]}.${IP[1]}
        echo "${IP_BACKEND[3]}.${IP_BACKEND[2]} IN      PTR     $BACKEND_SUB_DOMAIN.$SERVICE_DOMAIN.  ; $BACKEND_SLB_IP" >> /etc/bind/zones/db.${IP[0]}.${IP[1]}

        systemctl restart bind9
    fi
    if [ "$1" == "CentOS" ]; then
        yum install -y bind bind-utils

        mv /etc/named.conf /etc/named.conf.bak
        echo "acl \"trusted\" {" > /etc/named.conf
        echo "        $HOST_IP;             # ns1 - can be set to localhost" >> /etc/named.conf
        echo "        $FRONTEND_SLB_IP;     # frontend SLB IP" >> /etc/named.conf
        echo "        $BACKEND_SLB_IP;      # backend SLB IP" >> /etc/named.conf
        echo "};" >> /etc/named.conf
        echo "" >> /etc/named.conf
        echo "options {" >> /etc/named.conf
        echo "        listen-on port 53 { 127.0.0.1; $HOST_IP; };" >> /etc/named.conf
        echo "        #listen-on-v6 port 53 { ::1; };" >> /etc/named.conf
        echo "        directory 	\"/var/named\";" >> /etc/named.conf
        echo "        dump-file 	\"/var/named/data/cache_dump.db\";" >> /etc/named.conf
        echo "        statistics-file \"/var/named/data/named_stats.txt\";" >> /etc/named.conf
        echo "        memstatistics-file \"/var/named/data/named_mem_stats.txt\";" >> /etc/named.conf
        echo "        recursing-file  \"/var/named/data/named.recursing\";" >> /etc/named.conf
        echo "        secroots-file   \"/var/named/data/named.secroots\";" >> /etc/named.conf
        echo "        allow-transfer { none; };      # disable zone transfers by default" >> /etc/named.conf
        echo "        allow-query     { trusted; };" >> /etc/named.conf
        echo "" >> /etc/named.conf
        echo "        recursion yes;" >> /etc/named.conf
        echo "" >> /etc/named.conf
        echo "        dnssec-enable yes;" >> /etc/named.conf
        echo "        dnssec-validation yes;" >> /etc/named.conf
        echo "" >> /etc/named.conf
        echo "        bindkeys-file \"/etc/named.root.key\";" >> /etc/named.conf
        echo "" >> /etc/named.conf
        echo "        managed-keys-directory \"/var/named/dynamic\";" >> /etc/named.conf
        echo "" >> /etc/named.conf
        echo "        pid-file \"/run/named/named.pid\";" >> /etc/named.conf
        echo "        session-keyfile \"/run/named/session.key\";" >> /etc/named.conf
        echo "};" >> /etc/named.conf
        echo "" >> /etc/named.conf
        echo "logging {" >> /etc/named.conf
        echo "        channel default_debug {" >> /etc/named.conf
        echo "                file \"data/named.run\";" >> /etc/named.conf
        echo "                severity dynamic;" >> /etc/named.conf
        echo "        };" >> /etc/named.conf
        echo "};" >> /etc/named.conf
        echo "" >> /etc/named.conf
        echo "zone \".\" IN {" >> /etc/named.conf
        echo "        type hint;" >> /etc/named.conf
        echo "        file \"named.ca\";" >> /etc/named.conf
        echo "};" >> /etc/named.conf
        echo "" >> /etc/named.conf
        echo "include \"/etc/named.rfc1912.zones\";" >> /etc/named.conf
        echo "include \"/etc/named.root.key\";" >> /etc/named.conf
        echo "include \"/etc/named/named.conf.local\";" >> /etc/named.conf

        local IP=(${FRONTEND_SLB_IP//./ });
        # named.conf.local
        echo "zone \"$SERVICE_DOMAIN\" {" > /etc/named/named.conf.local
        echo "    type master;" >> /etc/named/named.conf.local
        echo "    file \"/etc/named/zones/db.$SERVICE_DOMAIN\"; # zone file path" >> /etc/named/named.conf.local
        echo "};" >> /etc/named/named.conf.local
        echo "" >> /etc/named/named.conf.local
        echo "zone \"${IP[1]}.${IP[0]}.in-addr.arpa\" {" >> /etc/named/named.conf.local
        echo "    type master;" >> /etc/named/named.conf.local
        echo "    file \"/etc/named/zones/db.${IP[0]}.${IP[1]}\";  # x.y.0.0/16 subnet" >> /etc/named/named.conf.local
        echo "};" >> /etc/named/named.conf.local

        chmod 755 /etc/named
        mkdir /etc/named/zones
        echo "\$TTL    604800" > /etc/named/zones/db.$SERVICE_DOMAIN
        echo "@       IN      SOA     ns1.$SERVICE_DOMAIN. admin.$SERVICE_DOMAIN. (" >> /etc/named/zones/db.$SERVICE_DOMAIN
        echo "                  3     ; Serial" >> /etc/named/zones/db.$SERVICE_DOMAIN
        echo "             604800     ; Refresh" >> /etc/named/zones/db.$SERVICE_DOMAIN
        echo "              86400     ; Retry" >> /etc/named/zones/db.$SERVICE_DOMAIN
        echo "            2419200     ; Expire" >> /etc/named/zones/db.$SERVICE_DOMAIN
        echo "             604800 )   ; Negative Cache TTL" >> /etc/named/zones/db.$SERVICE_DOMAIN
        echo ";" >> /etc/named/zones/db.$SERVICE_DOMAIN
        echo "; name servers - NS records" >> /etc/named/zones/db.$SERVICE_DOMAIN
        echo "     IN      NS      ns1.$SERVICE_DOMAIN." >> /etc/named/zones/db.$SERVICE_DOMAIN
        echo "" >> /etc/named/zones/db.$SERVICE_DOMAIN
        echo "; name servers - A records" >> /etc/named/zones/db.$SERVICE_DOMAIN
        echo "ns1.$SERVICE_DOMAIN.          IN      A       $HOST_IP" >> /etc/named/zones/db.$SERVICE_DOMAIN
        echo "" >> /etc/named/zones/db.$SERVICE_DOMAIN
        echo "; ${IP[0]}.${IP[1]}.0.0/16 - A records" >> /etc/named/zones/db.$SERVICE_DOMAIN
        echo "$FRONTEND_SUB_DOMAIN.$SERVICE_DOMAIN.        IN      A      $FRONTEND_SLB_IP" >> /etc/named/zones/db.$SERVICE_DOMAIN
        echo "$BACKEND_SUB_DOMAIN.$SERVICE_DOMAIN.        IN      A      $BACKEND_SLB_IP" >> /etc/named/zones/db.$SERVICE_DOMAIN

        local IP_FRONTEND=(${FRONTEND_SLB_IP//./ });
        local IP_BACKEND=(${BACKEND_SLB_IP//./ });
        local IP_HOST=(${HOST_IP//./ });

        echo "\$TTL    604800" > /etc/named/zones/db.${IP[0]}.${IP[1]}
        echo "@       IN      SOA     $SERVICE_DOMAIN. admin.$SERVICE_DOMAIN. (" >> /etc/named/zones/db.${IP[0]}.${IP[1]}
        echo "                  3     ; Serial" >> /etc/named/zones/db.${IP[0]}.${IP[1]}
        echo "             604800     ; Refresh" >> /etc/named/zones/db.${IP[0]}.${IP[1]}
        echo "              86400     ; Retry" >> /etc/named/zones/db.${IP[0]}.${IP[1]}
        echo "            2419200     ; Expire" >> /etc/named/zones/db.${IP[0]}.${IP[1]}
        echo "             604800 )   ; Negative Cache TTL" >> /etc/named/zones/db.${IP[0]}.${IP[1]}
        #echo ";" >> /etc/named/zones/db.${IP[0]}.${IP[1]}
        echo "; name servers" >> /etc/named/zones/db.${IP[0]}.${IP[1]}
        echo "     IN      NS      ns1.$SERVICE_DOMAIN." >> /etc/named/zones/db.${IP[0]}.${IP[1]}
        echo "" >> /etc/named/zones/db.${IP[0]}.${IP[1]}
        echo "; PTR Records" >> /etc/named/zones/db.${IP[0]}.${IP[1]}
        echo "${IP_HOST[3]}.${IP_HOST[2]}   IN      PTR     ns1.$SERVICE_DOMAIN.    ; $HOST_IP" >> /etc/named/zones/db.${IP[0]}.${IP[1]}
        echo "" >> /etc/named/zones/db.${IP[0]}.${IP[1]}
        echo "${IP_FRONTEND[3]}.${IP_FRONTEND[2]} IN      PTR     $FRONTEND_SUB_DOMAIN.$SERVICE_DOMAIN.  ; $FRONTEND_SLB_IP" >> /etc/named/zones/db.${IP[0]}.${IP[1]}
        echo "${IP_BACKEND[3]}.${IP_BACKEND[2]} IN      PTR     $BACKEND_SUB_DOMAIN.$SERVICE_DOMAIN.  ; $BACKEND_SLB_IP" >> /etc/named/zones/db.${IP[0]}.${IP[1]}

        systemctl start named
        systemctl enable named
    fi
}

do_install_nfs() {
    if [ "$1" == "Ubuntu" ] || [ "$1" == "Debian" ]; then
        if [ "$1" == "Ubuntu" ]; then
            apt-get install -y nfs-kernel-server
        fi

        if [ "$1" == "Debian" ]; then
            apt-get install -y nfs-kernel-server nfs-common
        fi

        mkdir -p /mnt/shared
        chown nobody:nogroup /mnt/shared
        chmod 755 /mnt/shared

        echo "/mnt/shared $WORKER_SUBNET_IP(rw,sync,no_root_squash,no_subtree_check)" > /etc/exports

        exportfs -a

        systemctl restart nfs-kernel-server
        
    fi
    if [ "$1" == "CentOS" ]; then
        yum -y install nfs-utils

        mkdir -p /mnt/shared
        chown nfsnobody:nfsnobody /mnt/shared
        chmod 755 /mnt/shared

        echo "/mnt/shared $WORKER_SUBNET_IP(rw,sync,no_root_squash,no_subtree_check)" > /etc/exports

        exportfs -a

        systemctl enable nfs-server.service
        systemctl start nfs-server.service
    fi
}

do_install_minio3() {
    if [ "$1" == "Ubuntu" ] || [ "$1" == "Debian" ]; then
        #local HOST_IP=""
        #HOST_IP=$(hostname -I | cut -d \  -f1)
        # Install NFS Client for NAS
        apt-get install -y nfs-common
        mkdir -p /mnt/$NAS_IP_ADDRESS/shared
        mount -t nfs $NAS_IP_ADDRESS:$NAS_EXPORTED_FOLDER /mnt/$NAS_IP_ADDRESS/shared
        
        # persisting mount in fstab
        echo "$NAS_IP_ADDRESS:$NAS_EXPORTED_FOLDER /mnt/$NAS_IP_ADDRESS/shared nfs defaults 0 0" >> /etc/fstab
        if [ "$1" == "Ubuntu" ]; then
            apt install -y openjdk-8-jdk
            export JAVA_HOME=/usr/lib/jvm/java-8-openjdk-amd64
            export PATH=$PATH:$JAVA_HOME/bin
            
        fi

        if [ "$1" == "Debian" ]; then
            echo "DEBIAN"
        fi
        
    fi
    if [ "$1" == "CentOS" ]; then
        yum install -y nfs-utils
        mkdir -p /mnt/$NAS_IP_ADDRESS/shared
        mount -t nfs $NAS_IP_ADDRESS:$NAS_EXPORTED_FOLDER /mnt/$NAS_IP_ADDRESS/shared/

    fi

    do_install_docker "$1"

    #docker run -p 9443:9443 --name key-manager -d --restart always \
    #    wso2/wso2is-km:5.7.0

    docker run -p 9443:9443 --name key-manager -d --restart always \ 
        wso2/wso2is:5.7.0

    #docker run -p 8280:8280 -p 8243:8243 -p 9443:9443 --name api-manager -d --restart always \
    #    wso2/wso2am:3.1.0

    rm -rf /tmp/etcd-data.tmp && mkdir -p /tmp/etcd-data.tmp && \
        docker rmi gcr.io/etcd-development/etcd:v3.3.9 || true && \
        docker run -d --restart always \
        -p 2379:2379 \
        -p 2380:2380 \
        --mount type=bind,source=/tmp/etcd-data.tmp,destination=/etcd-data \
        --name etcd-gcr \
        gcr.io/etcd-development/etcd:v3.3.9 \
        /usr/local/bin/etcd \
        --name s1 \
        --data-dir /etcd-data \
        --listen-client-urls http://0.0.0.0:2379 \
        --advertise-client-urls http://0.0.0.0:2379 \
        --listen-peer-urls http://0.0.0.0:2380 \
        --initial-advertise-peer-urls http://0.0.0.0:2380 \
        --initial-cluster s1=http://0.0.0.0:2380 \
        --initial-cluster-token tkn \
        --initial-cluster-state new

    docker run --link key-manager --link etcd-gcr -p 9000:9000 --name minio-nas -d --restart always \
        -e "MINIO_ACCESS_KEY=$MINIO_ACCESS_KEY" \
        -e "MINIO_SECRET_KEY=$MINIO_SECRET_KEY" \
        -e "MINIO_IDENTITY_OPENID_CONFIG_URL=http://key-manager:9443/oauth2/oidcdiscovery/.well-known/openid-configuration" \
        -e "MINIO_IDENTITY_OPENID_CLIENT_ID=843351d4-1080-11ea-aa20-271ecba3924a" \
        -e "MINIO_ETCD_ENDPOINTS=http://etcd-gcr:2379" \
        -v /mnt/$NAS_IP_ADDRESS/shared:/shared/vol \
        minio/minio gateway nas /shared/vol
}

do_install_minio2() {
    if [ "$1" == "Ubuntu" ] || [ "$1" == "Debian" ]; then
        #local HOST_IP=""
        #HOST_IP=$(hostname -I | cut -d \  -f1)
        # Install NFS Client for NAS
        apt-get install -y nfs-common unzip openjdk-8-jdk
        mkdir -p /mnt/$NAS_IP_ADDRESS/shared
        mount -t nfs $NAS_IP_ADDRESS:$NAS_EXPORTED_FOLDER /mnt/$NAS_IP_ADDRESS/shared
        
        # persisting mount in fstab
        echo "$NAS_IP_ADDRESS:$NAS_EXPORTED_FOLDER /mnt/$NAS_IP_ADDRESS/shared nfs defaults 0 0" >> /etc/fstab
        if [ "$1" == "Ubuntu" ]; then
            echo "export JAVA_HOME=/usr/lib/jvm/java-8-openjdk-amd64" >> ~/.bashrc
            echo "export PATH=\$PATH:\$JAVA_HOME/bin" >> ~/.bashrc
            source ~/.bashrc
        fi

        if [ "$1" == "Debian" ]; then
            echo "DEBIAN"
        fi
        
    fi
    if [ "$1" == "CentOS" ]; then
        yum install -y nfs-utils
        mkdir -p /mnt/$NAS_IP_ADDRESS/shared
        mount -t nfs $NAS_IP_ADDRESS:$NAS_EXPORTED_FOLDER /mnt/$NAS_IP_ADDRESS/shared/

    fi

    do_install_docker "$1"

    # Install WSO 2 Identity Server
    wget https://github.com/wso2/product-is/releases/download/v5.10.0/wso2is-5.10.0.zip
    unzip wso2is-5.10.0.zip -d /opt/WSO2/

    sed -i.bak 's/<IdentityOAuthTokenGenerator>org.wso2.carbon.identity.oauth2.token.OauthTokenIssuerImpl<\/IdentityOAuthTokenGenerator>/<IdentityOAuthTokenGenerator>org.wso2.carbon.identity.oauth2.token.JWTTokenIssuer<\/IdentityOAuthTokenGenerator>/' /opt/WSO2/wso2is-5.10.0/repository/conf/identity/identity.xml

    echo "#! /bin/sh" > /etc/init.d/identityserver
    echo "### BEGIN INIT INFO" >> /etc/init.d/identityserver
    echo "# Provides:          wso2is" >> /etc/init.d/identityserver
    echo "# Required-Start:    \$all" >> /etc/init.d/identityserver
    echo "# Required-Stop:" >> /etc/init.d/identityserver
    echo "# Default-Start:     2 3 4 5" >> /etc/init.d/identityserver
    echo "# Default-Stop:" >> /etc/init.d/identityserver
    echo "# Short-Description: starts the wso2 identity server" >> /etc/init.d/identityserver
    echo "### END INIT INFO" >> /etc/init.d/identityserver
    echo "export JAVA_HOME=\"/usr/lib/jvm/java-8-openjdk-amd64\"" >> /etc/init.d/identityserver
    echo "" >> /etc/init.d/identityserver
    echo "startcmd='/opt/WSO2/wso2is-5.10.0/bin/wso2server.sh start > /dev/null &'" >> /etc/init.d/identityserver
    echo "restartcmd='/opt/WSO2/wso2is-5.10.0/bin/wso2server.sh restart > /dev/null &'" >> /etc/init.d/identityserver
    echo "stopcmd='/opt/WSO2/wso2is-5.10.0/bin/wso2server.sh stop > /dev/null &'" >> /etc/init.d/identityserver
    echo "" >> /etc/init.d/identityserver
    echo "case \"\$1\" in" >> /etc/init.d/identityserver
    echo "start)" >> /etc/init.d/identityserver
    echo "   echo \"Starting WSO2 Identity Server ...\"" >> /etc/init.d/identityserver
    #echo "   su -c \"\${startcmd}\" user1" >> /etc/init.d/identityserver
    echo "   \${startcmd}" >> /etc/init.d/identityserver
    echo ";;" >> /etc/init.d/identityserver
    echo "restart)" >> /etc/init.d/identityserver
    echo "   echo \"Re-starting WSO2 Identity Server ...\"" >> /etc/init.d/identityserver
    #echo "   su -c \"\${restartcmd}\" user1" >> /etc/init.d/identityserver
    echo "   \${restartcmd}" >> /etc/init.d/identityserver
    echo ";;" >> /etc/init.d/identityserver
    echo "stop)" >> /etc/init.d/identityserver
    echo "   echo \"Stopping WSO2 Identity Server ...\"" >> /etc/init.d/identityserver
    #echo "   su -c \"\${stopcmd}\" user1" >> /etc/init.d/identityserver
    echo "   \${stopcmd}" >> /etc/init.d/identityserver
    echo ";;" >> /etc/init.d/identityserver
    echo "*)" >> /etc/init.d/identityserver
    echo "   echo \"Usage: \$0 {start|stop|restart}\"" >> /etc/init.d/identityserver
    echo "exit 1" >> /etc/init.d/identityserver
    echo "esac" >> /etc/init.d/identityserver

    update-rc.d identityserver defaults
    service identityserver start

    # Install ETCD 
    rm -rf /tmp/etcd-data.tmp && mkdir -p /tmp/etcd-data.tmp && \
        docker rmi gcr.io/etcd-development/etcd:v3.3.9 || true && \
        docker run -d --restart always \
        -p 2379:2379 \
        -p 2380:2380 \
        --mount type=bind,source=/tmp/etcd-data.tmp,destination=/etcd-data \
        --name etcd-gcr \
        gcr.io/etcd-development/etcd:v3.3.9 \
        /usr/local/bin/etcd \
        --name s1 \
        --data-dir /etcd-data \
        --listen-client-urls http://0.0.0.0:2379 \
        --advertise-client-urls http://0.0.0.0:2379 \
        --listen-peer-urls http://0.0.0.0:2380 \
        --initial-advertise-peer-urls http://0.0.0.0:2380 \
        --initial-cluster s1=http://0.0.0.0:2380 \
        --initial-cluster-token tkn \
        --initial-cluster-state new

    # Install Minio

    wget https://dl.min.io/server/minio/release/linux-amd64/minio
    mv minio /usr/local/bin/minio
    chmod +x /usr/local/bin/minio

    echo "MINIO_VOLUMES=\"/mnt/$NAS_IP_ADDRESS/shared/\"" > /etc/default/minio
    echo "MINIO_ACCESS_KEY=$MINIO_ACCESS_KEY" >> /etc/default/minio
    echo "MINIO_SECRET_KEY=$MINIO_SECRET_KEY" >> /etc/default/minio
    echo "MINIO_IDENTITY_OPENID_CONFIG_URL=https://localhost:9443/oauth2/oidcdiscovery/.well-known/openid-configuration" >> /etc/default/minio
    echo "MINIO_IDENTITY_OPENID_CLIENT_ID=843351d4-1080-11ea-aa20-271ecba3924a" >> /etc/default/minio
    echo "MINIO_ETCD_ENDPOINTS=http://localhost:2379" >> /etc/default/minio

    echo "[Unit]" > /etc/systemd/system/minio.service
    echo "Documentation=https://docs.min.io" >> /etc/systemd/system/minio.service
    echo "Wants=network-online.target" >> /etc/systemd/system/minio.service
    echo "After=network-online.target" >> /etc/systemd/system/minio.service
    echo "AssertFileIsExecutable=/usr/local/bin/minio" >> /etc/systemd/system/minio.service
    echo "" >> /etc/systemd/system/minio.service
    echo "[Service]" >> /etc/systemd/system/minio.service
    echo "WorkingDirectory=/usr/local/" >> /etc/systemd/system/minio.service
    echo "" >> /etc/systemd/system/minio.service
    echo "User=minio-user" >> /etc/systemd/system/minio.service
    echo "Group=minio-user" >> /etc/systemd/system/minio.service
    echo "" >> /etc/systemd/system/minio.service
    echo "EnvironmentFile=/etc/default/minio" >> /etc/systemd/system/minio.service
    echo "ExecStartPre=/bin/bash -c \"if [ -z \\\"\${MINIO_VOLUMES}\\\" ]; then echo \\\"Variable MINIO_VOLUMES not set in /etc/default/minio\\\"; exit 1; fi\"" >> /etc/systemd/system/minio.service
    echo "" >> /etc/systemd/system/minio.service
    echo "ExecStart=/usr/local/bin/minio gateway nas \$MINIO_OPTS \$MINIO_VOLUMES" >> /etc/systemd/system/minio.service
    echo "" >> /etc/systemd/system/minio.service
    echo "# Let systemd restart this service always" >> /etc/systemd/system/minio.service
    echo "Restart=always" >> /etc/systemd/system/minio.service
    echo "" >> /etc/systemd/system/minio.service
    echo "# Specifies the maximum file descriptor number that can be opened by this process" >> /etc/systemd/system/minio.service
    echo "LimitNOFILE=65536" >> /etc/systemd/system/minio.service
    echo "" >> /etc/systemd/system/minio.service
    echo "# Disable timeout logic and wait until process is stopped" >> /etc/systemd/system/minio.service
    echo "TimeoutStopSec=infinity" >> /etc/systemd/system/minio.service
    echo "SendSIGKILL=no" >> /etc/systemd/system/minio.service
    echo "" >> /etc/systemd/system/minio.service
    echo "[Install]" >> /etc/systemd/system/minio.service
    echo "WantedBy=multi-user.target" >> /etc/systemd/system/minio.service
    echo "" >> /etc/systemd/system/minio.service
    echo "# Built for \${project.name}-\${project.version} (\${project.name})" >> /etc/systemd/system/minio.service

    systemctl enable minio.service
}

do_install_minio() {
    if [ "$1" == "Ubuntu" ] || [ "$1" == "Debian" ]; then
        # Install NFS Client for NAS
        apt-get install -y nfs-common
        mkdir -p /mnt/$NAS_IP_ADDRESS/shared
        mount -t nfs $NAS_IP_ADDRESS:$NAS_EXPORTED_FOLDER /mnt/$NAS_IP_ADDRESS/shared
        
        # persisting mount in fstab
        echo "$NAS_IP_ADDRESS:$NAS_EXPORTED_FOLDER /mnt/$NAS_IP_ADDRESS/shared nfs defaults 0 0" >> /etc/fstab
        
    fi
    if [ "$1" == "CentOS" ]; then
        # Install NFS Client for NAS
        yum install -y nfs-utils
        mkdir -p /mnt/$NAS_IP_ADDRESS/shared
        mount -t nfs $NAS_IP_ADDRESS:$NAS_EXPORTED_FOLDER /mnt/$NAS_IP_ADDRESS/shared/
    fi

    do_install_docker "$1"

    docker run -p 9000:9000 --name minio-nas -d --restart always \
        -e "MINIO_ACCESS_KEY=$MINIO_ACCESS_KEY" \
        -e "MINIO_SECRET_KEY=$MINIO_SECRET_KEY" \
        -v /mnt/$NAS_IP_ADDRESS/shared:/shared/vol \
        minio/minio gateway nas /shared/vol
}