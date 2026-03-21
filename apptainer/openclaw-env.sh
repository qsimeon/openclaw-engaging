#!/usr/bin/env bash
# openclaw-env.sh — Source this to get the 'openclaw' command
#
# Add to your ~/.bashrc:
#   source ~/orcd/scratch/oclaw/openclaw-engaging/apptainer/openclaw-env.sh
#
# Or wherever you cloned the repo.

_OPENCLAW_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"

# Load Apptainer module if available
if command -v module &>/dev/null; then
  module load apptainer/1.4.2 2>/dev/null || module load apptainer 2>/dev/null || true
fi

# Containall is on by default (set OPENCLAW_CONTAINALL=0 to disable)
export OPENCLAW_CONTAINALL="${OPENCLAW_CONTAINALL:-1}"

# Shell alias
alias openclaw="$_OPENCLAW_DIR/openclaw-engaging.sh"

# Tab completion (if available)
if [ -f "$HOME/.openclaw/completions/openclaw.bash" ]; then
  source "$HOME/.openclaw/completions/openclaw.bash"
fi
