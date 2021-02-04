# dockernet-access-server
A docker container enabling access to docker's internal (bridge) network, by bundling an openvpn & dns server.
Also included a docker-compose setup which can be used instead of the single container bundling openvpn & dns server. 

# Using docker image
An example docker-compose code to instantate this image follows:

```
services:

  tunnel:
    image: evicertia/dockernet-access-server
    hostname: dockernet-access-server
    domainname: myapp.test
    init: true
    network_mode: myapp
    ports:
      - "1194:1194/udp"
    cap_add:
      - NET_ADMIN
    sysctls:
      net.ipv6.conf.default.forwarding: 1
      net.ipv6.conf.all.forwarding: 1
      net.ipv6.conf.all.disable_ipv6: 0
    environment:
      DNS_DOMAIN: ~
    volumes:
      - /var/run/docker.sock:/var/run/docker.sock:ro
      - ./.tunnel:/etc/openvpn
    healthcheck:
      test: ["CMD-SHELL", "nc -w0 -z -n 127.0.0.1 53"]
      interval: 5s
      timeout: 1s
      retries: 3

networks:
  myapp:
    driver: bridge

```

On startup, a new file would be created at .tunnel/dockernet.ovpn which can be imported into tunnelbrik/viscosity.

# Extra credits
This is partly based on previous work by:
 * https://github.com/kylemanna/docker-openvpn
 * https://github.com/wojas/docker-mac-network
 * https://github.com/fardjad/docker-network-exposer
 * https://github.com/ruudud/devdns

