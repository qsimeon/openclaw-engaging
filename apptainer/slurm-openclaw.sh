#!/bin/bash
#SBATCH --job-name=openclaw
#SBATCH --time=06:00:00
#SBATCH --mem=4G
#SBATCH --cpus-per-task=2
#SBATCH --output=openclaw-%j.out
#SBATCH --error=openclaw-%j.err

## ── Uncomment ONE of the following lines to request a GPU ──
## Default GPU (L40S, 44GB):
# #SBATCH -p mit_normal_gpu
# #SBATCH --gres=gpu:1
## Or request a specific GPU type:
# #SBATCH -p mit_normal_gpu
# #SBATCH --gres=gpu:h100:1
## For longer jobs (up to 48h, preemptable):
# #SBATCH -p mit_preemptable
# #SBATCH --gres=gpu:1

# OpenClaw batch job for MIT Engaging HPC
#
# Sessions persist across jobs — if this job is preempted or times out,
# just resubmit and the agent resumes where it left off.
#
# Usage:
#   sbatch apptainer/slurm-openclaw.sh                                    # default
#   OPENCLAW_PROMPT="Analyze my data" sbatch apptainer/slurm-openclaw.sh  # custom prompt
#   OPENCLAW_AGENT=my-project sbatch apptainer/slurm-openclaw.sh          # named agent
#
# GPU usage:
#   Edit the #SBATCH lines above to uncomment a GPU partition + --gres line.
#   The agent will then have access to the GPU inside the container.
#
# Bind extra data directories:
#   APPTAINER_BIND="/pool/lab-data,/scratch/$USER" sbatch apptainer/slurm-openclaw.sh
#
# See docs/engaging-apptainer-guide.md for the full setup guide.

set -euo pipefail

# --- Load Apptainer ---
module load apptainer/1.4.2

# --- Paths ---
# SBATCH copies the script to a spool dir, so BASH_SOURCE won't point
# back to the repo.  Use SLURM_SUBMIT_DIR (the CWD at sbatch time) instead.
REPO_DIR="${SLURM_SUBMIT_DIR:-$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)}"
SIF_FILE="${OPENCLAW_SIF:-$REPO_DIR/apptainer/openclaw.sif}"

if [ ! -f "$SIF_FILE" ]; then
  echo "Error: Container not found at $SIF_FILE"
  echo "Run setup.sh first, or set OPENCLAW_SIF to the .sif path."
  exit 1
fi

# --- Build env flags ---
ENV_FLAGS=""
[ -n "${ANTHROPIC_API_KEY:-}" ] && ENV_FLAGS="$ENV_FLAGS --env ANTHROPIC_API_KEY=$ANTHROPIC_API_KEY"
[ -n "${OPENAI_API_KEY:-}" ] && ENV_FLAGS="$ENV_FLAGS --env OPENAI_API_KEY=$OPENAI_API_KEY"
[ -n "${OPENROUTER_API_KEY:-}" ] && ENV_FLAGS="$ENV_FLAGS --env OPENROUTER_API_KEY=$OPENROUTER_API_KEY"
[ -n "${GEMINI_API_KEY:-}" ] && ENV_FLAGS="$ENV_FLAGS --env GEMINI_API_KEY=$GEMINI_API_KEY"

# Set container home to the parent of the repo — .openclaw/ lives next to
# the repo (e.g., clone to ~/openclaw-engaging → ~/.openclaw/).
INSTALL_DIR="$(dirname "$REPO_DIR")"
REAL_HOME="$(readlink -f "$HOME")"
if [ "$(readlink -f "$INSTALL_DIR")" = "$REAL_HOME" ]; then
  INSTALL_DIR="$HOME"
fi
REAL_INSTALL_DIR="$(readlink -f "$INSTALL_DIR")"
HOME_FLAGS="--home $REAL_INSTALL_DIR:/home/$(id -un)"

# If .openclaw is a symlink, bind-mount the target so it's reachable
BIND_FLAGS=""
if [ -L "$INSTALL_DIR/.openclaw" ]; then
  SYMLINK_TARGET="$(readlink -f "$INSTALL_DIR/.openclaw")"
  BIND_FLAGS="-B $(dirname "$SYMLINK_TARGET")"
fi

# SLURM binds: let the agent submit jobs from inside the container
if [ "${OPENCLAW_SLURM_BINDS:-}" = "1" ]; then
  for cmd in sbatch squeue scancel sinfo srun sacct; do
    [ -f "/usr/bin/$cmd" ] && BIND_FLAGS="$BIND_FLAGS -B /usr/bin/$cmd"
  done
  [ -d /etc/slurm ] && BIND_FLAGS="$BIND_FLAGS -B /etc/slurm"
  [ -d /usr/lib64/slurm ] && BIND_FLAGS="$BIND_FLAGS -B /usr/lib64/slurm"
  [ -d /run/munge ] && BIND_FLAGS="$BIND_FLAGS -B /run/munge"
fi

# Strict filesystem isolation (--containall disables auto-mounts)
CONTAINALL_FLAGS=""
if [ "${OPENCLAW_CONTAINALL:-1}" != "0" ]; then
  CONTAINALL_FLAGS="--containall"
  BIND_FLAGS="$BIND_FLAGS -B /tmp"
fi

# --- Nvidia GPU support (if allocated) ---
NV_FLAG=""
if command -v nvidia-smi &>/dev/null || [ -n "${SLURM_JOB_GPUS:-}" ] || [ -n "${CUDA_VISIBLE_DEVICES:-}" ]; then
  NV_FLAG="--nv"
fi

# --- Config ---
AGENT="${OPENCLAW_AGENT:-main}"
PROMPT="${OPENCLAW_PROMPT:-Hello from Engaging! What can you help me with?}"

# --- Print job info ---
echo "╔══════════════════════════════════════════════════════════════╗"
echo "║  OpenClaw Agent                                            ║"
echo "╚══════════════════════════════════════════════════════════════╝"
echo ""
echo "  Node:    $(hostname)"
echo "  Job ID:  $SLURM_JOB_ID"
echo "  Agent:   $AGENT"
echo "  CPUs:    ${SLURM_CPUS_PER_TASK:-1}"
echo "  Memory:  ${SLURM_MEM_PER_NODE:-unknown} MB"
if [ -n "$NV_FLAG" ]; then
  echo "  GPU:     yes (--nv flag enabled)"
  nvidia-smi --query-gpu=name,memory.total --format=csv,noheader 2>/dev/null || true
else
  echo "  GPU:     none (no GPU allocated)"
fi
echo "  State:   ~/.openclaw/agents/$AGENT/sessions/"
echo "  Started: $(date)"
echo ""

# --- Run OpenClaw ---
# shellcheck disable=SC2086
apptainer exec \
  $CONTAINALL_FLAGS \
  $HOME_FLAGS \
  $BIND_FLAGS \
  $NV_FLAG \
  $ENV_FLAGS \
  "$SIF_FILE" \
  openclaw agent --local --agent "$AGENT" -m "$PROMPT"

echo ""
echo "OpenClaw finished at $(date)"
echo "Session state saved to ~/.openclaw/agents/$AGENT/sessions/"
echo "To resume, resubmit: sbatch apptainer/slurm-openclaw.sh"
