#!/bin/sh

set -ex

CLIENT_CONFIG=dockernet.ovpn

if [ ! -f "/etc/openvpn/openvpn.conf" ]; then
	echo "Generating openvpn server config..."

	rm -f /etc/openvpn/ovpn_env.sh
	ovpn_genconfig -d -D -b -u udp://localhost \
		-e 'persist-remote-ip' \
		-e 'client-connect /usr/local/sbin/on-client-connect.sh' \
		-p "route 172.16.0.0 255.240.0.0" \
		-p "dhcp-option DOMAIN test"

	echo "Generating openvpn server config... done"
fi

if [ ! -d /etc/openvpn/pki ]; then
	echo "Generating openvpn pki data..."

	echo localhost | ovpn_initpki nopass
	easyrsa build-client-full client nopass

	echo "Generating openvpn pki data... done"
fi

if [ ! -f "/etc/openvpn/$CLIENT_CONFIG" ]; then
	echo "Generating openvpn client config..."

	ovpn_getclient client > "/etc/openvpn/$CLIENT_CONFIG"
	echo '#viscosity name DOCKERNET' >> "/etc/openvpn/$CLIENT_CONFIG"

	echo "Generating openvpn client config... done"
fi

exec ovpn_run
