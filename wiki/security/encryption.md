# Encryption

## How AI VaultIO Encrypts Your Data

AI VaultIO uses AES encryption to protect sensitive data at rest. The encryption is handled by the `EncryptionService` class.

## What Gets Encrypted

- **Secret values** (passwords, API keys, tokens)
- **Note bodies**
- **Idea bodies**

Titles, tags, categories, and metadata are stored in plaintext to enable search and indexing.

## Encryption Flow

```
User enters data -> EncryptionService.encrypt() -> Encrypted blob -> SQLite DB
SQLite DB -> Encrypted blob -> EncryptionService.decrypt() -> Displayed to user
```

## Database Location

The SQLite database is stored in your Application Support directory:

```
~/Library/Application Support/com.sbcsp.aiVault/ai_vault.sqlite
```

This location is within the macOS app sandbox, providing OS-level protection in addition to application-level encryption.

## Key Management

The encryption key is derived from your master PIN and stored securely using the platform keychain via `flutter_secure_storage`. The key never touches disk in plaintext.

## At Rest vs In Transit

- **At rest** — AES encryption in the SQLite database
- **In transit (local)** — Ollama communication is over localhost HTTP (no network exposure)
- **In transit (cloud)** — Claude API calls use HTTPS/TLS
- **In transit (Vault API)** — Self-signed TLS certificate for localhost HTTPS
- **In transit (aiv_agent)** — Mutual TLS with CA-signed certificates
