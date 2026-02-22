# Knowledge Providers

The soul protocol defines WHAT operations are needed on knowledge. Providers define HOW.

## Interface

Every provider must support these operations:

| Operation | Description | Required |
|---|---|---|
| `search(query)` | Semantic or keyword search across knowledge files | Yes |
| `read(path)` | Read a specific file | Yes |
| `write(path, content)` | Write/update a specific file | Yes (agent mode) |
| `index(path)` | Add or refresh content in the search index | Optional |

The orchestrator adapts its instructions based on the declared provider in `soul.config.yml`.

## Providers

### `kiro-cli` — Kiro CLI built-in knowledge tool

Uses the `knowledge` tool for semantic search across indexed knowledge bases.

**Search:** `knowledge` tool with `search` command
**Read:** `fs_read` (fallback when search returns no results)
**Write:** `fs_write` to knowledge files, then `knowledge` tool `update` to re-index
**Index:** `knowledge` tool `add` command

**Orchestrator instructions:**
```
Always use the `knowledge` tool to search before reading files directly.
Fall back to `read` only if the knowledge tool fails or returns no results.
After writing to knowledge files, update the knowledge index.
```

### `qmd` — Local hybrid search (BM25 + vectors + LLM reranking)

Uses [qmd](https://github.com/tobi/qmd) for high-quality local search over markdown files. Combines BM25 full-text search, vector semantic search, and LLM re-ranking — all running locally.

**Setup:**
```bash
# Install
npm install -g @tobilu/qmd

# Create collections from soul knowledge domains
qmd collection add ~/.soul/knowledge --name soul
qmd collection add ~/.soul/knowledge/sales --name soul-sales
qmd collection add ~/.soul/knowledge/journal --name soul-journal

# Add context metadata (from soul.config.yml domain contexts)
qmd context add qmd://soul "Personal knowledge: lessons, preferences, decisions, sessions"
qmd context add qmd://soul-sales "Sales: activities, contacts, insights, team feedback"
qmd context add qmd://soul-journal "Daily session logs: raw capture of notable events"

# Generate embeddings
qmd embed
```

**Search:** Three modes depending on need:
- `qmd search "<query>" --json` — fast BM25 keyword search
- `qmd vsearch "<query>" --json` — semantic vector search
- `qmd query "<query>" --json` — hybrid + query expansion + LLM reranking (best quality)

**Read:** `qmd get <path>` or `fs_read` for full file content
**Write:** `fs_write` to knowledge files, then `qmd update` to re-index
**Index:** `qmd embed` for vectors, `qmd update` for full re-index

**MCP server (recommended):**

QMD exposes an MCP server that any MCP-compatible agent can use directly:

```json
{
  "mcpServers": {
    "qmd": {
      "command": "qmd",
      "args": ["mcp"]
    }
  }
}
```

Tools exposed: `qmd_search`, `qmd_vector_search`, `qmd_deep_search`, `qmd_get`, `qmd_multi_get`, `qmd_status`. When using the MCP server, no provider-specific orchestrator instructions are needed — the agent discovers and uses the tools natively.

**Collection-scoped search:**
```bash
qmd search "quarterly planning" -c soul-sales    # search only sales domain
qmd query "lessons learned" -c soul              # search only general knowledge
```

**After sync:** Run `qmd update` after `soul-sync` to re-index changed files. Can be chained:
```bash
soul-sync --commit && qmd update
```

### `file` — Plain file reads (lowest common denominator)

No semantic search. Uses direct file reads and grep for keyword matching. Works everywhere.

**Search:** `grep` or equivalent text search across knowledge directory
**Read:** `fs_read`
**Write:** `fs_write`
**Index:** N/A

**Orchestrator instructions:**
```
Read knowledge files directly. Use grep to search for keywords across
the knowledge directory. No semantic search is available — rely on
file organization and entry format for discoverability.
```

### `mem0` — Mem0 OpenMemory MCP

Uses Mem0's MCP server for persistent memory with semantic search.

**Search:** Mem0 MCP `search_memory` tool
**Read:** Mem0 MCP `get_memory` tool or `fs_read` for raw files
**Write:** Mem0 MCP `add_memory` tool
**Index:** Automatic (Mem0 indexes on write)

**Orchestrator instructions:**
```
Use Mem0 MCP tools for memory operations. Mem0 handles indexing automatically.
For files not managed by Mem0 (identity, soul, system), use fs_read/fs_write.
```

### `custom` — User-defined commands

For any backend not listed above. Define search and index commands in `soul.config.yml`.

**Configuration:**
```yaml
knowledge:
  provider: custom
  config:
    search_command: "my-tool search {query} --path {path} --json"
    index_command: "my-tool index {path}"
```

**Orchestrator instructions:**
```
Search knowledge by executing the configured search command via bash.
Parse results as JSON. Read/write files directly with fs_read/fs_write.
```

## Adding a Provider

To add a new provider:

1. Add a section to this file describing the provider's operations
2. Add the provider name to the supported list in `soul.config.yml`
3. Add orchestrator instructions that the soul-protocol.md can reference
4. Test with both the minimal and full templates
