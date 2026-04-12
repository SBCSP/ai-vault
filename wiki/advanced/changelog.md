# Changelog

## v1.3.1 — LanceDB Exclusive + Enterprise UI
- Full enterprise UI revamp: 220px dark sidebar (GitHub-inspired), Inter font, compact desktop density, border-over-shadow design
- Design token system: AppColors, AppSpacing, AppTheme with full Material 3 overrides
- Grouped sidebar navigation with section labels and hover states
- Smooth 160ms fade transitions between sections
- LanceDB is now the exclusive vector store — SQLite embedding fallback removed
- New LanceDB management screen in the sidebar (metrics, dimension config, index controls)
- Vector Database card removed from Settings
- Renamed "Documents" nav item to "Files"
- Linear integration added as a first-class sidebar item

## v1.1.0 — Document Builder
- AI-powered Document Builder with split-pane .docx editor and LLM chat
- Real-time document editing: AI directly inserts, replaces, and deletes content at the right location
- Structured edit commands (insert_after, insert_before, replace, delete, append)
- Undo/redo support for all AI edits (50-state history)
- Activity timeseries charts on the dashboard (daily activity, CRUD, security, AI/MCP, infrastructure)
- Audit log RAG vectorization for semantic search of audit events

## v1.0.0 — Fresh Release
- All previous features consolidated under v1.0.0
- Sidebar navigation with customizable nav items

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
