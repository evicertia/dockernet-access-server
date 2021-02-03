#!/bin/bash

RESET="\e[0;0m"
RED="\e[0;31;49m"
BRED="\e[1;31m"
BIRED="\e[1;91m"
RRED="\e[31;7m"
GREEN="\e[0;32;49m"
BGREE="\e[1;32m"
YELLOW="\e[0;33;49m"
BYELLOW="\e[1;33m"
BPURPLE="\e[1;35m"
BIPURPLE="\e[1;95m"
BOLD="\e[1m"


print_logo(){
        o=$(echo -en "\e[1;38;5;208m")
		b=$(echo -en "\e[1;38;5;27m")
		r=$(echo -en "${RESET}")
        cat <<-EOF
${o}            __${b}               _   _        ${r}
${o}   _____   / /${b}  ___ ___ _ __| |_(_) __ _  ${r}
${o}  / _ \ \ / / |${b}/ __/ _ \ '__| __| |/ _\` | ${r}
${o} |  __/\ V /| |${b} (_|  __/ |  | |_| | (_| | ${r}
${o}  \___| \_/ |_|${b}\___\___|_|   \__|_|\__,_| ${r}
${o}               ${b}                           ${r}
EOF
        echo -e "${RESET}"
}

print_logo

exec "$@"

# vim: ai ts=4 sw=4 noet sts=4 ft=sh
