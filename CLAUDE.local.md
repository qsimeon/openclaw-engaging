# OpenClaw on MIT Engaging (Fork-Specific)

This file extends the upstream `CLAUDE.md` (→ `AGENTS.md`) with HPC/Apptainer context specific to this fork.

## HPC / Apptainer (MIT Engaging)

The `apptainer/` directory contains recipes for running OpenClaw on the MIT Engaging HPC cluster:

- `openclaw.def` — Apptainer definition file (pulls official Docker image)
- `setup.sh` — Automated build + config helper (1-click deploy)
- `slurm-openclaw.sh` — SLURM batch job template for agent
- `slurm-gateway.sh` — SLURM job for the gateway server (dashboard + channels)
- `start-gateway.sh` — 1-click gateway launcher (submits job, waits, prints connection info)
- `update.sh` — Automated upstream sync: fetch + merge + rebuild (`--check` for check-only)
- `openclaw-engaging.sh` — Convenience wrapper (API key passthrough, module loading)

Build: `module load apptainer/1.4.2 && srun --mem=8G --time=01:00:00 --cpus-per-task=2 apptainer build apptainer/openclaw.sif apptainer/openclaw.def`

Full guide: `docs/engaging-apptainer-guide.md`

Key design: all state lives on `~/.openclaw/` (NFS home directory), so sessions survive SLURM job preemption. Config sets `session.reset.mode: "idle"` with a 1-year timeout for HPC use. The gateway launcher auto-checks for upstream updates on every launch.

## Fork Maintenance

This fork (`qsimeon/openclaw-engaging`) tracks upstream (`openclaw/openclaw`). To merge cleanly:

- **CLAUDE.md** must remain the upstream symlink (→ `AGENTS.md`). Fork-specific guidance goes here in `CLAUDE.local.md`.
- **`.gitignore`** — fork additions (apptainer/*.sif, SLURM logs, STATUS.md) go at the bottom, after the last upstream line. Do not modify upstream lines.
- Run `./apptainer/update.sh` to fetch, merge, and rebuild in one step.
