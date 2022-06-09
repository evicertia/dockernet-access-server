#!/bin/bash

[[ -n "$DEBUG" ]] && set -x

domain="${DNS_DOMAIN:-}"
fallbackdns="${FALLBACK_DNS:-8.8.8.8}"
hostmachineip="${HOSTMACHINE_IP:-172.17.0.1}"
network="${NETWORK:-bridge}"
naming="${NAMING:-default}"
read -r -a extrahosts <<< "$EXTRA_HOSTS"

dnsmasq_pid=""
dnsmasq_path="/etc/dnsmasq.d"
dnsmasq_hostsdir="/etc/hosts.d"
resolvconf_file="/mnt/resolv.conf"
resolvconf_comment="# added by devdns"
restart=0

RESET="\e[0;0m"
RED="\e[0;31;49m"
BRED="\e[1;31m"
BIRED="\e[1;91m"
RRED="\e[31;7m"
GREEN="\e[0;32;49m"
BGREEN="\e[1;32m"
BIGREEN="\e[1;92m"
YELLOW="\e[0;33;49m"
BYELLOW="\e[1;33m"
BPURPLE="\e[1;35m"
BIPURPLE="\e[1;95m"
BOLD="\e[1m"


trap shutdown SIGINT SIGTERM

waitport() {
	while ! nc -z localhost $1 ; do sleep 0.25 ; done
}

waitnport() {
	while nc -z localhost $1 ; do sleep 0.25 ; done
}

start_dnsmasq(){
	dnsmasq --keep-in-foreground &
	dnsmasq_pid=$!
}

reload_dnsmasq(){
	if [ $restart -eq 0 ]; then
		kill -HUP $dnsmasq_pid
	else
		kill $dnsmasq_pid
		waitnport 53
		start_dnsmasq
	fi
}

shutdown(){
	echo "Shutting down..."
	if [[ -f "$resolvconf_file" ]]; then
		ed -s "$resolvconf_file" <<EOF
g/${resolvconf_comment}/d
w
EOF
	fi
	kill $dnsmasq_pid
	exit 0
}

print_error() {
	local errcode="$1" arg="$2"
	case "$errcode" in
		network)
			echo -e "${BOLD}E Could not locate network '${network}'${RESET}"
			;;
		ip)
			echo -e "${BOLD}E Could not get IP for container '${arg}'${RESET}"
			;;
		*)
			;;
	esac
}

get_name(){
	local cid="$1"
	docker inspect -f '{{ .Name }}' "$cid" | sed "s,^/,,"
}

get_hostname(){
	local cid="$1"
	docker inspect -f '{{ .Config.Hostname }}' "$cid" | sed "s,^/,,"
}

get_domainname(){
	local cid="$1"
	docker inspect -f '{{ .Config.Domainname }}' "$cid" | sed "s,^/,,"
}

get_safename(){
	local name="$1"
	case "$naming" in
		full)
			# Replace _ with -, useful when using default Docker naming
			name="${name//_/-}"
			;;
		*)
			# Docker allows _ in names, but other than that same as RFC 1123
			# We remove everything from "_" and use the result as record.
			if [[ ! "$name" =~ ^[a-zA-Z0-9.-]+$ ]]; then
				name="${name%%_*}"
			fi
			;;
	esac

	echo "$name"
}

add_record(){
	local record="$1" ip="$2" fpath="$dnsmasq_hostsdir/$3"
	local pattern=$(echo "$1"| sed -e 's/[]\/$*.^[]/\\&/g')

	[[ -z "$ip" ]] && print_error "ip" "$record" && return 1
	[[ "$ip" == "<no value>" ]] && print_error "ip" "$record" && return 1

	if [[ -f "$fpath" ]] && grep -q "[[:space:]]${pattern}$" "$fpath"; then
		echo -e "${YELLOW}+ Replacing ${record} → ${ip}${RESET}"
		sed -i'' -e "/[[:space:]]${pattern}$/d" "${fpath}"
	else
		echo -e "${GREEN}+ Adding ${record} → ${ip}${RESET}"
	fi

	echo "$ip $record" >> "${fpath}"
}

set_wildcard_record(){
	local record="$1" ip="$2" fpath="${dnsmasq_path}/${3}.conf"

	[[ -z "$ip" ]] && print_error "ip" "$record" && return 1
	[[ "$ip" == "<no value>" ]] && print_error "ip" "$record" && return 1

	if [[ ! -f "$fpath" ]]; then
		echo -e "${GREEN}+ Adding *.${record} → ${ip}${RESET}"
	else
		echo -e "${YELLOW}+ Replacing *.${record} → ${ip}${RESET}"
	fi

	echo "address=/.${record}/${ip}" > "$fpath"

	restart=1
}

set_container_records(){
	local cid="$1" ip name safename record cnetwork hostname domainname
	cnetwork="$network"

	# set the network to the first detected network, if any
	if [[ "$network" == "auto" ]]; then
		cnetwork=$(docker inspect -f '{{ range $k, $v := .NetworkSettings.Networks }}{{ $k }}{{ end }}' "$cid" | head -n1)
		# abort if the container has no network interfaces, e.g.
		# if it inherited its network from another container
		[[ -z "$cnetwork" ]] && print_error "network" && return 1
	fi
	ip=$(docker inspect -f "{{with index .NetworkSettings.Networks \"${cnetwork}\"}}{{.IPAddress}}{{end}}" "$cid" | head -n1)
	name=$(get_name "$cid")
	safename=$(get_safename "$name")
	hostname=$(get_hostname "$cid")
	domainname=$(get_domainname "$cid")

	[ -n "$domain" ] && add_record "${safename}.${domain}" "$ip" "$safename" || :
	[ -n "$hostname" -a -n "$domain" -a "$domain" != "$domainname" ] && add_record "${hostname}.${domain}" "$ip" "$safename" || :
	[ -n "$hostname" -a -n "$domainname" ] && add_record "${hostname}.${domainname}" "$ip" "$safename" || :
	[ -z "$hostname" -a -n "$domainname" ] && set_wildcard_record "$domainname" "$ip" "$safename" || :
}

del_container_records(){
	local name="$1" safename=$(get_safename "$1")
	local wfile="$dnsmasq_path/${safename}.conf" hfile="$dnsmasq_hostsdir/${safename}"

	[ -f "$wfile" ] && rm "$wfile" && echo -e "${RED}- Removed wildcard record for ${name}${RESET}"
	[ -f "$hfile" ] && rm "$hfile" && echo -e "${RED}- Removed hosts records for ${name}${RESET}"
}

find_and_set_prev_record(){
	local name="$1" prevcid=$(docker ps -q -f "name=${name}.*" | head -n1)

	[[ -z "$prevcid" ]] && return 0

	echo -e "${YELLOW}+ Found other active container with matching name: ${name}${RESET}"
	set_container_records "$prevcid"
}

setup_listener(){
	local name
	while read -r _ _ event container meta; do
		case "$event" in
			start|rename)
				set_container_records "$container"
				reload_dnsmasq
				;;
			die)
				name=$(echo "$meta" | grep -Eow "name=[a-zA-Z0-9.-_]+" | cut -d= -f2 |head -n 1)
				[[ -z "$name" ]] && continue

				del_container_records "$name"
				sleep 1
				find_and_set_prev_record "$name"
				reload_dnsmasq
				;;
		esac
	done < <(docker events -f event=start -f event=die -f event=rename)
}

add_running_containers(){
	local ids
	ids=$(docker ps -q)
	for id in $ids; do
		set_container_records "$id"
	done
}

set_extra_records(){
	local host ip
	for record in "${extrahosts[@]}"; do
		host=${record%=*}
		ip=${record#*=}

		if [[ "$host" == .* ]]; then
			set_wildcard_record "$host" "$ip" "_extras"
		else
			add_record "$host" "$ip" "_extras"
		fi
	done
}

set_base_config(){
	echo "hostsdir=${dnsmasq_hostsdir}" > "${dnsmasq_path}/_hosts.conf"

	if [ -n "$domain" ]; then
		echo -e "auth-server=${domain}\nauth-zone=${domain}\n" > "${dnsmasq_path}/authzone.conf"
		echo -e "${GREEN}+ Set dnsmasq as authoritative for ${domain}${RESET}"
		echo "address=/.${domain}/${hostmachineip}" > "${dnsmasq_path}/hostmachine.conf"
		echo -e "${GREEN}+ Added *.${domain} → ${hostmachineip}${RESET}"
	elif [ -n "$(hostname -d)" ]; then
		echo -e "auth-server=$(hostname -d)\nauth-zone=$(hostname -d)\n" > "${dnsmasq_path}/authzone.conf"
		echo -e "${GREEN}+ Set dnsmasq as authoritative for $(hostname -d)${RESET}"
	fi
}

set_resolvconf(){

	if [[ -f "$resolvconf_file" ]]; then
		local ip=$(hostname -i)
		ed -s "$resolvconf_file" <<-EOF
			g/${resolvconf_comment}/d
			0a
			nameserver $ip $resolvconf_comment
			.
			w
EOF
		echo "Host machine resolv.conf configured to use devdns at ${ip}"
	fi
}

set_fallback_dns(){
	[ -z "${fallbackdns}" ] && print_error "Missing FALLBACK_DNS env variable." && exit 254

	if ! [[ ${fallbackdns} =~ ^[0-9]+\.[0-9]+\.[0-9]+\.[0-9]+$ ]]; then
		fallbackdns=$(getent hosts "${fallbackdns}" | awk '{ print $1 }')
		[ -z "${fallbackdns}" ] && print_error "Unable to resolve FALLBACK_DNS address." && exit 254
	fi

	sed -i "s/{{FALLBACK_DNS}}/${fallbackdns}/" "/etc/dnsmasq.conf"
	echo "Fallback DNS set to ${fallbackdns}"
}

print_startup_msg(){
	b=$(echo -en "${BIGREEN}")
	c=$(echo -en "${BRED}")
	cat <<EOF
${b}  ____             _             _   _      _
${b} |  _ \  ___   ___| | _____ _ __| \ | | ___| |_
${b} | | | |/ _ \ / __| |/ / _ | '__|  \| |/ _ | __|
${b} | |_| | (_) | (__|   |  __| |  | |\  |  __| |_
${b} |____/ \___/ \___|_|\_\___|_|  |_| \_|\___|\__|
${c}        ____  _   _ ____    ____
${c}       |  _ \| \ | / ___|  / ___|  ___ _ ____   _____ _ __
${c}       | | | |  \| \___ \  \___ \ / _ | '__\ \ / / _ | '__|
${c}       | |_| | |\  |___) |  ___) |  __| |   \ V |  __| |
${c}       |____/|_| \_|____/  |____/ \___|_|    \_/ \___|_|
${c}
EOF
	echo -e "${RESET}"
}

mkdir -p "$dnsmasq_path"
mkdir -p "$dnsmasq_hostsdir"
rm -f "$dnsmasq_path/*"
rm -f "$dnsmasq_hostsdir"/*


set -Eeo pipefail
print_startup_msg
set_fallback_dns
set_resolvconf
set_base_config
set_extra_records
add_running_containers
start_dnsmasq
set +Eeo pipefail

setup_listener

# vim: ai ts=4 sw=4 noet sts=4 ft=sh
