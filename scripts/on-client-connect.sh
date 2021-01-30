#!/bin/bash

ccd=$1
dnsserver=$(grep dockernet-dns-server /etc/hosts|head -n 1| awk '{ print $1 }')

( env ; echo CONFIG_FILE  ${ccd} ) >> /var/tmp/openvpn-up-client.log

cat <<-EOF > "$ccd"
	push "dhcp-option DNS ${dnsserver}"
EOF

exit 0
