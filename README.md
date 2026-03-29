<p align="center">
  <img src="aiLogo.jpg" alt="AI VaultIO Logo" width="200" />
</p>

<h1 align="center">AI VaultIO</h1>

<p align="center">
  <strong>AI-Powered Local Secrets Manager & Knowledge Vault</strong>
</p>

<p align="center">
  A privacy-first macOS desktop app that combines encrypted credential storage, notes, ideas, document indexing, AI-powered semantic search, cloud LLM integration, MCP tool calling, server monitoring, and AWS Secrets Manager sync — with a full RAG pipeline running on your machine.
</p>

<p align="center">
  <a href="https://github.com/SBCSP/ai-vault/releases/latest">
    <img src="https://img.shields.io/github/v/release/SBCSP/ai-vault?label=Download&style=for-the-badge&logo=apple&logoColor=white" alt="Download Latest Release" />
  </a>
</p>

---

## Install

### macOS (DMG)

1. Download the latest `.dmg` from the [**Releases page**](https://github.com/SBCSP/ai-vault/releases/latest)
2. Open the `.dmg` and drag **AI VaultIO** into **Applications**
3. **First launch — bypass Gatekeeper** (the app is ad-hoc signed, not Apple-notarized):
   - Open **System Settings > Privacy & Security**
   - Find _"AI VaultIO" was blocked_ and click **Open Anyway**
   - Or run:
     ```bash
     xattr -cr /Applications/AI\ VaultIO.app
     ```

> **Requires:** macOS 12+ and [Ollama](https://ollama.com) for local AI features. Claude API works without Ollama.

---

## What is AI VaultIO?

AI VaultIO is a local-first secrets manager, knowledge vault, and AI assistant built with Flutter. It keeps your passwords, API keys, notes, ideas, and documents encrypted and searchable — without sending your data to a third-party cloud.

What makes it different:

- **Dual LLM support** — Use a local Ollama model for full vault access, or Anthropic's Claude API for more capable reasoning (secrets are automatically locked when using cloud models).
- **RAG pipeline** — Ask questions in natural language and the AI retrieves relevant secrets, notes, ideas, documents, wiki pages, and past conversations to give context-aware answers.
- **MCP tool calling** — Connect to external MCP servers (Linear, GitHub, etc.) so the LLM can discover and invoke tools on your behalf.
- **Streaming responses** — LLM output streams in real time with a typing effect for both Ollama and Claude.
- **Server monitoring** — Deploy a lightweight Go agent (`aiv_agent`) on Linux servers and view live system metrics from the app.
- **AWS integration** — Pull secrets from AWS Secrets Manager via SSO directly into your local vault.

---

## Key Features

### Encrypted Secrets Management
- Store passwords, API keys, SSH keys, WiFi credentials, credit card info, and more
- **AES-256-CBC** encryption with PBKDF2 key derivation (100,000 iterations, HMAC-SHA256)
- Per-entry random IV and 16-byte salt — every sensitive field encrypted at rest
- Organize with categories (Login, API Key, Credit Card, SSH Key, WiFi, General, AWS-SM) and custom categories
- Free-form tags for flexible organization
- Expiration date tracking with dashboard alerts for expired and expiring-soon credentials
- Configurable auto-lock timeout (5–60 minutes)

### AI Chat with RAG
- Chat with a local LLM via Ollama or Anthropic's Claude API
- **Streaming responses** — text appears in real time as the model generates
- Semantic search across your entire vault: secrets, notes, ideas, documents, wiki pages, and past chats
- Top-10 retrieval with cosine similarity scoring (0.3 threshold)
- RAG source badges show which data matched (Vault, Notes, Ideas, Documents, Wiki, Chats)
- Full markdown rendering in responses (code blocks, tables, lists)
- Save and revisit past chat sessions with auto-generated titles
- Full-screen **Focus Mode** with canned suggestion prompts for new users
- Compact chat widget on the dashboard for quick queries

### Dual LLM Providers
- **Ollama (Local)** — Your data never leaves your machine. Full access to unlocked secrets. Browse, download, and switch models from the UI.
- **Claude API (Cloud)** — Anthropic's Claude Sonnet 4, Opus 4, and Haiku 4 models. Secrets are **automatically locked** before every message — the LLM never sees your secret values. API key stored in the platform keychain.

### MCP Server Integration
- Connect to remote MCP servers (e.g., `https://mcp.linear.app/mcp`) to give the LLM access to external tools
- LLM autonomously discovers and calls tools via Ollama's native function-calling API
- Up to 10 tool-calling rounds per query with results fed back to the LLM
- Tool call details shown in chat bubbles (name, arguments, result, duration)
- Add/remove/enable/disable servers from Settings with optional bearer token auth
- Works with tool-capable models (Llama 3.1+, Qwen 2.5+, Mistral, Command R+)

### Notes & Ideas
- **Notes** — Encrypted title + body with tags, word/character count, full RAG indexing
- **Ideas** — Separate brainstorming space with the same capabilities
- Both are searchable via AI chat and contribute to RAG context

### Document Indexing
- Import individual files or **map entire directories** for recursive scanning
- Supported formats: `.txt`, `.md`, `.json`, `.yaml`, `.yml`, `.csv`, `.log`, `.pdf`
- PDF text extraction via Syncfusion
- Smart chunking (~1,000 chars with 200-char overlap) at paragraph and sentence boundaries
- Content hash tracking detects when files change on disk
- **Index All** from the speed dial: re-scans directories, clears stale embeddings, re-indexes everything
- Progress dialogs with per-document status

### In-App Wiki
- Bundled markdown documentation covering all features, security, and setup guides
- Sidebar navigation across 4 sections (Getting Started, Features, Security, Advanced)
- Wiki pages are **indexed for RAG** — users can ask the LLM about AI VaultIO and get accurate answers
- Updated with each release to stay in sync with the codebase

### Server Monitoring (aiv_agent)
- Deploy the `aiv_agent` Go binary on Linux servers (RPM package or standalone binary)
- Collects: CPU, memory, load averages, disk usage, network I/O, top processes, systemd service statuses
- Communicates with AI VaultIO over **mutual TLS** (certificates generated in-app)
- Live metrics dashboard with per-server detail views
- Add/remove servers from Settings > Server Management

### AWS Secrets Manager Integration
- **One-way sync** from AWS Secrets Manager into your local vault
- Authenticates via **AWS SSO (OIDC Device Authorization Flow)** — opens your browser, you log in
- Multi-key JSON secrets parsed into individual rows with per-row show/hide and copy
- SigV4-signed API requests — no AWS CLI required
- Configurable region and SSO start URL

### Local HTTPS Vault API
- Self-signed HTTPS server running on localhost (default port 8484)
- REST endpoints:
  - `GET /api/secrets` — list all (no passwords)
  - `GET /api/secrets/:id` — single secret (includes password)
  - `GET /api/secrets/lookup?title=...` — lookup by title
  - `GET /api/notes` / `GET /api/notes/:id` — notes access
  - `GET /api/health` — health check
- API key authentication
- Use from scripts, CI/CD pipelines, Home Assistant, n8n, or any HTTP client

### Audit Logging
- Every significant action logged: secret CRUD, note/idea CRUD, document indexing, vault lock/unlock, failed unlock attempts, secrets lock toggles, AWS sync events, MCP tool calls, and more
- Browse the full audit trail from Settings > Audit Log
- Timestamps in UTC with action details

### Secrets Lock
- Independent toggle from vault unlock — controls whether the AI can access secret values
- **Automatically engaged** when using Claude (cloud LLM)
- Manually toggle for Ollama when you want to chat without exposing secrets
- Lock/unlock events recorded in the audit log

### Dashboard
- At-a-glance stats: secrets, notes, ideas, documents, chats, expired items
- Ollama connection status with model info
- Category breakdown and recently updated secrets
- Upcoming expirations (next 90 days)
- Speed dial FAB for quick access to add secrets, notes, or documents

---

## Use Cases

### For Developers
- Store API keys and database credentials with AES-256 encryption
- Sync secrets from AWS Secrets Manager onto dev machines via SSO
- Index project docs, READMEs, and config files for instant AI search
- Expose secrets via the local HTTPS API for scripts and dev tooling
- Connect MCP servers to let the AI create tickets, check PRs, or query external systems
- Ask: _"What's the API key for the staging database?"_

### For Security-Conscious Users
- Keep all credentials offline — no cloud sync, no third-party servers
- Master password + auto-lock + secrets lock for layered security
- Cloud LLM integration that **never sees your secrets** (auto-locked)
- Track which credentials are expiring and need rotation
- Full audit trail of every vault access

### For Knowledge Workers
- Build a personal knowledge base from notes, ideas, and documents
- Map entire project directories to index hundreds of files
- Ask the AI questions across your entire knowledge vault
- Use Claude for complex reasoning tasks while keeping secrets private
- _"Summarize the key points from my meeting notes"_
- _"What config values does the payments service need?"_

### For Teams Using AWS
- Distribute AWS Secrets Manager secrets to developer workstations securely
- SSO login — no long-lived AWS credentials on disk
- Pull-only sync — developers read secrets but never push to AWS
- JSON secrets parsed into readable key/value rows

### For Homelab & Self-Hosting Enthusiasts
- Manage credentials for all your self-hosted services
- Monitor Linux servers with `aiv_agent` and mTLS
- Run the local API server to integrate with Home Assistant, n8n, or custom scripts
- Everything runs locally — pair with your own Ollama instance

### For AI Power Users
- Connect multiple MCP servers to extend the LLM with external tools
- Use RAG to ground AI responses in your actual data
- Switch between local and cloud models depending on the task
- Save and index chat sessions to build institutional knowledge over time
- Browse the in-app wiki or ask the AI how features work

---

## Tech Stack

| Layer | Technology |
|-------|-----------|
| **UI** | Flutter + Material Design 3 |
| **State** | Riverpod (StateNotifier, StreamProvider, Provider) |
| **Database** | SQLite via Drift ORM (schema v10) |
| **Encryption** | AES-256-CBC + PBKDF2 (PointyCastle + Encrypt) |
| **AI / LLM** | Ollama (local) + Claude API (cloud) |
| **Embeddings** | nomic-embed-text (via Ollama) |
| **MCP** | mcp_dart (Streamable HTTP transport) |
| **PDF** | Syncfusion Flutter PDF |
| **AWS** | SSO OIDC + SigV4 (built-in, no AWS CLI) |
| **API Server** | Built-in Dart HTTPS with self-signed TLS |
| **Server Agent** | aiv_agent (Go, mTLS, RPM) |

---

## Getting Started

### Prerequisites
- macOS 12+ (Monterey or later)
- [Ollama](https://ollama.com) installed and running (for local AI)
- _(Optional)_ [Flutter SDK](https://flutter.dev/docs/get-started/install) 3.x+ if building from source

### Run from Source
```bash
git clone https://github.com/SBCSP/ai-vault.git
cd ai-vault
flutter pub get
dart run build_runner build
flutter run -d macos
```

### First Launch
1. **Set your master password** — this derives your AES-256 encryption key
2. Go to **Settings > Ollama** and configure your local Ollama connection
3. Pull a chat model (`ollama pull gemma3:1b`) and embedding model (`ollama pull nomic-embed-text`)
4. Start adding secrets, notes, ideas, and documents
5. Use **Index All** to vectorize your vault for AI search
6. Open **AI Chat** and start asking questions

### Optional Setup
- **Settings > Claude API** — Add your Anthropic API key for cloud LLM access
- **Settings > AWS Secrets Manager** — Configure SSO to pull cloud secrets
- **Settings > MCP Servers** — Connect to external tool servers
- **Settings > Server Management** — Set up `aiv_agent` monitoring on Linux servers

---

## Architecture

```
lib/
├── database/        # Drift ORM schema & migrations (v10)
├── models/          # Data models (VaultEntry, Note, Idea, Document, ChatSession, etc.)
├── providers/       # Riverpod state (auth, vault, notes, ideas, docs, AI, MCP, AWS, audit, embeddings)
├── screens/         # 22 Flutter UI screens
├── services/        # AI, Claude API, embedding, documents, encryption, AWS SSO/SM, MCP, certificates
└── widgets/         # Shared components (markdown renderer, search bar)

wiki/                # Bundled markdown documentation (15 pages, 4 sections)
```

### RAG Pipeline
1. **Index** — Vault entries, notes, ideas, document chunks, wiki pages, and chat sessions are converted to vector embeddings via Ollama
2. **Query** — User messages are embedded and compared against stored vectors using cosine similarity
3. **Retrieve** — Top-10 matching items above 0.3 similarity threshold are fetched
4. **Augment** — Matched items injected as structured context into the LLM prompt
5. **Generate** — The LLM produces a streaming response grounded in your actual data

### Database Tables
| Table | Purpose |
|-------|---------|
| `VaultEntries` | Encrypted secrets and credentials |
| `Notes` | Encrypted notes |
| `Ideas` | Encrypted ideas |
| `Documents` | Document metadata and file paths |
| `DocumentChunks` | Chunked document content for granular retrieval |
| `Embeddings` | Vector embeddings for all indexed content |
| `ChatSessions` | Saved AI chat conversations |
| `McpServers` | MCP server configurations |
| `Servers` | Monitored server definitions |
| `AuditLogs` | Action audit trail |

---

## License

This project is provided as-is for personal use.

---

<p align="center">
  Built with Flutter, Ollama & Claude — local-first, privacy-forward.
</p>
