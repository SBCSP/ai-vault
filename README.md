<p align="center">
  <img src="aiLogo.jpg" alt="AI VaultIO Logo" width="200" />
</p>

<h1 align="center">AI VaultIO</h1>

<p align="center">
  <strong>Your AI-Powered Local Secrets Manager & Knowledge Vault</strong>
</p>

<p align="center">
  A privacy-first desktop application that combines encrypted credential storage, note-taking, document indexing, and AI-powered semantic search — all running entirely on your machine.
</p>

---

## What is AI VaultIO?

AI VaultIO is a local-first secrets manager and knowledge vault built with Flutter. It keeps your passwords, API keys, notes, and documents encrypted and searchable — without ever sending your data to the cloud.

What sets it apart is its built-in **RAG (Retrieval-Augmented Generation)** pipeline powered by [Ollama](https://ollama.com). Ask questions in natural language and the AI retrieves relevant secrets, notes, and document excerpts from your vault to give you context-aware answers.

## Key Features

### Encrypted Secrets Management
- Store passwords, API keys, SSH keys, WiFi credentials, credit card info, and more
- AES encryption with a master password
- Organize with categories and tags
- Track expiration dates with alerts for expiring credentials
- Auto-lock timeout to protect your vault when you step away

### Notes
- Create and organize rich text notes with tags
- Full-text search across all notes
- Notes are indexed for AI-powered semantic retrieval

### Document Indexing
- Import individual files or scan entire directories
- Supports `.txt`, `.md`, `.json`, `.yaml`, `.csv`, `.log`, and `.pdf`
- Automatic text extraction from PDFs
- Smart chunking with overlap for accurate vector search
- Change detection — knows when files have been modified on disk

### AI Chat with RAG
- Chat with a local LLM via Ollama — your data never leaves your machine
- Semantic search across your entire vault: secrets, notes, and documents
- The AI references matched items inline so you can see exactly what it found
- Save and revisit past chat sessions
- Full markdown rendering in responses

### Ollama Integration
- Connect to your local Ollama instance
- Browse, download, and switch between available models
- Manage embedding models for vector search
- Real-time connection status on the dashboard

### Local HTTPS Vault API
- Spin up a self-signed HTTPS server directly from the app
- REST API to query your secrets and notes programmatically
- API key authentication for secure access
- Perfect for integrating with scripts, CLI tools, or local automation

### Dashboard
- At-a-glance stats: total secrets, notes, documents, chats, expired items
- Ollama connection status
- Recently updated secrets and upcoming expirations
- Quick-access speed dial to add secrets, notes, or documents

## Use Cases

**For Developers**
- Store API keys and database credentials locally with encryption
- Index project documentation and READMEs for instant AI-powered search
- Expose secrets via the local HTTPS API for use in scripts and dev tooling
- Ask the AI: _"What's the API key for the staging database?"_

**For Security-Conscious Users**
- Keep all credentials offline — no cloud sync, no third-party servers
- Master password + auto-lock keeps your vault secure
- Track which credentials are expiring and need rotation

**For Knowledge Workers**
- Build a personal knowledge base from notes and documents
- Map entire project directories to index hundreds of files at once
- Ask the AI natural language questions across your entire knowledge vault
- _"Summarize the key points from my meeting notes last week"_

**For Homelab & Self-Hosting Enthusiasts**
- Manage credentials for all your self-hosted services
- Run the local API server to integrate with Home Assistant, n8n, or custom scripts
- Everything runs locally — pair with your own Ollama instance

## Tech Stack

| Layer | Technology |
|-------|-----------|
| **UI** | Flutter + Material Design 3 |
| **State** | Riverpod |
| **Database** | SQLite via Drift ORM |
| **Encryption** | AES (Encrypt + PointyCastle) |
| **AI / LLM** | Ollama (local inference) |
| **Embeddings** | nomic-embed-text (default) |
| **PDF** | Syncfusion Flutter PDF |
| **API Server** | Built-in Dart HTTPS server |

## Getting Started

### Prerequisites
- [Flutter SDK](https://flutter.dev/docs/get-started/install) (3.x+)
- [Ollama](https://ollama.com) installed and running locally
- A pulled model (e.g., `ollama pull llama3`) and embedding model (`ollama pull nomic-embed-text`)

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
1. Set your **master password** — this encrypts your vault
2. Navigate to **Settings → Ollama** to configure your local Ollama connection
3. Pull a chat model and embedding model from the Ollama screen
4. Start adding secrets, notes, and documents
5. Hit the **Index All** button to vectorize your vault for AI search
6. Open **AI Chat** and ask questions about your stored data

## Architecture

```
lib/
├── database/        # Drift ORM schema & migrations
├── models/          # Data models (VaultEntry, Note, Document, ChatSession)
├── providers/       # Riverpod state management
├── screens/         # Flutter UI screens
└── services/        # Business logic (AI, embedding, documents, API server)
```

The RAG pipeline works as follows:
1. **Index** — Vault entries, notes, and document chunks are converted to vector embeddings via Ollama
2. **Query** — User messages are embedded and compared against stored vectors using cosine similarity
3. **Retrieve** — Top matching items are fetched and injected as context into the LLM prompt
4. **Generate** — The LLM produces a response grounded in your actual vault data

## License

This project is provided as-is for personal use.

---

<p align="center">
  Built with Flutter & Ollama — 100% local, 100% private.
</p>
