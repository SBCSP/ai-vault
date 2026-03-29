# MCP Servers

## What is MCP?

MCP (Model Context Protocol) is an open standard that allows AI models to call external tools. AI VaultIO acts as an MCP client, connecting to MCP servers that expose tools the AI can use.

## Setting Up MCP Servers

1. Go to **Settings > MCP Servers**
2. Tap **Add Server**
3. Enter the server details:
   - **Name** — A display name (e.g., "Linear")
   - **URL** — The MCP endpoint (e.g., `https://mcp.linear.app/mcp`)
   - **Auth Token** — Bearer token if required (stored securely)
4. Toggle the server **Enabled** to connect

## How Tool Calling Works

When you ask the AI a question that could be answered by an external tool:

1. The AI recognizes the question matches a tool's description
2. It generates a tool call request with arguments
3. AI VaultIO executes the tool via MCP
4. The result is fed back to the AI
5. The AI synthesizes the tool result into a natural response

This loops up to 10 rounds if multiple tool calls are needed.

## Example

With a Linear MCP server connected:

> **You:** "What are my open issues?"
>
> **AI:** *Calls `list_issues` tool* -> "You have 5 open issues: ..."

## Tool Calling Requirements

- The Ollama model must support function/tool calling (llama3.1+, qwen2.5+, mistral, etc.)
- Tool descriptions are included in the system prompt to help the model decide when to use them
- If no MCP servers are connected, the AI operates normally without tools

## Status Indicators

- **MCP badge** in chat header shows tool count (e.g., "MCP: 5")
- **Tool call badges** on responses show which tools were called, duration, and results
- Expandable tool call details show arguments and return values
