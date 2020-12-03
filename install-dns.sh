#!/bin/bash
source functions.sh

do_install_bind9() {
    echo "Please enter app's SLB IP Address: "
    read SLB_IP
    echo "(echo) Application's SLB IP: $SLB_IP"
    echo "Please enter service's domain: "
    read SERVICE_DOMAIN
    echo "(echo) Service domain (only TLD - e.g. test.com): $SERVICE_DOMAIN"
    echo "Please enter application's subdomain: "
    read SUB_DOMAIN
    echo "(echo) Application sub domain: $SUB_DOMAIN"
    
    local DISTRO="$( get_linux_distro )"
    local HOST_IP=""
    HOST_IP=$(hostname -I | cut -d \  -f1)

    if [ "$DISTRO" == "Ubuntu" ] || [ "$DISTRO" == "Debian" ]; then
        apt-get update
        apt-get install -y bind9 bind9utils bind9-doc
        
        sed -i.bak 's/OPTIONS=\"-u bind\"/OPTIONS=\"-u bind -4\"/g' /etc/default/bind9

        systemctl restart bind9

        # named.conf.options
        mv /etc/bind/named.conf.options /etc/bind/named.conf.options.bak
        echo "acl \"trusted\" {" > /etc/bind/named.conf.options
        echo "        $HOST_IP;             # ns1 - can be set to localhost" >> /etc/bind/named.conf.options
        echo "        $SLB_IP;              # application SLB IP" >> /etc/bind/named.conf.options
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
        if [ "$DISTRO" == "Ubuntu" ]; then
            echo "        auth-nxdomain no;    # conform to RFC1035" >> /etc/bind/named.conf.options
        fi
        echo "        listen-on-v6 { any; };" >> /etc/bind/named.conf.options
        echo "};" >> /etc/bind/named.conf.options

        local IP=(${SLB_IP//./ });
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
        echo "$SUB_DOMAIN.$SERVICE_DOMAIN.        IN      A      $SLB_IP" >> /etc/bind/zones/db.$SERVICE_DOMAIN

        local IP_APP=(${SLB_IP//./ });
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
        echo "${IP_APP[3]}.${IP_APP[2]} IN      PTR     $SUB_DOMAIN.$SERVICE_DOMAIN.  ; $SLB_IP" >> /etc/bind/zones/db.${IP[0]}.${IP[1]}

        systemctl restart bind9
    fi
    if [ "$DISTRO" == "CentOS" ]; then
        yum install -y bind bind-utils

        mv /etc/named.conf /etc/named.conf.bak
        echo "acl \"trusted\" {" > /etc/named.conf
        echo "        $HOST_IP;             # ns1 - can be set to localhost" >> /etc/named.conf
        echo "        $SLB_IP;     # application SLB IP" >> /etc/named.conf
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

        local IP=(${SLB_IP//./ });
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
        echo "$SUB_DOMAIN.$SERVICE_DOMAIN.        IN      A      $SLB_IP" >> /etc/named/zones/db.$SERVICE_DOMAIN

        local IP_APP=(${SLB_IP//./ });
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
        echo "${IP_APP[3]}.${IP_APP[2]} IN      PTR     $SUB_DOMAIN.$SERVICE_DOMAIN.  ; $SLB_IP" >> /etc/named/zones/db.${IP[0]}.${IP[1]}

        systemctl start named
        systemctl enable named
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
        
        ufw allow Bind9
        ufw allow 53/tcp
        
        ufw reload
    fi
    if [ "$DISTRO" == "CentOS" ]; then
        # Setup firewall
        firewall-cmd --permanent --add-port=22/tcp
        
        firewall-cmd --permanent --add-service=dns
        firewall-cmd --permanent --add-port=53/tcp
        
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



echo "$( date ) Install Bind9 DNS script start"

# Step 1. Check OS type and version
echo "Checking system..."
do_check_os

# Step 2. Update the OS
echo "Updating operating system..."
do_os_update

# Step 3. Setup hostname
echo "Setup hostname..."
do_setup_hostname

# Step 4. Install bind9
echo "Install bind9..."
do_install_bind9

# Step 5. Setup firewall
echo "Setup Firewall"
do_setup_firewall

echo "$( date ) Install Bind9 DNS script end"