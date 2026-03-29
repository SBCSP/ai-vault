# Changelog

## v1.2.1 — Streaming Responses
- LLM responses now stream in real-time with a typing effect
- Both Ollama and Claude support streaming
- Text appears progressively as the model generates it

## v1.2.0 — Claude API Integration
- Added Anthropic Claude as a cloud LLM provider
- Available models: Sonnet 4, Opus 4, Haiku 4
- Automatic secrets locking when cloud LLM is active
- LLM provider selector in Settings (Ollama / Claude)
- Cloud/Local indicator badge in chat header
- Claude API key configuration with test connection

## v1.1.2 — Agent Download
- Download aiv_agent RPM directly from within the app
- Version-matched downloads (app v1.1.x gets agent v1.1.x)
- Progress indicator during download

## v1.1.1 — Database Fix
- Fixed SQLite read-only error on macOS sandbox
- Moved database to Application Support directory

## v1.1.0 — Server Management
- Added `aiv_agent` remote server monitoring
- mTLS certificate generation (pure Dart, no OpenSSL dependency)
- Server dashboard with live metrics (CPU, memory, disk, network, processes, services)
- RPM packaging for Linux agent
- GitHub Actions CI/CD for parallel DMG + RPM builds

## v1.0.2 — MCP Tool Calling
- MCP client integration for external tool calling
- MCP server management screen
- Tool call badges and expandable details in chat
- Audit logging for MCP events

## v1.0.1 — Documents & RAG
- Document ingestion (PDF and text)
- Chunked indexing with embeddings
- RAG-powered semantic search
- Chat session save and indexing
- Embedding-based retrieval for all vault content

## v1.0.0 — Initial Release
- Secrets vault with AES encryption
- Notes and Ideas with tagging
- AI chat with Ollama
- Master PIN authentication
- Auto-lock timeout
- Category management
- Audit logging
- Vault REST API with TLS
- AWS Secrets Manager SSO integration
