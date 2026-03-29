# Welcome to AI VaultIO

AI VaultIO is an AI-powered local vault for managing secrets, notes, ideas, and documents — all on your machine with local-first encryption.

## What is AI VaultIO?

AI VaultIO combines the security of a local password vault with the power of AI-assisted search and retrieval. Instead of scrolling through lists, just ask your AI assistant to find what you need.

### Key Capabilities

- **Secrets vault** with AES encryption at rest
- **Notes & Ideas** with full-text search and tagging
- **Document ingestion** with chunked indexing for RAG
- **AI chat** powered by local Ollama or cloud Claude models
- **Semantic search** via RAG (Retrieval-Augmented Generation)
- **MCP tool calling** to connect AI to external services
- **Server monitoring** via the `aiv_agent` remote agent
- **Audit logging** for every vault action
- **Vault REST API** for programmatic access

## How It Works

```
You <-> AI VaultIO <-> Ollama (local) or Claude (cloud)
                   <-> SQLite (encrypted)
                   <-> MCP Servers (tools)
                   <-> aiv_agent (remote servers)
```

Your data stays local. The AI reads your vault context to answer questions, find records, and help you organize your information.

## Next Steps

Head to **Installation** to get set up, or jump to **First Steps** to start using the app right away.
