#!/bin/bash
export DEBIAN_FRONTEND=noninteractive
OS=$(uname -m)
MYIP=$(curl -s https://api.ipify.org)
domain=$(cat /root/domain || echo "$MYIP") # Fallback ke IP jika domain tidak ada
MYIP2="s/xxxxxxxxx/$domain/g"

function ovpn_install() {
    rm -rf /etc/openvpn
    mkdir -p /etc/openvpn
    wget -q -O /etc/openvpn/vpn.zip "https://raw.githubusercontent.com/angga2103/autoscript-vip/main/install/vpn.zip"
    if [ $? -ne 0 ]; then
        echo "Error: Gagal mengunduh file vpn.zip"
        exit 1
    fi
    unzip -d /etc/openvpn/ /etc/openvpn/vpn.zip || { echo "Error: Gagal mengekstrak vpn.zip"; exit 1; }
    rm -f /etc/openvpn/vpn.zip
    chown -R root:root /etc/openvpn/server/easy-rsa/
}

function config_easy() {
    mkdir -p /usr/lib/openvpn/
    if [ -f /usr/lib/x86_64-linux-gnu/openvpn/plugins/openvpn-plugin-auth-pam.so ]; then
        cp /usr/lib/x86_64-linux-gnu/openvpn/plugins/openvpn-plugin-auth-pam.so /usr/lib/openvpn/openvpn-plugin-auth-pam.so
    else
        echo "Error: Plugin openvpn-plugin-auth-pam.so tidak ditemukan"
        exit 1
    fi
    sed -i 's/#AUTOSTART="all"/AUTOSTART="all"/g' /etc/default/openvpn
    systemctl enable --now openvpn-server@server-tcp
    systemctl enable --now openvpn-server@server-udp
    systemctl restart openvpn || { echo "Error: Gagal me-restart OpenVPN"; exit 1; }
}

function make_follow() {
    echo 1 > /proc/sys/net/ipv4/ip_forward
    sed -i 's/#net.ipv4.ip_forward=1/net.ipv4.ip_forward=1/g' /etc/sysctl.conf

    # Buat file konfigurasi OpenVPN
    for proto in tcp udp ws-ssl ssl; do
        port=1194
        [[ $proto == "udp" ]] && port=2200
        [[ $proto == "ws-ssl" || $proto == "ssl" ]] && port=443
        cat > /etc/openvpn/${proto}.ovpn <<-END
        client
        dev tun
        proto ${proto/tcp/tcp} # Ganti proto sesuai kebutuhan
        remote xxxxxxxxx ${port}
        resolv-retry infinite
        route-method exe
        nobind
        persist-key
        persist-tun
        auth-user-pass
        comp-lzo
        verb 3
        END
        sed -i $MYIP2 /etc/openvpn/${proto}.ovpn
    done
}

function cert_ovpn() {
    for proto in tcp udp ws-ssl ssl; do
        echo '<ca>' >> /etc/openvpn/${proto}.ovpn
        cat /etc/openvpn/server/ca.crt >> /etc/openvpn/${proto}.ovpn
        echo '</ca>' >> /etc/openvpn/${proto}.ovpn
        cp /etc/openvpn/${proto}.ovpn /var/www/html/${proto}.ovpn
    done

    # Buat file zip
    cd /var/www/html || exit
    zip Kyt-Project.zip tcp.ovpn udp.ovpn ssl.ovpn ws-ssl.ovpn > /dev/null 2>&1
}

function install_ovpn() {
    ovpn_install
    config_easy
    make_follow
    cert_ovpn
    systemctl enable openvpn
    systemctl start openvpn
    systemctl restart openvpn
}

install_ovpn
