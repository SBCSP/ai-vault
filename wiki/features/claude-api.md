# Claude API

## Overview

AI VaultIO supports Anthropic's Claude as a cloud LLM provider, giving you access to more powerful models for complex reasoning, summarization, and analysis.

## Setup

1. Get an API key from [console.anthropic.com](https://console.anthropic.com)
2. Go to **Settings > Claude API**
3. Enter your API key and tap **Save**
4. Select your preferred model
5. Tap **Test Connection** to verify
6. Switch to Claude in the **Active LLM Provider** selector

## Available Models

| Model | Description | Best For |
|-------|-------------|----------|
| Claude Sonnet 4 | Fast & capable | General use, daily tasks |
| Claude Opus 4 | Most intelligent | Complex reasoning, analysis |
| Claude Haiku 4 | Fastest & compact | Quick answers, high volume |

## Security: Automatic Secrets Lock

**When Claude is the active provider, secrets are automatically locked.** This is a core security feature:

- Secret values are never sent to the Claude API
- The AI's context includes notes, ideas, and documents but NOT secrets
- The system prompt explicitly tells Claude it's running as a cloud model
- To access secrets via AI, switch back to Ollama (local)

This ensures your sensitive credentials never leave your machine, even when using cloud AI.

## Streaming

Claude responses stream in real-time via Server-Sent Events (SSE). Text appears progressively as the model generates it, giving you immediate feedback.

## Cost

Claude API usage is billed by Anthropic based on input/output tokens. AI VaultIO sends your vault context as input, so larger vaults = more tokens. Consider using Haiku for cost-sensitive workloads.
