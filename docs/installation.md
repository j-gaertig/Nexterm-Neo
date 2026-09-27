# 🚀 Installation

> [!WARNING]
> Nexterm is still in beta. Please back up your data regularly and report any issues on [GitHub](https://github.com/gnmyt/Nexterm/issues).

## 🔐 Generate Encryption Key

Nexterm requires an encryption key to securely store your data. You can generate a strong key using the following command:

```sh
openssl rand -hex 32
```

## Docker Images

Nexterm is distributed as three Docker images:

| Image            | Description                                                                        |
|------------------|------------------------------------------------------------------------------------|
| `nexterm/aio`    | **All-In-One** - server, client, and engine in a single container. Simplest setup. |
| `nexterm/server` | **Server only** - Node.js backend + web client. Requires a separate engine.        |
| `nexterm/engine` | **Engine only** - Connection service (SSH, VNC, RDP, Telnet).                      |

For simple deployments, use `nexterm/aio`. For multi-network or distributed setups, deploy `nexterm/server` with one or
more `nexterm/engine` instances on different networks.

## 🐳 All-In-One (Simple Setup)

::: code-group

```shell [Host Network (Recommended)]
docker run -d \
  -e ENCRYPTION_KEY=aba3aa8e29b9904d5d8d705230b664c053415c54be20ad13be99af0057dfa23a \ # Replace with your generated key
  --network host \
  --name nexterm \
  --restart always \
  -v nexterm:/app/data \
  nexterm/aio:latest
```

```shell [Bridge Network]
docker run -d \
  -e ENCRYPTION_KEY=aba3aa8e29b9904d5d8d705230b664c053415c54be20ad13be99af0057dfa23a \ # Replace with your generated key
  -p 6989:6989 \
  --name nexterm \
  --restart always \
  -v nexterm:/app/data \
  nexterm/aio:latest
```

:::

> [!NOTE]
> **Host Network** is strongly recommended. It allows Nexterm to access your host's network stack directly, which is required for features like Wake-on-LAN and connecting to servers via `localhost`. Only use **Bridge Network** if you specifically need network isolation.

### Optional AIO host command bridge

ENGINE hooks normally run inside the Alpine container. To run a local hook on the Linux Docker host, install the optional Debian/Ubuntu systemd bridge before starting AIO:

```sh
curl -fsSL https://raw.githubusercontent.com/j-gaertig/Nexterm-Neo/main/scripts/install-host-exec-bridge.sh | sudo bash -s -- /opt/nexterm
```

The bridge executes configured hook commands as host root. Any user allowed to connect to an entry can trigger its configured Pre-Connect command. Enable this only when that host-level access is intended. The installer enables the service and creates `/run/nexterm-host-exec`. The bridge currently requires rootful Docker; rootless Docker and user-namespace remapping are unsupported.

When installing from a release tag instead of `main`, set `NEXTERM_SOURCE_REF` to that same tag and preserve it through `sudo` so the bridge files match the installer version.

For `docker run`, add this bind mount:

```sh
-v /run/nexterm-host-exec:/run/nexterm-host-exec
```

For Docker Compose, add this volume to the AIO service:

```yaml
      - /run/nexterm-host-exec:/run/nexterm-host-exec
```

In the server dialog, choose **Linux Docker host (root)** for the local hook target. Commands start in the AIO installation directory. Use `cd /path/to/project && docker compose ps` for another Compose project. The existing ENGINE target continues to run in the Engine container/runtime.

## 📦 Docker Compose

### All-In-One

::: code-group

```yaml [Host Network (Recommended)]
services:
  nexterm:
    image: nexterm/aio:latest
    environment:
      ENCRYPTION_KEY: "aba3aa8e29b9904d5d8d705230b664c053415c54be20ad13be99af0057dfa23a" # Replace with your generated key
    network_mode: host
    restart: always
    volumes:
      - nexterm:/app/data
volumes:
  nexterm:
```

```yaml [Bridge Network]
services:
  nexterm:
    image: nexterm/aio:latest
    environment:
      ENCRYPTION_KEY: "aba3aa8e29b9904d5d8d705230b664c053415c54be20ad13be99af0057dfa23a" # Replace with your generated key
    ports:
      - "6989:6989"
    restart: always
    volumes:
      - nexterm:/app/data
volumes:
  nexterm:
```

:::

### Split Deployment (Server + Engine)

Use this when you need the engine on a different network or want to run multiple engines.

First, create a `config.yaml` for the engine:

```yaml
server_host: "server"
server_port: 7800
registration_token: ""
```

Then create your `docker-compose.yml`:

```yaml
services:
  server:
    image: nexterm/server:latest
    environment:
      ENCRYPTION_KEY: "aba3aa8e29b9904d5d8d705230b664c053415c54be20ad13be99af0057dfa23a" # Replace with your generated key
    ports:
      - "6989:6989"
    restart: always
    volumes:
      - nexterm:/app/data

  engine:
    image: nexterm/engine:latest
    restart: always
    volumes:
      - ./config.yaml:/etc/nexterm/config.yaml

volumes:
  nexterm:
```

```sh
docker-compose up -d
```

### 🌐 IPv6 Support

To connect to IPv6 servers from within the container using bridge networking, add the following to your existing `docker-compose.yml` (not needed for host network):

```diff
services:
  nexterm:
+   networks:
+     - nexterm-net

+networks:
+  nexterm-net:
+    enable_ipv6: true
```
