# Secrets Management

## Overview

AI VaultIO stores your secrets locally with AES encryption. Each secret entry can include a title, category, username, password/value, URL, notes, tags, and an optional expiration date.

## Categories

Secrets are organized by category:

- **Login** — Website and service credentials
- **API Key** — API tokens and keys
- **SSH Key** — SSH keys and passphrases
- **Credit Card** — Payment information
- **Custom** — Add your own categories in Settings

## Expiration Tracking

Set an expiration date on any secret. AI VaultIO tracks:

- **Expired** secrets (shown in red)
- **Expiring soon** — within 30 days (shown in orange)
- **Active** — no expiry or far in the future

Access the **Expired Secrets** view from the home screen to see all secrets needing rotation.

## AI Search

Ask the AI to find secrets naturally:

- *"Find my AWS credentials"*
- *"What API keys are expiring soon?"*
- *"Show me all my login entries"*

The AI uses RAG to semantically match your query against all secret titles, tags, notes, and categories.

## Security

- Secrets are encrypted at rest using AES via `EncryptionService`
- The master PIN must be entered to unlock the vault
- Secrets can be locked independently via the **Secrets Lock** toggle
- Cloud LLMs (Claude) never receive secret values — they are automatically excluded
