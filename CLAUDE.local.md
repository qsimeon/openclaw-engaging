# OpenClaw on MIT Engaging (Fork-Specific)

This file extends the upstream `CLAUDE.md` (→ `AGENTS.md`) with HPC/Apptainer context specific to this fork.

## HPC / Apptainer (MIT Engaging)

The `apptainer/` directory contains recipes for running OpenClaw on the MIT Engaging HPC cluster:

- `openclaw.def` — Apptainer definition file (pulls official Docker image)
- `setup.sh` — Automated build + config helper (1-click deploy)
- `slurm-openclaw.sh` — SLURM batch job template for agent
- `slurm-gateway.sh` — SLURM job for the gateway server (dashboard + channels)
- `start-gateway.sh` — 1-click gateway launcher (submits job, waits, prints connection info)
- `start-multi.sh` — Multi-agent launcher (N independent gateway instances on consecutive ports)
- `update.sh` — Automated upstream sync: fetch + merge + rebuild (`--check` for check-only)
- `openclaw-engaging.sh` — Convenience wrapper (API key passthrough, module loading)
- `orcd-workspace-init.sh` — Populates `$INSTALL_DIR/.openclaw/workspace/` with ORCD/Engaging cluster context (TOOLS.md, SOUL.md). Idempotent; called by `setup.sh` after onboarding.

Build: `module load apptainer/1.4.2 && srun --mem=8G --time=01:00:00 --cpus-per-task=2 apptainer build apptainer/openclaw.sif apptainer/openclaw.def`

Full guide: `docs/engaging-apptainer-guide.md`

Key design: all state lives on `~/.openclaw/` (NFS home directory), so sessions survive SLURM job preemption. Config sets `session.reset.mode: "idle"` with a 1-year timeout for HPC use. The gateway launcher auto-checks for upstream updates on every launch.

### Container home directory

All exec scripts pass `--home $(dirname $REPO_DIR)` to Apptainer, so the container's `$HOME` is the parent of the repo. `.openclaw/` lives next to the repo (e.g., clone to `~/openclaw-engaging` → `~/.openclaw/`; clone to `~/orcd/scratch/openclaw-engaging` → `~/orcd/scratch/.openclaw/`). The clone location implicitly determines where state lives — no extra flags needed.

### Environment variables (all exec scripts)

- `OPENCLAW_SLURM_BINDS=1` — bind-mount host SLURM binaries, libraries, config, and munge socket into the container so the agent can run `sbatch`, `squeue`, etc.
- `OPENCLAW_CONTAINALL=1` — enable `--containall` for strict filesystem isolation. Scripts auto-add `--home` and `-B /tmp`; extra directories via `APPTAINER_BIND`.

## Fork Maintenance

This fork (`qsimeon/openclaw-engaging`) tracks upstream (`openclaw/openclaw`). To merge cleanly:

- **CLAUDE.md** must remain the upstream symlink (→ `AGENTS.md`). Fork-specific guidance goes here in `CLAUDE.local.md`.
- **`.gitignore`** — do NOT modify. Fork-specific excludes live in `.git/info/exclude` (untracked, never causes merge conflicts). Never add fork lines to `.gitignore`.
- Run `./apptainer/update.sh` to fetch, merge, and rebuild in one step.
