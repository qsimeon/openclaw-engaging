#!/usr/bin/env bash
# start-gateway.sh — Submit the gateway job and display connection info
#
# This is the "1-click" gateway launcher. It submits the SLURM job,
# waits for it to start running, then prints the SSH tunnel command
# and dashboard URL — ready to copy-paste.
#
# Usage:
#   ./apptainer/start-gateway.sh
#
# See docs/engaging-apptainer-guide.md for the full guide.

set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
REPO_DIR="$(cd "$SCRIPT_DIR/.." && pwd)"
SLURM_SCRIPT="$SCRIPT_DIR/slurm-gateway.sh"

if [ ! -f "$SLURM_SCRIPT" ]; then
  echo "Error: $SLURM_SCRIPT not found."
  exit 1
fi

# --- Check for existing gateway job ---
EXISTING=$(squeue -u "$USER" -n openclaw-gw -h -o "%i %N %T" 2>/dev/null | head -1)
if [ -n "$EXISTING" ]; then
  JOB_ID=$(echo "$EXISTING" | awk '{print $1}')
  NODE=$(echo "$EXISTING" | awk '{print $2}')
  STATE=$(echo "$EXISTING" | awk '{print $3}')
  echo "Gateway already running: job $JOB_ID on $NODE ($STATE)"
  echo ""
  OUT_FILE="$REPO_DIR/openclaw-gw-$JOB_ID.out"
  if [ -f "$OUT_FILE" ]; then
    cat "$OUT_FILE"
  else
    echo "Output file not found yet. Try: cat openclaw-gw-$JOB_ID.out"
  fi
  exit 0
fi

# --- Submit the job ---
echo "Submitting gateway job..."
OUTPUT=$(cd "$REPO_DIR" && sbatch "$SLURM_SCRIPT" 2>&1)
JOB_ID=$(echo "$OUTPUT" | grep -oP '\d+$')

if [ -z "$JOB_ID" ]; then
  echo "Error: sbatch failed:"
  echo "$OUTPUT"
  exit 1
fi

echo "Submitted job $JOB_ID"

# --- Wait for the job to start and produce output ---
OUT_FILE="$REPO_DIR/openclaw-gw-$JOB_ID.out"
echo -n "Waiting for job to start"

WAITED=0
MAX_WAIT=120  # seconds
while [ $WAITED -lt $MAX_WAIT ]; do
  STATE=$(squeue -j "$JOB_ID" -h -o "%T" 2>/dev/null)

  if [ -z "$STATE" ]; then
    echo ""
    echo "Job $JOB_ID is no longer in the queue. Check:"
    echo "  cat openclaw-gw-$JOB_ID.out"
    echo "  cat openclaw-gw-$JOB_ID.err"
    exit 1
  fi

  # Once running, wait for the output file to have the connection info
  if [ "$STATE" = "RUNNING" ] && [ -f "$OUT_FILE" ]; then
    # Wait until the banner is fully written (look for the separator line)
    if grep -q "──────────────────────────────" "$OUT_FILE" 2>/dev/null; then
      echo " running!"
      echo ""
      cat "$OUT_FILE"
      exit 0
    fi
  fi

  echo -n "."
  sleep 2
  WAITED=$((WAITED + 2))
done

echo ""
echo "Job $JOB_ID is still starting (waited ${MAX_WAIT}s)."
echo "Check manually:"
echo "  squeue -j $JOB_ID"
echo "  cat openclaw-gw-$JOB_ID.out"
