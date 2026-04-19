# CLAUDE.md

This file provides guidance to Claude Code (claude.ai/code) when working with code in this repository.

## Build & Development Commands

```bash
# Dependencies
flutter pub get

# Code generation (must re-run after modifying Drift schema or Rust API)
dart run build_runner build --delete-conflicting-outputs   # Drift ORM
dart run flutter_rust_bridge_codegen generate              # Rust ↔ Dart bridge

# Lint
flutter analyze

# Build macOS app
flutter build macos

# Build distributable DMG (ad-hoc signed)
./scripts/build_dmg.sh

# First-time Rust bridge setup (installs toolchain, adds Apple targets, generates bindings)
bash scripts/setup_lance.sh

# Build aiv_agent (Go, Linux cross-compile + RPM)
cd aiv_agent && make build-linux && make rpm
```

## Releasing a New Version

Three things must be updated together:

1. `pubspec.yaml` — `version:` field (e.g., `1.3.3+7`)
2. `lib/providers/version_provider.dart` — `appVersion` constant to match
3. Git tag + push to trigger CI:
   ```bash
   git tag v1.3.3 && git push origin v1.3.3
   ```

`.github/workflows/release-macos.yml` triggers on `v*` tags, builds macOS DMG + Linux RPM, and publishes a GitHub Release. The release version comes from `GITHUB_REF_NAME` (the tag), not `pubspec.yaml`.

## Architecture

### Layer Separation

| Layer | Location | Role |
|---|---|---|
| State / UI binding | `lib/providers/` | Riverpod notifiers & stream providers |
| Business logic | `lib/services/` | Crypto, API calls, Rust FFI wrappers |
| Data models | `lib/models/` | Immutable structs with `copyWith()` |
| Persistence | `lib/database/` | Drift ORM (SQLite, schema v10) |
| Screens | `lib/screens/` | Flutter UI, consumes providers via `ref.watch/read` |

### Database

Drift ORM with SQLite. Schema version is in `lib/database/database.dart` (`schemaVersion`). When adding a table or column, bump the version and add a migration in `_onUpgrade`. Current schema version: **10**.

Tables: `VaultEntries`, `Notes`, `Ideas`, `Documents`, `DocumentChunks`, `Embeddings`, `ChatSessions`, `McpServers`, `Servers`, `AuditLogs`.

Platform connection: `lib/database/connection/native.dart` (FFI for macOS/Linux) or `web.dart`.

### Encryption

`EncryptionService` (`lib/services/encryption_service.dart`) uses AES-256-CBC + PBKDF2 (100k iterations for key derivation, 10k for verification). Random IV (16 bytes) + 16-byte salt per entry; format on disk: `base64(iv):base64(ciphertext)`.

The derived key lives in memory only. On lock, it is cleared; on unlock, it is re-derived from the master password. Sensitive fields encrypted at rest: secret values, note/idea bodies.

### AI & RAG Pipeline

Dual LLM support:
- **Ollama** (local) — full vault access, manual secrets-lock toggle
- **Claude API** (cloud) — secrets auto-lock; LLM never sees secret values

RAG flow: user message → embedding (Ollama `nomic-embed-text` or Claude) → cosine similarity search (threshold 0.3, top-10) → structured context assembled from vault/notes/ideas/docs/wiki/chats → streamed LLM response with source badges.

`ai_provider.dart` orchestrates retrieval and LLM dispatch. `embedding_provider.dart` manages the indexing state machine.

### Vector Storage (LanceDB / Rust Bridge)

`rust/src/api.rs` exports async FFI functions (initialize, insert, search, delete, stats) backed by LanceDB 0.14 + Apache Arrow. Generated Dart bindings are at `lib/src/rust/frb_generated.dart` — regenerate with `flutter_rust_bridge_codegen generate`.

Global Rust state uses `OnceCell<Arc<Mutex<Option<LanceConfig>>>>` with a Tokio multi-threaded runtime. If the Rust dylib is not found at runtime, the app falls back to SQLite-only mode (no ANN search).

`lib/services/lance_db_service.dart` wraps the generated bindings; `lib/providers/vector_db_provider.dart` exposes stats and collection counts to the UI.

### MCP (Model Context Protocol)

`McpService` (`lib/services/mcp_service.dart`) manages a pool of `McpClient` connections. Tools are discovered via `listTools()`, cached in memory, and passed to Ollama as function-calling schemas. Tool calls route back to the correct server; results loop to the LLM (max 10 rounds). Bearer token auth is supported per server.

`mcp_provider.dart` holds connection state, exposes add/remove/toggle actions, and emits audit events for connect, disconnect, and tool calls.

### Audit Logging

`AuditLogger` is injected into action providers (`VaultActions`, document builders, `McpNotifier`). Auth events are logged from `lock_screen.dart` to break a circular dependency. Writes are async to Drift; `auditLogsProvider` streams the last 200 logs. Standard action names live in `AuditAction` in `audit_provider.dart`.

### AWS Integration

One-way sync from AWS Secrets Manager using OIDC Device Authorization Flow (no long-lived credentials). SigV4-signed requests. Multi-key JSON secrets are parsed into individual vault rows. Implementation: `lib/services/aws_sso_service.dart` + `aws_secrets_manager_service.dart`.

### Remote Server Monitoring

`aiv_agent` is a Go binary deployed on Linux servers (`aiv_agent/`). It collects CPU, memory, disk, network, top processes, and systemd service status, and communicates with AI VaultIO over mTLS (certificates generated in-app). Build targets: native, Linux amd64 cross-compile, RPM.

## Wiki Maintenance

The in-app wiki lives in `wiki/` (bundled as a Flutter asset). The index is `wiki/wiki.json`. **Whenever you change code — features, behavior, settings, or bug fixes — update the relevant wiki pages.** Stale wiki content causes the RAG pipeline to return wrong answers to users.

- New features → add a markdown page + register it in `wiki/wiki.json`
- Changed behavior → update the relevant `wiki/features/` or `wiki/advanced/` page
- Version bumps → add an entry to `wiki/advanced/changelog.md`
