# CLAUDE.md

This file provides guidance to Claude Code (claude.ai/code) when working with code in this repository.

Also read `AGENTS.md` for the full upstream contributor guidelines (commit conventions, multi-agent safety, plugin release workflow, etc.).

## Project Overview

OpenClaw is a personal AI assistant platform — a Node.js application that connects to cloud LLM providers (Anthropic, OpenAI, OpenRouter, Google, etc.) and exposes the assistant across multiple messaging channels (WhatsApp, Telegram, Slack, Discord, Signal, iMessage, etc.). It can run as a CLI agent, a persistent gateway server, or inside an Apptainer container on HPC clusters.

Repository: https://github.com/openclaw/openclaw

## Build & Development Commands

Runtime: **Node 22+**. Package manager: **pnpm** (Bun also supported for TypeScript execution).

```bash
pnpm install                  # Install dependencies
pnpm build                    # Full build (TypeScript via tsdown → dist/)
pnpm dev                      # Run CLI in dev mode
pnpm check                    # Format check + typecheck (tsgo) + lint (oxlint)
pnpm lint                     # oxlint with type-aware checks
pnpm format                   # oxfmt --write
pnpm lint:fix                 # Auto-fix lint + format

# Gateway
pnpm gateway:dev              # Run gateway in dev mode (skip channels)
pnpm openclaw <subcommand>    # Run any CLI command in dev mode
```

### Testing

Framework: **Vitest** with v8 coverage (thresholds: 70% lines/functions/statements, 55% branches).

```bash
pnpm test                     # Run all unit tests (parallel)
pnpm test:fast                # Quick unit tests only (vitest.unit.config.ts)
pnpm test:e2e                 # E2E tests (vitest.e2e.config.ts)
pnpm test:coverage            # Coverage report

# Single test file
vitest run --config vitest.unit.config.ts src/path/to/file.test.ts

# Live tests (require real API keys)
OPENCLAW_LIVE_TEST=1 pnpm test:live
```

Tests are colocated: `src/foo.ts` → `src/foo.test.ts`. E2E tests use `*.e2e.test.ts`.

### Commits

Use the repo's commit script instead of manual `git add`/`git commit`:
```bash
scripts/committer "CLI: add verbose flag" src/commands/agent.ts
```

## Architecture

### Entry Points

1. **CLI**: `openclaw.mjs` → `src/entry.ts` → `src/cli/run-main.ts` → `buildProgram()` (command registration)
2. **Library**: `src/index.ts` (programmatic API)
3. **Gateway**: `openclaw gateway` — Express + WebSocket server (`src/gateway/server.impl.ts`)

### Source Layout

```
src/
├── cli/           # CLI wiring, command registration (program/build-program.ts)
├── commands/      # Command implementations (agent, agents, gateway, configure, etc.)
├── agents/        # Multi-agent system (model resolution, session, skills, auth profiles)
├── config/        # Config load pipeline: dotenv → env → JSON5 file → schema validation → defaults
├── gateway/       # Express + WebSocket gateway server, server methods
├── channels/      # Channel registry + dock (lifecycle, allowlists, mention gating)
├── providers/     # LLM provider integrations (Anthropic, OpenAI, Google, etc.)
├── hooks/         # Hook system (bundled + custom event handlers)
├── routing/       # Message routing logic
├── media/         # Media pipeline
├── infra/         # Infrastructure utilities
├── terminal/      # Terminal UI (palette, tables, progress)
└── *.test.ts      # Colocated tests
```

### Key Directories Outside `src/`

- `extensions/` — Channel plugins (Matrix, Teams, Zalo, etc.) with independent `package.json`
- `skills/` — ~50 built-in skill directories
- `ui/` — React control UI (dashboard)
- `apps/` — Native apps (macOS, iOS, Android)
- `docs/` — Mintlify documentation (docs.openclaw.ai)
- `apptainer/` — Apptainer/Singularity container recipes for HPC (MIT Engaging)

### Key Patterns

**Config system** (`src/config/`): Loads via dotenv → shell env fallback → config file (`~/.openclaw/openclaw.json`, JSON5) → env substitution → includes → Zod schema validation → defaults. Includes can reference local/remote YAML/JSON5.

**Command registration**: Lazy-loaded via `registerProgramCommands()` in `src/cli/program/command-registry.ts`. Core commands, then subclis, then plugins. Reduces startup time.

**Dependency injection**: `createDefaultDeps()` in `src/cli/deps.ts`. Command action functions receive deps as closures for testability.

**Session persistence**: File-based at `~/.openclaw/agents/<agentId>/sessions/`. Sessions store metadata (model, auth overrides, token counts) in `sessions.json` and conversation transcripts in `<sessionId>.jsonl`. Sessions survive process restarts. Reset modes: `idle` (default 30 min), `daily`, `never`, `always`.

**Plugin system**: Extensions live in `extensions/*/` with own `package.json`. Runtime deps in `dependencies` (not `devDependencies`). Avoid `workspace:*` in `dependencies`. `openclaw` itself goes in `devDependencies` or `peerDependencies`.

**Channel system**: Central registry (`src/channels/registry.ts`) manages built-in + extension channels. The dock (`src/channels/dock.ts`) handles lifecycle, allowlists, and message gating. When refactoring shared logic, consider all channels (both core and extensions).

## HPC / Apptainer (MIT Engaging)

The `apptainer/` directory contains recipes for running OpenClaw on the MIT Engaging HPC cluster:

- `openclaw.def` — Apptainer definition file (pulls official Docker image)
- `setup.sh` — Automated build + config helper
- `slurm-openclaw.sh` — SLURM batch job template

Build: `module load apptainer/1.4.2 && srun --mem=4G --time=00:30:00 --cpus-per-task=2 apptainer build apptainer/openclaw.sif apptainer/openclaw.def`

Full guide: `docs/engaging-apptainer-guide.md`

Key design: all state lives on `~/.openclaw/` (NFS home directory), so sessions survive SLURM job preemption. Config sets `session.reset.mode: "never"` for HPC use.

## Style Notes

- Naming: **OpenClaw** for product/docs headings; `openclaw` for CLI/package/paths/config keys.
- Files: aim for under ~500 LOC; split when it improves clarity.
- CLI progress: use `src/cli/progress.ts` (not hand-rolled spinners).
- Terminal colors: use `src/terminal/palette.ts` (no hardcoded colors).
- Tool schemas: no `Type.Union` in tool input schemas; use `stringEnum`/`optionalStringEnum` for string lists.
- Docs links: root-relative, no `.md` suffix (e.g., `[Config](/configuration)`). Avoid em dashes in headings (breaks Mintlify anchors).
