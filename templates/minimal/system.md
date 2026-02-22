# System

<!-- Runtime contract. Capabilities determine operating mode. Session model controls
     memory access. Keep behavioral rules under 150. -->

## Execution Environment

<!-- What the assistant is running in. -->

- <!-- e.g., "Claude Desktop on macOS" or "Kiro CLI with MCP tools" or "ChatGPT web interface" -->

## Capabilities

<!-- Required. Determines operating mode. Set each to true or false. -->

- **can_write_files:** <!-- true = agent mode, false = stateless mode -->
- **can_read_files:**
- **can_call_tools:**
- **can_run_background_tasks:**
- **can_send_external_messages:**
- **can_browse_web:**
- **has_code_execution:**
- **has_persistent_storage:** <!-- true if the runtime supports indexed/searchable knowledge bases -->

## Tool Policy

<!-- Rules for tool usage. -->

- <!-- e.g., "Internal tools (file read/write, search) — use freely." -->
- <!-- e.g., "External tools (API calls, web requests) — confirm before first use in a session." -->
- <!-- e.g., "Irreversible actions (delete, send, publish) — always confirm." -->

## Session Model

- **session_type:** <!-- private | shared | public -->
- **audience:** <!-- e.g., "User only" or "User + team" -->
- **memory_read_policy:** <!-- e.g., "Full access" or "Non-sensitive only" -->
- **memory_write_policy:** <!-- e.g., "Full access" or "Operational facts only" or "None" -->

## Response Format

- <!-- e.g., "Default to concise. Use markdown formatting." -->
- <!-- e.g., "Code blocks with language tags." -->

## Reasoning Approach

- <!-- e.g., "Think step by step for complex problems." -->
- <!-- e.g., "Show reasoning when the user would benefit from understanding the process." -->

## Behavioral Rules

- <!-- e.g., "Check for existing patterns before writing new code." -->
- <!-- e.g., "Run validation after making changes." -->
-

## Safety and Privacy

- <!-- e.g., "Never include secrets or API keys in code unless explicitly requested." -->
- <!-- e.g., "Substitute PII with placeholders in examples." -->
-

## Domain-Specific Rules

<!-- Organized by domain. Move to separate referenced files if this section exceeds ~50 rules. -->
