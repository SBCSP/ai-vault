# Documents

## Overview

AI VaultIO can ingest documents (PDF and text) and make them searchable through AI chat. Documents are split into chunks, embedded, and indexed for semantic retrieval.

## Adding Documents

1. Navigate to **Documents** from the home screen
2. Tap **+** to add a new document
3. Select a file from your system
4. The document is parsed, chunked, and indexed automatically

## How It Works

```
Document -> Parse text -> Split into chunks -> Generate embeddings -> Store in DB
```

When you ask the AI a question, relevant chunks are retrieved via cosine similarity and included in the context. The AI cites the source document in its response.

## Supported Formats

- **PDF** — Text is extracted from PDF pages (scanned/image PDFs are not supported)
- **Plain text** — `.txt` files are ingested directly

## Chunking Strategy

Documents are split into overlapping chunks to preserve context across boundaries. Each chunk is typically 500-1000 characters with overlap to ensure relevant passages aren't split awkwardly.

## Tips

- Shorter, focused documents work better than massive dumps
- The AI cites document titles — use descriptive names
- Ask specific questions: *"What does the security policy say about password rotation?"*
- Chunks appear in the RAG source badges on AI responses
