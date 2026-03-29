# AI Chat

## Overview

The AI chat is your primary interface for interacting with your vault. Ask natural language questions and the AI searches your secrets, notes, ideas, documents, and past conversations to give you answers.

## Chat Modes

### Home Screen Search Bar
Quick questions from the dashboard. Results appear inline.

### Focus Mode
Full-screen chat with conversation history. Enter by tapping the expand icon on the search bar or navigating to the chat screen.

## How It Works

1. You type a question
2. AI VaultIO generates an embedding of your query
3. RAG retrieves the top-K most relevant items from your vault
4. The relevant context + your question is sent to the LLM
5. The response streams back in real-time

## Streaming Responses

Responses appear with a typing effect as chunks arrive from the LLM. Both Ollama and Claude support streaming for immediate feedback.

## LLM Providers

### Ollama (Local)
- Runs entirely on your machine
- Full access to secrets (when unlocked)
- No data leaves your computer
- Models: gemma3, llama3, qwen2.5, mistral, etc.

### Claude (Cloud)
- Powered by Anthropic's Claude API
- Secrets are automatically locked
- More capable for complex reasoning
- Models: Sonnet 4, Opus 4, Haiku 4

Switch between providers in **Settings > Active LLM Provider**.

## Chat Sessions

- **Save & Index** — Saves the conversation and indexes it for future RAG retrieval
- **Chat History** — Browse and reload past conversations
- **New Chat** — Start fresh (with option to save current chat first)

## Status Badges

Each AI response shows badges indicating:

- **AI** (green) or **Local** (orange) — Whether the AI was online
- **Cloud** or **Local** — Which LLM provider was used
- **RAG** — Which vault sources were used for context
- **MCP** — If external tools were called
- **Secrets Locked/Open** — Current secrets lock state
