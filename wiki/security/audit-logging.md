# Audit Logging

## Overview

AI VaultIO logs all significant actions to an audit trail. This provides accountability and helps you track who did what and when.

## Viewing the Audit Log

Go to **Settings > Audit Log** to browse all recorded events.

## Logged Actions

### Vault Operations
- `secret_created` — New secret added
- `secret_updated` — Secret modified
- `secret_deleted` — Secret removed
- `secret_viewed` — Secret value revealed

### Notes & Ideas
- `note_created`, `note_updated`, `note_deleted`
- `idea_created`, `idea_updated`, `idea_deleted`

### Security
- `vault_unlocked` — Master PIN entered successfully
- `vault_locked` — Vault manually locked
- `secrets_locked` — Secrets lock engaged
- `secrets_unlocked` — Secrets lock disengaged
- `failed_unlock_attempt` — Incorrect PIN entered

### MCP
- `mcp_server_added` — New MCP server configured
- `mcp_server_removed` — MCP server deleted
- `mcp_connected` — Connected to MCP server
- `mcp_disconnected` — Disconnected from MCP server
- `mcp_tool_called` — Tool executed via MCP
- `mcp_tool_failed` — Tool execution failed

### Documents
- `document_uploaded` — Document added and indexed
- `document_deleted` — Document removed

## Log Entry Format

Each entry records:

- **Timestamp** — When the action occurred
- **Action** — The type of event
- **Target type** — What was affected (secret, note, mcp_tool, etc.)
- **Target name** — The specific item name
- **Details** — Additional context

## Retention

Audit logs are stored in the local SQLite database and persist across app restarts. There is no automatic purge — logs grow over time.
