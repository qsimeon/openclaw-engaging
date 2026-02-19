#!/usr/bin/env bash
# setup.sh — "1-Click" OpenClaw deploy for MIT Engaging HPC
#
# Builds the Apptainer container (if needed) then launches the OpenClaw
# onboarding wizard — the same wizard used by the DigitalOcean and Docker
# deployments. The wizard walks you through API keys, model selection,
# channels, skills, and everything else.
#
# Usage (on a compute node — login nodes may hit resource limits):
#   srun --pty --mem=8G --time=01:00:00 --cpus-per-task=2 ./apptainer/setup.sh
#
# Or split into two steps:
#   # Step 1: Build (non-interactive, can run without --pty)
#   srun --mem=8G --time=01:00:00 --cpus-per-task=2 ./apptainer/setup.sh --build-only
#
#   # Step 2: Onboard (interactive, needs --pty for the wizard)
#   srun --pty --mem=1G --time=00:30:00 ./apptainer/setup.sh --onboard-only
#
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
DEF_FILE="$SCRIPT_DIR/openclaw.def"
SIF_FILE="$SCRIPT_DIR/openclaw.sif"

BUILD_ONLY=false
ONBOARD_ONLY=false

for arg in "$@"; do
  case "$arg" in
    --build-only)  BUILD_ONLY=true ;;
    --onboard-only) ONBOARD_ONLY=true ;;
    --help|-h)
      echo "Usage: $0 [--build-only | --onboard-only]"
      echo ""
      echo "  (no flags)      Build container + run onboarding wizard"
      echo "  --build-only    Just build the .sif container image"
      echo "  --onboard-only  Just run the onboarding wizard (container must exist)"
      exit 0
      ;;
  esac
done

# ── Load Apptainer ──────────────────────────────────────────────────
if command -v module &>/dev/null; then
  module load apptainer/1.4.2 2>/dev/null || module load apptainer 2>/dev/null || true
fi

if ! command -v apptainer &>/dev/null; then
  echo "Error: apptainer not found. On Engaging, run: module load apptainer/1.4.2"
  exit 1
fi

# ── Build the container ─────────────────────────────────────────────
if [ "$ONBOARD_ONLY" = false ]; then
  if [ -f "$SIF_FILE" ]; then
    echo "Container already exists at $SIF_FILE"
    read -rp "Rebuild? [y/N] " rebuild
    if [[ "$rebuild" =~ ^[Yy]$ ]]; then
      rm -f "$SIF_FILE"
    else
      echo "Keeping existing container."
    fi
  fi

  if [ ! -f "$SIF_FILE" ]; then
    echo ""
    echo "Building OpenClaw container..."
    echo "(If this fails with 'Failed to create thread', you need a compute node:"
    echo "  srun --pty --mem=8G --time=01:00:00 --cpus-per-task=2 $0)"
    echo ""
    apptainer build "$SIF_FILE" "$DEF_FILE"
    echo ""
    echo "Built: $SIF_FILE"
  fi

  # Verify
  echo ""
  VERSION=$(apptainer exec "$SIF_FILE" openclaw --version 2>/dev/null || echo "unknown")
  echo "OpenClaw version: $VERSION"

  if [ "$BUILD_ONLY" = true ]; then
    echo ""
    echo "Container built. To continue setup, run:"
    echo "  srun --pty --mem=1G --time=00:30:00 $0 --onboard-only"
    exit 0
  fi
fi

# ── Verify container exists (for --onboard-only) ────────────────────
if [ ! -f "$SIF_FILE" ]; then
  echo "Error: Container not found at $SIF_FILE"
  echo "Run without --onboard-only first to build it."
  exit 1
fi

# ── Set HPC-friendly session config before onboarding ────────────────
# On HPC, sessions should never auto-reset (jobs get preempted).
# This sets up the base config so onboarding layers on top of it.
CONFIG_DIR="$HOME/.openclaw"
CONFIG_FILE="$CONFIG_DIR/openclaw.json"
mkdir -p "$CONFIG_DIR"

if [ ! -f "$CONFIG_FILE" ]; then
  cat > "$CONFIG_FILE" << 'EOF'
{
  "agents": {
    "defaults": {
      "sandbox": {
        "mode": "off"
      }
    }
  },
  "session": {
    "reset": {
      "mode": "idle",
      "idleMinutes": 525600
    }
  },
  "gateway": {
    "port": 18790,
    "bind": "lan",
    "controlUi": {
      "dangerouslyDisableDeviceAuth": true
    }
  }
}
EOF
  echo "Created HPC-friendly config at $CONFIG_FILE"
  echo "  • Sandbox: off (no Docker-in-Docker on HPC)"
  echo "  • Session idle timeout: 1 year (effectively never — survives job preemption)"
  echo "  • Gateway: port 18790, LAN bind, device auth disabled (SSH tunnel)"
fi

# ── Run the OpenClaw onboarding wizard ──────────────────────────────
echo ""
echo "╔══════════════════════════════════════════════════════════════╗"
echo "║  OpenClaw Setup Wizard                                     ║"
echo "║                                                            ║"
echo "║  This will walk you through setting up your AI assistant:  ║"
echo "║    • LLM provider & API key                                ║"
echo "║    • Model selection                                       ║"
echo "║    • Messaging channels (optional)                         ║"
echo "║    • Skills & tools (optional)                             ║"
echo "║                                                            ║"
echo "║  All config is saved to ~/.openclaw/ on your home dir.     ║"
echo "║  It persists across SLURM jobs.                            ║"
echo "╚══════════════════════════════════════════════════════════════╝"
echo ""

apptainer exec "$SIF_FILE" \
  openclaw onboard --skip-daemon

echo ""
echo "════════════════════════════════════════════════════════════════"
echo "  Setup complete!"
echo ""
echo "  Your config:  ~/.openclaw/"
echo "  Container:    $SIF_FILE"
echo ""
echo "  Quick test (on a compute node):"
echo "    module load apptainer/1.4.2"
echo "    apptainer exec $SIF_FILE openclaw agent --local --agent main -m \"Hello!\""
echo ""
echo "  Interactive session:"
echo "    srun --pty --mem=1G --time=02:00:00 bash"
echo "    module load apptainer/1.4.2"
echo "    apptainer exec $SIF_FILE openclaw agent --local --agent main -m \"What can you help me with?\""
echo ""
echo "  Batch job:"
echo "    sbatch $SCRIPT_DIR/slurm-openclaw.sh"
echo ""
echo "  Reconfigure later:"
echo "    apptainer exec $SIF_FILE openclaw configure"
echo ""
echo "  Sessions persist across jobs — just rerun the same command"
echo "  and the agent picks up where you left off."
echo "════════════════════════════════════════════════════════════════"
