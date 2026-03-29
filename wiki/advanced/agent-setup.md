# Agent Setup (aiv_agent)

## Overview

The `aiv_agent` is a lightweight Go binary that runs on your Linux servers and serves system metrics over mTLS. AI VaultIO connects to agents to display live server data.

## Installation (RPM)

### 1. Download

Download the agent RPM from AI VaultIO:

1. Go to **Settings > Server Management**
2. Click **Download Agent (.rpm)**
3. Transfer the RPM to your server

Or download directly from GitHub Releases:

```bash
VERSION=1.2.1
wget https://github.com/SBCSP/ai-vault/releases/download/v${VERSION}/aiv_agent-${VERSION}-1.x86_64.rpm
```

### 2. Install

```bash
sudo rpm -i aiv_agent-${VERSION}-1.x86_64.rpm
```

This creates:
- `/usr/local/bin/aiv_agent` — The binary
- `/etc/aiv_agent/` — Configuration directory
- `aiv_agent` systemd service

### 3. Configure Certificates

Generate certificates in AI VaultIO (**Settings > Server Management > Generate Certificates**), then copy the server certificate and key to the agent:

```bash
# Copy these files to your server:
sudo cp server-cert.pem /etc/aiv_agent/server-cert.pem
sudo cp server-key.pem /etc/aiv_agent/server-key.pem
sudo cp ca-cert.pem /etc/aiv_agent/ca-cert.pem
```

### 4. Start the Service

```bash
sudo systemctl enable aiv_agent
sudo systemctl start aiv_agent
```

### 5. Verify

```bash
sudo systemctl status aiv_agent
# Should show: active (running)

curl --cert client-cert.pem --key client-key.pem --cacert ca-cert.pem \
  https://your-server:8444/health
# Should return: {"status":"ok","version":"1.2.1"}
```

## Adding the Server in AI VaultIO

1. Go to **Settings > Server Management**
2. Tap **Add Server**
3. Enter hostname/IP and port (default: 8444)
4. The app connects using the client certificate generated earlier

## Agent Endpoints

| Path | Description |
|------|-------------|
| `/health` | Health check with version |
| `/metrics/performance` | CPU, memory, load, uptime |
| `/metrics/disk` | Filesystem usage |
| `/metrics/network` | Interface stats, connections |
| `/metrics/processes` | Top processes by CPU/memory |
| `/metrics/services` | Systemd service statuses |

## Versioning

The agent version matches the AI VaultIO version. When you update AI VaultIO, download the matching agent version for compatibility.
