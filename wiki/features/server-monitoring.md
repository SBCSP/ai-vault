# Server Monitoring

## Overview

AI VaultIO can monitor remote Linux servers using the `aiv_agent` — a lightweight Go-based agent that collects and serves system metrics over mTLS.

## Architecture

```
AI VaultIO (macOS) --mTLS--> aiv_agent (Linux server)
                              |
                              +-> /metrics/performance
                              +-> /metrics/disk
                              +-> /metrics/network
                              +-> /metrics/processes
                              +-> /metrics/services
```

## Metrics Collected

### Performance
- CPU usage percentage
- Memory usage (total, used, available)
- Load averages (1m, 5m, 15m)
- System uptime

### Disk
- Filesystem usage per mount point
- Disk type, total, used, available, percentage
- Inode counts

### Network
- Per-interface RX/TX bytes and packets
- Connection summary (established, listening, etc.)

### Processes
- Top 15 processes by CPU and memory usage
- PID, user, CPU%, memory%, command

### Services
- Systemd service statuses
- Active, inactive, failed services

## Setting Up

1. Go to **Settings > Server Management**
2. Generate certificates (creates CA + client + server certs)
3. Download the `aiv_agent` RPM for your server
4. Install on your Linux server and configure with the server certificate
5. Add the server in AI VaultIO with hostname and port
6. View live metrics in the server dashboard

See **Advanced > Agent Setup** for detailed installation instructions.
