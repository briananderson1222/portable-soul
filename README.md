# Portable Soul

**A two-layer specification for portable AI identity, memory, and continuity.**

Portable Soul defines a structured, human-readable system that decouples who an AI assistant is, what it knows, and how it learns from any specific model, provider, or framework. It combines the portability of [Soul Protocol](https://soul-protocol.com/) with a richer memory model, self-learning, session continuity, and disciplined capture — designed for AI that works with you professionally, not just chats with you.

> Change the brain. Keep the soul. Bring the memory.

## Get Started in One Command

```bash
npx portable-soul              # Install to ~/.soul/
```

The installer creates `~/.soul/` — a clean Obsidian vault and private git repo. Your identity and memory files are yours to edit.

**Additional options:**

```bash
npx portable-soul --dir PATH   # Install to custom directory
npx portable-soul --yes        # Non-interactive mode (skip prompts)
npx portable-soul --help       # Show all options
```

**Update your soul protocol:**

```bash
npx portable-soul --update     # Refresh soul-protocol.md to latest
```

**On Windows without Node.js:**

```powershell
.\cli.ps1              # Downloads templates from GitHub
.\cli.ps1 -Update      # Update soul-protocol.md
```

## The Problem

Every AI assistant starts from zero. Switch models, switch tools, start a new session — your context is gone. The few systems that offer memory lock it to a single platform. There is no standard way to carry identity, accumulated knowledge, and working context across AI systems.

Soul Protocol proposed a clean solution: decouple identity from the model using portable Markdown files. Portable Soul builds on that foundation and extends it for real-world professional use — where memory isn't just facts, learning compounds over time, and work spans sessions, tools, and years.

## Two-Layer Architecture

Portable Soul separates concerns into two composable layers:

### Layer 1: Portable Core (any LLM)

Six Markdown files that work with any LLM that accepts text context — ChatGPT, Claude, local models, IDE assistants, anything. No tools required. No framework dependencies.

```
soul-protocol.md     ← Orchestrator: loading, modes, conflict resolution, updates
identity.md          ← Who the assistant is: personality, voice, values, boundaries
soul.md              ← Philosophical foundation: essence, values, purpose, continuity
user.md              ← Who the user is: preferences, style, goals, relationship
system.md            ← Runtime contract: capabilities, session model, rules
memory.md            ← What the assistant remembers: facts, events, decisions
```

In chat-only LLMs (stateless mode), the assistant proposes memory updates using a structured envelope format. The user or host system applies them between sessions.

### Layer 2: Operational Extensions (agent runtimes)

Additional files that activate when the runtime supports file access, tools, and persistent storage. These are what make the soul useful for real work.

```
lessons.md           ← What went wrong and why: failures, workarounds, gotchas
preferences.md       ← Confirmed user preferences and conventions
decisions.md         ← Architectural choices with rationale
continuity.md        ← Session management: registry, handoffs, wind-down
followups.md         ← Action items: explicit-intent-only, tagged
bookmarks.md         ← Reference links: categorized, persistent
journal/             ← Daily session logs: raw capture, curated over time
```

The extended orchestrator also upgrades memory from two tiers to three:

- **Index** — Lightweight pointers auto-written after artifact creation. Date, topic, summary, link to source. Never pruned.
- **Working Memory** — Session context, handoffs, active facts. Auto-expires.
- **Career Knowledge** — Long-lived insights that require justification. Never auto-pruned.

## Your Vault

After install, `~/.soul/` looks like this:

```
~/.soul/                      # Obsidian vault + private git repo
├── .git/
├── .gitignore
├── .obsidian/                # Obsidian config (partially gitignored)
├── .obsidianignore
├── .config/                  # Path management config
│   ├── default.toml
│   └── <hostname>.toml      # Machine-specific overrides
├── soul-protocol.md          # SYSTEM — updated via npx
├── soul.config.yml           # SEED — provider and vault config
├── identity.md               # SEED → user edits
├── soul.md                   # SEED → user edits
├── user.md                   # SEED → user edits
├── system.md                 # SEED → user edits
├── memory.md                 # SEED → AI manages
├── lessons.md                # SEED → AI appends
├── preferences.md            # SEED → AI appends
├── decisions.md              # SEED → AI appends
├── continuity.md             # SEED → AI manages
├── followups.md              # SEED → AI manages
├── bookmarks.md              # SEED → AI manages
└── journal/                  # DYNAMIC
    └── README.md
```

Three file categories:

| Category | On install | On update | Examples |
|----------|-----------|-----------|---------|
| System | Copied | Replaced | `soul-protocol.md` |
| Seed | Copied | Only new files added | `identity.md`, `soul.md`, etc. |
| Dynamic | Empty stub | Never touched | `journal/` |

## Using Your Soul

**With ChatGPT / Claude Web:**
- Attach the 6 core files as context to your chat

**With AI Agents (file access):**
- Point them to `~/.soul/`
- They read `soul-protocol.md` first and initialize from there

**With Obsidian:**
- Open `~/.soul/` as a vault
- Edit, browse, and curate your knowledge graph

### Path Management

Soul files can be synced to external locations (e.g., `.config/claude/`, `.config/kiro/`) for use by multiple AI tools:

```bash
npx portable-soul symlinks                      # Show current path status
npx portable-soul symlinks --sync              # Sync all configured paths
npx portable-soul symlinks --sync --mode copy  # Use copy mode instead of symlinks
npx portable-soul symlinks --sync --dry-run    # Preview changes without applying
npx portable-soul symlinks --remove            # Remove all linked paths
```

Configure paths in `~/.soul/.config/default.toml`:

```toml
[paths]
identity.md = "~/.config/claude/identity.md"
memory.md = ["~/.config/kiro/memory.md", "~/.config/claude/memory.md"]

[sync]
link_mode = "link"      # "link" (symlink) or "copy"
provider = "copy"       # "copy", "rsync", or "git-sync"
direction = "forward"   # "forward", "reverse", or "bidirectional"
exclude = [".DS_Store", "*.tmp"]
dry_run = false
```

### Minimal Setup (no file access)

For LLMs that can't write files:

1. Copy `templates/minimal/` anywhere
2. Fill in `identity.md`, `soul.md`, and `user.md`
3. Paste all 6 files as context when chatting

The assistant will propose memory updates using a structured envelope format. You apply them between sessions.

## What Makes This Different

Most approaches to AI memory and identity are either locked to a platform (Mem0, Letta) or limited to personality without operational depth (OpenClaw SOUL.md, Soul Protocol).

Portable Soul combines portability with professional-grade memory:

- **Three-tier memory** — index entries (auto-written pointers to source systems), working memory (session context, auto-expires), and career knowledge (long-lived, requires justification, never auto-pruned)
- **Capture discipline** — concrete signal classes and timing tiers (immediate, continuous, background) instead of vague "save what matters" rules. Never depends on session end.
- **Bidirectional sync** — same file format on both sides, `rsync --update` (newer wins), no format translation
- **Pluggable search** — swap between kiro-cli, QMD (BM25 + vectors + reranking), Mem0, or plain file reads via config
- **Vault-aware writing** — adapts to Obsidian (wikilinks, frontmatter, tags), Logseq, or plain markdown based on declared features
- **Knowledge domains** — separate namespaced areas (sales, career, journal) with their own structure and context metadata
- **Self-learning** — structured lessons, preferences, and decisions with explicit when-to-add and when-NOT-to-add rules
- **Session continuity** — registry, handoffs, EOD wind-down, automatic stale cleanup
- **Source system indexing** — pointers back to where records live, not copies of them

Built on [Soul Protocol](https://soul-protocol.com/)'s foundation (orchestrator, conflict resolution, capability-aware modes, update envelope) and inspired by [OpenClaw](https://www.openclaw.ai)'s pioneering work on agent identity files.

## Design Principles

- **Markdown-first.** Plain text. Git-friendly. Human-auditable. Any LLM can read it.
- **Two layers, one identity.** The portable core travels everywhere. Extensions activate where supported.
- **Index freely, capture carefully.** Lightweight pointers flow automatically. Career knowledge requires justification.
- **Don't copy records — index them.** The knowledge base is a personal index, not a duplicate of source systems.
- **Age is not staleness.** Multi-year context is expected. Only prune what's genuinely irrelevant.
- **Explicit intent over inference.** Only track action items when the user explicitly asks. Don't infer TODOs.
- **Justify before offering.** When proposing to save something, articulate why it has future value.

## Pluggable Knowledge Backends

The soul protocol defines what operations are needed (search, read, write). The provider defines how. Declare your backend in `soul.config.yml`:

```yaml
knowledge:
  provider: qmd        # or: kiro-cli, file, mem0, custom
  path: ./knowledge

  domains:
    general:
      source: ~/.agent/knowledge/memories
      dest: ./knowledge
      context: "Personal knowledge: lessons, preferences, decisions"
    sales:
      source: ~/.agent/knowledge/sales
      dest: ./knowledge/sales
      context: "Sales: activities, contacts, insights"
```

Supported providers:
- **kiro-cli** — built-in semantic search via MiniLLM
- **qmd** — local hybrid search (BM25 + vectors + LLM reranking), MCP server included
- **file** — plain file reads + grep (works everywhere)
- **mem0** — Mem0 OpenMemory MCP server
- **custom** — your own search/index commands

## Vault-Aware Writing

The soul adapts its writing style based on the declared vault provider:

```yaml
vault:
  provider: obsidian    # or: plain, logseq
  features: [wikilinks, frontmatter, tags, daily-notes, backlinks]
```

With `plain` (default), agents write standard markdown. With `obsidian`, agents use `[[wikilinks]]` to connect entries, YAML frontmatter for metadata, and `#tags` for categorization — building a navigable knowledge graph over time.

See `providers/README.md` for the full provider and vault interface specs.

## Integration with Agent Frameworks

The soul repo (`~/.soul/`) is the source of truth. Agent frameworks integrate via sync:

```bash
soul-sync              # Forward: agent runtime → soul repo (newer wins)
soul-sync --reverse    # Reverse: soul repo → agent runtime (newer wins)
soul-sync --commit     # Forward + auto-commit to soul repo
```

All sync is bidirectional `rsync --update` — same file format on both sides, no translation. Sources and domains are configured in `soul.config.yml`.

Integration patterns:
- **Agent frameworks** — pre-build sync copies `soul-protocol.md` into the framework's context. Knowledge syncs bidirectionally via `soul-sync`.
- **Obsidian** — open `~/.soul/` as a vault. Browse, edit, and curate knowledge. Daily notes map to `journal/YYYY-MM-DD.md`.
- **QMD** — index soul knowledge as collections. Agents search via MCP server or CLI.
- **Cursor / Copilot** — export core files to `.cursorrules` or `copilot-instructions.md`
- **Claude / ChatGPT** — paste minimal template files as context, use update envelopes

### Git Workflow

Your `~/.soul/` directory is your private git repo:

```bash
# Your changes
git add identity.md soul.md user.md
git commit -m "update my soul"
git push  # To your private remote

# Update the protocol
npx portable-soul --update
```

## Project Structure

```
portable-soul/                 # npm package
├── README.md                  ← You are here
├── ARCHITECTURE.md            ← Two-layer design, integration model, comparisons
├── LICENSE                    ← MIT
├── package.json               ← npm config (npx portable-soul)
├── cli.js                    ← CLI installer (Node.js)
├── cli.ps1                   ← CLI installer (PowerShell, no Node.js needed)
├── soul.config.yml            ← Default config template
├── providers/
│   └── README.md              ← Knowledge provider interface + implementations
├── tools/
│   └── soul-sync              ← Extract knowledge from agent runtimes → soul repo
├── templates/
│   ├── minimal/               ← Portable core (6 files, any LLM)
│   └── full/                  ← Core + extensions (agent runtimes)
└── examples/
    └── README.md
```

## Acknowledgments

Portable Soul builds directly on [Soul Protocol](https://soul-protocol.com/) by Luis H. Garcia, which defined the foundational architecture of portable AI identity using Markdown files. The orchestrator design, capability-aware modes, conflict resolution hierarchy, and update envelope format are adapted from Soul Protocol's specification.

The concept of soul files for AI agents was pioneered by [OpenClaw](https://www.openclaw.ai). The capture policy and daily journal pattern draw from OpenClaw's memory architecture.

The knowledge search layer is powered by [QMD](https://github.com/tobi/qmd) by Tobi Lütke — a local hybrid search engine combining BM25, vector embeddings, and LLM reranking for markdown files.

The vault-aware writing system is designed for use with [Obsidian](https://obsidian.md), enabling wikilinks, frontmatter, tags, and knowledge graph navigation across soul files.

[memspan](https://github.com/ericblue/memspan) by Eric Blue informed the file-first, portable memory philosophy — identity continuity across AI tools without infrastructure dependencies.

## License

MIT
