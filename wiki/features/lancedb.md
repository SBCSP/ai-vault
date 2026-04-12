# LanceDB

## Overview

LanceDB is the exclusive vector store for AI VaultIO. It is a Rust-native, embedded vector database compiled directly into the app via the Flutter Rust Bridge. No external server or setup script is required — LanceDB is always available.

## Accessing LanceDB

Open the **LanceDB** screen from the sidebar. It provides:

- **Status banner** — Active (green), initializing, or error (red with details)
- **Metrics** — Total embeddings, vector dimension, index type
- **Dimension selector** — Match the embedding dimension to your Ollama model
- **Index management** — Build, rebuild, or delete all embeddings

## Embedding Dimensions

The vector dimension must match the model you use in Settings → Embedding Model:

| Model | Dimension |
|---|---|
| nomic-embed-text | 768 |
| mxbai-embed-large | 1024 |
| all-minilm | 384 |
| text-embedding-3-large | 4096 |

Changing the dimension requires a full re-index (all existing embeddings are deleted and rebuilt).

## Index Management

### Build Index
Creates an IVF_PQ (Inverted File with Product Quantization) ANN index over existing embeddings. Required for fast similarity search at scale.

### Re-Index All
Deletes all embeddings and rebuilds from scratch by re-embedding every secret, note, idea, document chunk, chat session, audit log, and wiki page. This operation is slow — it makes one Ollama API call per item.

### Delete All Embeddings
Clears all vectors from LanceDB. RAG search will return no results until you re-index.

## Storage Location

LanceDB files are stored in your macOS Application Support directory alongside the SQLite database:

```
~/Library/Application Support/com.example.aiVault/lance_db/
```

## Troubleshooting

If the status banner shows an error:
- Ensure the app was built with the Rust bridge compiled (`flutter build macos`)
- Check that `ai_vault_rust.framework` is present in the app bundle
- Try the **Retry** button to re-initialize
