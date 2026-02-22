# Portable Soul

**A two-layer specification for portable AI identity, memory, and continuity.**

Portable Soul defines a structured, human-readable system that decouples who an AI assistant is, what it knows, and how it learns from any specific model, provider, or framework. It combines the portability of [Soul Protocol](https://soul-protocol.com/) with a richer memory model, self-learning, session continuity, and disciplined capture — designed for AI that works with you professionally, not just chats with you.

> Change the brain. Keep the soul. Bring the memory.

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
learning.md          ← Self-learning: lessons, preferences, decisions
continuity.md        ← Session management: registry, handoffs, wind-down
followups.md         ← Action items: explicit-intent-only, tagged
bookmarks.md         ← Reference links: categorized, persistent
```

The extended orchestrator also upgrades memory from two tiers to three:

- **Index** — Lightweight pointers auto-written after artifact creation. Date, topic, summary, link to source. Never pruned.
- **Working Memory** — Session context, handoffs, active facts. Auto-expires.
- **Career Knowledge** — Long-lived insights that require justification. Never auto-pruned.

## Quick Start

### Minimal (chat-only LLMs)

1. Copy `templates/minimal/` to your working directory
2. Fill in `identity.md`, `soul.md`, and `user.md`
3. Attach all six files as context to your LLM
4. The assistant reads `soul-protocol.md` first and initializes from there

### Full (agent runtimes)

1. Copy `templates/full/` to your working directory
2. Fill in the core files (identity, soul, user, system)
3. Configure `system.md` with your runtime's capabilities
4. The orchestrator activates extensions based on declared capabilities

## What Makes This Different

| | Portable Soul | Soul Protocol | OpenClaw SOUL.md | Mem0 / Letta |
|---|---|---|---|---|
| Portable across LLMs | ✅ | ✅ | ❌ (OpenClaw only) | ❌ (platform-specific) |
| Memory tiers | 3 (index/working/career) | 2 (working/archive) | 2 (daily/curated) | Runtime-dependent |
| Self-learning framework | ✅ | ❌ | ❌ | Partial |
| Session continuity | ✅ | Philosophical only | ❌ | ❌ |
| Capture discipline | Justify before saving | Save after meaningful interaction | Informal | Automatic |
| Multi-year context | ✅ (age ≠ staleness) | ❌ (90-day decay) | ❌ | ❌ |
| Source system indexing | ✅ (pointers, not copies) | ❌ | ❌ | ❌ |
| Conflict resolution | 7-level hierarchy | 7-level hierarchy | Implicit | N/A |
| Pure spec (no runtime) | ✅ | ✅ | ❌ | ❌ |

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
```

Supported providers:
- **kiro-cli** — built-in semantic search via MiniLLM
- **qmd** — local hybrid search (BM25 + vectors + LLM reranking)
- **file** — plain file reads + grep (works everywhere)
- **mem0** — Mem0 OpenMemory MCP server
- **custom** — your own search/index commands

See `providers/README.md` for the full interface spec.

## Integration with Agent Frameworks

The soul repo (`~/.soul/`) is the source of truth. Agent frameworks consume it:

- **Agent frameworks** — bridge file loads soul from `~/.soul/`, knowledge dir symlinked or synced
- **Cursor / Copilot** — export core files to `.cursorrules` or `copilot-instructions.md`
- **Claude / ChatGPT** — paste minimal template files as context, use update envelopes

See `ARCHITECTURE.md` for the full integration model.

## Project Structure

```
portable-soul/
├── README.md              ← You are here
├── ARCHITECTURE.md        ← Two-layer design, integration model, comparisons
├── LICENSE                ← MIT
├── soul.config.yml        ← Provider, sync, and adapter configuration
├── providers/
│   └── README.md          ← Knowledge provider interface + implementations
├── tools/
│   └── soul-sync          ← Extract knowledge from agent runtimes → soul repo
├── templates/
│   ├── minimal/           ← Portable core (6 files, any LLM)
│   └── full/              ← Core + extensions (agent runtimes)
└── examples/
    └── README.md
```

## Acknowledgments

Portable Soul builds directly on [Soul Protocol](https://soul-protocol.com/) by Luis H. Garcia, which defined the foundational architecture of portable AI identity using Markdown files. The orchestrator design, capability-aware modes, conflict resolution hierarchy, and update envelope format are adapted from Soul Protocol's specification.

The concept of soul files for AI agents was pioneered by [OpenClaw](https://www.openclaw.ai).

## License

MIT
