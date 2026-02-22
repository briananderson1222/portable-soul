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

---

## Vault Providers

Vault providers determine how knowledge files are authored and organized. They control what markdown features the orchestrator can use when writing entries.

### Interface

| Capability | Description |
|---|---|
| `wikilinks` | `[[link]]` syntax for connecting related entries |
| `frontmatter` | YAML frontmatter for metadata (tags, date, type) |
| `tags` | `#tag` inline tags for categorization |
| `daily-notes` | Auto-creates dated files for journal entries |
| `backlinks` | Bidirectional link graph for discovery |

### `plain` (default)

Standard markdown. No special syntax. Works everywhere.

**Writing rules:**
- Use standard markdown headings, lists, and links
- Reference other files by name in prose: "see decisions.md"
- No frontmatter unless the file template includes it

### `obsidian`

[Obsidian](https://obsidian.md) vault. Enables rich linking, metadata, and graph navigation.

**Features:** wikilinks, frontmatter, tags, daily-notes, backlinks

**Setup:**
1. Open Obsidian → "Open folder as vault" → select the soul repo root
2. Configure daily notes plugin: folder = `knowledge/journal`, format = `YYYY-MM-DD`
3. Add `.obsidian/` to `.gitignore` (workspace state is local, not portable)

**Writing rules (when features are enabled):**

- **Frontmatter:** Add YAML frontmatter to entries that benefit from metadata:
  ```yaml
  ---
  date: 2026-02-22
  tags: [architecture, decision]
  type: decision
  ---
  ```
- **Wikilinks:** Connect related entries with `[[filename]]` or `[[filename#heading]]`:
  ```markdown
  - Decided on bidirectional sync — see [[decisions#bidirectional-sync]]
  - Related lesson: [[lessons#bash-compat]]
  ```
- **Tags:** Use inline `#tags` for categorization beyond frontmatter:
  ```markdown
  - #project/portable-soul — chose rsync over custom merge
  - #account/acme — prefers REST over GraphQL
  ```
- **Daily notes:** Journal entries use Obsidian's daily notes format. The daily notes plugin auto-creates `knowledge/journal/YYYY-MM-DD.md`.
- **Backlinks:** When writing a new entry, link to related existing entries. Obsidian's backlink panel makes these connections discoverable.

**What stays portable:** Wikilinks and frontmatter are valid markdown — other tools just ignore the `[[]]` syntax and `---` blocks. QMD indexes the content regardless. The vault features add navigability for humans without breaking machine readability.

### `logseq`

[Logseq](https://logseq.com) — outliner-based. Similar to Obsidian but block-oriented.

**Features:** wikilinks, frontmatter, tags, daily-notes, backlinks

**Notes:** Logseq uses a block-reference model (`((block-id))`) that is less portable than Obsidian's file-based links. Use wikilinks for cross-file references, avoid block references in knowledge files that need to be agent-readable.

### Adding a vault provider

1. Add a section to this file describing the provider's features and writing rules
2. Add the provider name to `soul.config.yml`
3. The orchestrator reads the declared features and adapts its writing instructions
