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

# shellcheck disable=SC2086
exec apptainer exec $ENV_FLAGS "$SIF_FILE" openclaw "$@"
