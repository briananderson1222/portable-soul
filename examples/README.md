# Examples

Example soul implementations demonstrating the range of the specification.

## Planned

- **Minimal chatbot** — A simple assistant using only the portable core (6 files). Demonstrates stateless mode with update envelopes.
- **Professional collaborator** — A full agent runtime soul with three-tier memory, self-learning, and session continuity. Demonstrates the operational extensions in practice.
- **Fictional character** — A character soul showing how identity and soul files create distinct personality. Demonstrates the expressive range of the spec.

## Reference Implementations

The spec is framework-agnostic. To prove it works with a real agent runtime, create a separate repo that:

1. Populates the templates with a real identity
2. Configures `soul.config.yml` for a specific provider and agent source
3. Runs `soul-sync` against live knowledge directories
4. Validates the round-trip: agent produces knowledge → sync extracts → soul repo captures it

### Recommended structure

Use the spec repo as a git submodule. Your populated soul files live alongside it.

```
my-soul-impl/
├── spec/                    ← submodule → portable-soul repo
│   ├── templates/
│   ├── tools/
│   └── providers/
├── soul/                    ← your actual populated soul
│   ├── soul-protocol.md     ← symlink → spec/templates/full/soul-protocol.md
│   ├── core/
│   │   ├── identity.md      ← your real identity
│   │   ├── soul.md          ← your real values
│   │   └── user.md          ← your real profile
│   ├── knowledge/           ← synced from agent runtime
│   │   ├── memory.md
│   │   ├── learning.md
│   │   ├── continuity.md
│   │   ├── followups.md
│   │   └── bookmarks.md
│   └── soul.config.yml      ← your provider + sync config
└── sync.sh                  ← wraps spec/tools/soul-sync with your paths
```

### Keeping spec and implementation in sync

The orchestrator (`soul-protocol.md`) is the one file that must always match the spec. Symlink it from the submodule so it stays current automatically. Your populated content (identity, soul, user, knowledge) is yours and never gets overwritten by spec updates.

```bash
# Setup
git submodule add <portable-soul-repo-url> spec
cd soul && ln -s ../spec/templates/full/soul-protocol.md soul-protocol.md

# When the spec updates
git submodule update --remote

# Check for new template fields you might want to adopt
diff <(grep "^##\|^###" spec/templates/full/identity.md) \
     <(grep "^##\|^###" soul/core/identity.md)
```

Submodules have a reputation for being painful, but the mechanical footguns (forgetting `--recurse-submodules`, detached HEAD) are exactly the kind of thing AI agents handle well. The conceptual model is clean: spec is a dependency, your soul is your content.

This keeps the spec clean while providing a concrete test harness.

## Contributing

To add an example, create a directory with a complete set of soul files and a README explaining the design decisions and what the example demonstrates.
