# Installation

## macOS

1. Download the latest `.dmg` from the [GitHub Releases](https://github.com/SBCSP/ai-vault/releases) page
2. Open the DMG and drag **AI VaultIO** to your Applications folder
3. Launch AI VaultIO from Applications

### Ollama (Recommended)

For local AI chat, install Ollama:

```bash
# Install from https://ollama.com or via Homebrew:
brew install ollama

# Pull a model:
ollama pull gemma3:1b
```

AI VaultIO connects to Ollama at `http://localhost:11434` by default. You can change this in **Settings > Ollama Models**.

### Claude API (Optional)

For cloud-based AI with more powerful models:

1. Get an API key from [console.anthropic.com](https://console.anthropic.com)
2. Go to **Settings > Claude API** in the app
3. Paste your API key and select a model

> **Note:** Secrets are automatically locked when using cloud models. Switch to Ollama for secrets access.

## First Launch

On first launch, you'll be prompted to create a master PIN. This PIN protects your vault — choose something memorable but secure. The app will create its encrypted database in your Application Support directory.

## System Requirements

- macOS 12.0 or later
- 4GB RAM minimum (8GB recommended for larger Ollama models)
- 500MB disk space for the app + model storage
