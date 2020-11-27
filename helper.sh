get_os() {
    local UNAME=""
    UNAME=$(uname | tr "[:upper:]" "[:lower:]")
    echo "$UNAME"
}

get_linux_distro () {
    local DISTRO=""
    DISTRO=$(awk -F= '/^NAME/{print $2}' /etc/os-release | tr -d '"' | cut -d' ' -f1)
    echo "$DISTRO"
}

get_linux_distro_version() {
    local DISTRO_VERSION=""

    if [ "$1" == "Ubuntu" ] || [ "$1" == "Debian" ]; then
        DISTRO_VERSION=$(lsb_release -r | cut -d: -f2 | sed s/'^\t'//)
    fi
    if [ "$1" == "CentOS" ]; then
        DISTRO_VERSION=$(cat /etc/centos-release | tr -dc '0-9.'|cut -d \. -f1)
    fi

    echo "$DISTRO_VERSION"
}