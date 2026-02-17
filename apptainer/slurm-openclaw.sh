#!/bin/bash
#SBATCH --job-name=openclaw
#SBATCH --time=01:00:00
#SBATCH --mem=1G
#SBATCH --cpus-per-task=1
#SBATCH --output=openclaw-%j.out
#SBATCH --error=openclaw-%j.err

# OpenClaw batch job for MIT Engaging HPC
#
# Sessions persist across jobs — if this job is preempted or times out,
# just resubmit and the agent resumes where it left off (provided
# session.reset.mode is set to "never" in ~/.openclaw/openclaw.json).
#
# Usage:
#   sbatch slurm-openclaw.sh                              # uses key from ~/.openclaw/.env
#   ANTHROPIC_API_KEY=sk-ant-... sbatch slurm-openclaw.sh  # explicit key
#   OPENCLAW_PROMPT="Analyze my data" sbatch slurm-openclaw.sh  # custom prompt
#   OPENCLAW_AGENT=my-project sbatch slurm-openclaw.sh     # target a named agent
#
# See docs/engaging-apptainer-guide.md for the full setup guide.

set -euo pipefail

# --- Load Apptainer ---
module load apptainer/1.4.2

# --- Paths ---
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
SIF_FILE="${OPENCLAW_SIF:-$SCRIPT_DIR/openclaw.sif}"

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

# --- Config ---
AGENT="${OPENCLAW_AGENT:-main}"
PROMPT="${OPENCLAW_PROMPT:-Hello from Engaging! What can you help me with?}"

# --- Run OpenClaw ---
echo "Starting OpenClaw on $(hostname) at $(date)"
echo "Job ID: $SLURM_JOB_ID"
echo "Agent:  $AGENT"
echo "State:  ~/.openclaw/agents/$AGENT/sessions/"
echo ""

# shellcheck disable=SC2086
apptainer exec \
  $ENV_FLAGS \
  "$SIF_FILE" \
  openclaw agent --local --agent "$AGENT" -m "$PROMPT"

echo ""
echo "OpenClaw finished at $(date)"
echo "Session state saved to ~/.openclaw/agents/$AGENT/sessions/"
echo "To resume, resubmit: sbatch $0"
