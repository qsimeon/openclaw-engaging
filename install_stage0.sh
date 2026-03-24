#!/usr/bin/env bash
# install_stage0.sh — Clone openclaw-engaging and set up remotes
#
# Usage:
#   curl -fsSL https://raw.githubusercontent.com/qsimeon/openclaw-engaging/main/install_stage0.sh | bash
#
# Or specify a custom install directory:
#   curl -fsSL ... | bash -s -- ~/my/custom/path
#
# After cloning, run setup on a compute node:
#   cd <install-dir>/openclaw-engaging
#   srun --pty --mem=8G --time=01:00:00 --cpus-per-task=2 ./apptainer/setup.sh

set -euo pipefail

INSTALL_DIR="${1:-$HOME/orcd/scratch/oclaw}"
REPO_NAME="openclaw-engaging"
REPO_URL="https://github.com/qsimeon/openclaw-engaging.git"
UPSTREAM_URL="https://github.com/openclaw/openclaw.git"

echo "Installing OpenClaw for Engaging HPC..."
echo ""

# Create install directory
mkdir -p "$INSTALL_DIR"
cd "$INSTALL_DIR"

# Check for existing clone
if [ -d "$REPO_NAME" ]; then
  echo "Error: '$REPO_NAME' already exists in $INSTALL_DIR"
  echo "  To update: cd $INSTALL_DIR/$REPO_NAME && ./apptainer/update.sh"
  echo "  To reinstall: rm -rf $INSTALL_DIR/$REPO_NAME && rerun this script"
  exit 1
fi

# Clone and set up remotes
echo "Cloning $REPO_URL..."
git clone "$REPO_URL"
cd "$REPO_NAME"

echo "Adding upstream remote..."
git remote add upstream "$UPSTREAM_URL"
# Note: we do NOT git fetch upstream here — the upstream repo is large and
# the fetch would add several minutes to the install for no immediate benefit.
# The upstream remote is used by ./apptainer/update.sh when you want to sync.

echo ""
echo "════════════════════════════════════════════════════════════════"
echo "  Cloned to: $INSTALL_DIR/$REPO_NAME"
echo ""
echo "  Next steps:"
echo ""
echo "  1) Build and configure (on a compute node, ~15 min):"
echo ""
echo "     cd $INSTALL_DIR/$REPO_NAME"
echo "     srun --pty --mem=8G --time=01:00:00 --cpus-per-task=2 \\"
echo "       ./apptainer/setup.sh"
echo ""
echo "  2) Add to your ~/.bashrc (after setup completes):"
echo ""
echo "     source $INSTALL_DIR/$REPO_NAME/apptainer/openclaw-env.sh"
echo ""
echo "  Guide: $INSTALL_DIR/$REPO_NAME/docs/engaging-apptainer-guide.md"
echo "════════════════════════════════════════════════════════════════"
