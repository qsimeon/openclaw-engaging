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
# Check by job name. When OPENCLAW_GATEWAY_PORT is set, also verify the port
# matches to avoid false positives from multi-instance setups.
TARGET_PORT="${OPENCLAW_GATEWAY_PORT:-18790}"
EXISTING=$(squeue -u "$USER" -n openclaw-gw -h -o "%i %N %T" 2>/dev/null | head -1)
if [ -n "$EXISTING" ]; then
  JOB_ID=$(echo "$EXISTING" | awk '{print $1}')
  NODE=$(echo "$EXISTING" | awk '{print $2}')
  STATE=$(echo "$EXISTING" | awk '{print $3}')

  # If a specific port was requested, check that the existing job uses it
  SHOW_EXISTING=true
  OUT_FILE="$REPO_DIR/openclaw-gw-$JOB_ID.out"
  if [ "$TARGET_PORT" != "18790" ] && [ -f "$OUT_FILE" ]; then
    if ! grep -q "Port:.*$TARGET_PORT" "$OUT_FILE" 2>/dev/null; then
      SHOW_EXISTING=false  # different port — not our job
    fi
  fi

  if [ "$SHOW_EXISTING" = true ]; then
    echo "Gateway already running: job $JOB_ID on $NODE ($STATE)"
    echo ""
    if [ -f "$OUT_FILE" ]; then
      cat "$OUT_FILE"
    else
      echo "Output file not found yet. Try: cat $REPO_DIR/openclaw-gw-$JOB_ID.out"
    fi
    exit 0
  fi
fi

# --- Check for upstream updates ---
"$SCRIPT_DIR/update.sh" --check 2>/dev/null || true

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
    echo "Job $JOB_ID exited unexpectedly."
    ERR_FILE="$REPO_DIR/openclaw-gw-$JOB_ID.err"
    if [ -f "$ERR_FILE" ] && [ -s "$ERR_FILE" ]; then
      echo ""
      echo "Error log:"
      tail -5 "$ERR_FILE"
      echo ""
      # Check for common errors and suggest fixes
      if grep -q "allowedOrigins" "$ERR_FILE" 2>/dev/null; then
        echo "Fix: The gateway now requires allowedOrigins for non-loopback binding."
        echo "  Run: openclaw config set gateway.controlUi.allowedOrigins '[\"http://localhost:$TARGET_PORT\"]'"
        echo "  Then relaunch: ./apptainer/start-gateway.sh"
      fi
    else
      echo "  Check: cat $REPO_DIR/openclaw-gw-$JOB_ID.out"
      echo "  Check: cat $REPO_DIR/openclaw-gw-$JOB_ID.err"
    fi
    exit 1
  fi

  # Once running, wait for the output file to have the connection info
  if [ "$STATE" = "RUNNING" ] && [ -f "$OUT_FILE" ]; then
    # Check if the gateway already crashed (job running but process exited)
    if grep -q "Gateway stopped at" "$OUT_FILE" 2>/dev/null; then
      echo " failed!"
      echo ""
      ERR_FILE="$REPO_DIR/openclaw-gw-$JOB_ID.err"
      echo "The gateway process exited. Check the error log:"
      if [ -f "$ERR_FILE" ] && [ -s "$ERR_FILE" ]; then
        echo ""
        tail -5 "$ERR_FILE"
      else
        echo "  cat $REPO_DIR/openclaw-gw-$JOB_ID.err"
      fi
      exit 1
    fi

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
echo "  cat $REPO_DIR/openclaw-gw-$JOB_ID.out"
