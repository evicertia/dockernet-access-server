# AGENTS.md — dockernet-access-server

## Project Overview

Docker infrastructure tool that exposes Docker's internal bridge network to the
host via a bundled OpenVPN + DNS (dnsmasq) server. See `README.md` for usage,
environment variables, and deployment instructions.

## Build / Run Commands

```bash
# Build Docker image (tags with git short-hash + latest)
make build

# Push image to Docker Hub
make push

# Login to Docker Hub (requires DOCKER_USER / DOCKER_PASS env vars)
make login

# Run the split-service compose stack
docker-compose up -d

# Rebuild and restart a single service
docker-compose up -d --build <service>

# View logs
docker-compose logs -f
```

There is **no test suite, linter, or CI pipeline**. Validation is done by
running the container and verifying VPN + DNS resolution manually.

## Repository Layout

```
.
├── Dockerfile              # Single-container bundled image
├── Makefile                # build / push / login targets
├── docker-compose.yml      # Two-service split deployment
├── files/
│   ├── dnsmasq.conf        # dnsmasq configuration template
│   └── supervisord.conf    # supervisord config (dnssrv + ovpnsrv)
├── scripts/
│   ├── dnssrv.sh           # DNS server management (main logic)
│   ├── ovpnsrv.sh          # OpenVPN server setup and launcher
│   ├── evilogo.sh          # Entrypoint: prints logo, execs CMD
│   ├── on-client-connect.sh  # OpenVPN hook: pushes DNS to clients
│   └── wait-for-it.sh      # TCP port readiness utility
├── conf/                   # Runtime PKI/config (gitignored)
├── README.md
└── LICENSE                 # MIT
```

## Language and Shell Conventions

All source code is **Bash**. Follow these conventions strictly.

### Shebang and Safety

- Every script starts with `#!/bin/bash`.
- Use `set -Eeo pipefail` for strict error handling during initialization.
- Relax with `set +Eeo pipefail` before long-running event loops that must
  tolerate transient failures (see `dnssrv.sh` pattern).
- Support debug mode: `[[ -n "$DEBUG" ]] && set -x`.

### Naming

- **Functions**: `lowercase_with_underscores` (e.g., `start_dnsmasq`,
  `set_container_records`, `add_running_containers`).
- **Local variables**: lowercase with underscores (`local container_name`).
- **Environment / global variables**: `UPPER_SNAKE_CASE` (`DNS_DOMAIN`,
  `HOSTMACHINE_IP`, `FALLBACK_DNS`).
- **Constants / color codes**: `UPPER_SNAKE_CASE` defined at script top.

### Environment Variables and Defaults

- Use `${VAR:-default}` for read-only defaults.
- Use `: ${VAR:=default}` to assign defaults in-place.
- All configurable behavior is driven through environment variables, never
  hardcoded values.

### Script Structure Pattern

Follow the established ordering in existing scripts:

1. Shebang + debug toggle
2. `set -e` / `set -Eeo pipefail`
3. Color/constant definitions
4. Environment variable defaults
5. Helper function definitions
6. Signal trap setup (`trap shutdown SIGINT SIGTERM`)
7. Main initialization logic
8. Long-running process or `exec` to hand off

### Output and Logging

- Use ANSI color codes for structured terminal output (defined as variables at
  the top of each script: `RED`, `GREEN`, `YELLOW`, `BLUE`, `RESET`, etc.).
- Prefix log lines with a colored tag to identify the subsystem.
- Direct stdout/stderr to `/dev/fd/1` and `/dev/fd/2` in supervisord config.

### Process Management

- Use `exec` to replace the shell process when launching the final long-running
  command (e.g., `exec ovpn_run`, `exec "$@"`).
- Use `trap` + a `shutdown` function for graceful cleanup on SIGINT/SIGTERM.
- Supervisord manages process lifecycle; scripts should not daemonize.

### Docker Integration

- Interact with Docker via CLI (`docker inspect`, `docker ps`, `docker events`).
- Parse JSON output with `jq`-style inline parsing or `grep`/`sed` pipelines.
- Mount the Docker socket (`/var/run/docker.sock`) read-only.

### Error Handling

- Critical startup steps run under `set -Eeo pipefail`.
- Guard optional operations with explicit conditionals rather than relying on
  `set -e` to abort.
- Check file/directory existence before operating (`[[ -f ... ]]`, `[[ -d ... ]]`).
- Use `|| true` for operations that may fail non-fatally in relaxed sections.

## File Formatting

- **Line endings**: LF only (enforced via `.gitattributes`: `*.sh text eol=lf`).
- **Indentation**: Tabs for shell scripts.
- **Quoting**: Always quote variable expansions (`"$VAR"`, `"${VAR}"`), except
  inside `[[ ]]` test expressions where it is optional.
- **No trailing whitespace**.

## Making Changes

1. Edit scripts in `scripts/` or configs in `files/`.
2. Rebuild: `make build`.
3. Test locally with `docker-compose up` or by running the built image directly.
4. Verify: connect via OpenVPN client and confirm DNS resolution of container
   names and VPN routing to Docker bridge network.
