#!/usr/bin/env bash
# setup.sh — Build OpenClaw Apptainer container and create starter config
# Usage: ./setup.sh [ANTHROPIC_API_KEY]
#
# Run on a compute node (login nodes may hit resource limits):
#   srun --mem=4G --time=00:30:00 --cpus-per-task=2 ./apptainer/setup.sh
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
DEF_FILE="$SCRIPT_DIR/openclaw.def"
SIF_FILE="$SCRIPT_DIR/openclaw.sif"
CONFIG_DIR="$HOME/.openclaw"
CONFIG_FILE="$CONFIG_DIR/openclaw.json"
ENV_FILE="$CONFIG_DIR/.env"

# --- Load Apptainer module (Engaging HPC) ---
if command -v module &>/dev/null; then
  echo "Loading apptainer module..."
  module load apptainer/1.4.2 2>/dev/null || module load apptainer 2>/dev/null || true
fi

if ! command -v apptainer &>/dev/null; then
  echo "Error: apptainer not found. On Engaging, run: module load apptainer/1.4.2"
  exit 1
fi

# --- Build the SIF image ---
if [ -f "$SIF_FILE" ]; then
  echo "Container already exists at $SIF_FILE"
  read -rp "Rebuild? [y/N] " rebuild
  if [[ "$rebuild" =~ ^[Yy]$ ]]; then
    rm -f "$SIF_FILE"
  else
    echo "Skipping build."
  fi
fi

if [ ! -f "$SIF_FILE" ]; then
  echo "Building container from $DEF_FILE ..."
  echo "(If this fails with 'Failed to create thread', run via srun:"
  echo "  srun --mem=4G --time=00:30:00 --cpus-per-task=2 $0 $*)"
  apptainer build "$SIF_FILE" "$DEF_FILE"
  echo "Built: $SIF_FILE"
fi

# --- Verify the build ---
echo ""
echo "Verifying installation..."
apptainer exec "$SIF_FILE" openclaw --version

# --- Create config directory ---
mkdir -p "$CONFIG_DIR"

# --- Get API key ---
KEY="${1:-${ANTHROPIC_API_KEY:-}}"

if [ -z "$KEY" ]; then
  echo ""
  echo "Which provider will you use?"
  echo "  1) Anthropic (Claude)"
  echo "  2) OpenAI (GPT-4o)"
  echo "  3) OpenRouter (multi-provider)"
  echo "  4) Skip for now"
  read -rp "Choice [1-4]: " choice
  case "$choice" in
    1)
      read -rsp "Enter your Anthropic API key (sk-ant-...): " KEY
      echo ""
      PROVIDER_VAR="ANTHROPIC_API_KEY"
      MODEL="anthropic/claude-sonnet-4-20250514"
      ;;
    2)
      read -rsp "Enter your OpenAI API key (sk-...): " KEY
      echo ""
      PROVIDER_VAR="OPENAI_API_KEY"
      MODEL="openai/gpt-4o"
      ;;
    3)
      read -rsp "Enter your OpenRouter API key (sk-or-...): " KEY
      echo ""
      PROVIDER_VAR="OPENROUTER_API_KEY"
      MODEL="anthropic/claude-sonnet-4-20250514"
      ;;
    *)
      echo "Skipping API key. Set it later in $ENV_FILE"
      KEY=""
      PROVIDER_VAR=""
      MODEL="anthropic/claude-sonnet-4-20250514"
      ;;
  esac
else
  # Detect provider from key prefix
  if [[ "$KEY" == sk-ant-* ]]; then
    PROVIDER_VAR="ANTHROPIC_API_KEY"
    MODEL="anthropic/claude-sonnet-4-20250514"
  elif [[ "$KEY" == sk-or-* ]]; then
    PROVIDER_VAR="OPENROUTER_API_KEY"
    MODEL="anthropic/claude-sonnet-4-20250514"
  else
    PROVIDER_VAR="OPENAI_API_KEY"
    MODEL="openai/gpt-4o"
  fi
fi

# --- Write .env file ---
if [ -f "$ENV_FILE" ]; then
  echo "Env file already exists at $ENV_FILE — not overwriting."
else
  if [ -n "$KEY" ] && [ -n "${PROVIDER_VAR:-}" ]; then
    cat > "$ENV_FILE" << EOF
# OpenClaw environment — MIT Engaging HPC
${PROVIDER_VAR}=${KEY}
EOF
    chmod 600 "$ENV_FILE"
    echo "Created env file at $ENV_FILE"
  fi
fi

# --- Write starter config ---
if [ -f "$CONFIG_FILE" ]; then
  echo "Config already exists at $CONFIG_FILE — not overwriting."
else
  cat > "$CONFIG_FILE" << EOF
{
  "agents": {
    "defaults": {
      "model": "${MODEL:-anthropic/claude-sonnet-4-20250514}"
    }
  }
}
EOF
  echo "Created config at $CONFIG_FILE"
fi

echo ""
echo "Setup complete!"
echo ""
if [ -n "${PROVIDER_VAR:-}" ]; then
  echo "  Run interactively:"
  echo "    srun --pty --mem=1G --time=01:00:00 bash"
  echo "    module load apptainer/1.4.2"
  echo "    apptainer exec $SIF_FILE openclaw agent --local --agent main -m \"Hello!\""
  echo ""
  echo "  Run a one-shot query:"
  echo "    apptainer exec $SIF_FILE openclaw agent --local --agent main -m \"Hello from Engaging!\""
else
  echo "  Set your API key, then run:"
  echo "    export ANTHROPIC_API_KEY=sk-ant-..."
  echo "    apptainer exec --env ANTHROPIC_API_KEY=\$ANTHROPIC_API_KEY $SIF_FILE openclaw agent --local --agent main -m \"Hello!\""
fi
echo ""
echo "  Submit as batch job:"
echo "    sbatch $SCRIPT_DIR/slurm-openclaw.sh"
