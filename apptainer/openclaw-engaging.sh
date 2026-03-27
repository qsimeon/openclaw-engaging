#!/usr/bin/env bash
# openclaw-engaging.sh — Run OpenClaw on MIT Engaging via Apptainer
#
# A convenience wrapper that handles module loading and container paths
# so you can just run:
#
#   ./openclaw-engaging.sh agent --local --agent main -m "Hello!"
#   ./openclaw-engaging.sh configure
#   ./openclaw-engaging.sh sessions
#   ./openclaw-engaging.sh doctor
#
# All arguments are passed directly to the openclaw CLI inside the container.

set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
REPO_DIR="$(cd "$SCRIPT_DIR/.." && pwd)"
SIF_FILE="${OPENCLAW_SIF:-$SCRIPT_DIR/openclaw.sif}"

# Load Apptainer module if on a module-managed system
if command -v module &>/dev/null; then
  module load apptainer/1.4.2 2>/dev/null || module load apptainer 2>/dev/null || true
fi

if ! command -v apptainer &>/dev/null; then
  echo "Error: apptainer not found. Run: module load apptainer/1.4.2"
  exit 1
fi

if [ ! -f "$SIF_FILE" ]; then
  echo "Error: Container not found at $SIF_FILE"
  echo "Run setup.sh first to build it."
  exit 1
fi

# Build env flags for any provider API keys in the environment
ENV_FLAGS=""
[ -n "${ANTHROPIC_API_KEY:-}" ] && ENV_FLAGS="$ENV_FLAGS --env ANTHROPIC_API_KEY=$ANTHROPIC_API_KEY"
[ -n "${OPENAI_API_KEY:-}" ] && ENV_FLAGS="$ENV_FLAGS --env OPENAI_API_KEY=$OPENAI_API_KEY"
[ -n "${OPENROUTER_API_KEY:-}" ] && ENV_FLAGS="$ENV_FLAGS --env OPENROUTER_API_KEY=$OPENROUTER_API_KEY"
[ -n "${GEMINI_API_KEY:-}" ] && ENV_FLAGS="$ENV_FLAGS --env GEMINI_API_KEY=$GEMINI_API_KEY"

# Set container home to the parent of the repo — .openclaw/ lives next to
# the repo (e.g., clone to ~/orcd/scratch/oclaw/openclaw-engaging →
# ~/orcd/scratch/oclaw/.openclaw/).
# Use $HOME when repo is under home dir to preserve symlink paths (on NFS
# clusters, /home/user may be a symlink to /orcd/home/002/user, and other
# symlinks like .openclaw may reference /home/user/... paths).
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

# shellcheck disable=SC2086
exec apptainer exec $CONTAINALL_FLAGS $HOME_FLAGS $BIND_FLAGS $ENV_FLAGS "$SIF_FILE" openclaw "$@"
