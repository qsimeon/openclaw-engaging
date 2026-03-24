# OpenClaw on MIT Engaging (Fork-Specific)

This file extends the upstream `CLAUDE.md` (→ `AGENTS.md`) with HPC/Apptainer context specific to this fork.

## HPC / Apptainer (MIT Engaging)

The `apptainer/` directory contains recipes for running OpenClaw on the MIT Engaging HPC cluster:

- `openclaw.def` — Apptainer definition file (pulls official Docker image; removes LINE extension)
- `setup.sh` — Automated build + config helper (1-click deploy)
- `slurm-openclaw.sh` — SLURM batch job template for agent
- `slurm-gateway.sh` — SLURM job for the gateway server (dashboard + channels)
- `start-gateway.sh` — 1-click gateway launcher (submits job, waits, prints connection info)
- `update.sh` — Automated upstream sync: fetch + merge + rebuild (`--check` for check-only)
- `openclaw-engaging.sh` — Convenience wrapper (API key passthrough, module loading, containall)
- `orcd-workspace-init.sh` — Populates `$INSTALL_DIR/.openclaw/workspace/` with ORCD/Engaging cluster context (TOOLS.md, SOUL.md). Idempotent; called by `setup.sh` after onboarding.
- `openclaw-env.sh` — Source file for `~/.bashrc` (provides `openclaw` alias + containall default)
- `openclaw.lua` — Lmod modulefile (alternative to source file)

Install: `curl -fsSL https://raw.githubusercontent.com/qsimeon/openclaw-engaging/main/install_stage0.sh | bash`

Build: `cd ~/orcd/scratch/oclaw/openclaw-engaging && srun --pty --mem=8G --time=01:00:00 --cpus-per-task=2 ./apptainer/setup.sh`

Full guide: `docs/engaging-apptainer-guide.md`

### Security model

- **`--containall` is ON by default.** The agent only sees the repo dir, `.openclaw/`, and `/tmp`. Host `~/.ssh/`, `~/.gnupg/`, etc. are NOT visible. Set `OPENCLAW_CONTAINALL=0` to disable.
- **Gateway binds to loopback** (localhost only). Access via `ssh -J user@login -L PORT:localhost:PORT user@node`.
- **No `.bashrc` modification.** Users `source openclaw-env.sh` or `module load openclaw`.
- Extra data directories: `APPTAINER_BIND="~/data" openclaw agent ...`

### Container home directory

All exec scripts pass `--home $(dirname $REPO_DIR)` to Apptainer, so the container's `$HOME` is the parent of the repo. `.openclaw/` lives next to the repo (e.g., clone to `~/orcd/scratch/oclaw/openclaw-engaging` → `~/orcd/scratch/oclaw/.openclaw/`). The clone location implicitly determines where state lives — no extra flags needed.

### Environment variables (all exec scripts)

- `OPENCLAW_CONTAINALL` — filesystem isolation via `--containall`. Default: `1` (on). Set to `0` to disable.
- `OPENCLAW_SLURM_BINDS=1` — bind-mount host SLURM binaries, libraries, config, and munge socket into the container so the agent can run `sbatch`, `squeue`, etc. (intentional sandbox escape — see docs).
- `OPENCLAW_GATEWAY_PORT` — override gateway port (default: auto-detect 18790-18799).
- `APPTAINER_BIND` — additional directories to bind-mount into the container.

## Fork Maintenance

This fork (`qsimeon/openclaw-engaging`) tracks upstream (`openclaw/openclaw`). To merge cleanly:

- **CLAUDE.md** must remain the upstream symlink (→ `AGENTS.md`). Fork-specific guidance goes here in `CLAUDE.local.md`.
- **`.gitignore`** — do NOT modify. Fork-specific excludes live in `.git/info/exclude` (untracked, never causes merge conflicts). Never add fork lines to `.gitignore`.
- Run `./apptainer/update.sh` to fetch, merge, and rebuild in one step.
