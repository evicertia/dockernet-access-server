#!/bin/bash

ccd=$1
dnsserver=$(grep dockernet-dns-server /etc/hosts|head -n 1| awk '{ print $1 }')

# if running as single-image container, fallback to our own address
[ -z "$dnsserver" ]&& dnsserver=$(hostname -i)

( env ; echo CONFIG_FILE  ${ccd} ) >> /var/tmp/openvpn-up-client.log

cat <<-EOF > "$ccd"
	push "dhcp-option DNS ${dnsserver}"
EOF

exit 0
