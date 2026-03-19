#!/usr/bin/env bash
# start-multi.sh — Launch multiple independent OpenClaw gateway instances
#
# Each instance gets its own port, SLURM job, and dashboard URL.
# Useful for class demos, parallel experiments, or team collaboration.
#
# Usage:
#   ./apptainer/start-multi.sh N              # launch N instances (ports 18790..18790+N-1)
#   ./apptainer/start-multi.sh N --prefix demo  # agents named demo-1, demo-2, ...
#
# Each instance is fully independent — its own gateway process, own port,
# own SSH tunnel. They share the same ~/.openclaw/ config but run as
# separate SLURM jobs.
#
# See docs/engaging-apptainer-guide.md for the full guide.

set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
REPO_DIR="$(cd "$SCRIPT_DIR/.." && pwd)"
SLURM_SCRIPT="$SCRIPT_DIR/slurm-gateway.sh"
BASE_PORT="${OPENCLAW_GATEWAY_PORT:-18790}"
LOGIN_NODE="${OPENCLAW_LOGIN_NODE:-orcd-login.mit.edu}"
PREFIX="agent"

# --- Parse arguments ---
NUM_INSTANCES=""
while [[ $# -gt 0 ]]; do
  case "$1" in
    --prefix)
      PREFIX="$2"
      shift 2
      ;;
    --help|-h)
      echo "Usage: $0 N [--prefix NAME]"
      echo ""
      echo "  N              Number of gateway instances to launch (1-10)"
      echo "  --prefix NAME  Agent name prefix (default: agent)"
      echo "                 Instances will be named NAME-1, NAME-2, ..."
      echo ""
      echo "Each instance gets port BASE_PORT + i - 1 (default base: 18790)."
      echo "Set OPENCLAW_GATEWAY_PORT to change the base port."
      echo "Set OPENCLAW_LOGIN_NODE to change the SSH tunnel target."
      exit 0
      ;;
    *)
      if [[ -z "$NUM_INSTANCES" ]] && [[ "$1" =~ ^[0-9]+$ ]]; then
        NUM_INSTANCES="$1"
      else
        echo "Error: unexpected argument '$1'"
        echo "Usage: $0 N [--prefix NAME]"
        exit 1
      fi
      shift
      ;;
  esac
done

if [[ -z "$NUM_INSTANCES" ]]; then
  echo "Error: number of instances required"
  echo "Usage: $0 N [--prefix NAME]"
  exit 1
fi

if [[ "$NUM_INSTANCES" -lt 1 || "$NUM_INSTANCES" -gt 10 ]]; then
  echo "Error: N must be between 1 and 10 (got $NUM_INSTANCES)"
  exit 1
fi

if [ ! -f "$SLURM_SCRIPT" ]; then
  echo "Error: $SLURM_SCRIPT not found."
  exit 1
fi

# --- Check for existing gateway jobs ---
EXISTING=$(squeue -u "$USER" -n openclaw-gw -h -o "%i" 2>/dev/null | wc -l)
if [[ "$EXISTING" -gt 0 ]]; then
  echo "Warning: $EXISTING existing openclaw-gw job(s) found."
  echo "Run 'squeue -u $USER -n openclaw-gw' to see them."
  read -rp "Continue anyway? [y/N] " cont
  if [[ ! "$cont" =~ ^[Yy]$ ]]; then
    echo "Aborted."
    exit 0
  fi
fi

echo "Launching $NUM_INSTANCES gateway instance(s)..."
echo ""

# --- Submit jobs ---
declare -a JOB_IDS
declare -a PORTS
declare -a NAMES

for i in $(seq 1 "$NUM_INSTANCES"); do
  PORT=$((BASE_PORT + i - 1))
  NAME="${PREFIX}-${i}"
  JOB_NAME="openclaw-gw-${i}"

  OUTPUT=$(cd "$REPO_DIR" && \
    OPENCLAW_GATEWAY_PORT="$PORT" \
    OPENCLAW_AGENT="$NAME" \
    sbatch --job-name="$JOB_NAME" \
           --output="$HOME/.openclaw/logs/openclaw-gw-${i}-%j.out" \
           --error="$HOME/.openclaw/logs/openclaw-gw-${i}-%j.err" \
           "$SLURM_SCRIPT" 2>&1)

  JOB_ID=$(echo "$OUTPUT" | grep -oP '\d+$')

  if [[ -z "$JOB_ID" ]]; then
    echo "Error: sbatch failed for instance $i:"
    echo "$OUTPUT"
    exit 1
  fi

  JOB_IDS+=("$JOB_ID")
  PORTS+=("$PORT")
  NAMES+=("$NAME")
  echo "  Submitted $NAME → job $JOB_ID (port $PORT)"
done

echo ""

# --- Wait for all jobs to start ---
echo -n "Waiting for jobs to start"
MAX_WAIT=120
WAITED=0
ALL_RUNNING=false

while [[ $WAITED -lt $MAX_WAIT ]]; do
  RUNNING_COUNT=0
  for JOB_ID in "${JOB_IDS[@]}"; do
    STATE=$(squeue -j "$JOB_ID" -h -o "%T" 2>/dev/null)
    if [[ "$STATE" == "RUNNING" ]]; then
      RUNNING_COUNT=$((RUNNING_COUNT + 1))
    elif [[ -z "$STATE" ]]; then
      echo ""
      echo "Error: job $JOB_ID exited unexpectedly."
      echo "Check logs: ls openclaw-gw-*-$JOB_ID.{out,err}"
      exit 1
    fi
  done

  if [[ $RUNNING_COUNT -eq $NUM_INSTANCES ]]; then
    ALL_RUNNING=true
    break
  fi

  echo -n "."
  sleep 2
  WAITED=$((WAITED + 2))
done

echo ""

if [[ "$ALL_RUNNING" != true ]]; then
  echo "Warning: not all jobs are running after ${MAX_WAIT}s."
  echo "Check: squeue -u $USER"
fi

# --- Wait a moment for banners to be written ---
sleep 3

# --- Extract nodes from job output ---
echo ""
echo "╔══════════════════════════════════════════════════════════════╗"
echo "║  OpenClaw Multi-Gateway Summary                            ║"
echo "╚══════════════════════════════════════════════════════════════╝"
echo ""

# Extract auth token (shared across instances)
# Use $HOME (logical path) when repo is under home dir to preserve symlink
# paths (on NFS clusters, /home/user may be a symlink to /orcd/home/002/user).
INSTALL_DIR="$(dirname "$REPO_DIR")"
REAL_HOME="$(readlink -f "$HOME")"
if [ "$(readlink -f "$INSTALL_DIR")" = "$REAL_HOME" ]; then
  INSTALL_DIR="$HOME"
fi
CONFIG_FILE="$INSTALL_DIR/.openclaw/openclaw.json"
TOKEN=""
if [ -f "$CONFIG_FILE" ]; then
  TOKEN=$(python3 -c "
import json
try:
    cfg = json.load(open('$CONFIG_FILE'))
    print(cfg.get('gateway',{}).get('auth',{}).get('token',''))
except: pass
" 2>/dev/null)
fi

printf "  %-12s %-12s %-16s %-8s\n" "AGENT" "JOB ID" "NODE" "PORT"
printf "  %-12s %-12s %-16s %-8s\n" "────────" "────────" "──────────────" "─────"

for idx in $(seq 0 $((NUM_INSTANCES - 1))); do
  JOB_ID="${JOB_IDS[$idx]}"
  PORT="${PORTS[$idx]}"
  NAME="${NAMES[$idx]}"
  NODE=$(squeue -j "$JOB_ID" -h -o "%N" 2>/dev/null || echo "pending")
  printf "  %-12s %-12s %-16s %-8s\n" "$NAME" "$JOB_ID" "$NODE" "$PORT"
done

echo ""
echo "  ── SSH Tunnels (run on your laptop) ───────────────────────"
echo ""
echo "  All tunnels in one command:"
echo ""

# Build combined tunnel command
TUNNEL_ARGS=""
for idx in $(seq 0 $((NUM_INSTANCES - 1))); do
  JOB_ID="${JOB_IDS[$idx]}"
  PORT="${PORTS[$idx]}"
  NODE=$(squeue -j "$JOB_ID" -h -o "%N" 2>/dev/null || echo "<node>")
  TUNNEL_ARGS="$TUNNEL_ARGS -L $PORT:$NODE:$PORT"
done
echo "     autossh -M 0 -f -N $TUNNEL_ARGS $(whoami)@$LOGIN_NODE"

echo ""
echo "  Or per-instance:"
echo ""
for idx in $(seq 0 $((NUM_INSTANCES - 1))); do
  JOB_ID="${JOB_IDS[$idx]}"
  PORT="${PORTS[$idx]}"
  NAME="${NAMES[$idx]}"
  NODE=$(squeue -j "$JOB_ID" -h -o "%N" 2>/dev/null || echo "<node>")
  echo "     # $NAME"
  echo "     autossh -M 0 -f -N -L $PORT:$NODE:$PORT $(whoami)@$LOGIN_NODE"
done

echo ""
echo "  ── Dashboard URLs ─────────────────────────────────────────"
echo ""
for idx in $(seq 0 $((NUM_INSTANCES - 1))); do
  PORT="${PORTS[$idx]}"
  NAME="${NAMES[$idx]}"
  if [ -n "$TOKEN" ]; then
    echo "     $NAME:  http://localhost:$PORT/?token=$TOKEN"
  else
    echo "     $NAME:  http://localhost:$PORT/"
  fi
done

echo ""
echo "  ── Cleanup ─────────────────────────────────────────────────"
echo ""
echo "  Stop all instances:"
echo "     scancel ${JOB_IDS[*]}"
echo ""
echo "  Stop one instance (replace JOB_ID):"
echo "     scancel JOB_ID"
echo ""
echo "  ──────────────────────────────────────────────────────────"
