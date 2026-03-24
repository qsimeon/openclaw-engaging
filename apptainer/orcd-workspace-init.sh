#!/usr/bin/env bash
# orcd-workspace-init.sh — Populate OpenClaw workspace with ORCD/Engaging context
#
# Makes agents automatically aware of MIT Engaging HPC: storage paths,
# SLURM partitions, module system, and cluster-specific commands.
#
# Idempotent: safe to run multiple times. Skips files that already
# contain ORCD content; overwrites default templates; leaves custom
# content untouched (prints a notice).
#
# Usage:
#   ./apptainer/orcd-workspace-init.sh          # standalone
#   Called automatically by setup.sh after onboarding
#
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
REPO_DIR="$(cd "$SCRIPT_DIR/.." && pwd)"
# Use $HOME (logical path) when repo is under home dir to preserve symlink
# paths (on NFS clusters, /home/user may be a symlink to /orcd/home/002/user).
INSTALL_DIR="$(dirname "$REPO_DIR")"
REAL_HOME="$(readlink -f "$HOME")"
if [ "$(readlink -f "$INSTALL_DIR")" = "$REAL_HOME" ]; then
  INSTALL_DIR="$HOME"
fi
WORKSPACE="${OPENCLAW_WORKSPACE:-$INSTALL_DIR/.openclaw/workspace}"
mkdir -p "$WORKSPACE"

# ── Helpers ───────────────────────────────────────────────────────────

has_orcd_content() {
  grep -q "MIT.*Engaging" "$1" 2>/dev/null
}

is_default_template() {
  # Check if the file is still the stock OpenClaw template
  grep -q "Camera names and locations" "$1" 2>/dev/null ||
  grep -q "Fill this in during your first conversation" "$1" 2>/dev/null
}

# ── TOOLS.md ──────────────────────────────────────────────────────────

write_tools() {
  # Auto-detect PI/group storage by checking for symlinks in ~/data or /orcd/data
  PI_STORAGE_LINE=""
  if [ -L "$HOME/data" ]; then
    PI_PATH="$(readlink -f "$HOME/data")"
    PI_STORAGE_LINE="| \`$PI_PATH/\` | PI storage | Group-allocated persistent storage |"
  fi

  cat > "$WORKSPACE/TOOLS.md" << TOOLS_EOF
# TOOLS.md - MIT Engaging HPC Environment

## Cluster Access

- **Login node:** \`orcd-login.mit.edu\` (SSH)
- **Docs:** https://orcd-docs.mit.edu/
- **Support:** orcd-help@mit.edu

## Storage

| Path | Type | Notes |
|------|------|-------|
| \`~/\` | Home | ~195 GB quota, NFS-shared across nodes |
| \`~/orcd/scratch\` | Scratch | Large, NOT backed up, auto-purged after ~90 days |
| \`~/orcd/pool\` | Pool | PI-allocated persistent storage (if available) |
| \`~/orcd/datasets\` | Datasets | Shared read-only datasets |
${PI_STORAGE_LINE:+$PI_STORAGE_LINE
}
- **Default scratch:** \`~/orcd/scratch\` (symlink to \`/orcd/scratch/orcd/002/\$USER\`)
- Check with your PI or run \`df -h\` to find group storage paths
- \`~/.openclaw/\` lives next to the repo (in the directory where you cloned \`openclaw-engaging\`)

## SLURM

### Partitions

| Partition | Use case | GPU |
|-----------|----------|-----|
| \`sched_mit_hill\` | Default CPU jobs | No |
| \`mit_normal\` | General CPU | No |
| \`mit_normal_gpu\` | GPU workloads | L40S, H100 |

### Common commands

\`\`\`bash
srun --pty --mem=4G --time=02:00:00 bash          # Interactive session
sbatch script.sh                                    # Submit batch job
squeue -u \$USER                                     # Check your jobs
scancel <jobid>                                     # Cancel a job
sinfo -p <partition> -o "%l"                        # Max wall time
\`\`\`

### GPU jobs

\`\`\`bash
srun --pty --mem=16G --time=02:00:00 --gres=gpu:1 -p mit_normal_gpu bash
\`\`\`

## Module System

\`\`\`bash
module avail                    # List all modules
module load apptainer/1.4.2    # Apptainer (container runtime)
module load python/3.11         # Python
module load cuda/12             # CUDA toolkit
\`\`\`

## OpenClaw Commands

All commands go through the \`openclaw\` alias (set up by \`setup.sh\`):

\`\`\`bash
openclaw agent --local --agent main -m "Hello!"     # One-shot query
openclaw agent --local --agent main                  # Interactive session
openclaw configure                                   # Reconfigure
openclaw doctor                                      # Health check
openclaw sessions                                    # List sessions
\`\`\`

### Gateway (browser dashboard)

\`\`\`bash
cd ~/orcd/scratch/oclaw/openclaw-engaging
./apptainer/start-gateway.sh                         # Launch gateway job
\`\`\`

### Batch jobs

\`\`\`bash
cd ~/openclaw-engaging
OPENCLAW_PROMPT="Your task here" sbatch apptainer/slurm-openclaw.sh
\`\`\`

## Data Privacy

Prompts and file excerpts are sent to cloud LLM APIs (Anthropic, OpenAI, etc.)
over HTTPS. Raw data files stay on the cluster. Do not point the agent at
restricted or sensitive datasets without understanding your provider's data
handling policies.

## Quick Reference Links

- ORCD docs: https://orcd-docs.mit.edu/
- ORCD storage guide: https://orcd-docs.mit.edu/recipes/filesystems/
- SLURM guide: https://orcd-docs.mit.edu/recipes/slurm/
- OpenClaw docs: https://docs.openclaw.ai/
- This fork: https://github.com/qsimeon/openclaw-engaging
TOOLS_EOF
}

# ── SOUL.md ───────────────────────────────────────────────────────────

append_soul() {
  cat >> "$WORKSPACE/SOUL.md" << 'SOUL_EOF'

---

## HPC Co-Scientist Context

You're running on **MIT's Engaging HPC cluster** (ORCD — Office of Research
Computing and Data), inside an Apptainer container. You are not on a personal
laptop or a cloud VM.

**What this means for you:**

- You have access to **SLURM** for job scheduling — use it for heavy compute
- The **module system** provides software (Python, CUDA, Apptainer, etc.)
- The user's research data is already on the cluster filesystem — no uploads needed
- Your state lives in `~/.openclaw/` on NFS, surviving job preemption
- You're in a **read-only container** — install user packages with `--user` flags

**Check `TOOLS.md` for cluster-specific commands, storage paths, and partitions.**

When the user asks about the cluster, storage, SLURM, or HPC workflows, you
have direct knowledge. For the latest ORCD docs, search https://orcd-docs.mit.edu/.
SOUL_EOF
}

# ── Apply TOOLS.md ────────────────────────────────────────────────────

if [ "${FORCE:-}" = "1" ]; then
  write_tools
  echo "TOOLS.md: force-overwritten with ORCD cluster info"
elif [ -f "$WORKSPACE/TOOLS.md" ]; then
  if has_orcd_content "$WORKSPACE/TOOLS.md"; then
    echo "TOOLS.md: already has ORCD content, skipping"
  elif is_default_template "$WORKSPACE/TOOLS.md"; then
    write_tools
    echo "TOOLS.md: replaced default template with ORCD cluster info"
  else
    echo "TOOLS.md: contains custom content — not overwriting"
    echo "  Run with FORCE=1 to overwrite, or edit manually"
  fi
else
  write_tools
  echo "TOOLS.md: created with ORCD cluster info"
fi

# ── Apply SOUL.md ─────────────────────────────────────────────────────

if [ -f "$WORKSPACE/SOUL.md" ]; then
  if has_orcd_content "$WORKSPACE/SOUL.md"; then
    echo "SOUL.md: already has ORCD content, skipping"
  else
    append_soul
    echo "SOUL.md: appended HPC co-scientist context"
  fi
else
  echo "SOUL.md: not found (will be created after first agent session)"
fi

# ── IDENTITY.md — leave as-is ────────────────────────────────────────

if [ -f "$WORKSPACE/IDENTITY.md" ]; then
  echo "IDENTITY.md: exists (keeping current content)"
else
  echo "IDENTITY.md: not found (will be created after first agent session)"
fi

echo ""
echo "Workspace initialized at $WORKSPACE"
echo "Agents will auto-load TOOLS.md, SOUL.md, and IDENTITY.md each session."
