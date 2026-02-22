# Architecture

## Two-Layer Model

Portable Soul separates identity into two composable layers that serve different contexts.

### Layer 1: Portable Core

The portable core is six Markdown files that define a complete identity. It works with any LLM that accepts text context — no tools, no file system, no framework required.

The core answers five questions:
1. **How should the assistant behave?** → `soul-protocol.md` (orchestrator)
2. **Who is the assistant?** → `identity.md` (personality) + `soul.md` (values)
3. **Who is the user?** → `user.md` (profile, preferences, relationship)
4. **What can the assistant do?** → `system.md` (capabilities, rules, session model)
5. **What does the assistant remember?** → `memory.md` (facts, events, decisions)

The orchestrator (`soul-protocol.md`) is the entry point. It contains the loading sequence, operating modes, conflict resolution, memory lifecycle, and update format. It is immutable by the assistant and identical across all souls.

### Layer 2: Operational Extensions

Extensions activate when the runtime supports file access, tools, and persistent storage. They add capabilities that require an agent runtime:

- **Three-tier memory** — upgrades the core's two-tier memory with an Index tier (lightweight pointers to source systems) and separates Working Memory from Career Knowledge
- **Self-learning** — structured capture of lessons, preferences, and decisions with explicit when-to-add/when-not-to-add rules
- **Session continuity** — session registry, context switching, handoff summaries, EOD wind-down
- **Followups** — action items tracked only on explicit user intent
- **Bookmarks** — persistent reference links with categories

Extensions are optional and independent. A runtime can support some extensions but not others. The orchestrator detects available extensions through the capability declaration in `system.md`.

## Design Decisions

### Why two layers instead of one?

Soul Protocol uses a single layer of six files. This works well for chat-only LLMs but leaves significant capability on the table for agent runtimes. A single-layer approach forces a choice: either the spec is simple enough for ChatGPT (and misses session continuity, learning, etc.) or it's rich enough for agents (and can't degrade to chat-only).

Two layers solve this. The portable core is the minimum viable identity — it works everywhere. Extensions add professional-grade capabilities where the runtime supports them. Same identity, different operational depth.

### Why separate identity from soul?

Identity defines *how* the assistant presents itself — personality, voice, tone, boundaries. Soul defines *who* the assistant chooses to be — values, essence, purpose, continuity. The distinction matters because identity can shift (tone adapts to context) while soul is stable (values don't change based on who's asking).

This separation comes from Soul Protocol and is preserved here.

### Why three memory tiers instead of two?

Soul Protocol defines Working Memory (always loaded) and Archive (on demand). This works for personal use but breaks down for professional contexts where you work across multiple systems (CRM, email, project management, etc.).

The three-tier model:

**Tier 1 — Index entries** are lightweight pointers written automatically after artifact creation in external systems. They contain a date, topic, one-line summary, and a link back to the source. They are never pruned. They solve the aggregation problem: "what did I do for this account this quarter?" becomes answerable without querying every source system.

**Tier 2 — Working Memory** is ephemeral session context: handoff notes, today's priorities, active session state. It auto-expires. Continuity handoffs older than 7 days are removed silently. Stale sessions are cleaned up automatically.

**Tier 3 — Career Knowledge** is high-signal context that matters long-term: key wins, relationship dynamics, strategic decisions, user corrections, institutional knowledge. It requires justification before saving and is never auto-pruned. Age alone is not a reason to remove an entry.

The key insight: **index freely, capture carefully.** Tier 1 flows automatically. Tier 3 requires the "future value" test.

### Why conservative capture?

Soul Protocol says: "after each meaningful interaction, evaluate whether new memory entries should be created." This is permissive — it leads to memory bloat over time because there's no quality gate.

Portable Soul requires justification for career knowledge. Before offering to save something, the agent must pass the future value test:
- What realistic query would surface this entry?
- Would future-me benefit from finding this?
- Does this context exist in any single source system, or is it synthesis?

If the agent can't articulate a clear reason, it shouldn't offer. If it can, it should — proactively, with the justification visible. The user learns what the system values and starts trusting its judgment.

### Why "don't copy records — index them"?

The knowledge base should never contain the full text of a CRM activity, email, or project document. Instead, it stores a one-line summary with a link back to the source. This keeps the knowledge base lean and scannable while making source systems navigable.

This is a philosophical departure from Soul Protocol, which stores facts directly in memory. Direct storage works for personal context but creates duplication problems for anyone working across professional tools.

### Why no age-based pruning of career knowledge?

Soul Protocol decays entries older than 90 days with low importance. This is dangerous for professional contexts where customer relationships and strategic decisions span years. A stakeholder dynamic noted 18 months ago might be exactly what you need before a renewal meeting.

Portable Soul never auto-prunes career knowledge. The agent may suggest consolidating related entries or flagging potential staleness, but never deletes without asking. Multi-year context is expected and valued.

### Why explicit-intent-only for followups?

It's tempting to have the agent infer action items from conversation context. But inferred TODOs create noise — the user knows what they deferred, and tracking it without being asked feels presumptuous.

Followups are only created when the user explicitly signals intent: "remind me," "TODO," "don't let me forget." This keeps the followup list trustworthy — everything on it was deliberately placed there.

## Integration Model

### Portable Soul as spec, agent frameworks as implementations

Portable Soul is a specification. Agent frameworks are implementations that may already follow these patterns — or can be adapted to. The soul repo is where the portable output lives, extracted from whatever framework produces it.

```
Agent Framework (any)
├── config/                           ← Behavior rules (the "how")
│   ├── personality.md                ← Personality + interaction rules
│   ├── memory-rules.md              ← Memory tier definitions
│   └── ...                           ← Domain-specific rules
├── knowledge/                        ← Runtime output (the "what")
│   ├── lessons.md                    ← Learned lessons
│   ├── preferences.md                ← Confirmed preferences
│   ├── decisions.md                  ← Architectural decisions
│   ├── user-profile.md              ← User context
│   ├── bookmarks.md                  ← Saved links
│   ├── sessions.md                   ← Session registry
│   └── continuity.md                 ← Handoff notes
└── skills/                           ← Specialist capabilities

         ↓ soul-sync (extract)

~/.soul/                              ← Git repo. The portable soul.
├── soul-protocol.md                  ← Orchestrator
├── soul.config.yml                   ← Provider + sync config
├── core/                             ← Identity layer
│   ├── identity.md
│   ├── soul.md
│   └── user.md
└── knowledge/                        ← Knowledge layer
    ├── memory.md
    ├── learning.md
    ├── continuity.md
    ├── followups.md
    └── bookmarks.md
```

The agent framework doesn't need to know about portable-soul. It continues to work as-is. The sync tool runs externally and extracts the portable parts.

### File mapping: Agent Framework → Portable Soul

The sync tool maps agent knowledge files to portable soul format:

| Agent Knowledge File | Portable Soul File | Strategy |
|---|---|---|
| `lessons.md` | `knowledge/learning.md` (Lessons section) | Merge by section |
| `preferences.md` | `knowledge/learning.md` (Preferences section) | Merge by section |
| `decisions.md` | `knowledge/learning.md` (Decisions section) | Merge by section |
| `user-profile.md` | `core/user.md` | Copy |
| `bookmarks.md` | `knowledge/bookmarks.md` | Copy |
| `continuity.md` | `knowledge/continuity.md` | Copy |
| `sessions.md` | `knowledge/continuity.md` (Sessions section) | Merge by section |
| `followups.md` | `knowledge/followups.md` | Copy |

These mappings are configurable in the sync tool. If your agent framework uses different file names or structures, adjust the mapping.

### Sync tool

`tools/soul-sync` extracts knowledge from agent runtimes into the soul repo:

```bash
soul-sync                    # Sync from configured agent sources
soul-sync --dry-run          # Preview changes without writing
soul-sync --commit           # Sync and auto-commit to soul repo
soul-sync --source /path     # Sync from a specific directory
```

Can be run manually, as a cron job, or as a boo scheduled task. Configure source directories in the script or via `SOUL_DIR` environment variable.

### Other consumers

Once knowledge is in the soul repo, other frameworks can consume it:

**IDE assistants** (Cursor, Copilot) — export core files to `.cursorrules` or `copilot-instructions.md`. Static snapshots of identity and preferences.

**Chat interfaces** (Claude, ChatGPT) — paste the minimal template files as context. Memory updates proposed via `[SOUL-UPDATE]` envelope, applied manually.

**Other agent frameworks** — read directly from `~/.soul/` or sync in the other direction.

### Pluggable knowledge backends

The soul protocol defines WHAT operations are needed (search, read, write, index). The provider defines HOW. This is declared in `soul.config.yml` and the orchestrator adapts.

```yaml
knowledge:
  provider: qmd          # or: kiro-cli, file, mem0, custom
  path: ./knowledge
```

The provider abstraction means the same soul works with:
- **kiro-cli** — built-in `knowledge` tool (semantic search via MiniLLM)
- **qmd** — local hybrid search (BM25 + vectors + LLM reranking)
- **file** — plain `fs_read` + grep (works everywhere, no semantic search)
- **mem0** — Mem0 OpenMemory MCP server
- **custom** — user-defined search/index commands

See `providers/README.md` for the full provider interface and per-provider orchestrator instructions.

The orchestrator includes a Knowledge Access section that adapts based on the declared provider. This is the single biggest enabler for framework portability — the same knowledge files work whether you're using kiro-cli's built-in search or qmd's hybrid retrieval.

### Separation of concerns

After integration, responsibilities split cleanly:

| Concern | Owner | Location |
|---|---|---|
| Identity, personality, values | Soul repo | `~/.soul/core/` |
| Memory, learning, continuity | Soul repo | `~/.soul/knowledge/` |
| Specialist skills, tools | Agent framework | Framework config, IDE settings, etc. |
| Domain-specific rules | Agent framework | Package context files |
| Knowledge search/indexing | Provider | Configured in `soul.config.yml` |
| Runtime capabilities | Agent framework | `system.md` (per-deployment) |

The soul is who you are. The agent framework is what you can do. They compose.

## Comparison with Soul Protocol

Portable Soul is built on Soul Protocol's foundation. The core architecture (orchestrator, six files, capability-aware modes, conflict resolution, update envelope) is adapted from Soul Protocol with attribution.

### What Portable Soul adds:
- Three-tier memory model (Index / Working / Career)
- Self-learning framework (lessons, preferences, decisions)
- Session continuity (registry, handoffs, EOD wind-down)
- Proactive capture with justification
- Future value test for career knowledge
- Multi-year context awareness (no age-based pruning)
- Source system indexing (pointers, not copies)
- Followups and bookmarks as first-class extensions
- Explicit-intent-only capture for action items

### What Portable Soul preserves:
- Markdown-first, human-readable, git-friendly
- Capability-aware operating modes (stateless / agent)
- Seven-level conflict resolution hierarchy
- Canonical update envelope format
- Graduated mutability model
- Session model with privacy controls
- User ownership of all data
- Specification purity (no runtime, no platform)

### What Portable Soul changes:
- Memory: three tiers instead of two, with different pruning rules per tier
- Capture: conservative (justify before saving) instead of permissive (evaluate after each interaction)
- Pruning: career knowledge is never auto-pruned; only working memory expires
- Extensions: modular operational layer that activates based on runtime capabilities
- Scope: designed for professional AI collaborators, not just personal companions
