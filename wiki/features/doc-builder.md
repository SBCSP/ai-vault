# Document Builder

The Document Builder is an AI-powered .docx editor that lets you create and edit Word documents with LLM assistance.

## Opening the Document Builder

Click **Doc Builder** in the sidebar to open the feature. You'll see two options:

- **Open .docx** — Select an existing Word document from your computer
- **Create New** — Choose a save location and start a fresh document

## Split-Pane Layout

Once a document is loaded, the screen splits into two panels:

- **Left panel (Document)** — Shows the document content as editable blocks (headings, paragraphs, lists, tables, page breaks)
- **Right panel (AI Chat)** — Chat with the LLM about your document

You can drag the divider between panels to resize them.

## Document Editing

### Block Types
Documents are composed of blocks:
- **Heading 1, 2, 3** — Section headings at different levels
- **Paragraph** — Regular text content
- **Bullet List** — Unordered list items
- **Numbered List** — Ordered list items
- **Table** — Tabular data
- **Page Break** — Forces a new page in the exported .docx

### Editing Blocks
- **Tap** a block to select it (highlighted with a blue border)
- **Double-tap** a block to edit its text inline
- Use the **popup menu** (right-click or long-press) to:
  - Edit the block content
  - Add a new block below
  - Delete the block
- Click the **+** button at the bottom to add a new block

### Undo / Redo
The toolbar includes undo and redo buttons. Up to 50 states are preserved in history.

## AI-Assisted Writing

The chat panel is document-aware. The LLM always has the full document content as context, including which block is currently selected.

### Real-Time Document Editing

The AI edits your document directly. When you ask it to write, add, edit, replace, or delete content, it automatically applies the changes to the document in real time. No manual copy/paste needed.

For example:
- "Add a paragraph about model cars below the section about model planes"
- "Replace the introduction with something more formal"
- "Delete the last paragraph"
- "Add a bullet list of key takeaways after block 3"

The AI understands your document's structure and intelligently places content at the right location using block references.

### Edit Operations

The AI can perform these operations:
- **Insert after** — Add new content after a specific block
- **Insert before** — Add new content before a specific block
- **Replace** — Replace an existing block with new content
- **Delete** — Remove a block
- **Append** — Add content to the end of the document

After each edit, the chat shows an "Auto-edited" summary describing what changed. You can always undo with the toolbar undo button.

### Suggested Actions
Quick-start chips are provided:
- "Write an introduction"
- "Create an outline"
- "Add a conclusion"
- "Expand the selected section"
- "Proofread and fix issues"
- "Add a summary paragraph"

## Saving

- Click **Save** in the toolbar to write changes back to the .docx file
- An unsaved changes indicator (*) appears next to the filename when edits are pending
- Click **Close** to close the current document (you'll be prompted if there are unsaved changes)

## RAG Integration

The Document Builder chat uses the same RAG pipeline as the main AI Chat. It can retrieve relevant context from your notes, ideas, documents, wiki pages, and audit logs to inform its responses.
