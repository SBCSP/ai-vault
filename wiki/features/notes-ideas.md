# Notes & Ideas

## Notes

Notes are free-form text entries for storing information that doesn't fit the secrets format. They support:

- **Title** and **body** (the body is encrypted at rest)
- **Tags** for organization and search
- **Markdown** rendering in the AI chat
- **Full-text search** and RAG indexing

### Use Cases

- Server configuration notes
- Meeting notes and decisions
- Runbooks and procedures
- Research snippets

## Ideas

Ideas are a separate space for brainstorming and capturing thoughts. They follow the same structure as notes but live in their own section:

- Separate **Ideas** tab on the home screen
- Dedicated list view with tag filtering
- Indexed for AI retrieval just like notes

### Use Cases

- Feature ideas and product concepts
- Architecture proposals
- Things to investigate later
- Quick brain dumps

## AI Integration

Both notes and ideas are included in the AI's context when you chat:

- RAG search finds the most relevant notes/ideas for your query
- The AI can reference and quote from your notes
- Ask questions like *"What did I write about Kubernetes networking?"*
- Save AI conversations as indexed chat sessions to build institutional knowledge
