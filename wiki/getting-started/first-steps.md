# First Steps

## Creating Your First Secret

1. From the home screen, tap the **+** button and select **Secret**
2. Fill in the fields:
   - **Title** — A name for the entry (e.g., "GitHub Personal")
   - **Category** — Select from Login, API Key, SSH Key, etc.
   - **Username** — Your username or label
   - **Password** — The secret value
   - **URL** — Associated website or service
   - **Notes** — Any additional context
   - **Tags** — Comma-separated tags for organization
   - **Expiry** — Optional expiration date
3. Tap **Save**

Your secret is encrypted and stored locally.

## Adding a Note

1. Tap **+** > **Note**
2. Give it a title and write your content in the body
3. Add tags for easy retrieval
4. Save

Notes support markdown formatting and are indexed for AI search.

## Chatting with Your AI

1. Use the search bar on the home screen, or tap the chat icon to enter **Focus Mode**
2. Ask natural language questions:
   - *"Find my GitHub credentials"*
   - *"How many API keys do I have?"*
   - *"What notes do I have about Kubernetes?"*
3. The AI searches your vault using semantic similarity (RAG) and returns matching records

## Importing Documents

1. Go to **Documents** from the home screen
2. Tap **+** to add a document (PDF or text)
3. The document is automatically chunked and indexed
4. You can now ask the AI about document contents

## Tips

- Use the **Secrets Lock** toggle in the chat header to control whether the AI can access secrets
- Save important chat conversations with **Save & Index** to build your AI's knowledge base
- Set up **auto-lock timeout** in Settings to protect your vault when away
