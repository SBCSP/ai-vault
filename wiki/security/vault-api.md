# Vault API

## Overview

AI VaultIO includes a built-in REST API server that allows other applications on your machine to programmatically access your vault. The API uses HTTPS with a self-signed TLS certificate and API key authentication.

## Enabling the API

1. Go to **Settings > Vault API**
2. Toggle the switch to enable
3. The API starts on `https://localhost:8443` by default
4. Copy the generated API key

## Authentication

Every request must include the API key via:

```bash
# Header authentication
curl -k https://localhost:8443/api/health \
  -H "Authorization: Bearer YOUR_API_KEY"

# Query parameter authentication
curl -k "https://localhost:8443/api/health?api_key=YOUR_API_KEY"
```

## Endpoints

| Method | Path | Description |
|--------|------|-------------|
| GET | `/api/health` | Health check |
| GET | `/api/secrets` | List all secrets |
| GET | `/api/secrets/:id` | Get a specific secret |
| GET | `/api/secrets?title=github` | Search secrets by title |
| GET | `/api/notes` | List all notes |
| GET | `/api/notes/:id` | Get a specific note |

## Security Notes

- **HTTPS only** — All traffic is encrypted with a self-signed TLS certificate
- **Localhost only** — The API binds to localhost and is not accessible from the network
- **API key rotation** — Disabling and re-enabling the API generates a new key
- **TLS certificate** — Auto-generated on first use, viewable in Settings
- Use `-k` or `--insecure` with curl to accept the self-signed certificate
