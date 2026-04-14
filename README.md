# dockernet-access-server

A Docker container that exposes Docker's internal bridge network to the host
machine by bundling an OpenVPN server and a DNS server (dnsmasq). Connect from
your host via any OpenVPN client and resolve running containers by name.

Two deployment modes are supported:

- **Single container** -- builds from `Dockerfile`, runs both OpenVPN and DNS
  via supervisord in a single image.
- **Compose split** -- uses `docker-compose.yml` to run DNS and OpenVPN as
  separate containers with different base images.

## Prerequisites

- Docker (with BuildKit support for building from source)
- An OpenVPN client such as [Tunnelblick](https://tunnelblick.net/) (macOS)
  or [Viscosity](https://www.sparklabs.com/viscosity/)

## Quick Start: Single Container

Add the following service to your project's `docker-compose.yml`:

```yaml
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

To build the image from source instead of pulling from Docker Hub:

```bash
make build    # tags with git short-hash + latest
```

## Quick Start: Compose Split

The included `docker-compose.yml` runs DNS and OpenVPN as separate containers.
This is useful for development of the tool itself:

```bash
docker-compose up -d
docker-compose logs -f
```

## Connecting

On first startup the container generates a PKI and writes a client profile to
the mounted volume. For the single-container example above, look for
`.tunnel/dockernet.ovpn`. Import this file into your OpenVPN client.

Once connected you should be able to:

- Reach containers on the Docker bridge network by IP.
- Resolve running container names via the built-in DNS server.

## Environment Variables

| Variable | Default | Description |
|----------|---------|-------------|
| `DNS_DOMAIN` | `""` | Domain suffix for container DNS |
| `EXTRA_HOSTS` | `""` | Additional host entries for dnsmasq |
| `HOSTMACHINE_IP` | `""` | IP to reach the host machine |
| `NAMING` | `default` | Container naming strategy for DNS |
| `NETWORK` | `bridge` | Docker network to monitor |
| `FALLBACK_DNS` | `gateway.docker.internal` | Upstream DNS server |
| `OVPN_SERVER` | `192.168.255.0/24` | VPN server subnet used to assign client IPs |
| `OVPN_NETWORK` | `172.16.0.0/12` | Route pushed to clients for Docker network reachability |
| `OVPN_KEEPCONFIG` | (unset) | Skip config regeneration if set |
| `DEBUG` | (unset) | Enable bash tracing if non-empty |

## Docker Image

- **Image**: `evicertia/dockernet-access-server`
- **Base**: `kylemanna/openvpn:latest` (Alpine Linux)
- **Ports**: 53/udp, 53/tcp (DNS), 1194/udp (OpenVPN)
- **Volume**: `/etc/openvpn` -- PKI and config persistence

## Security

The `conf/` directory is gitignored and contains PKI private keys and
certificates -- never commit its contents. The container runs as root, which is
required for network manipulation and binding to port 53. The Docker socket is
mounted read-only but still grants container discovery access.

## Credits

Based on previous work by:

- [kylemanna/docker-openvpn](https://github.com/kylemanna/docker-openvpn)
- [wojas/docker-mac-network](https://github.com/wojas/docker-mac-network)
- [fardjad/docker-network-exposer](https://github.com/fardjad/docker-network-exposer)
- [ruudud/devdns](https://github.com/ruudud/devdns)

## License

[MIT](LICENSE)
