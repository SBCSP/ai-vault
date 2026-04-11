# RAG Search

## What is RAG?

RAG (Retrieval-Augmented Generation) is a technique that enhances AI responses by first retrieving relevant context from your data, then feeding that context to the LLM along with your question.

## How AI VaultIO Uses RAG

```
Query -> Embed query -> Compare against all embeddings -> Top-K results -> LLM context
```

### Step-by-Step

1. **Embedding** — Your question is converted to a numerical vector using Ollama's embedding model
2. **Similarity search** — The query vector is compared against all stored embeddings using cosine similarity
3. **Top-K selection** — The most relevant items (score >= 0.3) are selected, up to 10 items
4. **Context building** — Selected secrets, notes, ideas, document chunks, and past chats are assembled into the LLM context
5. **Generation** — The LLM answers your question using this focused context

## What Gets Indexed

- **Secrets** — Title, category, username, URL, tags, notes
- **Notes** — Title, body, tags
- **Ideas** — Title, body, tags
- **Documents** — Chunked text content
- **Chat sessions** — Saved and indexed conversations
- **Audit logs** — Action, target, details, timestamp
- **Wiki pages** — Built-in app documentation

## RAG Source Badges

Each AI response that used RAG shows a purple badge listing the sources:

- *"RAG: 2 secrets, 1 note"*
- *"RAG: 3 chunks from 1 doc"*
- *"RAG: 1 past chat"*
- *"RAG: 5 audit events"*

## Embedding Provider

Embeddings are generated using Ollama's embedding API. The embedding model runs locally, so your data never leaves your machine during indexing.

## Audit Log Search

Audit logs are automatically vectorized at startup and during re-indexing. This lets you ask the AI natural language questions about your vault activity:

- *"When was the last time I created a secret?"*
- *"Show me recent failed unlock attempts"*
- *"What MCP tools were called this week?"*

Each audit event is embedded with its action, target, details, and timestamp.

## Tips

- Index your chat sessions to build institutional knowledge over time
- Use descriptive titles and tags — they improve semantic matching
- If the AI can't find something, try rephrasing with keywords from the record
- Audit logs are indexed in batches at startup — new events will be indexed on the next app launch or manual re-index
