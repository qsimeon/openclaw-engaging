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
# IMPORTANT: No GPU needed! The gateway is a lightweight Node.js server
# that only needs 1 CPU + 4 GB RAM. Do NOT request a GPU partition —
# GPU nodes are a scarce shared resource. Use the default partition.
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

# Set container home to the parent of the repo — .openclaw/ lives next to
# the repo (e.g., clone to ~/openclaw-engaging → ~/.openclaw/).
# Use $HOME (logical path) when repo is under home dir to preserve symlink
# paths (on NFS clusters, /home/user may be a symlink to /orcd/home/002/user).
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

# --- Auto-detect free port ---
# If OPENCLAW_GATEWAY_PORT is set, use it. Otherwise scan 18790-18799.
PORT="${OPENCLAW_GATEWAY_PORT:-}"
if [ -z "$PORT" ]; then
  for candidate in $(seq 18790 18799); do
    if ! ss -tln 2>/dev/null | grep -q ":${candidate} "; then
      PORT=$candidate
      break
    fi
  done
  PORT="${PORT:-18790}"
fi
NODE=$(hostname)
LOGIN_NODE="${OPENCLAW_LOGIN_NODE:-orcd-login.mit.edu}"
AGENT_NAME="${OPENCLAW_AGENT:-}"

# --- Extract gateway auth token + ensure allowedOrigins ---
CONFIG_FILE="$INSTALL_DIR/.openclaw/openclaw.json"
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
echo "     lsof -ti:$PORT | xargs kill -9 2>/dev/null; sleep 1; ssh -f -N -J $(whoami)@$LOGIN_NODE -L $PORT:localhost:$PORT $(whoami)@$NODE"
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
echo "  Sessions and config persist in $INSTALL_DIR/.openclaw/"
echo ""

# --- Start Gateway ---
# Bind to LAN (0.0.0.0) so the login node can reach it via SSH tunnel.
# Auth token protects against unauthorized access.
# --allow-unconfigured: start even if no channels are fully configured yet.
# shellcheck disable=SC2086
apptainer exec \
  $CONTAINALL_FLAGS \
  $HOME_FLAGS \
  $BIND_FLAGS \
  $ENV_FLAGS \
  "$SIF_FILE" \
  openclaw gateway \
    --port "$PORT" \
    --bind loopback \
    --allow-unconfigured

echo ""
echo "Gateway stopped at $(date)"
