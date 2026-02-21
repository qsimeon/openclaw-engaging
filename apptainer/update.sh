#!/usr/bin/env bash
# update.sh — Check for and apply upstream OpenClaw updates
#
# Usage:
#   ./apptainer/update.sh           # Full update: fetch + merge + rebuild
#   ./apptainer/update.sh --check   # Check only: print update status
#
# Run from anywhere — the script finds the repo root automatically.
# The rebuild uses srun since login nodes can't build containers.

set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
REPO_DIR="$(cd "$SCRIPT_DIR/.." && pwd)"
UPSTREAM_URL="https://github.com/openclaw/openclaw.git"
UPSTREAM_BRANCH="main"
CHECK_ONLY=false

if [[ "${1:-}" == "--check" ]]; then
  CHECK_ONLY=true
fi

cd "$REPO_DIR"

# --- Ensure upstream remote exists ---
if ! git remote get-url upstream &>/dev/null; then
  if $CHECK_ONLY; then
    # Silently add upstream in check mode
    git remote add upstream "$UPSTREAM_URL" 2>/dev/null || true
  else
    echo "Adding upstream remote: $UPSTREAM_URL"
    git remote add upstream "$UPSTREAM_URL"
  fi
fi

# --- Fetch upstream ---
if $CHECK_ONLY; then
  git fetch upstream --quiet 2>/dev/null || exit 0
else
  echo "Fetching upstream..."
  git fetch upstream
fi

# --- Count new commits ---
LOCAL=$(git rev-parse HEAD)
UPSTREAM=$(git rev-parse "upstream/$UPSTREAM_BRANCH" 2>/dev/null || echo "")

if [[ -z "$UPSTREAM" ]]; then
  $CHECK_ONLY || echo "Could not find upstream/$UPSTREAM_BRANCH."
  exit 0
fi

BEHIND=$(git rev-list --count "HEAD..upstream/$UPSTREAM_BRANCH" 2>/dev/null || echo 0)

if [[ "$BEHIND" -eq 0 ]]; then
  if $CHECK_ONLY; then
    # Silent — no output when up to date
    :
  else
    echo "Already up to date with upstream/$UPSTREAM_BRANCH."
  fi
  exit 0
fi

# --- Check-only mode: print notice and exit ---
if $CHECK_ONLY; then
  echo ""
  echo "  Upstream has $BEHIND new commit(s). Run ./apptainer/update.sh to update."
  echo ""
  exit 0
fi

# --- Full update: merge ---
echo ""
echo "$BEHIND new commit(s) available from upstream/$UPSTREAM_BRANCH."
echo ""
echo "Merging upstream/$UPSTREAM_BRANCH..."

if ! git merge "upstream/$UPSTREAM_BRANCH" --no-edit; then
  echo ""
  echo "Merge conflict detected. Aborting merge."
  echo "Resolve conflicts manually, then rebuild the container."
  git merge --abort 2>/dev/null || true
  exit 1
fi

echo ""
echo "Merge successful."

# --- Rebuild container ---
echo ""
read -rp "Rebuild the container now? [Y/n] " REPLY
REPLY="${REPLY:-Y}"

if [[ "$REPLY" =~ ^[Yy]$ ]]; then
  echo ""
  echo "Submitting container build via srun (this takes ~10 minutes)..."
  echo ""
  module load apptainer/1.4.2 2>/dev/null || true
  srun --mem=8G --time=01:00:00 --cpus-per-task=2 \
    apptainer build --force apptainer/openclaw.sif apptainer/openclaw.def

  echo ""
  echo "Container rebuilt. New version:"
  apptainer exec apptainer/openclaw.sif openclaw --version 2>/dev/null || echo "(could not read version)"
else
  echo ""
  echo "Skipping rebuild. When ready, run:"
  echo "  srun --mem=8G --time=01:00:00 --cpus-per-task=2 \\"
  echo "    apptainer build --force apptainer/openclaw.sif apptainer/openclaw.def"
fi
