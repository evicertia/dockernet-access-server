#!/bin/bash

[[ -n "$DEBUG" ]] && set -x

set -e

LOCALADDR=$(hostname -i)
LOCALROUTE=$(ip -4 route |egrep  "src[[:space:]]+$(echo -n $LOCALADDR|sed -e 's/[]\/$*.^[]/\\&/g')"|awk '{ print $1 }')

: ${OVPN_DOMAIN:=test}
: ${OVPN_NETWORK:=$LOCALROUTE}
: ${OVPN_ENDPOINT:=udp://localhost}
: ${OVPN_CLIENTCFG:=dockernet.ovpn}
: ${OVPN_NETNAME:=DOCKERNET}
: ${OVPN_KEEPALIVE:=2 15}

RESET="\e[0;0m"

b=$(echo -en "\e[1;35m")
c=$(echo -en "\e[1;96m")
cat <<EOF
${b}  ____             _             _   _      _
${b} |  _ \  ___   ___| | _____ _ __| \ | | ___| |_
${b} | | | |/ _ \ / __| |/ / _ | '__|  \| |/ _ | __|
${b} | |_| | (_) | (__|   |  __| |  | |\  |  __| |_
${b} |____/ \___/ \___|_|\_\___|_|  |_| \_|\___|\__|
${c}        __     ______  _   _   ____                           
${c}        \ \   / |  _ \| \ | | / ___|  ___ _ ____   _____ _ __ 
${c}         \ \ / /| |_) |  \| | \___ \ / _ | '__\ \ / / _ | '__|
${c}          \ V / |  __/| |\  |  ___) |  __| |   \ V |  __| |   
${c}           \_/  |_|   |_| \_| |____/ \___|_|    \_/ \___|_|   
${c}                                                         
EOF
echo -e "${RESET}"

GENCLIENTCFG=0

if [ "$OVPN_KEEPCONFIG" != "1" -o ! -f "/etc/openvpn/openvpn.conf" ]; then
	echo "Generating openvpn server config..."

	rm -f /etc/openvpn/openvpn.conf /etc/openvpn/ovpn_env.sh
	source <(ipcalc -n -m "$OVPN_NETWORK")
	ovpn_genconfig -d -D -b -N -u "${OVPN_ENDPOINT}" \
		-k "${OVPN_KEEPALIVE}" \
		-e 'persist-remote-ip' \
		-e 'script-security 2' \
		-e 'client-connect /usr/local/sbin/on-client-connect.sh' \
		-p "route $NETWORK $NETMASK" \
		-p "dhcp-option DOMAIN ${OVPN_DOMAIN}"
	GENCLIENTCFG=1

	echo "Generating openvpn server config... done"
fi

if [ ! -d /etc/openvpn/pki ]; then
	echo "Generating openvpn pki data..."

	echo localhost | ovpn_initpki nopass
	easyrsa build-client-full client nopass
	GENCLIENTCFG=1

	echo "Generating openvpn pki data... done"
fi

if [ "$GENCLIENTCFG" == "1" -o ! -f "/etc/openvpn/$OVPN_CLIENTCFG" ]; then
	echo "Generating openvpn client config..."

	ovpn_getclient client > "/etc/openvpn/$OVPN_CLIENTCFG"
	echo "#viscosity name $OVPN_NETNAME" >> "/etc/openvpn/$OVPN_CLIENTCFG"

	echo "Generating openvpn client config... done"
fi

exec ovpn_run
