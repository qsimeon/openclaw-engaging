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
#   srun --pty --mem=4G --time=00:30:00 ./apptainer/setup.sh --onboard-only
#
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
REPO_DIR="$(cd "$SCRIPT_DIR/.." && pwd)"
# Normalize NFS paths: on Engaging, /home/user is a symlink to /orcd/home/NNN/user.
# SLURM resolves symlinks, so pwd may return the NFS path. Prefer $HOME-relative
# paths so output messages and aliases show user-friendly paths.
_REAL_HOME="$(readlink -f "$HOME")"
_REAL_SCRIPT="$(readlink -f "$SCRIPT_DIR")"
if [[ "$_REAL_SCRIPT" == "$_REAL_HOME"/* ]]; then
  SCRIPT_DIR="$HOME/${_REAL_SCRIPT#$_REAL_HOME/}"
  REPO_DIR="$(dirname "$SCRIPT_DIR")"
fi
DEF_FILE="$SCRIPT_DIR/openclaw.def"
SIF_FILE="$SCRIPT_DIR/openclaw.sif"

BUILD_ONLY=false
ONBOARD_ONLY=false
YES=false

for arg in "$@"; do
  case "$arg" in
    --build-only)   BUILD_ONLY=true ;;
    --onboard-only) ONBOARD_ONLY=true ;;
    --yes|-y)       YES=true ;;
    --help|-h)
      echo "Usage: $0 [--build-only | --onboard-only] [--yes]"
      echo ""
      echo "  (no flags)      Build container + run onboarding wizard"
      echo "  --build-only    Just build the .sif container image (no wizard)"
      echo "  --onboard-only  Just run the onboarding wizard (container must exist)"
      echo "  --yes / -y      Non-interactive: skip all prompts (use defaults)"
      echo ""
      echo "  Tip: submit the build step without --pty, then do the wizard separately:"
      echo "    srun --mem=8G --time=01:00:00 --cpus-per-task=2 $0 --build-only --yes"
      echo "    srun --pty --mem=4G --time=00:30:00 $0 --onboard-only"
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

# ── Auto-update from upstream ──────────────────────────────────────
# Ensures users always build the latest version of OpenClaw.
# Non-fatal: if network is down or merge conflicts, setup continues
# with whatever is currently checked out.
if [ "$ONBOARD_ONLY" = false ] && command -v git &>/dev/null; then
  echo "Checking for upstream updates..."
  "$SCRIPT_DIR/update.sh" --check 2>/dev/null || true
  # Just report — don't prompt. Run ./apptainer/update.sh separately to update.
  BEHIND=$(cd "$REPO_DIR" && git rev-list --count "HEAD..upstream/main" 2>/dev/null || echo 0)
  if [ "$BEHIND" -gt 0 ]; then
    echo "  $BEHIND new commit(s) from upstream."
    echo "  Run ./apptainer/update.sh to update (then rebuild with --build-only)."
  else
    echo "  Already up to date."
  fi
fi

# ── Build the container ─────────────────────────────────────────────
if [ "$ONBOARD_ONLY" = false ]; then
  if [ -f "$SIF_FILE" ]; then
    echo "Container already exists at $SIF_FILE — skipping build."
    echo "(To rebuild: rm $SIF_FILE && $0 --build-only)"
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
    echo "  srun --pty --mem=4G --time=00:30:00 $0 --onboard-only"
    exit 0
  fi
fi

# ── Verify container exists (for --onboard-only) ────────────────────
if [ ! -f "$SIF_FILE" ]; then
  echo "Error: Container not found at $SIF_FILE"
  echo "Run without --onboard-only first to build it."
  exit 1
fi

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

# ── Ensure config directory exists ────────────────────────────────────
mkdir -p "$INSTALL_DIR/.openclaw"

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
echo "║  All config is saved to .openclaw/ next to the repo.        ║"
echo "║  It persists across SLURM jobs.                            ║"
echo "╚══════════════════════════════════════════════════════════════╝"
echo ""

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
# Onboard may crash due to plugin init errors (e.g., LINE plugin) — don't
# let that abort setup.  HPC settings, alias, and workspace init must run
# regardless.
ONBOARD_OK=true
if ! apptainer exec $CONTAINALL_FLAGS $HOME_FLAGS $BIND_FLAGS "$SIF_FILE" \
  openclaw onboard --skip-daemon; then
  ONBOARD_OK=false
  echo ""
  echo "  ⚠  Onboarding wizard exited with an error."
  echo "     This is usually caused by a plugin initialization issue."
  echo "     Setup will continue — you can configure your API key later:"
  echo ""
  echo "       openclaw configure --section model"
  echo ""
fi

# ── Apply HPC-friendly settings AFTER onboarding ────────────────────
# Onboarding creates/modifies openclaw.json. We layer HPC settings on
# top so they aren't overwritten by the wizard.
echo ""
echo "Applying HPC-friendly settings..."
# shellcheck disable=SC2086
apptainer exec $CONTAINALL_FLAGS $HOME_FLAGS $BIND_FLAGS "$SIF_FILE" openclaw config set agents.defaults.sandbox.mode off
# shellcheck disable=SC2086
apptainer exec $CONTAINALL_FLAGS $HOME_FLAGS $BIND_FLAGS "$SIF_FILE" openclaw config set session.reset.mode idle
# shellcheck disable=SC2086
apptainer exec $CONTAINALL_FLAGS $HOME_FLAGS $BIND_FLAGS "$SIF_FILE" openclaw config set session.reset.idleMinutes 525600
# shellcheck disable=SC2086
apptainer exec $CONTAINALL_FLAGS $HOME_FLAGS $BIND_FLAGS "$SIF_FILE" openclaw config set gateway.port 18790
# shellcheck disable=SC2086
apptainer exec $CONTAINALL_FLAGS $HOME_FLAGS $BIND_FLAGS "$SIF_FILE" openclaw config set gateway.bind loopback
# shellcheck disable=SC2086
apptainer exec $CONTAINALL_FLAGS $HOME_FLAGS $BIND_FLAGS "$SIF_FILE" openclaw config set gateway.controlUi.dangerouslyDisableDeviceAuth true
# shellcheck disable=SC2086
apptainer exec $CONTAINALL_FLAGS $HOME_FLAGS $BIND_FLAGS "$SIF_FILE" openclaw config set gateway.controlUi.allowedOrigins '["http://localhost:18790"]'

echo ""
echo "  • Sandbox: off (Apptainer --containall is the security boundary)"
echo "  • Filesystem isolation: on (only repo + .openclaw/ visible)"
echo "  • Session idle timeout: 1 year (survives job preemption)"
echo "  • Gateway: port 18790, loopback bind (SSH tunnel required)"
echo "  • Home: $INSTALL_DIR (container \$HOME = parent of repo)"
echo ""
echo "  Config and sessions live in $INSTALL_DIR/.openclaw/"

# ── Populate workspace with ORCD cluster context ─────────────────────
"$SCRIPT_DIR/orcd-workspace-init.sh" 2>/dev/null || true

# ── Install Lmod modulefile to ~/modulefiles/ ────────────────────────
MODDIR="$HOME/modulefiles"
mkdir -p "$MODDIR"
cp "$SCRIPT_DIR/openclaw.lua" "$MODDIR/openclaw.lua"

echo ""
echo "════════════════════════════════════════════════════════════════"
echo "  Setup complete!"
echo ""
echo "  Your config:  $INSTALL_DIR/.openclaw/"
echo "  Container:    $SIF_FILE"
echo "  Modulefile:   $MODDIR/openclaw.lua"
echo ""
echo "  ── Activate the openclaw command ─────────────────────────"
echo ""
echo "  1) Add to ~/.bashrc (one time — standard HPC practice):"
echo ""
echo "     echo 'module use ~/modulefiles' >> ~/.bashrc"
echo "     source ~/.bashrc"
echo ""
echo "  2) Load OpenClaw each session (or add to ~/.bashrc after step 1):"
echo ""
echo "     module load openclaw"
echo ""
echo "  Then use:"
echo ""
echo "    openclaw --help"
echo "    openclaw agent --local --agent main -m \"Hello!\""
echo "    openclaw configure"
echo ""
echo "  ── Next: Start the Gateway (browser dashboard) ──────────"
echo ""
echo "  1) Launch the gateway (submits job + shows connection info):"
echo ""
echo "     cd $REPO_DIR"
echo "     ./apptainer/start-gateway.sh"
echo ""
echo "  2) On your laptop, run the SSH tunnel (copy from output):"
echo ""
echo "     ssh -J \$(whoami)@orcd-login.mit.edu -L 18790:localhost:18790 \$(whoami)@<node> -N"
echo ""
echo "  3) Open the dashboard URL from the output in your browser."
echo ""
echo "  ── Other ways to use your agent ─────────────────────────"
echo ""
echo "  Quick test (on a compute node):"
echo "    openclaw agent --local --agent main -m \"Hello!\""
echo ""
echo "  Interactive session:"
echo "    srun --pty --mem=1G --time=02:00:00 bash"
echo "    openclaw agent --local --agent main"
echo ""
echo "  Batch job:"
echo "    cd $REPO_DIR"
echo "    sbatch apptainer/slurm-openclaw.sh"
echo ""
echo "  Reconfigure later:"
echo "    openclaw configure"
echo ""
echo "  Sessions persist across jobs — just rerun the same command"
echo "  and the agent picks up where you left off."
echo "════════════════════════════════════════════════════════════════"
