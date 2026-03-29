# Secrets Lock

## Overview

The Secrets Lock is an independent control that prevents the AI from accessing your secrets, even when the vault is unlocked. This gives you fine-grained control over what the AI can see.

## How It Works

- **Secrets Unlocked** — The AI includes secret values in its context and can search/reference them
- **Secrets Locked** — Secrets are excluded from the AI context entirely. The AI can still access notes, ideas, and documents.

## Automatic Locking

Secrets are **automatically locked** when you switch to a cloud LLM (Claude). This is enforced at the provider level:

1. User selects Claude as the active LLM
2. Before every message, `sendMessage()` calls `secretsLockProvider.lock()`
3. Vault context sent to Claude has an empty secrets list
4. System prompt tells Claude: *"Secrets have been automatically locked for security"*

To unlock secrets, switch back to Ollama (local).

## Manual Control

You can also toggle secrets manually:

- The **Secrets Lock badge** in the chat header shows the current state
- Toggle it from the home screen secrets section
- Lock state is persisted across app restarts

## Audit Trail

All lock/unlock events are recorded in the audit log:

- `secrets_locked` — When secrets are locked (manual or automatic)
- `secrets_unlocked` — When secrets are unlocked

## Why This Matters

Even if you trust your local Ollama model with secrets, you might want to lock them during a screen share, demo, or when exploring a question that doesn't require secret access. The lock gives you that control.
