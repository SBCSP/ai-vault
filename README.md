<p align="center">
  <img src="aiLogo.jpg" alt="AI VaultIO Logo" width="200" />
</p>

<h1 align="center">AI VaultIO</h1>

<p align="center">
  <strong>Your AI-Powered Local Secrets Manager & Knowledge Vault</strong>
</p>

<p align="center">
  A privacy-first macOS desktop app that combines encrypted credential storage, notes, document indexing, AWS Secrets Manager sync, and AI-powered semantic search — all running entirely on your machine with Ollama.
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
2. Open the `.dmg` file
3. Drag **AI VaultIO** into your **Applications** folder
4. **First launch — bypass Gatekeeper** (the app is not Apple-notarized):
   - Open **System Settings → Privacy & Security**
   - Scroll down to find _"AI VaultIO" was blocked_ and click **Open Anyway**
   - Or run this in Terminal:
     ```bash
     xattr -cr /Applications/AI\ VaultIO.app
     ```

> **Requires:** macOS 12+ (Monterey or later) and [Ollama](https://ollama.com) for AI features.

---

## What is AI VaultIO?

AI VaultIO is a local-first secrets manager and knowledge vault built with Flutter. It keeps your passwords, API keys, notes, and documents encrypted and searchable — without ever sending your data to a cloud service.

What sets it apart is its built-in **RAG (Retrieval-Augmented Generation)** pipeline powered by [Ollama](https://ollama.com). Ask questions in natural language and the AI retrieves relevant secrets, notes, and document excerpts from your vault to give you context-aware answers. It also integrates with **AWS Secrets Manager** via SSO, letting you pull cloud secrets directly into your local vault.

---

## Key Features

### Encrypted Secrets Management
- Store passwords, API keys, SSH keys, WiFi credentials, credit card info, and more
- **AES-256-CBC** encryption with PBKDF2 key derivation (100,000 iterations, HMAC-SHA256)
- Per-entry random IV and 16-byte salt — every field encrypted at rest
- Organize with categories (Login, API Key, Credit Card, SSH Key, WiFi, General, AWS-SM) and free-form tags
- Track expiration dates with dashboard alerts for expired and expiring-soon credentials
- Configurable auto-lock timeout (5–60 minutes) to protect your vault when you step away

### AWS Secrets Manager Integration
- **One-way sync** from AWS Secrets Manager to your local vault — pull cloud secrets onto dev machines
- Authenticates via **AWS SSO (OIDC Device Authorization Flow)**: opens your browser, you log in, and the app gets a token
- Select your AWS account and IAM role, then sync with one click
- Secrets stored under a dedicated **AWS-SM** category with JSON key/value display
- Multi-key secrets are parsed and shown as individual rows with per-row show/hide and copy
- SigV4-signed API requests — no AWS CLI required
- Configurable region and SSO Start URL in Settings
- Session expiration detection with reconnect prompts

### Notes
- Create and organize encrypted notes with title, body, and tags
- Word and character count while editing
- Notes are automatically indexed for AI-powered semantic retrieval

### Document Indexing
- Import individual files or **map entire directories** to recursively scan and index
- Supported formats: `.txt`, `.md`, `.json`, `.yaml`, `.yml`, `.csv`, `.log`, `.pdf`
- Automatic PDF text extraction via Syncfusion
- Smart chunking (1,000 characters with 200-character overlap) that breaks at paragraph and sentence boundaries
- Content hash tracking — detects when files change on disk
- **Index All** from the speed dial menu: re-scans mapped directories for new/removed files, clears old embeddings, and re-indexes everything from scratch
- Progress dialogs with per-document status during bulk operations

### AI Chat with RAG
- Chat with a local LLM via Ollama — **your data never leaves your machine**
- Semantic search across your entire vault: secrets, notes, documents, and past chats
- Top-10 retrieval with cosine similarity scoring (0.3 threshold)
- RAG source badges show which data sources matched (Vault, Notes, Documents, Chats)
- Full markdown rendering in AI responses
- Save and revisit past chat sessions with auto-generated titles
- Full-screen **Focus Mode** for extended conversations
- Compact chat widget embedded in the dashboard for quick queries

### Ollama Integration
- Connect to your local Ollama instance (default: `localhost:11434`)
- Browse, download, and switch between chat models
- Manage embedding models for vector search (default: `nomic-embed-text`)
- Real-time connection and model status on the dashboard
- One-click **Re-index All** to rebuild your entire embedding index

### Local HTTPS Vault API
- Spin up a self-signed HTTPS server directly from the app
- REST API to query secrets and notes programmatically:
  - `GET /api/secrets` — list all (no passwords)
  - `GET /api/secrets/:id` — single secret (includes password)
  - `GET /api/secrets/lookup?title=...` — lookup by title
  - `GET /api/notes` / `GET /api/notes/:id` — notes access
  - `GET /api/health` — health check
- API key authentication for secure local access
- Default port: `8484`, localhost only

### Dashboard
- At-a-glance stats: total secrets, notes, documents, chats, expired items
- Ollama connection status with model info
- Category breakdown of your vault
- Recently updated secrets and upcoming expirations (next 90 days)
- Speed dial FAB for quick access to add secrets, notes, or documents

---

## Use Cases

### For Developers
- Store API keys and database credentials locally with AES-256 encryption
- **Sync secrets from AWS Secrets Manager** onto dev machines via SSO — no more sharing credentials over Slack
- Index project documentation and READMEs for instant AI-powered search
- Expose secrets via the local HTTPS API for use in scripts, CI/CD pipelines, and dev tooling
- Ask the AI: _"What's the API key for the staging database?"_

### For Security-Conscious Users
- Keep all credentials offline — no cloud sync, no third-party servers
- Master password + auto-lock keeps your vault secure
- Track which credentials are expiring and need rotation
- AES-256-CBC with PBKDF2 — industry-standard encryption

### For Knowledge Workers
- Build a personal knowledge base from notes and documents
- Map entire project directories to index hundreds of files at once
- Ask the AI natural language questions across your entire knowledge vault
- _"Summarize the key points from my meeting notes last week"_
- _"What config values does the payments microservice need?"_

### For Teams Using AWS
- Distribute AWS Secrets Manager secrets to developer workstations securely
- SSO login means no long-lived AWS credentials stored on disk
- Pull-only sync — developers can read secrets but never push back to AWS
- JSON secrets parsed into readable key/value rows with copy support

### For Homelab & Self-Hosting Enthusiasts
- Manage credentials for all your self-hosted services
- Run the local API server to integrate with Home Assistant, n8n, or custom scripts
- Everything runs locally — pair with your own Ollama instance on any hardware

---

## Tech Stack

| Layer | Technology |
|-------|-----------|
| **UI** | Flutter + Material Design 3 |
| **State** | Riverpod |
| **Database** | SQLite via Drift ORM (v6 schema) |
| **Encryption** | AES-256-CBC + PBKDF2 (Encrypt + PointyCastle) |
| **AI / LLM** | Ollama (local inference) |
| **Embeddings** | nomic-embed-text (via Ollama) |
| **PDF** | Syncfusion Flutter PDF |
| **AWS** | SSO OIDC + SigV4 (built-in, no AWS CLI) |
| **API Server** | Built-in Dart HTTPS server with self-signed TLS |

---

## Getting Started

### Prerequisites
- macOS (primary supported platform)
- [Flutter SDK](https://flutter.dev/docs/get-started/install) (3.x+)
- [Ollama](https://ollama.com) installed and running locally

### Run the App
```bash
# Clone the repository
git clone <repo-url>
cd ai-vault

# Install dependencies
flutter pub get

# Generate database code
dart run build_runner build

# Run on macOS
flutter run -d macos
```

### First Launch
1. **Set your master password** — this encrypts your vault (AES-256)
2. Navigate to **Settings → Ollama** to configure your local Ollama connection
3. Pull a chat model (`ollama pull gemma3:1b`) and embedding model (`ollama pull nomic-embed-text`)
4. Start adding secrets, notes, and documents
5. *(Optional)* Navigate to **Settings → AWS Secrets Manager** to configure SSO and pull cloud secrets
6. Use **Index All** from any section's menu to vectorize your vault for AI search
7. Open **AI Chat** and ask questions about your stored data

---

## Architecture

```
lib/
├── database/        # Drift ORM schema & migrations (v6)
├── models/          # Data models (VaultEntry, Note, Document, DocumentChunk, ChatSession)
├── providers/       # Riverpod state management (auth, vault, notes, docs, AI, AWS, embeddings)
├── screens/         # Flutter UI screens (15 screens)
└── services/        # Business logic (AI, embedding, documents, encryption, AWS SSO, AWS SM, API server)
```

### RAG Pipeline
1. **Index** — Vault entries, notes, and document chunks are converted to vector embeddings via Ollama's embedding model
2. **Query** — User messages are embedded and compared against stored vectors using cosine similarity
3. **Retrieve** — Top-10 matching items (above 0.3 similarity threshold) are fetched from the database
4. **Augment** — Matched items are injected as structured context into the LLM prompt
5. **Generate** — The LLM produces a response grounded in your actual vault data

### Database Tables
| Table | Purpose |
|-------|---------|
| `VaultEntries` | Encrypted secrets and credentials |
| `Notes` | Encrypted notes |
| `Documents` | Document metadata and file paths |
| `DocumentChunks` | Chunked document content for granular retrieval |
| `Embeddings` | Vector embeddings for all indexed content |
| `ChatSessions` | Saved AI chat conversations |

---

## License

This project is provided as-is for personal use.

---

<p align="center">
  Built with Flutter & Ollama — 100% local, 100% private.
</p>
