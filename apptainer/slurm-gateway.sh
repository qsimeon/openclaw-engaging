#!/bin/bash
#SBATCH --job-name=openclaw-gw
#SBATCH --time=08:00:00
#SBATCH --mem=4G
#SBATCH --cpus-per-task=1
#SBATCH --output=openclaw-gw-%j.out
#SBATCH --error=openclaw-gw-%j.err

# OpenClaw Gateway — persistent server for MIT Engaging HPC
#
# Runs the gateway on a compute node so you can access the dashboard
# and Telegram/Discord channels from your browser via SSH tunnel.
#
# Usage:
#   sbatch apptainer/slurm-gateway.sh
#
# The job output will print the exact SSH tunnel command and dashboard
# URL (including the auth token) — just copy and paste.
#
# See docs/engaging-apptainer-guide.md for the full guide.

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
  echo "Run setup.sh first."
  exit 1
fi

# --- Build env flags ---
ENV_FLAGS=""
[ -n "${ANTHROPIC_API_KEY:-}" ] && ENV_FLAGS="$ENV_FLAGS --env ANTHROPIC_API_KEY=$ANTHROPIC_API_KEY"
[ -n "${OPENAI_API_KEY:-}" ] && ENV_FLAGS="$ENV_FLAGS --env OPENAI_API_KEY=$OPENAI_API_KEY"
[ -n "${OPENROUTER_API_KEY:-}" ] && ENV_FLAGS="$ENV_FLAGS --env OPENROUTER_API_KEY=$OPENROUTER_API_KEY"
[ -n "${GEMINI_API_KEY:-}" ] && ENV_FLAGS="$ENV_FLAGS --env GEMINI_API_KEY=$GEMINI_API_KEY"

# If ~/.openclaw is a symlink (e.g. to /orcd/data/...), bind-mount the target
BIND_FLAGS=""
if [ -L "$HOME/.openclaw" ]; then
  SYMLINK_TARGET="$(readlink -f "$HOME/.openclaw")"
  BIND_FLAGS="-B $(dirname "$SYMLINK_TARGET")"
fi

PORT="${OPENCLAW_GATEWAY_PORT:-18790}"
NODE=$(hostname)
LOGIN_NODE="${OPENCLAW_LOGIN_NODE:-orcd-login.mit.edu}"
AGENT_NAME="${OPENCLAW_AGENT:-}"

# --- Extract gateway auth token + ensure allowedOrigins ---
CONFIG_FILE="$HOME/.openclaw/openclaw.json"
TOKEN=""
if [ -f "$CONFIG_FILE" ]; then
  # Extract token and patch allowedOrigins if missing (required since upstream v2026.2.22+)
  TOKEN=$(python3 -c "
import json, sys
try:
    cfg = json.load(open('$CONFIG_FILE'))
    print(cfg.get('gateway',{}).get('auth',{}).get('token',''))
except: pass
" 2>/dev/null)

  # Ensure allowedOrigins is set (upstream now requires it for non-loopback)
  python3 -c "
import json, os
cfg_path = '$CONFIG_FILE'
with open(cfg_path) as f:
    cfg = json.load(f)
gw = cfg.setdefault('gateway', {})
cui = gw.setdefault('controlUi', {})
if 'allowedOrigins' not in cui:
    cui['allowedOrigins'] = ['http://localhost:$PORT']
    with open(cfg_path, 'w') as f:
        json.dump(cfg, f, indent=2)
" 2>/dev/null || true
fi

echo "╔══════════════════════════════════════════════════════════════╗"
if [ -n "$AGENT_NAME" ]; then
  printf "║  OpenClaw Gateway — %-39s ║\n" "$AGENT_NAME"
else
  echo "║  OpenClaw Gateway                                          ║"
fi
echo "╚══════════════════════════════════════════════════════════════╝"
echo ""
[ -n "$AGENT_NAME" ] && echo "  Agent:   $AGENT_NAME"
echo "  Node:    $NODE"
echo "  Port:    $PORT"
echo "  Job ID:  $SLURM_JOB_ID"
echo "  Started: $(date)"
echo ""
echo "  ── Connect from your laptop ──────────────────────────────"
echo ""
echo "  1) SSH tunnel (run on your laptop — kills any old tunnel first):"
echo ""
echo "     lsof -ti:$PORT | xargs kill -9 2>/dev/null; autossh -M 0 -f -N -L $PORT:$NODE:$PORT $(whoami)@$LOGIN_NODE"
echo ""
echo "     (autossh auto-reconnects if your laptop sleeps; install with:"
echo "      brew install autossh on Mac, apt install autossh on Linux)"
echo ""
echo "     Or without autossh:"
echo "     lsof -ti:$PORT | xargs kill -9 2>/dev/null; ssh -f -N -L $PORT:$NODE:$PORT $(whoami)@$LOGIN_NODE"
echo ""
echo "  2) Open in your browser:"
echo ""
if [ -n "$TOKEN" ]; then
  echo "     http://localhost:$PORT/?token=$TOKEN"
else
  echo "     http://localhost:$PORT/"
  echo ""
  echo "     (no token found in config — you may need to paste"
  echo "      it manually in the dashboard settings)"
fi
echo ""
echo "  ──────────────────────────────────────────────────────────"
echo ""
echo "  The gateway will run until the job times out or you cancel it."
echo "  To stop early:  scancel $SLURM_JOB_ID"
echo "  Sessions and config persist in ~/.openclaw/"
echo ""

# --- Start Gateway ---
# Bind to LAN (0.0.0.0) so the login node can reach it via SSH tunnel.
# Auth token protects against unauthorized access.
# --allow-unconfigured: start even if no channels are fully configured yet.
# shellcheck disable=SC2086
apptainer exec \
  $BIND_FLAGS \
  $ENV_FLAGS \
  "$SIF_FILE" \
  openclaw gateway \
    --port "$PORT" \
    --bind lan \
    --allow-unconfigured

echo ""
echo "Gateway stopped at $(date)"
